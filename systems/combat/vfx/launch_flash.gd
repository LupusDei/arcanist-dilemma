class_name LaunchFlash
extends Node3D
## The flash at the hand as a bolt leaves: an arcane circle spinning open
## toward the target, a pop of light, a spray of sparks and a zap.

const LIFETIME := 0.6

var visual: SpellVisual
var power_scale := 1.0
var _age := 0.0
var _sigil: MeshInstance3D
var _sigil_material: ShaderMaterial
var _pop: MeshInstance3D
var _pop_material: ShaderMaterial
var _light: OmniLight3D


static func spawn(parent: Node, at: Vector3, direction: Vector3, p_visual: SpellVisual, p_power_scale := 1.0) -> LaunchFlash:
	if parent == null or not parent.is_inside_tree():
		return null
	var flash := LaunchFlash.new()
	flash.visual = p_visual
	flash.power_scale = p_power_scale
	parent.add_child(flash)
	flash.global_position = at
	flash._build(direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD)
	return flash


func _build(direction: Vector3) -> void:
	if visual.launch_sigil:
		_sigil_material = VfxLib.shader_material(VfxLib.SIGIL, {
			"color": visual.glow_color,
			"accent": visual.rim_color,
			"intensity": visual.intensity * 0.6,
			"spin": 6.0,
		})
		_sigil = VfxLib.add_quad(self, _sigil_material, 0.5 * power_scale)
		_sigil.position = direction * 0.25
		_sigil.look_at(global_position + direction * 3.0, Vector3.UP if absf(direction.y) < 0.95 else Vector3.FORWARD)

	_pop_material = VfxLib.shader_material(VfxLib.BOLT_GLOW, {
		"core_color": Color.WHITE,
		"glow_color": visual.glow_color,
		"rim_color": visual.rim_color,
		"intensity": visual.intensity,
		"core_size": 0.25,
	})
	_pop = VfxLib.add_quad(self, _pop_material, visual.size * 1.6 * power_scale)

	var spray := SparkParticles.new().colors(Color.WHITE, visual.spark_color, visual.rim_color)
	spray.damping = 9.0
	add_child(spray)
	spray.burst(int(14 * power_scale), global_position, direction, 28.0, Vector2(5.0, 11.0 * power_scale), Vector2(0.04, 0.09), Vector2(0.2, 0.35))

	_light = OmniLight3D.new()
	_light.light_color = visual.glow_color.lerp(Color.WHITE, 0.4)
	_light.light_energy = 4.0 * power_scale
	_light.omni_range = 4.0
	add_child(_light)

	if visual.sound_set != &"":
		SpellSfx.play_at(self, global_position, &"zap", -4.0 + 4.0 * (power_scale - 1.0), randf_range(0.92, 1.12) / sqrt(power_scale))


func _process(delta: float) -> void:
	_age += delta
	var t := _age
	if _sigil:
		_sigil.scale = Vector3.ONE * lerpf(0.35, 1.1, ease(minf(t / 0.25, 1.0), 0.4)) * power_scale
		_sigil_material.set_shader_parameter("alpha", 1.0 - smoothstep(0.12, 0.4, t))
	_pop_material.set_shader_parameter("alpha", 1.0 - smoothstep(0.02, 0.14, t))
	_light.light_energy = 4.0 * power_scale * maxf(1.0 - t / 0.18, 0.0)
	if _age >= LIFETIME:
		queue_free()
