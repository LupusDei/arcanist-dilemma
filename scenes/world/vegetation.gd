@tool
extends Node3D
## Scatters trees, rocks, grass and flowers over the Terrain using MultiMeshes.
## Placement is seeded, so the world looks the same every run.

@export var terrain_path: NodePath = ^"../Terrain"
@export var scatter_seed := 7
@export var tree_attempts := 9000
@export var tree_spacing := 3.4
@export var boulder_count := 45
@export var pebble_count := 350
@export var grass_radius := 95.0
@export var grass_spacing := 0.75
@export var grass_view_distance := 75.0
@export var flower_patches := 70

const CHUNK_SIZE := 32.0
const FLOWER_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.25), Color(1.0, 0.95, 0.9), Color(0.95, 0.5, 0.7), Color(0.7, 0.55, 1.0), Color(1.0, 0.6, 0.3),
]

var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _colliders: StaticBody3D


func _ready() -> void:
	_terrain = get_node(terrain_path) as Terrain
	_terrain.generate()
	_rng.seed = scatter_seed
	_colliders = StaticBody3D.new()
	_colliders.name = "Colliders"
	add_child(_colliders)
	_scatter_trees()
	_scatter_rocks()
	_scatter_grass()
	_scatter_flowers()


func _scatter_trees() -> void:
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.45, 0.31, 0.2)
	trunk_material.roughness = 0.9
	var broadleaf_material := _shader_material(preload("res://materials/foliage.gdshader"), {"leaf_color": Color(0.55, 0.66, 0.2)})
	var pine_material := _shader_material(preload("res://materials/foliage.gdshader"), {"leaf_color": Color(0.22, 0.4, 0.24), "sway": 0.02})

	var broadleaf: Array[Mesh] = []
	var pines: Array[Mesh] = []
	for i in 3:
		broadleaf.append(MeshFactory.broadleaf_tree(_rng, trunk_material, broadleaf_material))
	for i in 2:
		pines.append(MeshFactory.pine_tree(_rng, trunk_material, pine_material))

	var forest := FastNoiseLite.new()
	forest.seed = scatter_seed
	forest.frequency = 0.02
	var placed := {}
	var buckets := {}  # Mesh -> Array[Transform3D]
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.4
	trunk_shape.height = 4.0

	for attempt in tree_attempts:
		var p := Vector2(_rng.randf_range(-150.0, 150.0), _rng.randf_range(-150.0, 150.0))
		var r := p.length()
		if r < 20.0 or r > 150.0:
			continue
		var density := forest.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		if r > _terrain.play_radius - 10.0:
			density += 0.3  # thicker treeline on the foothills
		if _rng.randf() > smoothstep(0.45, 0.75, density):
			continue
		if not _is_open_ground(p, 0.8, 4.0) or _terrain.normal_at(p.x, p.y).y < 0.8:
			continue
		if p.distance_to(_terrain.hill_center) < 16.0:
			continue  # keep the ruins clear
		if _is_crowded(placed, p, tree_spacing):
			continue

		var height := _terrain.height_at(p.x, p.y)
		var pine := height > 14.0 or r > _terrain.play_radius - 15.0 or _rng.randf() < 0.2
		var mesh: Mesh = pines.pick_random() if pine else broadleaf.pick_random()
		var size_factor := _rng.randf_range(0.8, 1.35)
		var rotation_basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * size_factor)
		buckets.get_or_add(mesh, []).append(Transform3D(rotation_basis, Vector3(p.x, height - 0.15, p.y)))

		if r < _terrain.play_radius + 20.0:
			var collision := CollisionShape3D.new()
			collision.shape = trunk_shape
			collision.position = Vector3(p.x, height + 2.0, p.y)
			_colliders.add_child(collision)

	for mesh in buckets:
		_add_multimesh("Trees", mesh, buckets[mesh], 0.15)


func _scatter_rocks() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.6, 0.62)
	material.roughness = 0.95
	var variants: Array[Mesh] = []
	for i in 4:
		variants.append(MeshFactory.rock(_rng, material))

	var transforms := {}
	# Boulders: big enough to collide with.
	var placed := 0
	while placed < boulder_count:
		var p := Vector2(_rng.randf_range(-110.0, 110.0), _rng.randf_range(-110.0, 110.0))
		if p.length() < 12.0 or not _is_open_ground(p, 0.3, 3.0):
			continue
		var size_factor := _rng.randf_range(0.9, 2.2)
		_add_rock(variants.pick_random(), transforms, p, size_factor, true)
		placed += 1
	# Pebbles: decoration only.
	for i in pebble_count:
		var p := Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(-120.0, 120.0))
		if _terrain.normal_at(p.x, p.y).y < 0.6 or _terrain.is_reserved(p.x, p.y):
			continue
		_add_rock(variants.pick_random(), transforms, p, _rng.randf_range(0.15, 0.5), false)
	# A ring of stones around the pond.
	for i in 22:
		var angle := TAU * i / 22.0 + _rng.randf_range(-0.1, 0.1)
		var p := _terrain.pond_center + Vector2(cos(angle), sin(angle)) * _terrain.pond_radius * _rng.randf_range(0.7, 0.85)
		_add_rock(variants.pick_random(), transforms, p, _rng.randf_range(0.35, 0.8), false)

	for mesh in transforms:
		_add_multimesh("Rocks", mesh, transforms[mesh], 0.1)


func _add_rock(mesh: Mesh, transforms: Dictionary, p: Vector2, size_factor: float, solid: bool) -> void:
	var rotation_basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * size_factor)
	var spot := Vector3(p.x, _terrain.height_at(p.x, p.y) - 0.05 * size_factor, p.y)
	transforms.get_or_add(mesh, []).append(Transform3D(rotation_basis, spot))
	if solid:
		var shape := SphereShape3D.new()
		shape.radius = 0.85 * size_factor
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = spot + Vector3(0, 0.1 * size_factor, 0)
		_colliders.add_child(collision)


func _scatter_grass() -> void:
	var material := _shader_material(preload("res://materials/grass.gdshader"), {})
	var tufts: Array[Mesh] = []
	for i in 3:
		tufts.append(MeshFactory.grass_tuft(_rng, material))
	var patchiness := FastNoiseLite.new()
	patchiness.seed = scatter_seed + 1
	patchiness.frequency = 0.05

	var chunks := {}  # Vector2i -> {Mesh -> Array[Transform3D]}
	var steps := int(grass_radius * 2.0 / grass_spacing)
	for gz in steps:
		for gx in steps:
			var p := Vector2(gx, gz) * grass_spacing - Vector2.ONE * grass_radius
			p += Vector2(_rng.randf(), _rng.randf()) * grass_spacing
			if p.length() > grass_radius:
				continue
			var patch := patchiness.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			if _rng.randf() > 0.35 + patch * 0.65:
				continue
			if _rng.randf() < _terrain.path_mask_at(p.x, p.y) * 1.3:
				continue
			if _terrain.is_reserved(p.x, p.y, true):
				continue
			var height := _terrain.height_at(p.x, p.y)
			if height < _terrain.water_level + 0.15 or _terrain.normal_at(p.x, p.y).y < 0.75:
				continue
			var size_factor := _rng.randf_range(0.7, 1.1) * (0.8 + patch * 0.6)
			var rotation_basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * size_factor)
			var key := Vector2i(floori(p.x / CHUNK_SIZE), floori(p.y / CHUNK_SIZE))
			var chunk: Dictionary = chunks.get_or_add(key, {})
			chunk.get_or_add(tufts.pick_random(), []).append(Transform3D(rotation_basis, Vector3(p.x, height, p.y)))

	var parent := Node3D.new()
	parent.name = "Grass"
	add_child(parent)
	for key in chunks:
		var center := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK_SIZE
		var origin := Vector3(center.x, 0.0, center.y)
		for mesh in chunks[key]:
			var local: Array = []
			for xf in chunks[key][mesh]:
				local.append(xf.translated(-origin))
			var instance := _make_multimesh(mesh, local, 0.15)
			instance.position = origin
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = grass_view_distance
			instance.visibility_range_end_margin = 10.0
			parent.add_child(instance)


func _scatter_flowers() -> void:
	var material := _shader_material(preload("res://materials/flower.gdshader"), {})
	var mesh := MeshFactory.flower(material)
	var transforms: Array = []
	var colors: Array[Color] = []
	for i in flower_patches:
		var center := Vector2(_rng.randf_range(-90.0, 90.0), _rng.randf_range(-90.0, 90.0))
		if not _is_open_ground(center, 0.3, 2.0):
			continue
		var color: Color = FLOWER_COLORS.pick_random()
		for f in _rng.randi_range(15, 45):
			var p := center + Vector2(_rng.randfn(0.0, 2.2), _rng.randfn(0.0, 2.2))
			if _terrain.path_mask_at(p.x, p.y) > 0.3:
				continue
			var rotation_basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.2))
			transforms.append(Transform3D(rotation_basis, Vector3(p.x, _terrain.height_at(p.x, p.y), p.y)))
			colors.append(color * _rng.randf_range(0.9, 1.1))
	var instance := _make_multimesh(mesh, transforms, 0.0, colors)
	instance.name = "Flowers"
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## True if the spot is dry, off the paths and outside the spawn clearing.
func _is_open_ground(p: Vector2, water_margin: float, path_margin: float) -> bool:
	if _terrain.is_reserved(p.x, p.y):
		return false
	if _terrain.height_at(p.x, p.y) < _terrain.water_level + water_margin:
		return false
	if p.distance_to(_terrain.pond_center) < _terrain.pond_radius + 2.0:
		return false
	for offset in [Vector2.ZERO, Vector2(path_margin, 0), Vector2(-path_margin, 0), Vector2(0, path_margin), Vector2(0, -path_margin)]:
		if _terrain.path_mask_at(p.x + offset.x, p.y + offset.y) > 0.0:
			return false
	return true


func _is_crowded(placed: Dictionary, p: Vector2, spacing: float) -> bool:
	var cell := Vector2i(floori(p.x / spacing), floori(p.y / spacing))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for other in placed.get(cell + Vector2i(dx, dz), []):
				if p.distance_to(other) < spacing:
					return true
	placed.get_or_add(cell, []).append(p)
	return false


func _add_multimesh(group_name: String, mesh: Mesh, transforms: Array, tint_variance: float) -> void:
	var parent := get_node_or_null(group_name)
	if parent == null:
		parent = Node3D.new()
		parent.name = group_name
		add_child(parent)
	parent.add_child(_make_multimesh(mesh, transforms, tint_variance))


func _make_multimesh(mesh: Mesh, transforms: Array, tint_variance: float, colors: Array[Color] = []) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if colors.is_empty():
			var v := 1.0 + _rng.randf_range(-tint_variance, tint_variance)
			multimesh.set_instance_color(i, Color(v, v * _rng.randf_range(0.97, 1.03), v))
		else:
			multimesh.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


func _shader_material(shader: Shader, parameters: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in parameters:
		material.set_shader_parameter(key, parameters[key])
	return material
