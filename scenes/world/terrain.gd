@tool
class_name Terrain
extends StaticBody3D
## Procedural meadow terrain: rolling hills, a central hill with a plateau, a pond
## bowl, dirt paths and a ring of mountains that keeps the player in bounds.
##
## Heights are generated once from a fixed seed and shared by the mesh, the
## collision shape and anything that needs to sit on the ground (see height_at).

var paths: Array[PackedVector2Array] = [
	# Spawn up the hill to the ruins.
	PackedVector2Array([Vector2(0, 12), Vector2(0, 0), Vector2(3, -14), Vector2(-3, -30), Vector2(2, -44), Vector2(10, -56), Vector2(14, -66), Vector2(12, -80)]),
	# Spawn to the pond.
	PackedVector2Array([Vector2(1, -6), Vector2(-9, -10), Vector2(-14, -13)]),
	# East trail.
	PackedVector2Array([Vector2(3, -14), Vector2(22, -22), Vector2(42, -14), Vector2(62, -2), Vector2(84, 8)]),
]
const PATH_HALF_WIDTH := 1.6
const PATH_FEATHER := 1.4

@export var size := 320
@export var noise_seed := 1337
@export var spawn_height := 3.0
@export var spawn_flat_radius := 14.0
@export var hill_center := Vector2(12, -80)
@export var hill_height := 24.0
@export var hill_spread := 30.0
@export var pond_center := Vector2(-24, -16)
@export var pond_radius := 12.0
@export var pond_depth := -2.4
@export var water_level := -0.3
## Beyond this distance from the origin the ground rises into mountains.
@export var play_radius := 105.0
@export var mountain_height := 55.0

var _heights := PackedFloat32Array()
var _path_mask := PackedFloat32Array()
var _n := 0
var _half := 0.0
var _generated := false
var _reserved: Array[Vector3] = []
var _reserved_grass: Array[Vector3] = []


func _ready() -> void:
	generate()


func generate() -> void:
	if _generated:
		return
	_generated = true
	_n = size + 1
	_half = size * 0.5
	_build_heights()
	_build_path_mask()
	_build_mesh()
	_build_collision()


func height_at(x: float, z: float) -> float:
	var gx := clampf(x + _half, 0.0, _n - 1.001)
	var gz := clampf(z + _half, 0.0, _n - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := _heights[j * _n + i]
	var h10 := _heights[j * _n + i + 1]
	var h01 := _heights[(j + 1) * _n + i]
	var h11 := _heights[(j + 1) * _n + i + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func normal_at(x: float, z: float) -> Vector3:
	return Vector3(
		height_at(x - 1.0, z) - height_at(x + 1.0, z),
		2.0,
		height_at(x, z - 1.0) - height_at(x, z + 1.0)
	).normalized()


## 0 on grass, 1 in the middle of a dirt path.
func path_mask_at(x: float, z: float) -> float:
	var i := clampi(roundi(x + _half), 0, _n - 1)
	var j := clampi(roundi(z + _half), 0, _n - 1)
	return _path_mask[j * _n + i]


func _build_heights() -> void:
	var base := FastNoiseLite.new()
	base.seed = noise_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.008
	base.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = noise_seed + 1
	ridge.frequency = 0.02
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4

	_heights.resize(_n * _n)
	for j in _n:
		for i in _n:
			_heights[j * _n + i] = _height_function(i - _half, j - _half, base, ridge)


func _height_function(x: float, z: float, base: FastNoiseLite, ridge: FastNoiseLite) -> float:
	var p := Vector2(x, z)

	# Central hill with a flat top for the ruins.
	var hill := exp(-p.distance_squared_to(hill_center) / (2.0 * hill_spread * hill_spread))
	var plateau := smoothstep(0.0, 0.8, hill)

	# Rolling meadow, kept above the waterline except in the pond.
	var h := base.get_noise_2d(x, z) * 7.0 * (1.0 - 0.8 * plateau) + 3.0
	h = _smooth_max(h, 0.6, 2.0)
	h += hill_height * plateau

	# Gentle clearing around the spawn point.
	h = lerpf(spawn_height, h, smoothstep(spawn_flat_radius, spawn_flat_radius + 25.0, p.length()))

	# Pond bowl.
	h = lerpf(pond_depth, h, smoothstep(pond_radius * 0.35, pond_radius, p.distance_to(pond_center)))

	# Mountain ring at the edge of the play area.
	var wobble := base.get_noise_2d(x * 0.5 + 500.0, z * 0.5) * 18.0
	var edge := smoothstep(play_radius, _half - 5.0, p.length() + wobble)
	h += edge * edge * mountain_height + edge * (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 20.0
	return h


func _smooth_max(a: float, b: float, k: float) -> float:
	var t := clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return lerpf(b, a, t) + k * t * (1.0 - t)


func _build_path_mask() -> void:
	_path_mask.resize(_n * _n)
	_path_mask.fill(0.0)
	for path in paths:
		paint_path(path, PATH_HALF_WIDTH)


## Paints a dirt path into the mask. Call rebuild() afterwards if the terrain
## has already been built.
func paint_path(path: PackedVector2Array, half_width: float) -> void:
	var reach := half_width + PATH_FEATHER
	for s in path.size() - 1:
		var a := path[s]
		var b := path[s + 1]
		var min_i := clampi(floori(minf(a.x, b.x) - reach + _half), 0, _n - 1)
		var max_i := clampi(ceili(maxf(a.x, b.x) + reach + _half), 0, _n - 1)
		var min_j := clampi(floori(minf(a.y, b.y) - reach + _half), 0, _n - 1)
		var max_j := clampi(ceili(maxf(a.y, b.y) + reach + _half), 0, _n - 1)
		for j in range(min_j, max_j + 1):
			for i in range(min_i, max_i + 1):
				var p := Vector2(i - _half, j - _half)
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				var value := 1.0 - smoothstep(half_width, reach, d)
				var index := j * _n + i
				_path_mask[index] = maxf(_path_mask[index], value)


## Flattens a rotated rectangle (same yaw convention as Node3D) to `height`,
## blending back into the surrounding ground over `margin` metres.
func flatten_rect(center: Vector2, half_size: Vector2, yaw: float, height: float, margin := 3.0) -> void:
	var reach := half_size.length() + margin
	var min_i := clampi(floori(center.x - reach + _half), 0, _n - 1)
	var max_i := clampi(ceili(center.x + reach + _half), 0, _n - 1)
	var min_j := clampi(floori(center.y - reach + _half), 0, _n - 1)
	var max_j := clampi(ceili(center.y + reach + _half), 0, _n - 1)
	var x_axis := Vector2(cos(yaw), -sin(yaw))
	var z_axis := Vector2(sin(yaw), cos(yaw))
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			var offset := Vector2(i - _half, j - _half) - center
			var local := Vector2(absf(offset.dot(x_axis)), absf(offset.dot(z_axis)))
			var outside := (local - half_size).max(Vector2.ZERO).length()
			var weight := 1.0 - smoothstep(0.0, margin, outside)
			var index := j * _n + i
			_heights[index] = lerpf(_heights[index], height, weight)


## Pulls a round area part of the way toward `height`, to settle a site
## before planning on it. `strength` 1 flattens it completely.
func soften_disc(center: Vector2, radius: float, height: float, strength: float, margin := 12.0) -> void:
	var reach := radius + margin
	for j in range(clampi(floori(center.y - reach + _half), 0, _n - 1), clampi(ceili(center.y + reach + _half), 0, _n - 1) + 1):
		for i in range(clampi(floori(center.x - reach + _half), 0, _n - 1), clampi(ceili(center.x + reach + _half), 0, _n - 1) + 1):
			var d := Vector2(i - _half, j - _half).distance_to(center)
			var weight := (1.0 - smoothstep(radius, reach, d)) * strength
			var index := j * _n + i
			_heights[index] = lerpf(_heights[index], height, weight)


## Marks an area as taken so scatterers skip it. Trees, rocks and flowers avoid
## every reserved area; grass only avoids the ones with `blocks_grass` (the
## footprints of buildings and fields, not the open ground between them).
func reserve_area(center: Vector2, radius: float, blocks_grass := false) -> void:
	(_reserved_grass if blocks_grass else _reserved).append(Vector3(center.x, center.y, radius))


func is_reserved(x: float, z: float, for_grass := false) -> bool:
	for area in _reserved_grass if for_grass else _reserved + _reserved_grass:
		if Vector2(x, z).distance_squared_to(Vector2(area.x, area.y)) < area.z * area.z:
			return true
	return false


func is_water(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(pond_center) < pond_radius and height_at(x, z) < water_level + 0.3


## Rebuilds the mesh and collision after flatten_rect or paint_path.
func rebuild() -> void:
	for child in [get_node_or_null("TerrainMesh"), get_node_or_null("TerrainCollision")]:
		if child != null:
			remove_child(child)
			child.free()
	_build_mesh()
	_build_collision()


func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(_n * _n)
	normals.resize(_n * _n)
	colors.resize(_n * _n)

	for j in _n:
		for i in _n:
			var index := j * _n + i
			vertices[index] = Vector3(i - _half, _heights[index], j - _half)
			var left := _heights[j * _n + maxi(i - 1, 0)]
			var right := _heights[j * _n + mini(i + 1, _n - 1)]
			var up := _heights[maxi(j - 1, 0) * _n + i]
			var down := _heights[mini(j + 1, _n - 1) * _n + i]
			normals[index] = Vector3(left - right, 2.0, up - down).normalized()
			colors[index] = Color(_path_mask[index], 0.0, 0.0)

	indices.resize((_n - 1) * (_n - 1) * 6)
	var k := 0
	for j in _n - 1:
		for i in _n - 1:
			var a := j * _n + i
			var b := a + 1
			var c := a + _n
			var d := c + 1
			indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
			indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var noise := FastNoiseLite.new()
	noise.seed = noise_seed + 2
	noise.frequency = 0.02
	var variation := NoiseTexture2D.new()
	variation.width = 512
	variation.height = 512
	variation.seamless = true
	variation.noise = noise
	var material := ShaderMaterial.new()
	material.shader = preload("res://materials/terrain.gdshader")
	material.set_shader_parameter("variation_noise", variation)
	material.set_shader_parameter("water_level", water_level)
	mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = "TerrainMesh"
	instance.mesh = mesh
	add_child(instance)


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _n
	shape.map_depth = _n
	shape.map_data = _heights
	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = shape
	add_child(collision)
