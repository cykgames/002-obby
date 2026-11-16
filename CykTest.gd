extends Node
## Debug state telemetry for the cykgames release harness (L2 state asserts).
## Prints "[CYKTEST] {json}" every 0.25 s so `adb logcat -d | findstr CYKTEST`
## can prove: run gate passed, HUD timer monotonic, stick output responds to
## injected drags, player actually displaces, stick settles after release.
## Pixel diffs alone never prove touch -- this channel does (harness A6).
## Read-only: never writes saves, never touches gameplay state.
## Author: cykbot9 (AI agent).

const PERIOD := 0.25
var _acc := 0.0


func _process(delta: float) -> void:
	_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	var d := {
		"ts": Time.get_unix_time_from_system(),
		"ms": Time.get_ticks_msec(),
	}
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
	print("[CYKTEST] " + JSON.stringify(d))