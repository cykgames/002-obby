extends Node
## W1-P0 preflight (P1+P2 plan v4.2): two-finger J-button causality through
## the REAL GUI event path. JumpButton extends Button (JumpButton.gd), so a
## second finger (idx1) must reach it via touch->mouse GUI emulation while
## idx0 holds the joystick (HUD._unhandled_input). Single-pointer emulation
## cross-talk is the risk this spike proves or disproves BEFORE any L1 shard
## work. Assertions (plan W1-P0):
##   (i)   idx1 press on the real J rect -> Input.is_action_pressed("jump")
##   (ii)  jumped / double_jumped signal fires
##   (iii) jump stays pressed across >=10 physics frames INCLUDING stick
##         drag and stick lift (negative fixture: stick lift while J held
##         must NOT release jump)
##   (iv)  J lift -> action released
## Plus: invalid-coordinate J press produces no jump (negative control),
## stick settles to zero, no residual jump, save file hash unchanged, and a
## headless fixed-fps throughput measurement (physics steps per wall second)
## for the W1 wall-budget derivation.
## Harness-owned subtree (LevelGen+Player+CameraRig+HUD, NO Main.gd): the
## finish/save/auto-reload orchestration is never attached.
## Run: Godot --headless --fixed-fps 60 --path . res://tools/test_jump_preflight.tscn

var _fails := 0
var _jumped_n := 0
var _double_n := 0
var _level: Node3D
var _player: CharacterBody3D
var _hud: CanvasLayer
var _joy: Joystick
var _jb: Button
var _save_before := ""


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("PREFLIGHT_OK: ", what)
	else:
		_fails += 1
		print("PREFLIGHT_FAIL: ", what)


func _save_sig() -> String:
	if not FileAccess.file_exists(Game.SAVE_PATH):
		return "absent"
	return FileAccess.get_file_as_bytes(Game.SAVE_PATH).hex_encode()


func _win(canvas_pos: Vector2) -> Vector2:
	# Contract: window coordinates, never design coordinates.
	return get_viewport().get_screen_transform() * canvas_pos


func _touch(idx: int, canvas_pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = _win(canvas_pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, canvas_pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = _win(canvas_pos)
	Input.parse_input_event(e)


func _joy_home_canvas() -> Vector2:
	return _joy.get_global_transform_with_canvas() * _joy.home_center


func _j_center_canvas() -> Vector2:
	return _jb.get_global_rect().get_center()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
		# guard: the headless autopilot must stay disabled for the whole
		# preflight -- input, not the bot, drives the player.
		if _player != null and _player.autopilot:
			_fails += 1
			print("PREFLIGHT_FAIL: autopilot re-enabled during test")


func _ready() -> void:
	get_window().size = Vector2i(1080, 2340)
	Game.level_index = 0
	_save_before = _save_sig()

	# --- harness-owned subtree: level_harness.tscn = Main.tscn minus
	# Main.gd/Audio (no finish/save/auto-reload orchestration). Scene
	# instantiation guarantees sibling-complete _ready ordering. ---
	var harness: Node3D = load("res://tools/level_harness.tscn").instantiate()
	add_child(harness)
	await get_tree().process_frame
	_level = harness.get_node("LevelGen")
	_player = harness.get_node("Player")
	_hud = harness.get_node("HUD")

	# Explicit initial setup (declared, not hidden): headless Player._ready
	# enables the waypoint autopilot; L1/preflight must drive REAL events, so
	# disable it. HUD headless _ready already called start_run().
	_player.autopilot = false
	_joy = _hud.get("_joy") as Joystick
	_jb = _hud.get("_jump_button") as Button
	_expect(_joy != null and _jb != null, "HUD controls exist")
	_expect(_hud.started and _hud.running, "run gate auto-started (headless HUD)")
	# spawn is 1.5 units above the pad: wait for the landing (<=1.5s sim).
	var gw := 0
	while not _player.is_on_floor() and gw < 90:
		await _frames(1)
		gw += 1
	_expect(_player.is_on_floor(), "player grounded at spawn")
	_player.jumped.connect(func(): _jumped_n += 1)
	_player.double_jumped.connect(func(): _double_n += 1)
	await _frames(3)
	_expect(not Input.is_action_pressed("jump"), "baseline: jump not pressed")
	_expect(_jumped_n == 0 and _double_n == 0, "baseline: no jump signals")

	# --- idx0 grabs the joystick (real ScreenTouch, window coords) ---
	var home := _joy_home_canvas()
	_touch(0, home, true)
	await _frames(2)
	_expect(_joy.active and _joy.touch_index() == 0, "idx0 press grabs joystick")

	# --- (i) idx1 presses the REAL J rect while idx0 holds the stick ---
	_touch(1, _j_center_canvas(), true)
	await _frames(2)
	_expect(Input.is_action_pressed("jump"), "(i) J press -> jump action pressed")

	# --- (ii) jump signal fires (grounded spawn -> jumped) ---
	var waited := 0
	while _jumped_n + _double_n == 0 and waited < 30:
		await _frames(1)
		waited += 1
	_expect(_jumped_n + _double_n >= 1,
		"(ii) jumped/double_jumped fired (jumped=%d double=%d)" % [_jumped_n, _double_n])

	# --- (iii) hold >=10 frames WITH stick drag, then stick lift ---
	var held_ok := true
	var steer := home + Vector2(80, 0)
	for i in range(12):
		if i == 3:
			_drag(0, steer)
		await _frames(1)
		if not Input.is_action_pressed("jump"):
			held_ok = false
	_expect(held_ok, "(iii-a) jump held across 12 frames incl. stick drag")
	_expect(_joy.output.length() > 0.3, "stick drag produced steering output")
	_expect(_player.input_dir.length() > 0.3, "steering reached player.input_dir")
	# negative fixture: lifting the STICK while J is held must not release jump
	_touch(0, steer, false)
	await _frames(4)
	_expect(Input.is_action_pressed("jump"),
		"(iii-b) NEGATIVE FIXTURE: stick lift while J held keeps jump pressed")
	_expect(_joy.output == Vector2.ZERO and _joy.touch_index() == -1,
		"stick released and settled to zero")

	# --- (iv) J lift releases the action ---
	_touch(1, _j_center_canvas(), false)
	await _frames(3)
	_expect(not Input.is_action_pressed("jump"), "(iv) J lift -> jump released")

	# --- negative control: press far outside J effective radius ---
	var jumps_before := _jumped_n + _double_n
	var vr := get_viewport().get_visible_rect().size
	_touch(1, vr * 0.5, true)
	await _frames(6)
	_expect(not Input.is_action_pressed("jump"),
		"negative control: invalid J coordinate does not press jump")
	_expect(_jumped_n + _double_n == jumps_before,
		"negative control: invalid J coordinate fires no jump signal")
	_touch(1, vr * 0.5, false)
	await _frames(2)

	# --- cleanup: no residual input ---
	Input.flush_buffered_events()
	_joy.force_release()
	await _frames(2)
	_expect(_joy.output == Vector2.ZERO, "cleanup: stick zero")
	_expect(not Input.is_action_pressed("jump"), "cleanup: no residual jump")

	# --- save isolation: harness-owned subtree never writes progress ---
	_expect(_save_sig() == _save_before, "save hash unchanged (no Main orchestration)")

	# --- throughput: physics steps per wall second at --fixed-fps 60 ---
	# Measurement only (harness budget derivation), never a planner decision.
	var t0 := Time.get_ticks_msec()
	var n := 0
	while n < 1200:
		await get_tree().physics_frame
		n += 1
	var wall := float(Time.get_ticks_msec() - t0) / 1000.0
	var sps := float(n) / maxf(wall, 0.001)
	print("THROUGHPUT physics_steps=%d wall_s=%.3f steps_per_s=%.1f sim_delta=%.5f"
		% [n, wall, sps, get_physics_process_delta_time()])

	if _fails == 0:
		print("PREFLIGHT_PASS")
	else:
		print("PREFLIGHT_FAIL count=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)