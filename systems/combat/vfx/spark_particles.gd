class_name SparkParticles
extends MultiMeshInstance3D
## Small glowing particles simulated by hand and drawn with one MultiMesh:
## embers, spark showers, sprays and motes drawn into a point. Written instead
## of CPUParticles3D for full control (and no zero-scale billboards).

var gravity := Vector3.ZERO
## Fraction of speed lost per second.
var damping := 2.0
## Pull toward `attract_point` (motes gathering into the hand), m/s².
var attraction := 0.0
var attract_point := Vector3.ZERO
## Sideways swirl around `attract_point`.
var swirl := 0.0
var start_color := Color.WHITE
var mid_color := Color(0.5, 0.8, 1.0)
var end_color := Color(0.5, 0.3, 1.0)
## Particles per second while `emitting` (continuous use).
var rate := 0.0
var emitting := false
## Where continuous emission happens: a node to follow, or a fixed point.
var follow: Node3D
var emit_radius := 0.05
var emit_speed := Vector2(0.3, 1.5)
var emit_size := Vector2(0.04, 0.1)
var emit_life := Vector2(0.3, 0.6)
## Free once nothing is alive and nothing will be emitted.
var auto_free := true
var max_particles := 160

var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _age: PackedFloat32Array
var _life: PackedFloat32Array
var _size: PackedFloat32Array
var _alive := 0
var _accum := 0.0
var _material: ShaderMaterial
var _quad: QuadMesh


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 32.0


func colors(start: Color, mid: Color, end: Color) -> SparkParticles:
	start_color = start
	mid_color = mid
	end_color = end
	return self


func _ready() -> void:
	global_transform = Transform3D.IDENTITY
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _quad
	multimesh.instance_count = max_particles
	multimesh.visible_instance_count = 0
	_material = VfxLib.shader_material(VfxLib.SPARK_DOT, {"intensity": 2.4})
	material_override = _material
	_pos.resize(max_particles)
	_vel.resize(max_particles)
	_age.resize(max_particles)
	_life.resize(max_particles)
	_size.resize(max_particles)


## A burst of `count` particles from `origin` along `direction` within `spread` degrees.
func burst(count: int, origin: Vector3, direction: Vector3, spread: float, speed: Vector2, size: Vector2, life: Vector2) -> void:
	for i in count:
		_spawn(origin, _random_dir(direction, spread) * randf_range(speed.x, speed.y), randf_range(size.x, size.y), randf_range(life.x, life.y))


## Particles appearing on a sphere around `center` (motes that then get pulled in).
func shell(count: int, center: Vector3, radius: float, size: Vector2, life: Vector2) -> void:
	for i in count:
		var dir := _random_dir(Vector3.UP, 179.0)
		_spawn(center + dir * radius, Vector3.ZERO, randf_range(size.x, size.y), randf_range(life.x, life.y))


func _spawn(at: Vector3, velocity: Vector3, size: float, life: float) -> void:
	if _alive >= max_particles:
		return
	_pos[_alive] = at
	_vel[_alive] = velocity
	_age[_alive] = 0.0
	_life[_alive] = maxf(life, 0.05)
	_size[_alive] = maxf(size, 0.005)
	_alive += 1


func _process(delta: float) -> void:
	if follow != null and not is_instance_valid(follow):
		# What we were following is gone: stop and let the rest fade.
		follow = null
		emitting = false
	if emitting and rate > 0.0:
		_accum += rate * delta
		var origin := follow.global_position if follow and is_instance_valid(follow) else attract_point
		while _accum >= 1.0:
			_accum -= 1.0
			var offset := _random_dir(Vector3.UP, 179.0) * randf() * emit_radius
			_spawn(origin + offset, _random_dir(Vector3.UP, 179.0) * randf_range(emit_speed.x, emit_speed.y), randf_range(emit_size.x, emit_size.y), randf_range(emit_life.x, emit_life.y))
	var keep := 0.0
	var i := 0
	while i < _alive:
		_age[i] += delta
		if _age[i] >= _life[i]:
			_alive -= 1
			_pos[i] = _pos[_alive]
			_vel[i] = _vel[_alive]
			_age[i] = _age[_alive]
			_life[i] = _life[_alive]
			_size[i] = _size[_alive]
			continue
		var v := _vel[i]
		if attraction != 0.0:
			var to := attract_point - _pos[i]
			var d := to.length()
			if d > 0.02:
				v += to / d * attraction * delta
				if swirl != 0.0:
					v += to.cross(Vector3.UP).normalized() * swirl * delta
		v += gravity * delta
		v *= maxf(1.0 - damping * delta, 0.0)
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	_draw_instances()
	if auto_free and _alive == 0 and not emitting:
		queue_free()


func _draw_instances() -> void:
	multimesh.visible_instance_count = _alive
	for i in _alive:
		var t := _age[i] / _life[i]
		var color := start_color.lerp(mid_color, minf(t / 0.45, 1.0)) if t < 0.45 else mid_color.lerp(end_color, (t - 0.45) / 0.55)
		color.a *= 1.0 - smoothstep(0.6, 1.0, t)
		var s := _size[i] * (1.0 - 0.6 * t)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), _pos[i]))
		multimesh.set_instance_color(i, color)


func alive_count() -> int:
	return _alive


static func _random_dir(direction: Vector3, spread: float) -> Vector3:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	if spread <= 0.0:
		return dir
	# Uniform direction inside a cone of half-angle `spread` around `dir`.
	var cos_max := cos(deg_to_rad(minf(spread, 179.0)))
	var z := randf_range(cos_max, 1.0)
	var phi := randf() * TAU
	var r := sqrt(maxf(1.0 - z * z, 0.0))
	var local := Vector3(r * cos(phi), r * sin(phi), z)
	var helper := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var x := helper.cross(dir).normalized()
	var y := dir.cross(x)
	return (x * local.x + y * local.y + dir * local.z).normalized()
