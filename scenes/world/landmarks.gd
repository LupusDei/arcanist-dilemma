@tool
extends Node3D
## Features placed on top of the terrain: the pond with stepping stones, the
## ruined stone circle on the hilltop with its floating crystal, and broken
## blocks along the trail.

@export var terrain_path: NodePath = ^"../Terrain"
@export var ruins_seed := 3

var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _colliders: StaticBody3D
var _stone_material: StandardMaterial3D
var _crystal: Node3D
var _crystal_base_y := 0.0
var _time := 0.0


func _ready() -> void:
	_terrain = get_node(terrain_path) as Terrain
	_terrain.generate()
	_rng.seed = ruins_seed
	_colliders = StaticBody3D.new()
	_colliders.name = "Colliders"
	add_child(_colliders)
	_stone_material = StandardMaterial3D.new()
	_stone_material.albedo_color = Color(0.68, 0.67, 0.64)
	_stone_material.roughness = 0.95
	_build_pond()
	_build_ruins()
	_build_trail_blocks()


func _process(delta: float) -> void:
	if _crystal == null:
		return
	_time += delta
	_crystal.rotation.y = _time * 0.6
	_crystal.position.y = _crystal_base_y + sin(_time * 1.5) * 0.2


func _build_pond() -> void:
	var center := _terrain.pond_center
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _terrain.pond_radius * 2.4
	var material := ShaderMaterial.new()
	material.shader = preload("res://materials/water.gdshader")
	material.set_shader_parameter("normal_a", _normal_noise(11, 0.04))
	material.set_shader_parameter("normal_b", _normal_noise(12, 0.07))
	plane.material = material
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position = Vector3(center.x, _terrain.water_level, center.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# Stepping stones across the pond, continuing the trail from spawn.
	var direction := (center - Vector2(-14, -13)).normalized()
	var stone := CylinderMesh.new()
	stone.top_radius = 0.75
	stone.bottom_radius = 0.9
	stone.height = 0.6
	stone.radial_segments = 8
	stone.rings = 1
	var shape := CylinderShape3D.new()
	shape.radius = 0.8
	shape.height = 0.6
	for i in 6:
		var p := center + direction * lerpf(-_terrain.pond_radius * 0.8, _terrain.pond_radius * 0.8, i / 5.0)
		p += Vector2(-direction.y, direction.x) * _rng.randf_range(-0.6, 0.6)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, _terrain.water_level + 0.05, p.y))
		_add_solid(stone, shape, xf)


func _build_ruins() -> void:
	var center := _terrain.hill_center
	var ground := _terrain.height_at(center.x, center.y)
	var count := 9
	var standing_heights := {}
	for i in count:
		var angle := TAU * i / count
		var p := center + Vector2(cos(angle), sin(angle)) * 9.0
		var y := _terrain.height_at(p.x, p.y)
		if i == 3 or i == 7:
			# Toppled stone lying in the grass.
			var size := Vector3(1.3, 0.9, 3.6)
			var xf := Transform3D(Basis(Vector3.UP, angle + _rng.randf_range(-0.4, 0.4)), Vector3(p.x, y + 0.35, p.y))
			_add_box(size, xf)
		else:
			var size := Vector3(1.3, _rng.randf_range(3.2, 4.6), 0.9)
			var tilt := Basis(Vector3.FORWARD, _rng.randf_range(-0.08, 0.08)) * Basis(Vector3.UP, -angle + PI / 2.0)
			_add_box(size, Transform3D(tilt, Vector3(p.x, y + size.y * 0.5 - 0.4, p.y)))
			standing_heights[i] = y + size.y - 0.4

	# Lintel across the first two standing stones.
	var a := center + Vector2(1, 0) * 9.0
	var b := center + Vector2(cos(TAU / count), sin(TAU / count)) * 9.0
	var mid := (a + b) * 0.5
	var top := minf(standing_heights[0], standing_heights[1]) + 0.3
	var along := (b - a).normalized()
	_add_box(Vector3(a.distance_to(b) + 1.4, 0.6, 1.0), Transform3D(Basis(Vector3.UP, -atan2(along.y, along.x)), Vector3(mid.x, top, mid.y)))

	# Altar and floating crystal.
	_add_box(Vector3(2.4, 1.0, 1.6), Transform3D(Basis.IDENTITY, Vector3(center.x, ground + 0.3, center.y)))
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radial_segments = 4
	crystal_mesh.rings = 2
	crystal_mesh.radius = 0.45
	crystal_mesh.height = 1.6
	var crystal_material := StandardMaterial3D.new()
	crystal_material.albedo_color = Color(0.45, 0.85, 1.0)
	crystal_material.emission_enabled = true
	crystal_material.emission = Color(0.35, 0.8, 1.0)
	crystal_material.emission_energy_multiplier = 2.5
	crystal_mesh.material = crystal_material
	var crystal := MeshInstance3D.new()
	crystal.name = "Crystal"
	crystal.mesh = crystal_mesh
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.85, 1.0)
	light.light_energy = 2.0
	light.omni_range = 9.0
	crystal.add_child(light)
	_crystal_base_y = ground + 2.6
	crystal.position = Vector3(center.x, _crystal_base_y, center.y)
	add_child(crystal)
	_crystal = crystal


func _build_trail_blocks() -> void:
	for spot in [Vector2(-5, 5), Vector2(7, -21), Vector2(-7, -35), Vector2(-5, -38), Vector2(7, -47), Vector2(18, -62)]:
		var size := Vector3(_rng.randf_range(1.0, 1.8), _rng.randf_range(0.8, 1.6), _rng.randf_range(1.0, 1.6))
		var y := _terrain.height_at(spot.x, spot.y)
		var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.12, 0.12))
		_add_box(size, Transform3D(tilt, Vector3(spot.x, y + size.y * 0.5 - 0.2, spot.y)))


func _add_box(size: Vector3, xf: Transform3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	_add_solid(mesh, shape, xf)


func _add_solid(mesh: PrimitiveMesh, shape: Shape3D, xf: Transform3D) -> void:
	if mesh.material == null:
		mesh.material = _stone_material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = xf
	add_child(instance)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xf
	_colliders.add_child(collision)


func _normal_noise(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.as_normal_map = true
	texture.bump_strength = 4.0
	texture.noise = noise
	return texture
