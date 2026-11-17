class_name L1Planner
extends Node
## W1 L1 test-only planner (P1+P2 plan v4.17 W1). Drives the player through
## REAL input events only: idx0 joystick ScreenTouch/Drag (window coords via
## get_screen_transform) + idx1 JumpButton ScreenTouch on the real J rect.
## Reads nav + player pos + camera basis; outputs a desired world direction +
## jump edges. ZERO writes to player internals (reads of _jumps_left /
## _last_checkpoint are read-only). Mirrors Player._autopilot_think decision
## logic but expresses it as joystick deflection + J tap edges, so the whole
## Godot input pipeline (HUD._unhandled_input routing, Joystick math,
## JumpButton GUI, Input action, Player wish/buffer) is exercised for real.
##
## Respawn re-sync is planner-owned (F6: Player.respawn only re-syncs the nav
## cursor when autopilot=true; L1 runs autopilot=false). Subscribes fell +
## checkpoint_reached, re-attaches its own waypoint cursor on fell, counts
## falls. No wall-clock reads anywhere (F7 determinism): decisions advance on
## physics frames; jitter (start offset / decision spacing) is planner-only
## and seeded, never touches game physics.

const LOOK_AHEAD := 1.1        # floor-ray lead: bot 1.0 + ~1 frame input delay
const KNOB_MAX := 108.0        # == Joystick.KNOB_MAX
const DEADZONE := 0.12         # == Joystick.DEADZONE
const J_HOLD_FRAMES := 2       # hold J >=1 physics frame so just_pressed lands

var level: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var joy: Joystick
var jb: Button

var _cursor := 0
var _falls := 0
var _stuck_t := 0.0
var _stick_down := false
var _j_down := false
var _j_hold := 0
var _jump_cooldown := 0
var _last_finger := Vector2.ZERO
var _last_w := Vector3.ZERO
var _frame := 0
var _next_decision := 0

# planner-only jitter (recorded in evidence; never alters game physics)
var start_offset := 0
var decision_jitter := 0
var _rng := RandomNumberGenerator.new()

# fixture switches
var _neg_stick := false        # route stick to invalid coords -> no movement
var _neg_jump := false         # route J to invalid coords -> no jump
var _deliberate_fall := false  # drive off the start pad to force a fall


func setup(p_level: Node3D, p_player: CharacterBody3D, p_hud: CanvasLayer) -> void:
	level = p_level
	player = p_player
	hud = p_hud
	joy = hud.get("_joy") as Joystick
	jb = hud.get("_jump_button") as Button
	player.fell.connect(_on_fell)
	player.checkpoint_reached.connect(_on_checkpoint)
	_rng.seed = 0


func _on_fell() -> void:
	_falls += 1
	# Re-attach the waypoint cursor to the nav point nearest the checkpoint we
	# fell back to (mirrors Player.respawn autopilot re-sync, planner-owned).
	var cp: Vector3 = player._last_checkpoint
	var best := 0
	var best_d := 1e20
	for i in range(level.nav.size()):
		var d: float = level.nav[i]["pos"].distance_to(cp)
		if d < best_d:
			best_d = d
			best = i
	_cursor = best
	_stuck_t = 0.0


func _on_checkpoint(_pos: Vector3) -> void:
	# Checkpoints never move the nav cursor forward (nav is forward-only);
	# observed for fall-budget accounting. Re-sync happens on fell.
	pass


func _win(canvas_pos: Vector2) -> Vector2:
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


func _j_center() -> Vector2:
	return jb.get_global_rect().get_center()


func _basis() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var fwd := player.global_position - cam.global_position
	fwd.y = 0.0
	if fwd.length() <= 0.01:
		return {}
	fwd = fwd.normalized()
	return {"fwd": fwd, "right": fwd.cross(Vector3.UP)}


## Called once per physics frame by the runner (after physics_frame). Reads
## the post-physics state and emits events consumed on the NEXT frame.
func step() -> void:
	_frame += 1
	# J hold/release bookkeeping (real press/release edges).
	if _j_down:
		_j_hold -= 1
		if _j_hold <= 0:
			_touch(1, _j_center(), false)
			_j_down = false
			_jump_cooldown = 2
	if _jump_cooldown > 0:
		_jump_cooldown -= 1
	if _frame <= start_offset:
		return
	# Deliberate-fall fixture: steer hard off the start pad until we fall.
	if _deliberate_fall and _falls == 0:
		var b := _basis()
		if not b.is_empty():
			_apply_stick(b["right"])
		return
	# Decision scheduling (jitter perturbs decision timing only).
	if _frame < _next_decision:
		_apply_stick(_last_w)
		return
	var extra := 0
	if decision_jitter > 0:
		extra = _rng.randi_range(0, decision_jitter)
	_next_decision = _frame + 1 + extra
	var w := _think()
	_last_w = w
	_apply_stick(w)


func _think() -> Vector3:
	var target: Vector3 = level.goal_pos
	var have_nav: bool = _cursor < level.nav.size()
	if have_nav:
		var n: Dictionary = level.nav[_cursor]
		target = n["pos"]
		if n["kind"] == "mover" and n["ref"] != null:
			target = (n["ref"] as Node3D).global_position + Vector3(0, 0.6, 0)
		if n["kind"] == "vanish" and player.is_on_floor():
			if not level.vanish_solid(n["ref"]) or level.vanish_remaining(n["ref"]) < 1.0:
				return Vector3.ZERO
	var to := target - player.position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 1.3 and absf(to.y) < 2.5:
		if have_nav:
			_cursor += 1
			_stuck_t = 0.0
			return Vector3.ZERO
	var w := flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	# Jump decisions (read-only mirror of the bot; _jumps_left is read, never
	# written). Real J tap edges replace the bot's direct _buffer write.
	var sp := player.get_world_3d().direct_space_state
	var want_jump := false
	if player.is_on_floor():
		var from := player.position + w * LOOK_AHEAD + Vector3(0, -0.4, 0)
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -2.5, 0)))
		var need_up := target.y > player.position.y + 0.8 and flat.length() < 4.0
		if hit.is_empty() or need_up:
			want_jump = true
	elif player.velocity.y < -2.0 and player._jumps_left > 0:
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(player.position, player.position + Vector3(0, -3.5, 0)))
		var ahead := player.position + Vector3(player.velocity.x, 0.0, player.velocity.z) * 0.35
		var hit_ahead := sp.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3(0, -3.5, 0)))
		if hit.is_empty() and hit_ahead.is_empty():
			want_jump = true
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	if w.length() > 0.1 and hspeed < 0.5:
		_stuck_t += get_physics_process_delta_time()
	else:
		_stuck_t = 0.0
	if _stuck_t > 2.0:
		want_jump = true
		_stuck_t = 0.0
	if want_jump and not _j_down and _jump_cooldown <= 0:
		_tap_j()
	return w


func _tap_j() -> void:
	var c := _j_center()
	if _neg_jump:
		c = get_viewport().get_visible_rect().size * 0.5
	_touch(1, c, true)
	_j_down = true
	_j_hold = J_HOLD_FRAMES


func _apply_stick(w: Vector3) -> void:
	# Inverse F13 basis: d2.x = w.right, d2.y = -(w.fwd), clamp <= 1.
	var d2 := Vector2.ZERO
	var b := _basis()
	if not b.is_empty() and w.length() > 0.01:
		d2 = Vector2(w.dot(b["right"]), -w.dot(b["fwd"]))
		if d2.length() > 1.0:
			d2 = d2.normalized()
	# Desired joystick output = d2. Invert Joystick.compute_output:
	# knob = dir * KNOB_MAX * (DEADZONE + (1-DEADZONE)*|d2|).
	var knob := Vector2.ZERO
	if d2.length() > 0.001:
		knob = d2.normalized() * KNOB_MAX * (DEADZONE + (1.0 - DEADZONE) * d2.length())
	var finger_canvas := joy.get_global_transform_with_canvas() * (joy.home_center + knob)
	if _neg_stick:
		finger_canvas = Vector2(5, 5)  # top-left: outside zone AND grab radius
	_last_finger = finger_canvas
	if not _stick_down:
		_touch(0, finger_canvas, true)
		_stick_down = true
	else:
		_drag(0, finger_canvas)


func cleanup() -> void:
	if _stick_down:
		_touch(0, _last_finger, false)
		_stick_down = false
	if _j_down:
		_touch(1, _j_center(), false)
		_j_down = false
	if joy != null:
		joy.force_release()