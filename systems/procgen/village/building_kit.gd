class_name BuildingKit
extends RefCounted
## Builds village buildings and props from parts: stone foundations, plank
## walls with a timber frame, shingled gable roofs with ridge caps and barge
## boards, framed windows with shutters and window boxes, plank doors with
## steps and lanterns, chimneys with smoke, woodpiles and crop fields.
##
## Every building is built in its own local space: origin at ground level in
## the middle of the footprint, front door facing +Z. Collision shapes are
## collected in `shapes` as [Shape3D, Transform3D] pairs in that local space.

const FOUNDATION_HEIGHT := 0.45
const FACTION_COLORS := {"wardens": Color(0.2, 0.36, 0.78), "unbound": Color(0.55, 0.25, 0.62), "none": Color(0.55, 0.35, 0.2)}
const SHUTTER_COLORS: Array[Color] = [Color(0.36, 0.5, 0.36), Color(0.3, 0.4, 0.56), Color(0.62, 0.24, 0.2), Color(0.78, 0.6, 0.25), Color(0.45, 0.35, 0.55)]
const FLOWER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.25), Color(0.95, 0.45, 0.6), Color(0.95, 0.95, 0.9), Color(0.7, 0.5, 1.0), Color(1.0, 0.5, 0.25)]

const WOOD_SHADER := preload("res://materials/village/wood.gdshader")
const SHINGLE_SHADER := preload("res://materials/village/shingles.gdshader")
const STONE_SHADER := preload("res://materials/village/stone.gdshader")

var shapes: Array = []
var _materials := {}
var _rng: RandomNumberGenerator


func _init(recipe: VillageRecipe, faction: String, seed_value: int) -> void:
	_rng = GenRng.stream(seed_value, "kit")
	_materials = {
		"wall": _shader(WOOD_SHADER, {"base_color": recipe.wall_color}),
		"wall_scorched": _shader(WOOD_SHADER, {"base_color": recipe.wall_color.darkened(0.6), "weathering": 0.6}),
		"trim": _shader(WOOD_SHADER, {"base_color": recipe.trim_color, "plank_width": 0.0}),
		"staves": _shader(WOOD_SHADER, {"base_color": recipe.wall_color.lightened(0.05), "plank_width": 0.16, "vertical": true}),
		"door": _shader(WOOD_SHADER, {"base_color": recipe.trim_color.lightened(0.12), "plank_width": 0.2, "vertical": true}),
		"deck": _shader(WOOD_SHADER, {"base_color": recipe.wall_color.lightened(0.1), "plank_width": 0.22}),
		"roof": _shader(SHINGLE_SHADER, {"base_color": recipe.roof_color}),
		"stone": _shader(STONE_SHADER, {"base_color": recipe.stone_color}),
		"cobble": _shader(STONE_SHADER, {"base_color": recipe.stone_color.darkened(0.1), "block_height": 0.22}),
		"dark": _material(Color(0.16, 0.12, 0.1)),
		"iron": _material(Color(0.2, 0.2, 0.22), 0.5),
		"brass": _material(Color(0.8, 0.62, 0.3), 0.35),
		"window": _glow(Color(1.0, 0.78, 0.42), 1.8),
		"window_dark": _material(Color(0.12, 0.14, 0.18), 0.2),
		"lantern": _glow(Color(1.0, 0.72, 0.38), 3.0),
		"forge": _glow(Color(1.0, 0.45, 0.15), 4.0),
		"rune": _glow(Color(0.4, 0.85, 1.0), 3.0),
		"bleed": _glow(Color(0.75, 0.45, 1.0), 2.5),
		"water": _material(Color(0.2, 0.35, 0.55), 0.1),
		"soil": _material(Color(0.42, 0.28, 0.17)),
		"soil_ridge": _material(Color(0.5, 0.34, 0.21)),
		"crop": _material(Color(0.42, 0.62, 0.16)),
		"wheat": _material(Color(0.9, 0.74, 0.32)),
		"leaves": _material(Color(0.32, 0.5, 0.15)),
		"earth": _material(Color(0.42, 0.3, 0.2)),
		"grass_top": _material(Color(0.45, 0.6, 0.18)),
		"faction": _material(FACTION_COLORS.get(faction, FACTION_COLORS["none"])),
		"paper": _material(Color(0.95, 0.92, 0.82)),
		"hat": _material(Color(0.3, 0.2, 0.55)),
		"log_end": _material(Color(0.78, 0.62, 0.42)),
		"smoke": _smoke_material(),
	}
	for i in SHUTTER_COLORS.size():
		_materials["shutter%d" % i] = _shader(WOOD_SHADER, {"base_color": SHUTTER_COLORS[i], "plank_width": 0.12, "vertical": true, "weathering": 0.25})
	for i in FLOWER_COLORS.size():
		_materials["flower%d" % i] = _material(FLOWER_COLORS[i])


# --- buildings ---------------------------------------------------------------

func build_building(b: VillagePlan.Building) -> Node3D:
	shapes = []
	var root := Node3D.new()
	root.name = b.kind.capitalize().replace(" ", "")
	var style := {
		"shutter": "shutter%d" % _rng.randi_range(0, SHUTTER_COLORS.size() - 1),
		"window_boxes": _rng.randf() < 0.55,
		"lantern": _rng.randf() < 0.5 or b.kind in ["tavern", "shrine"],
		"awning": _rng.randf() < 0.35 or b.kind in ["tavern", "bakery"],
		"woodpile": _rng.randf() < 0.45,
	}
	match b.kind:
		"warden_post":
			_tower(root, b)
		"shrine":
			_cottage(root, b, style, true)
			_window(root, Vector3(0, FOUNDATION_HEIGHT + b.size.y + 0.9, b.size.z * 0.5), Vector3.BACK, Vector2(0.9, 1.1), "rune", "", false, true)
		_:
			_cottage(root, b, style, false)
	match b.kind:
		"tavern":
			_tavern_sign(root, Vector3(b.size.x * 0.32, FOUNDATION_HEIGHT + 2.7, b.size.z * 0.5))
		"bakery":
			_oven(root, Vector3(b.size.x * 0.5 + 1.0, 0.0, 0.0))
		"smithy":
			_forge(root, Vector3(b.size.x * 0.5 + 1.3, 0.0, 0.4))
	if b.has_field():
		_field(root, b)
	if b.kind == "home_farm":
		_scarecrow(root, Vector3(b.field_size.x * 0.25, b.field_ground - b.ground, b.field_offset))
	if b.lift > 0.0:
		_floating_earth(root, b)
	if b.roof_damage > 0.5 or b.scorched:
		_rubble(root, b)
	return root


func _cottage(root: Node3D, b: VillagePlan.Building, style: Dictionary, stone_walls: bool) -> void:
	var w := b.size.x
	var d := b.size.z
	var wall_height := b.size.y * b.floors
	var wall_top := FOUNDATION_HEIGHT + wall_height
	var wall_material := "stone" if stone_walls else ("wall_scorched" if b.scorched else "wall")
	var lit := not b.scorched

	# Foundation, walls and timber frame.
	_box(root, "stone", Vector3(w + 0.4, FOUNDATION_HEIGHT + 0.3, d + 0.4), Vector3(0, (FOUNDATION_HEIGHT - 0.3) * 0.5, 0))
	_box(root, wall_material, Vector3(w, wall_height, d), Vector3(0, FOUNDATION_HEIGHT + wall_height * 0.5, 0))
	_add_shape(BoxShape3D.new(), Vector3(w + 0.4, wall_top, d + 0.4), Vector3(0, wall_top * 0.5, 0))
	if not stone_walls:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_box(root, "trim", Vector3(0.3, wall_height + 0.1, 0.3), Vector3(corner.x * w * 0.5, FOUNDATION_HEIGHT + wall_height * 0.5, corner.y * d * 0.5))
		_band(root, w, d, FOUNDATION_HEIGHT + 0.1, 0.2)
		_band(root, w, d, wall_top - 0.1, 0.24)
		for floor_index in range(1, b.floors):
			_band(root, w, d, FOUNDATION_HEIGHT + b.size.y * floor_index, 0.22)

	# Front door with frame, step and lantern; awning on busier houses.
	var front := d * 0.5
	var door_x := 0.0 if w < 6.5 else -w * 0.18
	_door(root, Vector3(door_x, FOUNDATION_HEIGHT, front), b.scorched)
	if style["lantern"] and lit:
		_wall_lantern(root, Vector3(door_x + 0.95, FOUNDATION_HEIGHT + 2.3, front))
	if style["awning"] and b.roof_damage < 0.5:
		_awning(root, Vector3(door_x, FOUNDATION_HEIGHT + 2.45, front), 1.8)

	# Windows: front either side of the door, sides and back on every floor.
	for floor_index in b.floors:
		var y := FOUNDATION_HEIGHT + b.size.y * floor_index + 1.55
		var front_slots := []
		if floor_index == 0:
			for x in [-w * 0.32, w * 0.32]:
				if absf(x - door_x) > 1.4:
					front_slots.append(x)
		else:
			front_slots = [-w * 0.28, w * 0.28] if w > 5.5 else [0.0]
		for x in front_slots:
			_window(root, Vector3(x, y, front), Vector3.BACK, Vector2(0.9, 1.0), "window" if lit else "window_dark", style["shutter"], style["window_boxes"] and floor_index == 0)
		var side_slots := [0.0] if d < 7.0 else [-d * 0.22, d * 0.22]
		for z in side_slots:
			_window(root, Vector3(w * 0.5, y, z), Vector3.RIGHT, Vector2(0.8, 0.9), "window" if lit else "window_dark", style["shutter"], false)
			_window(root, Vector3(-w * 0.5, y, z), Vector3.LEFT, Vector2(0.8, 0.9), "window" if lit else "window_dark", style["shutter"], false)
		_window(root, Vector3(0, y, -front), Vector3.FORWARD, Vector2(0.8, 0.9), "window" if lit else "window_dark", "", false)

	if style["woodpile"] and not stone_walls:
		_woodpile(root, Vector3(-w * 0.5 - 0.45, 0.0, -d * 0.15))

	# Roof.
	var steep := 0.9 if b.kind == "shrine" else 0.55
	var rise := w * 0.5 * steep + 0.6
	if b.roof_damage > 0.5:
		# Burned roof: only charred rafters are left.
		for i in 4:
			var z := lerpf(-d * 0.42, d * 0.42, i / 3.0)
			_roof_plane(root, b, "dark", rise, wall_top, 0.22, z, 0.18)
		_box(root, "dark", Vector3(0.25, 0.25, d), Vector3(0, wall_top + rise, 0))
		return
	_gable(root, wall_material, w, rise, d, wall_top)
	if lit:
		_round_window(root, Vector3(0, wall_top + rise * 0.38, front))
	_roof_plane(root, b, "roof", rise, wall_top, d + 0.9, 0.0, 0.22)
	_box(root, "trim", Vector3(0.36, 0.26, d + 1.0), Vector3(0, wall_top + rise + 0.12, 0))
	_barge_boards(root, b, rise, wall_top, d + 0.9)
	if b.kind == "shrine":
		_box(root, "stone", Vector3(1.3, 2.4, 1.3), Vector3(0, wall_top + rise + 0.7, front - 0.7))
		_box(root, "iron", Vector3(0.5, 0.5, 0.5), Vector3(0, wall_top + rise + 1.4, front - 0.7))
		_cone(root, "roof", 1.1, 1.6, Vector3(0, wall_top + rise + 2.7, front - 0.7), 4)
	else:
		_chimney(root, Vector3(w * 0.24, wall_top, -d * 0.24), rise + 1.3, lit)


## A horizontal timber beam all the way round the walls.
func _band(root: Node3D, w: float, d: float, y: float, thickness: float) -> void:
	_box(root, "trim", Vector3(w + 0.12, thickness, 0.12), Vector3(0, y, d * 0.5 + 0.02))
	_box(root, "trim", Vector3(w + 0.12, thickness, 0.12), Vector3(0, y, -d * 0.5 - 0.02))
	_box(root, "trim", Vector3(0.12, thickness, d + 0.12), Vector3(w * 0.5 + 0.02, y, 0))
	_box(root, "trim", Vector3(0.12, thickness, d + 0.12), Vector3(-w * 0.5 - 0.02, y, 0))


func _gable(root: Node3D, material: String, w: float, rise: float, d: float, wall_top: float) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(w, rise, d)
	_mesh(root, prism, material, Vector3(0, wall_top + rise * 0.5, 0))


## Both slopes of a gable roof. Each plane is turned so its local +X runs down
## the slope, which is what the shingle shader expects.
func _roof_plane(root: Node3D, b: VillagePlan.Building, material: String, rise: float, wall_top: float, length: float, z: float, thickness: float) -> void:
	var half_span := b.size.x * 0.5
	var angle := atan2(rise, half_span)
	var slope_length := sqrt(half_span * half_span + rise * rise) + 0.7
	for side in [-1.0, 1.0]:
		var normal := Vector3(side * sin(angle), cos(angle), 0)
		var center := Vector3(side * (half_span * 0.5 + 0.17), wall_top + rise * 0.5 - 0.12, z) + normal * thickness * 0.55
		var instance := _box(root, material, Vector3(slope_length, thickness, length), center)
		instance.rotation = Vector3(0, 0.0 if side > 0 else PI, -angle)


func _barge_boards(root: Node3D, b: VillagePlan.Building, rise: float, wall_top: float, length: float) -> void:
	var half_span := b.size.x * 0.5
	var angle := atan2(rise, half_span)
	var slope_length := sqrt(half_span * half_span + rise * rise) + 0.7
	for end in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			var center := Vector3(side * (half_span * 0.5 + 0.17), wall_top + rise * 0.5 - 0.12, end * (length * 0.5 + 0.05))
			var board := _box(root, "trim", Vector3(slope_length, 0.32, 0.1), center)
			board.rotation.z = -side * angle


func _door(root: Node3D, at: Vector3, scorched: bool) -> void:
	var frame := _facing(root, at, Vector3.BACK)
	_box(frame, "trim", Vector3(0.18, 2.25, 0.2), Vector3(-0.64, 1.12, 0.04))
	_box(frame, "trim", Vector3(0.18, 2.25, 0.2), Vector3(0.64, 1.12, 0.04))
	_box(frame, "trim", Vector3(1.5, 0.2, 0.22), Vector3(0, 2.3, 0.05))
	_box(frame, "dark" if scorched else "door", Vector3(1.1, 2.1, 0.08), Vector3(0, 1.05, -0.01))
	if not scorched:
		_box(frame, "iron", Vector3(0.9, 0.06, 0.03), Vector3(0, 0.5, 0.04))
		_box(frame, "iron", Vector3(0.9, 0.06, 0.03), Vector3(0, 1.6, 0.04))
		var knob := SphereMesh.new()
		knob.radius = 0.05
		knob.height = 0.1
		_mesh(frame, knob, "brass", Vector3(0.38, 1.05, 0.07))
	# Step down to the ground.
	_box(frame, "cobble", Vector3(1.6, at.y + 0.05, 0.7), Vector3(0, -at.y * 0.5 + 0.02, 0.4))


func _window(root: Node3D, at: Vector3, normal: Vector3, size: Vector2, glass: String, shutter: String, flower_box: bool, round_top := false) -> void:
	var frame := _facing(root, at, normal)
	var w := size.x
	var h := size.y
	_box(frame, glass, Vector3(w, h, 0.04), Vector3(0, 0, 0.0))
	if not round_top:
		_box(frame, "trim", Vector3(0.05, h, 0.06), Vector3(0, 0, 0.04))
		_box(frame, "trim", Vector3(w, 0.05, 0.06), Vector3(0, 0, 0.04))
	for x in [-w * 0.5 - 0.06, w * 0.5 + 0.06]:
		_box(frame, "trim", Vector3(0.12, h + 0.24, 0.12), Vector3(x, 0, 0.04))
	_box(frame, "trim", Vector3(w + 0.24, 0.12, 0.12), Vector3(0, h * 0.5 + 0.06, 0.04))
	_box(frame, "trim", Vector3(w + 0.4, 0.09, 0.26), Vector3(0, -h * 0.5 - 0.06, 0.1))
	if shutter != "":
		for x in [-1.0, 1.0]:
			var panel := _box(frame, shutter, Vector3(w * 0.5, h + 0.05, 0.05), Vector3(x * (w * 0.75 + 0.16), 0, 0.05))
			panel.rotation.y = x * 0.12
	if flower_box:
		_box(frame, "deck", Vector3(w + 0.2, 0.24, 0.28), Vector3(0, -h * 0.5 - 0.22, 0.2))
		_box(frame, "leaves", Vector3(w + 0.1, 0.12, 0.22), Vector3(0, -h * 0.5 - 0.06, 0.2))
		for i in 6:
			var bloom := SphereMesh.new()
			bloom.radius = 0.07
			bloom.height = 0.14
			bloom.radial_segments = 6
			bloom.rings = 3
			_mesh(frame, bloom, "flower%d" % _rng.randi_range(0, FLOWER_COLORS.size() - 1), Vector3(lerpf(-w * 0.45, w * 0.45, i / 5.0), -h * 0.5 + 0.02 + _rng.randf() * 0.05, 0.2 + _rng.randf_range(-0.06, 0.06)))


func _round_window(root: Node3D, at: Vector3) -> void:
	var frame := _facing(root, at, Vector3.BACK)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.42
	ring.bottom_radius = 0.42
	ring.height = 0.1
	ring.radial_segments = 12
	_mesh(frame, ring, "trim", Vector3(0, 0, 0.03)).rotation.x = PI / 2.0
	var pane := CylinderMesh.new()
	pane.top_radius = 0.32
	pane.bottom_radius = 0.32
	pane.height = 0.12
	pane.radial_segments = 12
	_mesh(frame, pane, "window", Vector3(0, 0, 0.04)).rotation.x = PI / 2.0
	_box(frame, "trim", Vector3(0.05, 0.64, 0.14), Vector3(0, 0, 0.05))
	_box(frame, "trim", Vector3(0.64, 0.05, 0.14), Vector3(0, 0, 0.05))


func _wall_lantern(root: Node3D, at: Vector3) -> void:
	var mount := _facing(root, at, Vector3.BACK)
	_box(mount, "iron", Vector3(0.05, 0.05, 0.35), Vector3(0, 0.12, 0.17))
	_box(mount, "iron", Vector3(0.24, 0.05, 0.24), Vector3(0, 0.1, 0.35))
	_box(mount, "lantern", Vector3(0.18, 0.26, 0.18), Vector3(0, -0.07, 0.35))
	_box(mount, "iron", Vector3(0.22, 0.04, 0.22), Vector3(0, -0.21, 0.35))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 0.9
	light.omni_range = 5.0
	light.position = Vector3(0, -0.1, 0.5)
	mount.add_child(light)


func _awning(root: Node3D, at: Vector3, width: float) -> void:
	var mount := _facing(root, at, Vector3.BACK)
	var roof := PrismMesh.new()
	roof.size = Vector3(width, 0.5, 1.0)
	_mesh(mount, roof, "roof", Vector3(0, 0.25, 0.5))
	for x in [-width * 0.42, width * 0.42]:
		var brace := _box(mount, "trim", Vector3(0.1, 0.1, 0.75), Vector3(x, -0.2, 0.32))
		brace.rotation.x = 0.6


func _chimney(root: Node3D, base: Vector3, height: float, smoking: bool) -> void:
	_box(root, "stone", Vector3(0.75, height, 0.75), base + Vector3(0, height * 0.5, 0))
	_box(root, "stone", Vector3(0.95, 0.15, 0.95), base + Vector3(0, height + 0.05, 0))
	_box(root, "dark", Vector3(0.45, 0.05, 0.45), base + Vector3(0, height + 0.14, 0))
	if smoking:
		var smoke := CPUParticles3D.new()
		smoke.amount = 10
		smoke.lifetime = 4.5
		smoke.preprocess = 4.5
		smoke.direction = Vector3.UP
		smoke.spread = 12.0
		smoke.initial_velocity_min = 0.4
		smoke.initial_velocity_max = 0.7
		smoke.gravity = Vector3(0.25, 0.15, 0.05)
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.0
		var growth := Curve.new()
		growth.add_point(Vector2(0, 0.4))
		growth.add_point(Vector2(1, 2.2))
		smoke.scale_amount_curve = growth
		var fade := Gradient.new()
		fade.set_color(0, Color(0.85, 0.82, 0.8, 0.45))
		fade.set_color(1, Color(0.85, 0.82, 0.8, 0.0))
		smoke.color_ramp = fade
		var puff := SphereMesh.new()
		puff.radius = 0.3
		puff.height = 0.6
		puff.radial_segments = 8
		puff.rings = 4
		puff.material = _materials["smoke"]
		smoke.mesh = puff
		smoke.position = base + Vector3(0, height + 0.3, 0)
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(smoke)


func _woodpile(root: Node3D, at: Vector3) -> void:
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.13
	log_mesh.bottom_radius = 0.13
	log_mesh.height = 1.3
	log_mesh.radial_segments = 7
	log_mesh.rings = 1
	log_mesh.material = _materials["trim"]
	for row in 3:
		for i in 4 - row:
			var instance := MeshInstance3D.new()
			instance.mesh = log_mesh
			instance.position = at + Vector3(0, 0.14 + row * 0.24, (i - (3 - row) * 0.5) * 0.27)
			instance.rotation.z = PI / 2.0
			root.add_child(instance)
	_add_shape(BoxShape3D.new(), Vector3(1.3, 0.8, 1.1), at + Vector3(0, 0.4, 0))


func _tavern_sign(root: Node3D, at: Vector3) -> void:
	var mount := _facing(root, at, Vector3.BACK)
	_box(mount, "iron", Vector3(0.06, 0.06, 1.3), Vector3(0, 0, 0.65))
	_box(mount, "trim", Vector3(0.08, 0.75, 0.95), Vector3(0, -0.5, 0.75))
	var emblem := CylinderMesh.new()
	emblem.top_radius = 0.22
	emblem.bottom_radius = 0.22
	emblem.height = 0.12
	emblem.radial_segments = 10
	for x in [-0.05, 0.05]:
		_mesh(mount, emblem, "brass", Vector3(x, -0.5, 0.75)).rotation.z = PI / 2.0


func _oven(root: Node3D, at: Vector3) -> void:
	var dome := SphereMesh.new()
	dome.radius = 1.1
	dome.height = 2.2
	dome.is_hemisphere = true
	_mesh(root, dome, "stone", at)
	_box(root, "forge", Vector3(0.6, 0.5, 0.05), at + Vector3(0, 0.3, 1.05))
	_box(root, "stone", Vector3(0.4, 1.4, 0.4), at + Vector3(0, 1.3, -0.4))
	_add_shape(CylinderShape3D.new(), Vector3(1.1, 1.1, 0), at + Vector3(0, 0.55, 0))


func _forge(root: Node3D, at: Vector3) -> void:
	_box(root, "stone", Vector3(1.4, 0.9, 1.4), at + Vector3(0, 0.45, 0), true)
	_box(root, "forge", Vector3(1.0, 0.1, 1.0), at + Vector3(0, 0.92, 0))
	_box(root, "iron", Vector3(0.8, 0.35, 0.3), at + Vector3(0, 0.75, -1.6), true)
	_box(root, "trim", Vector3(0.5, 0.4, 0.4), at + Vector3(0, 0.2, -1.6))
	for x in [-0.8, 0.8]:
		_box(root, "trim", Vector3(0.15, 2.6, 0.15), at + Vector3(x, 1.3, 0.8))
	var roof := _box(root, "roof", Vector3(2.0, 0.15, 2.4), at + Vector3(0, 2.6, 0.1))
	roof.rotation.x = 0.15


func _tower(root: Node3D, b: VillagePlan.Building) -> void:
	var height := b.size.y
	var radius := b.size.x * 0.5
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.92
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 14
	_mesh(root, cylinder, "stone", Vector3(0, height * 0.5, 0))
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shapes.append([shape, Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0))])
	# Crenellated top under a pointed roof.
	var ring := CylinderMesh.new()
	ring.top_radius = radius + 0.3
	ring.bottom_radius = radius + 0.3
	ring.height = 0.4
	ring.radial_segments = 14
	_mesh(root, ring, "stone", Vector3(0, height + 0.2, 0))
	for i in 10:
		var angle := TAU * i / 10.0
		var merlon := _box(root, "stone", Vector3(0.6, 0.6, 0.35), Vector3(sin(angle), 0, cos(angle)) * (radius + 0.15) + Vector3(0, height + 0.7, 0))
		merlon.rotation.y = angle
	_cone(root, "roof" if b.roof_damage < 0.5 else "dark", radius * 0.95, 2.8, Vector3(0, height + 2.4, 0), 12)
	_door(root, Vector3(0, 0.0, radius - 0.12), b.scorched)
	for angle in [0.75, -0.75]:
		var at := Vector3(sin(angle), 0, cos(angle)) * (radius + 0.05)
		var banner := _box(root, "faction", Vector3(0.9, 2.4, 0.06), at + Vector3(0, height * 0.62, 0))
		banner.rotation.y = angle
		var rod := _box(root, "iron", Vector3(1.1, 0.06, 0.06), at + Vector3(0, height * 0.62 + 1.2, 0))
		rod.rotation.y = angle
	for i in 4:
		var angle := TAU * i / 4.0 + PI / 4.0
		var slit := _box(root, "dark", Vector3(0.18, 0.9, 0.2), Vector3(sin(angle), 0, cos(angle)) * radius * 0.93 + Vector3(0, height * 0.78, 0))
		slit.rotation.y = angle


func _field(root: Node3D, b: VillagePlan.Building) -> void:
	var y := b.field_ground - b.ground
	var size := b.field_size
	var center := Vector3(0, y, b.field_offset)
	_box(root, "soil", Vector3(size.x, 0.12, size.y), center + Vector3(0, 0.02, 0))
	var wheat := _rng.randf() < 0.5
	var plant: PrimitiveMesh
	if wheat:
		var stalks := CylinderMesh.new()
		stalks.top_radius = 0.14
		stalks.bottom_radius = 0.05
		stalks.height = 0.8
		stalks.radial_segments = 5
		stalks.rings = 1
		plant = stalks
	else:
		var head := SphereMesh.new()
		head.radius = 0.28
		head.height = 0.4
		head.radial_segments = 6
		head.rings = 3
		plant = head
	plant.material = _materials["wheat" if wheat else "crop"]
	var transforms: Array[Transform3D] = []
	var rows := int(size.x / 1.3)
	for i in rows:
		var x := lerpf(-size.x * 0.5 + 0.8, size.x * 0.5 - 0.8, float(i) / maxi(rows - 1, 1))
		_box(root, "soil_ridge", Vector3(0.7, 0.18, size.y - 1.2), center + Vector3(x, 0.1, 0))
		var count := int((size.y - 1.6) / 0.45)
		for k in count:
			var z := lerpf(-size.y * 0.5 + 0.9, size.y * 0.5 - 0.9, float(k) / maxi(count - 1, 1))
			var plant_scale := _rng.randf_range(0.75, 1.2)
			var plant_basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * plant_scale)
			transforms.append(Transform3D(plant_basis, center + Vector3(x + _rng.randf_range(-0.1, 0.1), 0.2 + (0.4 if wheat else 0.15) * plant_scale, z)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = plant
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var crops := MultiMeshInstance3D.new()
	crops.multimesh = multimesh
	root.add_child(crops)
	# Fence with a gate gap on the side facing the house.
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		var a: Vector2 = corners[i] * size * 0.5
		var c: Vector2 = corners[(i + 1) % 4] * size * 0.5
		_fence(root, Vector3(a.x, y, a.y + b.field_offset), Vector3(c.x, y, c.y + b.field_offset), i == 2)
	for i in _rng.randi_range(1, 3):
		var hay := CylinderMesh.new()
		hay.top_radius = 0.6
		hay.bottom_radius = 0.6
		hay.height = 1.0
		var bale := _mesh(root, hay, "wheat", center + Vector3((_rng.randf() - 0.5) * 0.8 * size.x, 0.6, (_rng.randf() - 0.5) * 0.8 * size.y))
		bale.rotation.z = PI / 2.0


func _fence(root: Node3D, from: Vector3, to: Vector3, gate: bool) -> void:
	var length := from.distance_to(to)
	var posts := maxi(2, ceili(length / 2.5) + 1)
	for i in posts:
		var t := float(i) / (posts - 1)
		if gate and absf(t - 0.5) < 0.12:
			continue
		var post := _box(root, "trim", Vector3(0.18, 1.15, 0.18), from.lerp(to, t) + Vector3(0, 0.57, 0))
		post.rotation.y = _rng.randf_range(-0.1, 0.1)
	var direction := (to - from).normalized()
	var yaw := atan2(direction.x, direction.z)
	var segments := [[0.0, 0.38], [0.62, 1.0]] if gate else [[0.0, 1.0]]
	for segment in segments:
		var a := from.lerp(to, segment[0])
		var c := from.lerp(to, segment[1])
		for height in [0.45, 0.88]:
			var rail := _box(root, "trim", Vector3(0.07, 0.12, a.distance_to(c)), (a + c) * 0.5 + Vector3(0, height, 0))
			rail.rotation.y = yaw
		var shape := BoxShape3D.new()
		var local := Transform3D(Basis(Vector3.UP, yaw), (a + c) * 0.5 + Vector3(0, 0.55, 0))
		shape.size = Vector3(0.2, 1.1, a.distance_to(c))
		shapes.append([shape, local])


func _scarecrow(root: Node3D, at: Vector3) -> void:
	_box(root, "trim", Vector3(0.12, 2.2, 0.12), at + Vector3(0, 1.1, 0))
	_box(root, "trim", Vector3(1.4, 0.1, 0.1), at + Vector3(0, 1.6, 0))
	_box(root, "wheat", Vector3(0.6, 0.8, 0.35), at + Vector3(0, 1.5, 0))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	_mesh(root, head, "paper", at + Vector3(0, 2.1, 0))
	_cone(root, "hat", 0.38, 0.7, at + Vector3(0, 2.55, 0), 8)


func _floating_earth(root: Node3D, b: VillagePlan.Building) -> void:
	var radius := maxf(b.size.x, b.size.z) * 0.62
	var depth := 2.5 + b.lift * 0.3
	_cone(root, "earth", radius, depth, Vector3(0, -depth * 0.5, 0), 9, true)
	_box(root, "grass_top", Vector3(radius * 1.7, 0.2, radius * 1.7), Vector3(0, -0.12, 0))
	for i in 4:
		var shard := _box(root, "bleed", Vector3(0.25, 0.8, 0.25), Vector3(_rng.randf_range(-radius, radius), -depth * _rng.randf_range(0.3, 0.9), _rng.randf_range(-radius, radius)))
		shard.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf())


func _rubble(root: Node3D, b: VillagePlan.Building) -> void:
	for i in _rng.randi_range(2, 5):
		var spot := Vector3(_rng.randf_range(-0.7, 0.7) * b.size.x, 0.2, b.size.z * 0.5 + _rng.randf_range(0.6, 2.0))
		var stone := _box(root, "stone", Vector3.ONE * _rng.randf_range(0.3, 0.7), spot)
		stone.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf())


# --- props -------------------------------------------------------------------

func build_prop(prop: VillagePlan.Prop) -> Node3D:
	shapes = []
	var root := Node3D.new()
	root.name = prop.kind.capitalize().replace(" ", "")
	match prop.kind:
		"well":
			var ring := CylinderMesh.new()
			ring.top_radius = 1.0
			ring.bottom_radius = 1.1
			ring.height = 0.9
			ring.radial_segments = 14
			_mesh(root, ring, "stone", Vector3(0, 0.45, 0))
			var lip := CylinderMesh.new()
			lip.top_radius = 1.1
			lip.bottom_radius = 1.1
			lip.height = 0.12
			lip.radial_segments = 14
			_mesh(root, lip, "cobble", Vector3(0, 0.95, 0))
			var water := CylinderMesh.new()
			water.top_radius = 0.8
			water.bottom_radius = 0.8
			water.height = 0.05
			_mesh(root, water, "water", Vector3(0, 0.75, 0))
			for x in [-0.85, 0.85]:
				_box(root, "trim", Vector3(0.15, 2.3, 0.15), Vector3(x, 1.15, 0))
			_box(root, "trim", Vector3(1.9, 0.12, 0.12), Vector3(0, 1.9, 0))
			var rope := CylinderMesh.new()
			rope.top_radius = 0.02
			rope.bottom_radius = 0.02
			rope.height = 0.9
			_mesh(root, rope, "wheat", Vector3(0, 1.45, 0))
			var bucket := CylinderMesh.new()
			bucket.top_radius = 0.2
			bucket.bottom_radius = 0.16
			bucket.height = 0.3
			_mesh(root, bucket, "staves", Vector3(0, 0.95, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(2.4, 0.8, 1.6)
			_mesh(root, roof, "roof", Vector3(0, 2.6, 0)).rotation.y = PI / 2.0
			_add_shape(CylinderShape3D.new(), Vector3(1.1, 1.0, 0), Vector3(0, 0.5, 0))
		"notice_board":
			for x in [-0.8, 0.8]:
				_box(root, "trim", Vector3(0.15, 2.2, 0.15), Vector3(x, 1.1, 0))
			_box(root, "deck", Vector3(1.8, 1.1, 0.1), Vector3(0, 1.5, 0))
			_box(root, "faction", Vector3(1.8, 0.2, 0.12), Vector3(0, 2.15, 0))
			var cap := PrismMesh.new()
			cap.size = Vector3(2.1, 0.35, 0.5)
			_mesh(root, cap, "roof", Vector3(0, 2.42, 0))
			for i in 5:
				var paper := _box(root, "paper", Vector3(0.32, 0.42, 0.02), Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(1.25, 1.75), 0.07))
				paper.rotation.z = _rng.randf_range(-0.15, 0.15)
			_add_shape(BoxShape3D.new(), Vector3(1.9, 2.2, 0.3), Vector3(0, 1.1, 0))
		"lamp":
			_box(root, "trim", Vector3(0.14, 2.8, 0.14), Vector3(0, 1.4, 0))
			_box(root, "stone", Vector3(0.35, 0.3, 0.35), Vector3(0, 0.15, 0))
			_box(root, "trim", Vector3(0.6, 0.1, 0.1), Vector3(0.25, 2.75, 0))
			_box(root, "iron", Vector3(0.36, 0.06, 0.36), Vector3(0.5, 2.7, 0))
			_box(root, "lantern", Vector3(0.26, 0.36, 0.26), Vector3(0.5, 2.48, 0))
			_box(root, "iron", Vector3(0.3, 0.05, 0.3), Vector3(0.5, 2.28, 0))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.75, 0.4)
			light.light_energy = 1.2
			light.omni_range = 7.0
			light.position = Vector3(0.5, 2.4, 0)
			root.add_child(light)
			_add_shape(BoxShape3D.new(), Vector3(0.2, 2.8, 0.2), Vector3(0, 1.4, 0))
		"crate":
			var size := _rng.randf_range(0.6, 0.9)
			_box(root, "deck", Vector3.ONE * size, Vector3(0, size * 0.5, 0), true)
			for y in [0.06, size - 0.06]:
				_box(root, "trim", Vector3(size + 0.02, 0.08, size + 0.02), Vector3(0, y, 0))
		"barrel":
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.34
			barrel.bottom_radius = 0.34
			barrel.height = 0.95
			barrel.radial_segments = 12
			_mesh(root, barrel, "staves", Vector3(0, 0.48, 0))
			for y in [0.18, 0.78]:
				var hoop := CylinderMesh.new()
				hoop.top_radius = 0.37
				hoop.bottom_radius = 0.37
				hoop.height = 0.06
				hoop.radial_segments = 12
				_mesh(root, hoop, "iron", Vector3(0, y, 0))
			_add_shape(CylinderShape3D.new(), Vector3(0.38, 0.95, 0), Vector3(0, 0.48, 0))
		"banner":
			_box(root, "trim", Vector3(0.15, 4.0, 0.15), Vector3(0, 2.0, 0))
			_box(root, "iron", Vector3(1.1, 0.06, 0.06), Vector3(0.5, 3.85, 0))
			_box(root, "faction", Vector3(0.9, 1.8, 0.05), Vector3(0.5, 2.9, 0))
	if prop.lift > 0.0:
		_cone(root, "earth", prop.radius * 1.3, 1.2, Vector3(0, -0.6, 0), 7, true)
	return root


# --- primitives --------------------------------------------------------------

## A child node at `at` turned so its local +Z points along `normal`, for
## building wall-mounted parts once and placing them on any face.
func _facing(root: Node3D, at: Vector3, normal: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	node.rotation.y = atan2(normal.x, normal.z)
	root.add_child(node)
	return node


func _box(root: Node3D, material: String, size: Vector3, at: Vector3, solid := false) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	if solid:
		_add_shape(BoxShape3D.new(), size, at)
	return _mesh(root, box, material, at)


func _cone(root: Node3D, material: String, radius: float, height: float, at: Vector3, segments: int, upside_down := false) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = radius if upside_down else 0.0
	cone.bottom_radius = 0.0 if upside_down else radius
	cone.height = height
	cone.radial_segments = segments
	cone.rings = 1
	return _mesh(root, cone, material, at)


func _mesh(root: Node3D, mesh: PrimitiveMesh, material: String, at: Vector3) -> MeshInstance3D:
	mesh.material = _materials[material]
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	root.add_child(instance)
	return instance


## For boxes `size` is the box size; for cylinders it is (radius, height, unused).
func _add_shape(shape: Shape3D, size: Vector3, at: Vector3) -> void:
	if shape is BoxShape3D:
		shape.size = size
	elif shape is CylinderShape3D:
		shape.radius = size.x
		shape.height = size.y
	shapes.append([shape, Transform3D(Basis.IDENTITY, at)])


func _shader(shader: Shader, parameters: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in parameters:
		material.set_shader_parameter(key, parameters[key])
	return material


func _material(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 1, 1)
	return material
