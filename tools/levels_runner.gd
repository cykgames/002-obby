extends Node
## W1 level verification runner (P1+P2 plan v4.17 W1), harness-owned lifecycle.
## Modes (set per scene via exported vars):
##   struct        : L0-struct -- per-level LevelGen geometry asserts (no player)
##   clear         : L0-clear  -- headless autopilot bot, harness-owned (no Main)
##   l1            : L1-replay -- real-event planner (idx0 stick + idx1 J)
##   l1_fall       : deliberate-fall recovery fixture (level 0, falls>=1 + clear)
##   l1_neg_stick  : negative control -- stick routed to invalid coords,
##                   traversal MUST fail (scene passes when it does)
##   l1_neg_jump   : negative control -- J routed to invalid coords, traversal
##                   MUST fail
##
## Save isolation double-insurance: (a) harness-owned subtree (level_harness
## .tscn = Main.tscn minus Main.gd/Audio) never attaches the finish/save/
## auto-reload orchestration; (b) Game.test_no_save=true blocks
## save_level_result. Before/after user://progress.json hash is asserted
## unchanged for EVERY scene (incl. L0-clear).
##
## Per-level fresh harness instance; between levels: full touch release +
## Input.flush_buffered_events. Deterministic: LevelGen has zero RNG and the
## planner reads no wall-clock; cap = max(par, preflight bot time) + margin.
## Jitter (sweep/seed/start_offset/decision_jitter) arrives via cmdline user
## args (after "++") and is planner-only; recorded in SHARD_META evidence.
## Run: Godot --headless --fixed-fps 60 --path . res://tools/<scene>.tscn

@export var mode := "l1"
@export var level_start := 0
@export var level_count := 4

const MARGIN := 15.0           # sim-s cap margin over max(par, bot)
const SHARD_WATCHDOG := 400.0  # wall-s self-guard (release.py per-scene 420)
# Preflight-measured per-level bot sim times (artifacts/tmp/p1p2_w1_bot_timing.json).
const BOT_TIME := [7.1, 9.27, 10.15, 9.25, 12.88, 8.37, 8.1, 8.87,
	10.95, 8.38, 10.95, 10.25, 8.43, 11.07, 14.05, 12.05]

var _fails := 0
var _save_before := ""
var _results := []
var _wall0 := 0
var _finished := false
var _final_time := 0.0


func _on_level_finished(t: float) -> void:
	_finished = true
	_final_time = t


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("W1_OK: ", what)
	else:
		_fails += 1
		print("W1_FAIL: ", what)


func _save_sig() -> String:
	if not FileAccess.file_exists(Game.SAVE_PATH):
		return "absent"
	return FileAccess.get_file_as_bytes(Game.SAVE_PATH).hex_encode()


func _user_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			d[kv[0]] = kv[1]
	return d


func _ready() -> void:
	get_window().size = Vector2i(1080, 2340)
	Game.test_no_save = true
	_save_before = _save_sig()
	_wall0 = Time.get_ticks_msec()
	var ua := _user_args()
	var seed := int(ua.get("seed", "0"))
	var start_offset := int(ua.get("start_offset", "0"))
	var decision_jitter := int(ua.get("decision_jitter", "0"))
	var sweep := int(ua.get("sweep", "0"))
	if mode == "struct":
		await _run_struct()
	else:
		for i in range(level_count):
			var lvl := level_start + i
			if lvl >= Game.LEVEL_COUNT:
				break
			await _run_level(lvl, seed, start_offset, decision_jitter)
	_expect(_save_sig() == _save_before, "save hash unchanged across shard (mode=%s)" % mode)
	var wall := float(Time.get_ticks_msec() - _wall0) / 1000.0
	print("SHARD_META " + JSON.stringify({
		"mode": mode, "start": level_start, "count": level_count,
		"sweep": sweep, "seed": seed, "start_offset": start_offset,
		"decision_jitter": decision_jitter,
		"wall_s": snappedf(wall, 0.001), "results": _results}))
	if _fails == 0:
		print("SHARD_PASS")
	else:
		print("SHARD_FAIL count=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _run_struct() -> void:
	for lvl in range(Game.LEVEL_COUNT):
		Game.level_index = lvl
		var lg := Node3D.new()
		lg.set_script(load("res://LevelGen.gd"))
		add_child(lg)
		await get_tree().process_frame
		var spawn_ok := _finite3(lg.spawn_point)
		var goal_ok := _finite3(lg.goal_pos)
		_expect(spawn_ok, "L%d spawn finite %s" % [lvl, lg.spawn_point])
		_expect(goal_ok, "L%d goal finite %s" % [lvl, lg.goal_pos])
		_expect(lg.nav.size() > 0, "L%d nav non-empty (%d)" % [lvl, lg.nav.size()])
		_expect(lg.checkpoints.size() >= 1, "L%d checkpoints>=1 (%d)" % [lvl, lg.checkpoints.size()])
		_expect(lg.kill_y < lg.spawn_point.y, "L%d kill_y below spawn (%.1f<%.1f)" % [lvl, lg.kill_y, lg.spawn_point.y])
		_expect(lg.goal_pos.distance_to(lg.spawn_point) > 3.0, "L%d goal separated from spawn")
		var last: Vector3 = lg.nav[lg.nav.size() - 1]["pos"]
		_expect(last.distance_to(lg.goal_pos) < 8.0, "L%d last nav near goal (%.2f)" % [lvl, last.distance_to(lg.goal_pos)])
		var ok: bool = spawn_ok and goal_ok and lg.nav.size() > 0 and lg.checkpoints.size() >= 1 \
			and lg.kill_y < lg.spawn_point.y and lg.goal_pos.distance_to(lg.spawn_point) > 3.0 \
			and last.distance_to(lg.goal_pos) < 8.0
		_results.append({"level": lvl, "name": lg.cfg["name"], "mode": "struct",
			"result": ("STRUCT_PASS" if ok else "STRUCT_FAIL"),
			"nav": lg.nav.size(), "checkpoints": lg.checkpoints.size(), "coins": lg.coin_total})
		print("LEVEL_RESULT " + JSON.stringify(_results[_results.size() - 1]))
		lg.queue_free()
		await get_tree().process_frame


func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _run_level(lvl: int, seed: int, start_offset: int, decision_jitter: int) -> void:
	Game.level_index = lvl
	var harness: Node3D = load("res://tools/level_harness.tscn").instantiate()
	add_child(harness)
	await get_tree().process_frame
	var level: Node3D = harness.get_node("LevelGen")
	var player: CharacterBody3D = harness.get_node("Player")
	var hud: CanvasLayer = harness.get_node("HUD")
	var cam: Camera3D = harness.get_node("CameraRig")
	cam.make_current()  # declared setup: guarantee camera-relative basis
	var cap: float = maxf(float(level.cfg["par"]), BOT_TIME[lvl]) + MARGIN
	_finished = false
	_final_time = 0.0
	level.finished.connect(_on_level_finished)
	var planner: L1Planner = null
	if mode == "clear":
		# L0-clear: headless Player._ready enables the waypoint autopilot.
		# Declared L0 setup -- the bot drives, not real events.
		_expect(player.autopilot, "L%d L0-clear autopilot enabled (headless)" % lvl)
	else:
		# L1: declared setup -- disable autopilot, real events drive.
		player.autopilot = false
		planner = L1Planner.new()
		add_child(planner)
		planner.setup(level, player, hud)
		planner.start_offset = start_offset
		planner.decision_jitter = decision_jitter
		planner._rng.seed = seed * 1000 + lvl
		if mode == "l1_neg_stick":
			planner._neg_stick = true
		elif mode == "l1_neg_jump":
			planner._neg_jump = true
		elif mode == "l1_fall":
			planner._deliberate_fall = true
	# Spawn is 1.5 units above the pad: wait for landing (<=2s sim).
	var gw := 0
	while not player.is_on_floor() and gw < 120:
		await get_tree().physics_frame
		gw += 1
	var sim_t := 0.0
	var delta := get_physics_process_delta_time()
	var falls0: int = hud.falls
	while not _finished and sim_t < cap:
		await get_tree().physics_frame
		sim_t += delta
		if mode != "clear" and player.autopilot:
			_expect(false, "L%d autopilot re-enabled during L1 (guard)" % lvl)
		if planner != null:
			planner.step()
		if float(Time.get_ticks_msec() - _wall0) / 1000.0 > SHARD_WATCHDOG:
			_expect(false, "shard wall watchdog exceeded (%.0fs)" % SHARD_WATCHDOG)
			break
	var falls: int = hud.falls - falls0
	var lname: String = level.cfg["name"]
	var ok: bool
	if mode == "l1_neg_stick" or mode == "l1_neg_jump":
		ok = not _finished
		_expect(ok, "L%d %s NEGATIVE: traversal correctly failed (finished=%s)" % [lvl, lname, _finished])
	else:
		ok = _finished
		_expect(ok, "L%d %s cleared within cap (finished=%s sim_t=%.2f cap=%.1f falls=%d)" % [lvl, lname, _finished, sim_t, cap, falls])
	if mode == "l1_fall":
		_expect(falls >= 1, "L%d deliberate-fall recovery: falls>=1 (got %d) then cleared" % [lvl, falls])
	var tag := "L1_PASS"
	if mode == "clear":
		tag = "CLEAR_PASS"
	elif mode == "l1_fall":
		tag = "FALL_PASS"
	elif mode == "l1_neg_stick" or mode == "l1_neg_jump":
		tag = "NEG_PASS"
	_results.append({"level": lvl, "name": lname, "mode": mode,
		"result": (tag if ok else "FAIL"),
		"sim_time": snappedf(sim_t, 0.01), "cap": cap, "falls": falls,
		"finished": _finished, "final_time": snappedf(_final_time, 0.01), "attempt": 1})
	print("LEVEL_RESULT " + JSON.stringify(_results[_results.size() - 1]))
	# Retry reset: release all touch, flush buffered events, fresh subtree next.
	if planner != null:
		planner.cleanup()
		planner.queue_free()
	Input.flush_buffered_events()
	harness.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame