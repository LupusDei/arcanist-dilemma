class_name LightningArcs
extends MeshInstance3D
## Procedural lightning drawn as camera-facing ribbons, re-jagged many times a
## second. Three uses: tendrils crackling around a moving point, a bolt between
## two points (chain hits), and a one-off radial burst on impact.

enum Mode { AROUND, BETWEEN, BURST }

var mode := Mode.AROUND
var count := 3
var reach := 0.5
var width := 0.05
var segments := 7
## Seconds the arcs live; 0 lives until freed.
var lifetime := 0.0
var refresh := 0.045
## Follow this node's position in AROUND mode.
var follow: Node3D
var center := Vector3.ZERO
var start_point := Vector3.ZERO
var end_point := Vector3.ZERO
var opacity := 1.0

var _mesh := ImmediateMesh.new()
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _age := 0.0
var _until_refresh := 0.0
var _burst_dirs: Array[Vector3] = []


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16.0


## Colors and brightness, from a SpellVisual.
func style(visual: SpellVisual, brightness := 2.2) -> LightningArcs:
	_material = VfxLib.shader_material(VfxLib.RIBBON, {
		"inner_color": visual.core_color,
		"outer_color": visual.rim_color.lerp(visual.glow_color, 0.4),
		"intensity": brightness,
		"streaks": 0.4,
		"scroll": 20.0,
	})
	material_override = _material
	return self


func _ready() -> void:
	_rng.randomize()
	global_transform = Transform3D.IDENTITY
	if mode == Mode.BURST:
		for i in count:
			var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)).normalized()
			_burst_dirs.append(dir)
	_rebuild()


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		queue_free()
		return
	_until_refresh -= delta
	if _until_refresh <= 0.0 or follow:
		_until_refresh = refresh
		_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if follow and is_instance_valid(follow):
		center = follow.global_position
	var fade := opacity
	if lifetime > 0.0:
		fade *= 1.0 - smoothstep(lifetime * 0.4, lifetime, _age)
	if fade <= 0.01:
		return
	var camera := VfxLib.camera_position(self)
	match mode:
		Mode.AROUND:
			for i in count:
				var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
				var end := center + dir * reach * _rng.randf_range(0.5, 1.0)
				_strip(VfxLib.jagged_path(center, end, 4, reach * 0.35, _rng), width, fade * _rng.randf_range(0.5, 1.0), camera, true)
		Mode.BETWEEN:
			var length := start_point.distance_to(end_point)
			for i in count:
				var path := VfxLib.jagged_path(start_point, end_point, maxi(segments, int(length * 2.5)), maxf(length * 0.08, 0.15), _rng)
				_strip(path, width * (1.0 if i == 0 else 0.5), fade * (1.0 if i == 0 else 0.55), camera, false)
		Mode.BURST:
			var grow := clampf(_age / maxf(lifetime * 0.25, 0.01), 0.15, 1.0)
			for dir in _burst_dirs:
				var end := center + dir * reach * grow
				var path := VfxLib.jagged_path(center, end, segments, reach * 0.22, _rng)
				_strip(path, width, fade, camera, true)
				# A small fork off the middle of each branch.
				var mid := path[path.size() / 2]
				var fork_end := mid + (dir + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.5, 0.8), _rng.randf_range(-0.8, 0.8))).normalized() * reach * 0.4 * grow
				_strip(VfxLib.jagged_path(mid, fork_end, 3, reach * 0.1, _rng), width * 0.6, fade * 0.8, camera, true)


func _strip(points: PackedVector3Array, w: float, alpha: float, camera: Vector3, taper: bool) -> void:
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for i in points.size():
		var t := float(i) / (points.size() - 1)
		widths.append(w * (1.0 - t * 0.8 if taper else 1.0))
		alphas.append(alpha * (1.0 - t * 0.5 if taper else 1.0))
	VfxLib.build_ribbon(_mesh, points, widths, alphas, camera)
