class_name VfxLib
extends RefCounted
## Shared building blocks for spell effects: shader materials, quads, particle
## materials and camera-facing ribbons. All static; shaders load once.

const BOLT_GLOW := preload("res://systems/combat/vfx/shaders/bolt_glow.gdshader")
const RIBBON := preload("res://systems/combat/vfx/shaders/ribbon.gdshader")
const SIGIL := preload("res://systems/combat/vfx/shaders/sigil.gdshader")
const SHOCKWAVE := preload("res://systems/combat/vfx/shaders/shockwave.gdshader")
const SCORCH := preload("res://systems/combat/vfx/shaders/scorch.gdshader")
const SPARK_DOT := preload("res://systems/combat/vfx/shaders/spark_dot.gdshader")

static var _quad: QuadMesh
static var _particle_quads: Dictionary = {}
static var _dot_texture: Texture2D


static func shader_material(shader: Shader, params := {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	return material


## A 1x1 quad facing +Z. Billboard shaders turn it to the camera.
static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A quad `size` metres across for particles. Particle size is set by the mesh,
## and scale_amount then works as a 0-1 multiplier on top.
static func particle_quad(size: float) -> QuadMesh:
	var key := snappedf(size, 0.005)
	if not _particle_quads.has(key):
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * key
		_particle_quads[key] = mesh
	return _particle_quads[key]


## A quad mesh instance with a material, added to `parent`.
static func add_quad(parent: Node, material: Material, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	parent.add_child(mi)
	return mi


## Soft round dot used by every particle.
static func dot_texture() -> Texture2D:
	if _dot_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.85))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_dot_texture = texture
	return _dot_texture


## Billboard particle material: HDR vertex colour over a soft dot.
static func particle_material(energy := 4.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = dot_texture()
	material.albedo_color = Color(energy, energy, energy, 1.0)
	material.no_depth_test = false
	material.disable_receive_shadows = true
	return material


## A colour ramp from `start` through `middle` to transparent `end`.
static func ramp(start: Color, middle: Color, end: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, start)
	gradient.set_color(1, Color(end, 0.0))
	gradient.add_point(0.45, middle)
	return gradient


## Writes a camera-facing strip through `points` into `mesh`. `widths` and
## `alphas` match `points`; UV.x runs head (0) to tail (1).
static func build_ribbon(mesh: ImmediateMesh, points: PackedVector3Array, widths: PackedFloat32Array, alphas: PackedFloat32Array, camera_pos: Vector3) -> void:
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := points.size()
	for i in count:
		var p := points[i]
		var tangent := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)])
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		var to_camera := (camera_pos - p).normalized()
		var side := tangent.cross(to_camera)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.UP)
		side = side.normalized() * widths[i] * 0.5
		var u := float(i) / float(count - 1)
		mesh.surface_set_color(Color(1, 1, 1, alphas[i]))
		mesh.surface_set_uv(Vector2(u, 0.0))
		mesh.surface_add_vertex(p - side)
		mesh.surface_set_color(Color(1, 1, 1, alphas[i]))
		mesh.surface_set_uv(Vector2(u, 1.0))
		mesh.surface_add_vertex(p + side)
	mesh.surface_end()


## A jagged lightning path from `a` to `b`, `segments` long, displaced up to `jitter`.
static func jagged_path(a: Vector3, b: Vector3, segments: int, jitter: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var points := PackedVector3Array()
	var dir := b - a
	var basis_x := dir.cross(Vector3.UP)
	if basis_x.length_squared() < 0.0001:
		basis_x = dir.cross(Vector3.RIGHT)
	basis_x = basis_x.normalized()
	var basis_y := dir.cross(basis_x).normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var envelope := sin(t * PI)
		var offset := (basis_x * rng.randf_range(-1, 1) + basis_y * rng.randf_range(-1, 1)) * jitter * envelope
		points.append(a.lerp(b, t) + offset)
	return points


static func camera_position(node: Node) -> Vector3:
	var camera := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	return camera.global_position if camera else Vector3(0, 10, 10)
