extends Node3D
class_name LevelGen
## Data-driven obby course builder: 16 levels (4 worlds x 4), parkour-style
## LEVELS table. A cursor walks a 4-direction path; steps place pads/hazards.
## Static terrain: one StaticBody3D + chunked ArrayMesh (vertex colors).
## Mechanics: moving platforms (AnimatableBody3D), lava (Area3D kill),
## bounce pads, vanish blocks, rotating bars (spinners), ice (low friction).
## Checkpoints: proximity + grounded only (W7 lesson: never skip forward).

const VOXEL := 1.0
const CHUNK := 16.0
const THICK := 1.0
const MOVER_SIZE := 3.0
const DIRS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]

const THEMES := [
	{
		"name": "MEADOW",
		"grass": Color(0.35, 0.75, 0.25), "dirt": Color(0.45, 0.30, 0.15),
		"stone": Color(0.55, 0.55, 0.58), "mover_col": Color(0.7, 0.5, 0.2),
		"sky_top": Color(0.30, 0.55, 0.95), "sky_horizon": Color(0.65, 0.78, 0.92),
		"sun": Color(1.0, 0.96, 0.85), "sun_rot": Vector3(-50, -30, 0),
	},
	{
		"name": "CANYON",
		"grass": Color(0.85, 0.62, 0.32), "dirt": Color(0.60, 0.38, 0.18),
		"stone": Color(0.70, 0.45, 0.28), "mover_col": Color(0.45, 0.30, 0.55),
		"sky_top": Color(0.85, 0.45, 0.25), "sky_horizon": Color(0.95, 0.72, 0.45),
		"sun": Color(1.0, 0.80, 0.55), "sun_rot": Vector3(-35, -45, 0),
	},
	{
		"name": "FROST",
		"grass": Color(0.78, 0.88, 0.98), "dirt": Color(0.45, 0.55, 0.70),
		"stone": Color(0.60, 0.70, 0.82), "mover_col": Color(0.30, 0.65, 0.80),
		"sky_top": Color(0.10, 0.14, 0.30), "sky_horizon": Color(0.35, 0.45, 0.65),
		"sun": Color(0.75, 0.85, 1.0), "sun_rot": Vector3(-60, 20, 0),
	},
	{
		"name": "VOLCANO",
		"grass": Color(0.30, 0.22, 0.24), "dirt": Color(0.16, 0.12, 0.14),
		"stone": Color(0.40, 0.28, 0.28), "mover_col": Color(0.95, 0.45, 0.10),
		"sky_top": Color(0.12, 0.04, 0.07), "sky_horizon": Color(0.65, 0.22, 0.10),
		"sun": Color(1.0, 0.60, 0.30), "sun_rot": Vector3(-40, -20, 0),
	},
]

## Steps: P=pad(w,l,dy) G=gap(d) L=lava(d) M=mover(d) B=bounce V=vanish(n)
##        S=spinner(w) I=ice(w,l) T=turn(+1 right / -1 left)
## Start pad (6x6) and goal pad (6x6) are added automatically.
const LEVELS := [
	{"name": "FIRST STEPS", "world": 0, "par": 40.0, "steps": [
		["G", 2.5], ["P", 4, 10], ["G", 3.0], ["P", 4, 10], ["G", 3.5], ["P", 4, 10]]},
	{"name": "LAVA HOP", "world": 0, "par": 45.0, "steps": [
		["G", 2.5], ["P", 4, 10], ["L", 3.0], ["P", 4, 10], ["G", 3.0],
		["P", 4, 10], ["L", 3.5], ["P", 4, 10]]},
	{"name": "BOUNCE HOUSE", "world": 0, "par": 50.0, "steps": [
		["G", 2.5], ["P", 4, 8], ["B"], ["G", 2.5], ["P", 4, 6, 2], ["G", 3.0],
		["P", 4, 8, -2], ["B"], ["G", 2.5], ["P", 4, 6, 2], ["G", 2.5], ["P", 4, 8, -2]]},
	{"name": "MOVING ON", "world": 0, "par": 55.0, "steps": [
		["G", 2.5], ["P", 4, 8], ["M", 6.5], ["P", 4, 8], ["G", 3.0],
		["P", 4, 8], ["M", 6.5], ["P", 4, 8]]},
	{"name": "VANISH PATH", "world": 1, "par": 55.0, "steps": [
		["G", 2.5], ["P", 4, 8], ["V", 3], ["P", 4, 8], ["G", 3.0],
		["P", 4, 8], ["V", 3], ["P", 4, 8]]},
	{"name": "SPIN ZONE", "world": 1, "par": 60.0, "steps": [
		["G", 2.5], ["P", 4, 6], ["S", 7], ["G", 3.0], ["P", 4, 6],
		["S", 7], ["G", 3.5], ["P", 4, 8]]},
	{"name": "ICE SLIDE", "world": 1, "par": 60.0, "steps": [
		["G", 2.5], ["I", 4, 10], ["G", 3.0], ["P", 4, 8], ["I", 4, 10],
		["G", 3.5], ["P", 4, 8]]},
	{"name": "CANYON MIX", "world": 1, "par": 65.0, "steps": [
		["G", 2.5], ["P", 4, 4], ["L", 3.0], ["P", 4, 6], ["M", 6.5], ["P", 4, 4],
		["B"], ["G", 2.5], ["P", 4, 6, 2], ["G", 2.5], ["P", 4, 8, -2]]},
	{"name": "FROST VANISH", "world": 2, "par": 65.0, "steps": [
		["G", 2.5], ["I", 4, 8], ["V", 3], ["P", 4, 8], ["G", 3.0],
		["I", 4, 8], ["V", 3], ["P", 4, 8]]},
	{"name": "SKY SPIN", "world": 2, "par": 70.0, "steps": [
		["G", 2.5], ["P", 4, 4, 1], ["S", 7], ["M", 6.5], ["P", 4, 6, 1],
		["S", 7], ["G", 3.0], ["P", 4, 8]]},
	{"name": "LAVA GAUNTLET", "world": 2, "par": 70.0, "steps": [
		["G", 2.5], ["P", 4, 6], ["L", 3.5], ["P", 4, 4], ["B"], ["G", 2.5],
		["P", 4, 6, 2], ["V", 3], ["P", 4, 6, -2], ["L", 3.5], ["P", 4, 8]]},
	{"name": "FINAL CLIMB", "world": 2, "par": 80.0, "steps": [
		["G", 2.5], ["P", 4, 4], ["T", 1], ["G", 3.0], ["P", 4, 6], ["M", 6.5],
		["P", 4, 4], ["T", 1], ["L", 3.0], ["P", 4, 6], ["S", 7], ["B"],
		["G", 2.5], ["P", 4, 6, 2], ["G", 2.5], ["P", 4, 4, -2]]},
	{"name": "EMBER HOP", "world": 3, "par": 70.0, "steps": [
		["G", 2.5], ["P", 4, 6], ["L", 3.0], ["P", 4, 6], ["L", 3.5],
		["P", 4, 6], ["G", 3.0], ["P", 4, 8], ["L", 3.0], ["P", 4, 6]]},
	{"name": "MAGMA RUN", "world": 3, "par": 75.0, "steps": [
		["G", 2.5], ["P", 4, 6], ["M", 6.5], ["P", 4, 4], ["L", 3.0], ["P", 4, 6],
		["M", 6.5], ["P", 4, 4], ["B"], ["G", 2.5], ["P", 4, 6, 2], ["G", 2.5], ["P", 4, 8, -2]]},
	{"name": "CRUMBLE PEAK", "world": 3, "par": 80.0, "steps": [
		["G", 2.5], ["I", 4, 8], ["V", 3], ["P", 4, 6], ["S", 7], ["G", 3.0],
		["P", 4, 6], ["V", 3], ["I", 4, 8], ["P", 4, 8]]},
	{"name": "ERUPTION", "world": 3, "par": 90.0, "steps": [
		["G", 2.5], ["P", 4, 4], ["T", 1], ["G", 3.0], ["P", 4, 6], ["L", 3.0],
		["P", 4, 4], ["M", 6.5], ["P", 4, 4], ["T", 1], ["S", 7], ["B"],
		["G", 2.5], ["P", 4, 6, 2], ["G", 2.5], ["P", 4, 6, -2], ["L", 3.0], ["P", 4, 8]]},
]

var cfg: Dictionary
var theme: Dictionary
var spawn_point := Vector3(0, 1.5, -3)
var goal_pos := Vector3.ZERO
var kill_y := -12.0
var checkpoints: Array[Vector3] = []
var nav: Array = []          # {pos, kind, ref} waypoints for the headless bot
var movers: Array = []
var spinners: Array = []
var vanish_blocks: Array = []
var flags: Array = []        # {pos, mat} checkpoint flag visuals
var coin_total := 0
var time := 0.0

var _cursor := Vector3.ZERO
var _dir := 0
var _min_top := 0.0
var _boxes: Array = []
var _terrain_body: StaticBody3D

signal finished(final_time: float)
signal coin_taken(pos: Vector3)


func _ready() -> void:
	cfg = LEVELS[clampi(Game.level_index, 0, LEVELS.size() - 1)]
	theme = THEMES[int(cfg["world"])]
	_pad(6, 6, 0, "start")
	for step in cfg["steps"]:
		_do_step(step)
	_pad(6, 6, 0, "goal")
	_build_collision()
	_build_chunk_meshes()
	_build_decorations()
	_build_light()
	kill_y = _min_top - 12.0


func _do_step(s: Array) -> void:
	match String(s[0]):
		"P": _pad(float(s[1]), float(s[2]), float(s[3]) if s.size() > 3 else 0.0, "normal")
		"I": _pad(float(s[1]), float(s[2]), 0.0, "ice")
		"G": _cursor += DIRS[_dir] * float(s[1])
		"L": _lava(float(s[1]))
		"M": _mover(float(s[1]))
		"B": _pad(3, 3, 0, "bounce")
		"V": _vanish(int(s[1]))
		"S": _spinner(float(s[1]))
		"T": _dir = (_dir + int(s[1]) + 4) % 4


func _pad(w: float, l: float, dy: float, kind: String) -> void:
	var dir := DIRS[_dir]
	var right := DIRS[(_dir + 1) % 4]
	var top := _cursor.y + dy
	var center := _cursor + dir * (l / 2.0) + Vector3(0, top - THICK / 2.0, 0)
	var size := Vector3(
		absf(right.x) * w + absf(dir.x) * l, THICK,
		absf(right.z) * w + absf(dir.z) * l)
	_min_top = minf(_min_top, top)
	if kind == "ice" or kind == "bounce":
		_build_special_pad(center, size, kind)
	else:
		_boxes.append({"min": center - size / 2.0, "size": size, "gold": kind == "goal"})
	if kind == "start":
		spawn_point = center + Vector3(0, THICK / 2.0 + 1.5, 0)
		checkpoints.append(spawn_point)
		_build_flag(spawn_point)
	elif kind == "goal":
		goal_pos = center + Vector3(0, THICK / 2.0 + 1.5, 0)
		_build_finish_gate(center + Vector3(0, THICK / 2.0, 0))
	elif l >= 5.0:
		var cp := _cursor + dir * 1.5 + Vector3(0, dy + 1.5, 0)
		if checkpoints.is_empty() or cp.distance_to(checkpoints.back()) > 5.0:
			checkpoints.append(cp)
			_build_flag(cp)
	nav.append({"pos": _cursor + dir * (l / 2.0) + Vector3(0, dy + 0.6, 0), "kind": kind, "ref": null})
	# Coins sit mid-pad (away from the jump takeoff zone at the far edge) so
	# they are collectible on foot; short/bounce pads get none.
	if kind != "start" and kind != "goal" and kind != "bounce":
		if l >= 8.0:
			_spawn_coin(self, _cursor + dir * (l * 0.3) + Vector3(0, dy + 0.9, 0))
			_spawn_coin(self, _cursor + dir * (l * 0.6) + Vector3(0, dy + 0.9, 0))
		elif l >= 6.0:
			_spawn_coin(self, _cursor + dir * (l * 0.6) + Vector3(0, dy + 0.9, 0))
	_cursor += dir * l
	_cursor.y = top


func _lava(d: float) -> void:
	var dir := DIRS[_dir]
	var right := DIRS[(_dir + 1) % 4]
	var center := _cursor + dir * (d / 2.0) + Vector3(0, -1.0, 0)
	var size := Vector3(
		absf(right.x) * 10.0 + absf(dir.x) * d, 0.5,
		absf(right.z) * 10.0 + absf(dir.z) * d)
	var area := Area3D.new()
	area.name = "Lava"
	area.add_to_group("lava")
	area.position = center
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	area.add_child(col)
	area.body_entered.connect(_on_lava_entered)
	add_child(area)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.30, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.25, 0.02)
	mat.emission_energy_multiplier = 1.4
	mat.roughness = 0.6
	mi.material_override = mat
	add_child(mi)
	_cursor += dir * d


func _on_lava_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("respawn"):
		body.respawn()


func _mover(d: float) -> void:
	var dir := DIRS[_dir]
	var right := DIRS[(_dir + 1) % 4]
	var center := _cursor + dir * (d / 2.0)
	var body := AnimatableBody3D.new()
	body.name = "Mover_%d" % movers.size()
	body.sync_to_physics = true
	body.position = center + Vector3(0, -THICK / 2.0, 0)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(MOVER_SIZE, THICK, MOVER_SIZE)
	col.shape = sh
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(MOVER_SIZE, THICK, MOVER_SIZE)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme["mover_col"]
	mat.roughness = 0.7
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	movers.append({"body": body, "center": center, "axis": right,
		"amp": 2.5, "period": 3.5, "phase": float(movers.size()) * 1.3})
	nav.append({"pos": center + Vector3(0, 0.6, 0), "kind": "mover", "ref": body})
	_spawn_coin(body, Vector3(0, THICK / 2.0 + 1.0, 0))
	_cursor += dir * d


func _vanish(n: float) -> void:
	var dir := DIRS[_dir]
	for i in range(int(n)):
		var c := _cursor + dir * (1.2 + 2.2 * i)
		var body := StaticBody3D.new()
		body.name = "Vanish_%d" % vanish_blocks.size()
		body.position = c + Vector3(0, -0.25, 0)
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(2, 0.5, 2)
		col.shape = sh
		body.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2, 0.5, 2)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.55, 0.95)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.5
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)
		var v := {"body": body, "col": col, "mat": mat,
			"period": 3.2, "solid": 2.0, "phase": -float(i) * 0.35, "is_solid": true}
		vanish_blocks.append(v)
		nav.append({"pos": c + Vector3(0, 0.6, 0), "kind": "vanish", "ref": v})
	_cursor += dir * (1.2 + 2.2 * (n - 1) + 1.2)


func _spinner(w: float) -> void:
	var dir := DIRS[_dir]
	var center := _cursor + dir * (w / 2.0)
	_pad(w, w, 0, "normal")
	var body := AnimatableBody3D.new()
	body.name = "Spinner_%d" % spinners.size()
	body.sync_to_physics = true
	body.position = center + Vector3(0, 0.55, 0)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w - 1.5, 0.5, 0.5)
	col.shape = sh
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w - 1.5, 0.5, 0.5)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.25, 0.25)
	mat.roughness = 0.6
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	spinners.append({"body": body, "speed": 1.3})
	# Visual-only center pole (no collision: it would block the path).
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.15
	cm.height = 1.4
	pole.mesh = cm
	pole.position = center + Vector3(0, 0.7, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = theme["stone"]
	pole.material_override = pm
	add_child(pole)


func _build_special_pad(center: Vector3, size: Vector3, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [kind.capitalize(), _special_count()]
	body.add_to_group(kind)
	body.position = center
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	if kind == "ice":
		mat.albedo_color = Color(0.65, 0.85, 0.98)
		mat.roughness = 0.12
		mat.metallic = 0.15
	else:
		mat.albedo_color = Color(1.0, 0.75, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.32, 0.02)
		mat.roughness = 0.5
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


var _special_n := 0
func _special_count() -> int:
	_special_n += 1
	return _special_n


func _build_flag(cp: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.7, 0.12)
	pole.mesh = bm
	pole.position = cp + Vector3(0, -0.65, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.85, 0.9)
	pole.material_override = pm
	add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.75, 0.45, 0.08)
	flag.mesh = fm
	flag.position = cp + Vector3(0.42, 0.55, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.25, 0.25)
	flag.material_override = mat
	add_child(flag)
	flags.append({"pos": cp, "mat": mat})


func activate_flag(cp: Vector3) -> void:
	for f in flags:
		if f["pos"].distance_to(cp) < 0.1:
			f["mat"].albedo_color = Color(0.25, 0.9, 0.35)
			return


func _build_collision() -> void:
	_terrain_body = StaticBody3D.new()
	_terrain_body.name = "TerrainBody"
	add_child(_terrain_body)
	for b in _boxes:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b["size"]
		col.shape = shape
		col.position = b["min"] + b["size"] / 2.0
		_terrain_body.add_child(col)


func _build_chunk_meshes() -> void:
	var chunk_quads := {}
	for b in _boxes:
		var mn: Vector3 = b["min"]
		var sz: Vector3 = b["size"]
		var gold: bool = b["gold"]
		var nx := int(sz.x / VOXEL)
		var nz := int(sz.z / VOXEL)
		for ix in range(nx):
			for iz in range(nz):
				var x0 := mn.x + ix * VOXEL
				var z0 := mn.z + iz * VOXEL
				var key := _chunk_key(x0, z0)
				if not chunk_quads.has(key):
					chunk_quads[key] = []
				(chunk_quads[key] as Array).append({"x0": x0, "z0": z0, "gold": gold, "y": mn.y + sz.y})
		var key0 := _chunk_key(mn.x, mn.z)
		if not chunk_quads.has(key0):
			chunk_quads[key0] = []
		(chunk_quads[key0] as Array).append({"side": true, "box_min": mn, "box_size": sz, "gold": gold})
	for key in chunk_quads:
		_build_single_mesh(key, chunk_quads[key])


func _chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))


func _build_single_mesh(key: Vector2i, quads: Array) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for q in quads:
		if q.has("side"):
			_emit_sides(verts, normals, colors, q["box_min"], q["box_size"], q["gold"])
		else:
			_emit_top(verts, normals, colors, q["x0"], q["z0"], q["gold"], q["y"])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [key.x, key.y]
	mi.mesh = mesh
	add_child(mi)


func _emit_top(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, x0: float, z0: float, gold: bool, y: float) -> void:
	var c: Color = Color(1.0, 0.8, 0.2) if gold else theme["grass"]
	var a := Vector3(x0, y, z0)
	var b := Vector3(x0 + VOXEL, y, z0)
	var cc := Vector3(x0 + VOXEL, y, z0 + VOXEL)
	var d := Vector3(x0, y, z0 + VOXEL)
	var n := Vector3.UP
	verts.append_array([a, b, cc, a, cc, d])
	for i in range(6):
		normals.append(n)
		colors.append(c)


func _emit_sides(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, mn: Vector3, sz: Vector3, gold: bool) -> void:
	var c: Color = Color(1.0, 0.8, 0.2) if gold else theme["dirt"]
	var y0 := mn.y
	var y1 := mn.y + sz.y
	var x0 := mn.x
	var x1 := mn.x + sz.x
	var z0 := mn.z
	var z1 := mn.z + sz.z
	_quads(verts, normals, colors, [Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1)], Vector3.LEFT, c)
	_quads(verts, normals, colors, [Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)], Vector3.RIGHT, c)
	_quads(verts, normals, colors, [Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1)], Vector3.BACK, c)
	_quads(verts, normals, colors, [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)], Vector3.FORWARD, c)


func _quads(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, corners: Array, n: Vector3, c: Color) -> void:
	verts.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	for i in range(6):
		normals.append(n)
		colors.append(c)


func _spawn_coin(parent: Node3D, lpos: Vector3) -> void:
	var coin := Area3D.new()
	coin.set_script(load("res://Coin.gd"))
	coin.position = lpos
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.55
	col.shape = sh
	coin.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 0.08
	cm.radial_segments = 16
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.42, 0.05)
	mat.metallic = 0.6
	mat.roughness = 0.3
	mi.material_override = mat
	coin.add_child(mi)
	coin.collected.connect(_on_coin_collected)
	parent.add_child(coin)
	coin_total += 1


func _on_coin_collected(pos: Vector3) -> void:
	coin_taken.emit(pos)


func _build_finish_gate(pad_top_center: Vector3) -> void:
	var area := Area3D.new()
	area.name = "GoalArea"
	area.position = pad_top_center + Vector3(0, 1.5, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 3, 6)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_goal_entered)
	add_child(area)
	for px in [-2.8, 2.8]:
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 4.0, 0.6)
		pillar.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.3, 0.05)
		pillar.material_override = mat
		pillar.position = pad_top_center + Vector3(px, 2.0, 0)
		add_child(pillar)


## Kenney Starter Kit decorations (CC0): grass tufts on pads, clouds above.
## Visual only -- no collision, physics stays on the proven voxel terrain.
func _build_decorations() -> void:
	var cloud_scene: PackedScene = null
	var grass_scene: PackedScene = null
	if ResourceLoader.exists("res://assets/cloud.glb"):
		cloud_scene = load("res://assets/cloud.glb")
	if ResourceLoader.exists("res://assets/grass.glb"):
		grass_scene = load("res://assets/grass.glb")
	for i in range(nav.size()):
		var p: Vector3 = nav[i]["pos"]
		if grass_scene != null and i % 2 == 0:
			var g := grass_scene.instantiate()
			g.position = p + Vector3(1.6, -0.6, 0.0)
			g.rotation.y = float(i) * 1.7
			var gs := 0.8 + 0.3 * absf(sin(float(i)))
			g.scale = Vector3(gs, gs, gs)
			add_child(g)
		if cloud_scene != null and i % 3 == 0:
			var c := cloud_scene.instantiate()
			c.position = p + Vector3(6.0 * sin(float(i) * 2.1), 11.0 + 2.0 * sin(float(i)), 6.0 * cos(float(i) * 1.3))
			var cs := 1.5 + 0.5 * absf(sin(float(i) * 0.7))
			c.scale = Vector3(cs, cs, cs)
			add_child(c)


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = theme["sun_rot"]
	sun.light_color = theme["sun"]
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme["sky_top"]
	sky_mat.ground_horizon_color = theme["sky_horizon"]
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.28)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.fog_enabled = true
	e.fog_light_color = theme["sky_horizon"]
	e.fog_density = 0.005
	env.environment = e
	add_child(env)


func _physics_process(delta: float) -> void:
	time += delta
	for m in movers:
		var off: float = m["amp"] * sin(TAU * time / m["period"] + m["phase"])
		m["body"].position = m["center"] + m["axis"] * off + Vector3(0, -THICK / 2.0, 0)
	for s in spinners:
		s["body"].rotation.y += s["speed"] * delta
	for v in vanish_blocks:
		var t := fmod(time + float(v["phase"]), float(v["period"]))
		var solid: bool = t < float(v["solid"])
		if solid != v["is_solid"]:
			v["is_solid"] = solid
			v["col"].set_deferred("disabled", not solid)
		var a := 0.15
		if solid:
			a = 0.55 if t > float(v["solid"]) - 0.4 else 1.0
		v["mat"].albedo_color.a = a


func _on_goal_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		finished.emit(_race_time())


func _race_time() -> float:
	var hud := get_node_or_null("../HUD")
	if hud != null and hud.has_method("get_time"):
		return hud.get_time()
	return 0.0


## Checkpoint activation: only when the player is grounded near it (W7 fix:
## respawn must go to the last checkpoint actually reached, never forward).
func checkpoint_at(pos: Vector3) -> Variant:
	for c in checkpoints:
		if absf(c.y - pos.y) < 3.0 and Vector2(c.x - pos.x, c.z - pos.z).length() < 2.5:
			return c
	return null


## Vanish block solid state + remaining solid time (headless bot timing).
func vanish_solid(v: Dictionary) -> bool:
	return v["is_solid"]


func vanish_remaining(v: Dictionary) -> float:
	var t := fmod(time + float(v["phase"]), float(v["period"]))
	return maxf(0.0, float(v["solid"]) - t) if t < float(v["solid"]) else 0.0
