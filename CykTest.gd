extends Node
## Debug state telemetry + W2 receipt rings for the cykgames release harness.
## [CYKTEST] {json} every 0.25 s: run gate / timer / stick / pos / vy / floor
## plus optional up (SystemClock.uptimeMillis common domain), session_id
## (64-bit nonce + pid + ready_up), jumps, jump_held, fps, ring watermarks.
## [CYKTEST-RING] {json} independent marker lines (<= 900 serialized bytes,
## bionic LOG_BUF_SIZE=1024): four receipt rings input/route/apply/jump, each
## {sid, ring, seq_range, entries[]}. Rings are NOT embedded in [CYKTEST].
## Test-only observers: never write saves, never change routing/consumption/
## gameplay. PROCESS_MODE_ALWAYS so rings drain during pause.
## Author: cykbot9 (AI agent).

const PERIOD := 0.25
const RING_LINE_MAX := 900
const CAP_INPUT := 512
const CAP_ROUTE := 256
const CAP_APPLY := 256
const CAP_JUMP := 64

var input_ring: CykRing
var route_ring: CykRing
var apply_ring: CykRing
var jump_ring: CykRing

var session_id := ""
var _nonce: int = 0
var _pid: int = -1
var _ready_up: int = -1
var _java_clock = null
var _acc := 0.0

# per-role state version / last-copied version (R6-n3 independent namespaces)
var _version := {"move": 0, "aim": 0, "shoot": 0, "jump": 0}
var _last_copied := {"move": 0, "aim": 0, "shoot": 0, "jump": 0}
# J GUI bridge context (synchronous dispatch lifetime witness; layer 2 wires
# JumpButton.gui_input/button_down/button_up). Cleared every _process tick.
var gui_context = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	input_ring = CykRing.new("input_log", CAP_INPUT)
	route_ring = CykRing.new("route_log", CAP_ROUTE)
	apply_ring = CykRing.new("apply_log", CAP_APPLY)
	jump_ring = CykRing.new("jump_log", CAP_JUMP)
	_init_session()


func _init_session() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# two independent randi() concatenated into a 64-bit nonce (not a renamed
# 32-bit value, not a fixed seed).
	var hi: int = rng.randi()
	var lo: int = rng.randi()
	_nonce = ((hi << 32) | (lo & 0xFFFFFFFF)) & 0xFFFFFFFFFFFFFFFF
	if Engine.has_singleton("JavaClassWrapper"):
		var jw = Engine.get_singleton("JavaClassWrapper")
		var sc = jw.wrap("android.os.SystemClock")
		if sc != null:
			_java_clock = sc
		var pr = jw.wrap("android.os.Process")
		if pr != null:
			_pid = int(pr.myPid())
	_ready_up = up()
	session_id = "%016x:%d:%d" % [_nonce, _pid, _ready_up]


func up() -> int:
	if _java_clock != null:
		return int(_java_clock.uptimeMillis())
	return -1


func lookup_input_seq(instance_id: int) -> int:
	var e = input_ring.find("e", instance_id)
	return int(e["s"]) if e != null else -1


## route observer helper: advance per-role version on an accepted write and
## push a route token. source_input_seq is the exact arrival seq ( looked up
## by event instance id at synchronous entry, never a "latest" guess).
func route_push(role: String, source_seq: int, stable_id: int, accepted: bool,
		value, bridge = null) -> int:
	if accepted:
		_version[role] = int(_version[role]) + 1
	var entry := {"u": up(), "src": source_seq, "id": stable_id, "role": role,
		"acc": accepted, "ver": int(_version[role]), "val": value}
	if bridge != null:
		entry["bridge"] = bridge
	route_ring.push(entry)
	return int(_version[role])


## apply observer helper: edge-triggered on per-role version advance (a
## periodic copy of an old version emits nothing). status=copied.
func apply_push(role: String, source_seq: int, value) -> void:
	if int(_version[role]) <= int(_last_copied[role]):
		return
	_last_copied[role] = int(_version[role])
	apply_ring.push({"u": up(), "src": source_seq, "ver": int(_version[role]),
		"role": role, "val": value, "st": "copied"})


## jump applied receipt: jump_log IS the applied receipt (velocity is canonical
## state, no downstream copy). status=applied.
func jump_push(jumps: int, source_seq: int) -> void:
	_version["jump"] = int(_version["jump"]) + 1
	jump_ring.push({"u": up(), "jumps": jumps, "src": source_seq,
		"ver": int(_version["jump"]), "st": "applied"})


# --------------------------------------------------------------------------- #
# W2 J GUI bridge (test-only non-consuming observers; plan v4.17 R7/R8/R9).
# gui_input fires before native GUI processing -> is_pressed() is the pre-
# transition state. The GUI clone's cyk_seq meta (merge_meta_from) bridges to
# the arrival seq. Context lifetime = current input dispatch; cleared every
# _process tick (frame-boundary witness) and replaced by the next gui_input.
# --------------------------------------------------------------------------- #
var pending_jump_token = null   # {src, up, ver} consumed by jump_applied
var jump_count := 0
var _pending_bridge = null      # emulated provisional bridge awaiting finalize


func gui_observe(event: InputEvent, control: BaseButton) -> void:
	var kind := ""
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		kind = "touch"
		pressed = event.pressed
		pos = event.position
	elif event is InputEventMouseButton:
		kind = "mouse"
		pressed = event.pressed
		pos = event.position
	elif event is InputEventMouseMotion:
		kind = "mouse_motion"
		pos = event.position
	else:
		return
	var cyk := -1
	if event.has_meta("cyk_seq"):
		cyk = int(event.get_meta("cyk_seq"))
	var disp := get_viewport().get_screen_transform() * pos
	gui_context = {
		"gui_eid": event.get_instance_id(), "gui_cyk_seq": cyk, "gui_kind": kind,
		"gui_pressed": pressed, "gui_x": snappedf(disp.x, 0.01),
		"gui_y": snappedf(disp.y, 0.01), "gui_up": up(),
		"control_id": control.get_instance_id(),
		"prev_pressed": control.is_pressed(), "disabled": control.disabled}


func _bridge_receipt(ctx: Dictionary, source_seq: int, path: String,
		status: String, mouse_seq: int, finalized_up: int) -> Dictionary:
	return {"gui_eid": ctx["gui_eid"], "gui_cyk_seq": ctx["gui_cyk_seq"],
		"control_id": ctx["control_id"], "gui_kind": ctx["gui_kind"],
		"gui_pressed": ctx["gui_pressed"], "gui_x": ctx["gui_x"],
		"gui_y": ctx["gui_y"], "gui_up": ctx["gui_up"], "src": source_seq,
		"path": path, "mouse_seq": mouse_seq, "status": status,
		"finalized_up": finalized_up}


func button_down_observe(control: BaseButton) -> void:
	var ctx = gui_context
	gui_context = null   # consume: one context per dispatch
	var action_up := up()
	if ctx == null or ctx["control_id"] != control.get_instance_id():
		route_push("jump", -1, 1, false, null,
			{"status": "unattributed", "reason": "no_context"})
		return
	# pressed-transition witness (false->true) + disabled guard at signal time
	if ctx["disabled"] or control.disabled or ctx["prev_pressed"] != false \
			or control.is_pressed() != true:
		route_push("jump", -1, 1, false, null,
			{"status": "unattributed", "reason": "transition_or_disabled"})
		return
	if ctx["gui_kind"] == "touch" and ctx["gui_cyk_seq"] >= 0:
		# native_meta: clone cyk_seq IS the source arrival seq (dual idx1 path)
		var src: int = ctx["gui_cyk_seq"]
		var br := _bridge_receipt(ctx, src, "native_meta", "finalized", -1, action_up)
		route_push("jump", src, 1, true, true, br)
		pending_jump_token = {"src": src, "up": action_up, "ver": int(_version["jump"])}
	elif ctx["gui_kind"] == "mouse" and ctx["gui_cyk_seq"] >= 0:
		# emulated adjacency (J-only idx0): source touch seq = mouse_seq + 1.
		# Provisional until the touch arrival is observed; finalize in _process.
		var mouse_seq: int = ctx["gui_cyk_seq"]
		_pending_bridge = {"ctx": ctx, "mouse_seq": mouse_seq, "action_up": action_up}
		_try_finalize_emulated()
	else:
		route_push("jump", -1, 1, false, null,
			{"status": "invalid", "reason": "no_cyk_seq"})


func _try_finalize_emulated() -> void:
	if _pending_bridge == null:
		return
	var ctx: Dictionary = _pending_bridge["ctx"]
	var mouse_seq: int = _pending_bridge["mouse_seq"]
	var action_up: int = _pending_bridge["action_up"]
	var touch_seq := mouse_seq + 1
	var te = input_ring.find("s", touch_seq)
	var ok := false
	if te != null and te["k"] == "touch_down" and te["i"] == 0:
		if absf(float(te["x"]) - float(ctx["gui_x"])) <= 2.0 \
				and absf(float(te["y"]) - float(ctx["gui_y"])) <= 2.0:
			ok = true
	if ok:
		var br := _bridge_receipt(ctx, touch_seq, "emulated_adjacency",
			"finalized", mouse_seq, up())
		br["adjacency_verified"] = true
		route_push("jump", touch_seq, 1, true, true, br)
		pending_jump_token = {"src": touch_seq, "up": action_up, "ver": int(_version["jump"])}
		_pending_bridge = null
	elif up() - action_up > 500:
		# collection window elapsed without a matching touch arrival -> invalid
		var br := _bridge_receipt(ctx, -1, "emulated_adjacency", "invalid", mouse_seq, up())
		route_push("jump", -1, 1, false, null, br)
		_pending_bridge = null


func button_up_observe(control: BaseButton) -> void:
	var ctx = gui_context
	gui_context = null
	var action_up := up()
	if ctx == null or ctx["control_id"] != control.get_instance_id():
		route_push("jump", -1, 1, false, null,
			{"status": "unattributed", "reason": "no_context_up"})
		return
	if ctx["disabled"] or control.disabled or ctx["prev_pressed"] != true \
			or control.is_pressed() != false:
		route_push("jump", -1, 1, false, null,
			{"status": "unattributed", "reason": "transition_or_disabled_up"})
		return
	# UP release predicate: route-release token (no jump_log requirement).
	var src: int = ctx["gui_cyk_seq"] if ctx["gui_cyk_seq"] >= 0 else -1
	var path := "native_meta" if ctx["gui_kind"] == "touch" else "emulated_adjacency"
	var br := _bridge_receipt(ctx, src, path, "finalized", -1, action_up)
	br["release"] = true
	route_push("jump", src, 1, true, false, br)


func jump_applied() -> void:
	jump_count += 1
	if pending_jump_token != null:
		var src: int = pending_jump_token["src"]
		pending_jump_token = null
		jump_push(jump_count, src)
	else:
		# no attributable press token -> conservative unattributed applied row
		jump_push(jump_count, -1)


func _input(event: InputEvent) -> void:
	# Non-consuming arrival observer. Records a receipt and tags the event with
	# namespaced test-only metadata cyk_seq (survives GUI xformed_by clones via
	# merge_meta_from) for the J bridge. Does NOT accept/consume the event.
	var kind := ""
	var idx := 0
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		kind = "touch_down" if event.pressed else "touch_up"
		idx = event.index
		pos = event.position
	elif event is InputEventScreenDrag:
		kind = "drag"
		idx = event.index
		pos = event.position
	elif event is InputEventMouseButton:
		kind = "mouse_down" if event.pressed else "mouse_up"
		idx = 0
		pos = event.position
	elif event is InputEventMouseMotion:
		kind = "mouse_motion"
		idx = 0
		pos = event.position
	else:
		return
	var disp := get_viewport().get_screen_transform() * pos
	var seq := input_ring.push({"u": up(), "k": kind, "i": idx, "d": event.device,
		"x": snappedf(disp.x, 0.01), "y": snappedf(disp.y, 0.01),
		"e": event.get_instance_id()})
	event.set_meta("cyk_seq", seq)


func _process(delta: float) -> void:
	# frame-boundary witness: clear the J GUI context EVERY tick (autoload
	# _process runs before scene nodes; probe verifies ordering).
	gui_context = null
	_try_finalize_emulated()
	_drain_ring(input_ring)
	_drain_ring(route_ring)
	_drain_ring(apply_ring)
	_drain_ring(jump_ring)
	_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	_emit_sample()


func _ring_line(name: String, entries: Array) -> String:
	var lo: int = entries[0]["s"]
	var hi: int = entries[entries.size() - 1]["s"]
	return "[CYKTEST-RING] " + JSON.stringify(
		{"sid": session_id, "ring": name, "seq_range": [lo, hi], "entries": entries})


func _drain_ring(r: CykRing) -> void:
	var pend := r.pending()
	if pend.is_empty():
		return
	var entries := []
	for e in pend:
		var trial := entries + [e]
		if entries.size() > 0 and len(_ring_line(r.ring_name, trial).to_utf8_buffer()) > RING_LINE_MAX:
			print(_ring_line(r.ring_name, entries))
			r.mark_emitted(int(entries[entries.size() - 1]["s"]))
			entries = [e]
		else:
			entries = trial
	if entries.size() > 0:
		print(_ring_line(r.ring_name, entries))
		r.mark_emitted(int(entries[entries.size() - 1]["s"]))


func _emit_sample() -> void:
	var d := {
		"ts": Time.get_unix_time_from_system(),
		"ms": Time.get_ticks_msec(),
	}
	var u := up()
	if u >= 0:
		d["up"] = u
	d["session_id"] = session_id
	var scene := get_tree().current_scene
	var hud: CanvasLayer = null
	var player: CharacterBody3D = null
	if scene != null:
		hud = scene.get_node_or_null("HUD") as CanvasLayer
		player = scene.get_node_or_null("Player") as CharacterBody3D
	if hud == null:
		d["scene"] = "select"
		d["stars"] = Game.total_stars()
	else:
		d["scene"] = "play"
		d["level"] = Game.level_index
		d["running"] = hud.running
		d["started"] = hud.started
		d["finished"] = hud.finished
		d["paused"] = hud.paused
		d["time"] = snappedf(hud.time, 0.01)
		d["falls"] = hud.falls
		d["coins"] = hud.coins
		var joy: Joystick = hud.get("_joy") as Joystick
		if joy != null:
			d["stick"] = [snappedf(joy.output.x, 0.001), snappedf(joy.output.y, 0.001)]
		if player != null:
			d["pos"] = [snappedf(player.position.x, 0.01),
				snappedf(player.position.y, 0.01),
				snappedf(player.position.z, 0.01)]
			d["vy"] = snappedf(player.velocity.y, 0.01)
			d["floor"] = player.is_on_floor()
	d["jumps"] = jump_ring.seq()
	d["jump_held"] = Input.is_action_pressed("jump")
	d["fps"] = snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.1)
	d["wm"] = {
		"input": input_ring.watermark(), "route": route_ring.watermark(),
		"apply": apply_ring.watermark(), "jump": jump_ring.watermark()}
	print("[CYKTEST] " + JSON.stringify(d))