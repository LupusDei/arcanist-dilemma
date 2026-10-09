class_name BuildingKit
extends RefCounted
## Builds the meshes for village buildings and props from simple primitives.
## Every building is built in its own local space: origin at ground level in
## the middle of the footprint, front door facing +Z. Collision shapes are
## collected in `shapes` as [Shape3D, Transform3D] pairs in that local space.

const FOUNDATION_HEIGHT := 0.45
const FACTION_COLORS := {"wardens": Color(0.2, 0.36, 0.78), "unbound": Color(0.55, 0.25, 0.62), "none": Color(0.55, 0.35, 0.2)}

var shapes: Array = []
var _materials := {}
var _rng: RandomNumberGenerator


func _init(recipe: VillageRecipe, faction: String, seed_value: int) -> void:
	_rng = GenRng.stream(seed_value, "kit")
	_materials = {
		"wall": _material(recipe.wall_color),
		"wall_scorched": _material(recipe.wall_color.darkened(0.6)),
		"trim": _material(recipe.trim_color),
		"roof": _material(recipe.roof_color),
		"stone": _material(recipe.stone_color),
		"dark": _material(Color(0.16, 0.12, 0.1)),
		"window": _glow(Color(1.0, 0.78, 0.42), 2.2),
		"forge": _glow(Color(1.0, 0.45, 0.15), 4.0),
		"rune": _glow(Color(0.4, 0.85, 1.0), 3.0),
		"bleed": _glow(Color(0.75, 0.45, 1.0), 2.5),
		"water": _material(Color(0.2, 0.35, 0.55), 0.1),
		"soil": _material(Color(0.5, 0.33, 0.2)),
		"crop": _material(Color(0.45, 0.62, 0.16)),
		"wheat": _material(Color(0.9, 0.74, 0.32)),
		"earth": _material(Color(0.42, 0.3, 0.2)),
		"grass_top": _material(Color(0.45, 0.6, 0.18)),
		"faction": _material(FACTION_COLORS.get(faction, FACTION_COLORS["none"])),
		"paper": _material(Color(0.95, 0.92, 0.82)),
		"hat": _material(Color(0.3, 0.2, 0.55)),
	}


# --- buildings ---------------------------------------------------------------

func build_building(b: VillagePlan.Building) -> Node3D:
	shapes = []
	var root := Node3D.new()
	root.name = b.kind.capitalize().replace(" ", "")
	match b.kind:
		"warden_post":
			_tower(root, b)
		"shrine":
			_cottage(root, b, true)
			_box(root, "rune", Vector3(1.0, 1.0, 0.06), Vector3(0, FOUNDATION_HEIGHT + b.size.y + 0.9, b.size.z * 0.5 + 0.05))
		_:
			_cottage(root, b, false)
	match b.kind:
		"tavern":
			_box(root, "trim", Vector3(0.1, 0.1, 1.4), Vector3(b.size.x * 0.25, FOUNDATION_HEIGHT + 2.6, b.size.z * 0.5 + 0.7))
			_box(root, "trim", Vector3(0.9, 0.7, 0.08), Vector3(b.size.x * 0.25, FOUNDATION_HEIGHT + 2.1, b.size.z * 0.5 + 1.2))
		"bakery":
			_dome(root, Vector3(b.size.x * 0.5 + 0.9, 0.0, 0.0), 1.1)
		"smithy":
			_box(root, "forge", Vector3(1.2, 0.8, 1.2), Vector3(b.size.x * 0.5 + 1.0, 0.4, 0.5), true)
			_box(root, "dark", Vector3(0.9, 0.5, 0.4), Vector3(b.size.x * 0.5 + 1.0, 0.25, -1.2), true)
	if b.has_field():
		_field(root, b)
	if b.kind == "home_farm":
		_scarecrow(root, Vector3(0, b.field_ground - b.ground, b.field_offset))
	if b.lift > 0.0:
		_floating_earth(root, b)
	if b.roof_damage > 0.5 or b.scorched:
		_rubble(root, b)
	return root


func _cottage(root: Node3D, b: VillagePlan.Building, stone_walls: bool) -> void:
	var w := b.size.x
	var d := b.size.z
	var wall_height := b.size.y * b.floors
	var wall_top := FOUNDATION_HEIGHT + wall_height
	var wall_material := "stone" if stone_walls else ("wall_scorched" if b.scorched else "wall")

	_box(root, "stone", Vector3(w + 0.4, FOUNDATION_HEIGHT + 0.3, d + 0.4), Vector3(0, (FOUNDATION_HEIGHT - 0.3) * 0.5, 0))
	_box(root, wall_material, Vector3(w, wall_height, d), Vector3(0, FOUNDATION_HEIGHT + wall_height * 0.5, 0))
	_add_shape(BoxShape3D.new(), Vector3(w + 0.4, wall_top, d + 0.4), Vector3(0, wall_top * 0.5, 0))
	if not stone_walls:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_box(root, "trim", Vector3(0.28, wall_height, 0.28), Vector3(corner.x * w * 0.5, FOUNDATION_HEIGHT + wall_height * 0.5, corner.y * d * 0.5))
		if b.floors > 1:
			_box(root, "trim", Vector3(w + 0.1, 0.25, d + 0.1), Vector3(0, FOUNDATION_HEIGHT + b.size.y, 0))

	# Door and windows; lit from inside unless the house is burned out.
	var window := "dark" if b.scorched else "window"
	_box(root, "dark" if b.scorched else "trim", Vector3(1.1, 2.0, 0.12), Vector3(0, FOUNDATION_HEIGHT + 1.0, d * 0.5 + 0.04))
	for floor_index in b.floors:
		var y := FOUNDATION_HEIGHT + b.size.y * floor_index + 1.6
		if w > 5.0:
			for x in [-w * 0.3, w * 0.3]:
				if floor_index > 0 or absf(x) > 1.2:
					_box(root, window, Vector3(0.8, 0.8, 0.08), Vector3(x, y, d * 0.5 + 0.04))
		for x in [-w * 0.5 - 0.04, w * 0.5 + 0.04]:
			_box(root, window, Vector3(0.08, 0.8, 0.8), Vector3(x, y, 0))
		_box(root, window, Vector3(0.8, 0.8, 0.08), Vector3(0, y, -d * 0.5 - 0.04))

	var steep := 0.9 if b.kind == "shrine" else 0.55
	var rise := w * 0.5 * steep + 0.6
	if b.roof_damage > 0.5:
		# Burned roof: only charred rafters are left.
		for i in 3:
			var z := lerpf(-d * 0.4, d * 0.4, i / 2.0)
			_box(root, "dark", Vector3(0.2, 0.2, 0.2), Vector3(0, wall_top + rise * 0.5, z))
			_roof_plane(root, b, "dark", rise, wall_top, 0.25, z)
		return
	_gable(root, wall_material, w, rise, d, wall_top)
	_roof_plane(root, b, "roof", rise, wall_top, d + 0.9, 0.0)
	if b.kind != "shrine":
		_box(root, "stone", Vector3(0.7, rise + 1.2, 0.7), Vector3(w * 0.22, wall_top + (rise + 1.2) * 0.5, -d * 0.25))
	else:
		_box(root, "stone", Vector3(1.2, 2.2, 1.2), Vector3(0, wall_top + rise + 0.6, d * 0.5 - 0.6))
		_cone(root, "roof", 1.0, 1.4, Vector3(0, wall_top + rise + 2.4, d * 0.5 - 0.6), 4)


func _gable(root: Node3D, material: String, w: float, rise: float, d: float, wall_top: float) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(w, rise, d)
	_mesh(root, prism, material, Vector3(0, wall_top + rise * 0.5, 0))


## Both slopes of a gable roof. `length` is the roof's extent along local Z.
func _roof_plane(root: Node3D, b: VillagePlan.Building, material: String, rise: float, wall_top: float, length: float, z: float) -> void:
	var half_span := b.size.x * 0.5
	var angle := atan2(rise, half_span)
	var slope_length := sqrt(half_span * half_span + rise * rise) + 0.7
	for side in [-1.0, 1.0]:
		var normal := Vector3(side * sin(angle), cos(angle), 0)
		var center := Vector3(side * half_span * 0.5, wall_top + rise * 0.5, z) + normal * 0.12
		var instance := _box(root, material, Vector3(slope_length, 0.22, length), center)
		instance.rotation.z = -side * angle


func _tower(root: Node3D, b: VillagePlan.Building) -> void:
	var height := b.size.y
	var radius := b.size.x * 0.5
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.9
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 10
	_mesh(root, cylinder, "stone", Vector3(0, height * 0.5, 0))
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shapes.append([shape, Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0))])
	_cone(root, "roof" if b.roof_damage < 0.5 else "dark", radius * 1.25, 2.6, Vector3(0, height + 1.3, 0), 10)
	_box(root, "trim", Vector3(1.2, 2.1, 0.3), Vector3(0, 1.05, radius - 0.05))
	for angle in [0.6, -0.6]:
		var at := Vector3(sin(angle), 0, cos(angle)) * (radius + 0.05)
		var banner := _box(root, "faction", Vector3(0.9, 2.2, 0.06), at + Vector3(0, height * 0.6, 0))
		banner.rotation.y = angle
	_box(root, "window", Vector3(0.5, 0.9, 0.1), Vector3(0, height * 0.75, radius * 0.92))


func _field(root: Node3D, b: VillagePlan.Building) -> void:
	var y := b.field_ground - b.ground
	var size := b.field_size
	var center := Vector3(0, y, b.field_offset)
	_box(root, "soil", Vector3(size.x, 0.12, size.y), center + Vector3(0, 0.02, 0))
	var crop := "wheat" if _rng.randf() < 0.5 else "crop"
	var rows := int(size.x / 1.4)
	for i in rows:
		var x := lerpf(-size.x * 0.5 + 0.8, size.x * 0.5 - 0.8, float(i) / maxi(rows - 1, 1))
		_box(root, crop, Vector3(0.6, 0.45, size.y - 1.4), center + Vector3(x, 0.28, 0))
	# Fence with a gate gap on the side facing the house.
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		var a: Vector2 = corners[i] * size * 0.5
		var c: Vector2 = corners[(i + 1) % 4] * size * 0.5
		var gate := i == 2
		_fence(root, Vector3(a.x, y, a.y + b.field_offset), Vector3(c.x, y, c.y + b.field_offset), gate)
	for i in _rng.randi_range(1, 3):
		var hay := CylinderMesh.new()
		hay.top_radius = 0.6
		hay.bottom_radius = 0.6
		hay.height = 1.0
		var bale := _mesh(root, hay, "wheat", center + Vector3(_rng.randf_range(-0.4, 0.4) * size.x, 0.6, _rng.randf_range(-0.4, 0.4) * size.y))
		bale.rotation.z = PI / 2.0


func _fence(root: Node3D, from: Vector3, to: Vector3, gate: bool) -> void:
	var length := from.distance_to(to)
	var posts := maxi(2, ceili(length / 2.5) + 1)
	for i in posts:
		var t := float(i) / (posts - 1)
		if gate and absf(t - 0.5) < 0.12:
			continue
		_box(root, "trim", Vector3(0.18, 1.1, 0.18), from.lerp(to, t) + Vector3(0, 0.55, 0))
	var direction := (to - from).normalized()
	var yaw := atan2(direction.x, direction.z)
	var segments := [[0.0, 0.38], [0.62, 1.0]] if gate else [[0.0, 1.0]]
	for segment in segments:
		var a := from.lerp(to, segment[0])
		var c := from.lerp(to, segment[1])
		for height in [0.45, 0.85]:
			var rail := _box(root, "trim", Vector3(0.08, 0.12, a.distance_to(c)), (a + c) * 0.5 + Vector3(0, height, 0))
			rail.rotation.y = yaw
		var shape := BoxShape3D.new()
		var local := Transform3D(Basis(Vector3.UP, yaw), (a + c) * 0.5 + Vector3(0, 0.55, 0))
		shape.size = Vector3(0.2, 1.1, a.distance_to(c))
		shapes.append([shape, local])


func _scarecrow(root: Node3D, at: Vector3) -> void:
	_box(root, "trim", Vector3(0.12, 2.2, 0.12), at + Vector3(0, 1.1, 0))
	_box(root, "trim", Vector3(1.4, 0.1, 0.1), at + Vector3(0, 1.6, 0))
	_box(root, "wheat", Vector3(0.6, 0.8, 0.35), at + Vector3(0, 1.5, 0))
	_cone(root, "hat", 0.38, 0.7, at + Vector3(0, 2.45, 0), 8)


func _dome(root: Node3D, at: Vector3, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.is_hemisphere = true
	_mesh(root, sphere, "stone", at)
	_box(root, "forge", Vector3(0.6, 0.5, 0.05), at + Vector3(0, 0.3, radius - 0.05))


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
			_mesh(root, ring, "stone", Vector3(0, 0.45, 0))
			var water := CylinderMesh.new()
			water.top_radius = 0.8
			water.bottom_radius = 0.8
			water.height = 0.05
			_mesh(root, water, "water", Vector3(0, 0.8, 0))
			for x in [-0.85, 0.85]:
				_box(root, "trim", Vector3(0.15, 2.3, 0.15), Vector3(x, 1.15, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(2.4, 0.8, 1.6)
			_mesh(root, roof, "roof", Vector3(0, 2.6, 0)).rotation.y = PI / 2.0
			_add_shape(CylinderShape3D.new(), Vector3(1.1, 1.0, 0), Vector3(0, 0.5, 0))
		"notice_board":
			for x in [-0.8, 0.8]:
				_box(root, "trim", Vector3(0.15, 2.2, 0.15), Vector3(x, 1.1, 0))
			_box(root, "trim", Vector3(1.8, 1.1, 0.1), Vector3(0, 1.5, 0))
			_box(root, "faction", Vector3(1.8, 0.2, 0.12), Vector3(0, 2.15, 0))
			for i in 4:
				var paper := _box(root, "paper", Vector3(0.35, 0.45, 0.02), Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(1.3, 1.75), 0.07))
				paper.rotation.z = _rng.randf_range(-0.15, 0.15)
			_add_shape(BoxShape3D.new(), Vector3(1.9, 2.2, 0.3), Vector3(0, 1.1, 0))
		"lamp":
			_box(root, "trim", Vector3(0.14, 2.8, 0.14), Vector3(0, 1.4, 0))
			_box(root, "trim", Vector3(0.6, 0.1, 0.1), Vector3(0.25, 2.75, 0))
			_box(root, "window", Vector3(0.3, 0.4, 0.3), Vector3(0.5, 2.5, 0))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.75, 0.4)
			light.light_energy = 1.2
			light.omni_range = 7.0
			light.position = Vector3(0.5, 2.4, 0)
			root.add_child(light)
			_add_shape(BoxShape3D.new(), Vector3(0.2, 2.8, 0.2), Vector3(0, 1.4, 0))
		"crate":
			var size := _rng.randf_range(0.6, 0.9)
			_box(root, "trim", Vector3.ONE * size, Vector3(0, size * 0.5, 0), true)
		"barrel":
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.38
			barrel.bottom_radius = 0.38
			barrel.height = 0.95
			barrel.radial_segments = 10
			_mesh(root, barrel, "wall", Vector3(0, 0.48, 0))
			_add_shape(CylinderShape3D.new(), Vector3(0.38, 0.95, 0), Vector3(0, 0.48, 0))
		"banner":
			_box(root, "trim", Vector3(0.15, 4.0, 0.15), Vector3(0, 2.0, 0))
			_box(root, "faction", Vector3(0.9, 1.8, 0.05), Vector3(0.5, 2.9, 0))
	if prop.lift > 0.0:
		_cone(root, "earth", prop.radius * 1.3, 1.2, Vector3(0, -0.6, 0), 7, true)
	return root


# --- primitives --------------------------------------------------------------

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
