class_name BoltTrail
extends MeshInstance3D
## A comet tail that follows a node through the world, tapering and fading by
## age. When the node is gone the tail keeps shrinking, then frees itself.

var target: Node3D
var visual: SpellVisual
var width_scale := 1.0

var _mesh := ImmediateMesh.new()
var _points: Array[Vector3] = []
var _times: Array[float] = []
var _clock := 0.0


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 32.0


func setup(p_target: Node3D, p_visual: SpellVisual, p_width_scale := 1.0) -> BoltTrail:
	target = p_target
	visual = p_visual
	width_scale = p_width_scale
	material_override = VfxLib.shader_material(VfxLib.RIBBON, {
		"inner_color": visual.trail_inner,
		"outer_color": visual.trail_outer,
		"intensity": visual.intensity * 0.45,
		"streaks": 1.0,
		"scroll": 9.0,
	})
	return self


func _ready() -> void:
	global_transform = Transform3D.IDENTITY


## Stop following; the tail finishes fading on its own.
func release() -> void:
	target = null


func _process(delta: float) -> void:
	_clock += delta
	if target and is_instance_valid(target) and target.is_inside_tree():
		var p := target.global_position
		if _points.is_empty() or _points[0].distance_squared_to(p) > 0.0004:
			_points.push_front(p)
			_times.push_front(_clock)
	else:
		target = null
	while not _times.is_empty() and _clock - _times[-1] > visual.trail_time:
		_points.pop_back()
		_times.pop_back()
	if target == null and _points.size() < 2:
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	var points := PackedVector3Array(_points)
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for i in _points.size():
		var age := clampf((_clock - _times[i]) / visual.trail_time, 0.0, 1.0)
		var fade := 1.0 - age
		widths.append(visual.trail_width * width_scale * (0.25 + 0.75 * fade))
		alphas.append(fade * fade)
	VfxLib.build_ribbon(_mesh, points, widths, alphas, VfxLib.camera_position(self))
