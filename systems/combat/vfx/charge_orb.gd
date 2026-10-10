class_name ChargeOrb
extends Node3D
## Power gathering in the hand while a chargeable spell is held: motes spiral
## in, an arcane circle fills, arcs multiply, the hum climbs, and at full
## charge it flares with a ping.

signal fully_charged

var visual: SpellVisual
## 0 to 1. Set every frame by the caster.
var charge := 0.0:
	set(value):
		var was_full := charge >= 1.0
		charge = clampf(value, 0.0, 1.0)
		if charge >= 1.0 and not was_full:
			_on_full()
## Returns the world position to sit at (the casting hand).
var anchor: Callable

var _age := 0.0
var _full_age := -1.0
var _glow: MeshInstance3D
var _glow_material: ShaderMaterial
var _sigil: MeshInstance3D
var _sigil_material: ShaderMaterial
var _motes: SparkParticles
var _mote_timer := 0.0
var _arcs: LightningArcs
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D


func setup(p_visual: SpellVisual, p_anchor: Callable) -> ChargeOrb:
	visual = p_visual
	anchor = p_anchor
	return self


func _ready() -> void:
	top_level = true
	_place()
	_glow_material = VfxLib.shader_material(VfxLib.BOLT_GLOW, {
		"core_color": visual.core_color,
		"glow_color": visual.glow_color,
		"rim_color": visual.rim_color,
		"intensity": visual.intensity,
		"flicker": visual.flicker,
		"core_size": 0.22,
		"seed": randf() * 30.0,
	})
	_glow = VfxLib.add_quad(self, _glow_material, 0.1)

	_sigil_material = VfxLib.shader_material(VfxLib.SIGIL, {
		"color": visual.glow_color,
		"accent": visual.rim_color,
		"intensity": visual.intensity * 0.55,
		"spin": 2.0,
		"fill": 0.0,
		"billboard": true,
		"alpha": 0.0,
	})
	_sigil = VfxLib.add_quad(self, _sigil_material, 0.9)

	_motes = SparkParticles.new().colors(Color(visual.spark_color, 0.0), visual.core_color, visual.glow_color)
	_motes.damping = 1.5
	_motes.attraction = 16.0
	_motes.swirl = 9.0
	_motes.auto_free = false
	add_child(_motes)

	_arcs = LightningArcs.new()
	_arcs.mode = LightningArcs.Mode.AROUND
	_arcs.count = 1
	_arcs.reach = 0.25
	_arcs.width = 0.025
	_arcs.follow = self
	_arcs.style(visual, 2.0)
	add_child(_arcs)

	_light = OmniLight3D.new()
	_light.light_color = visual.glow_color
	_light.omni_range = 3.0
	add_child(_light)

	if visual.sound_set != &"":
		_hum = SpellSfx.play_at(self, global_position, &"hum", -16.0, 0.7)


func _process(delta: float) -> void:
	_age += delta
	_place()
	var c := charge
	var full_pulse := 0.0
	if _full_age >= 0.0:
		_full_age += delta
		full_pulse = maxf(1.0 - _full_age / 0.25, 0.0) + 0.15 * (0.5 + 0.5 * sin(_age * 18.0))
	var size := lerpf(0.12, 0.62, ease(c, 0.6)) * (1.0 + 0.08 * sin(_age * 30.0)) * (1.0 + full_pulse * 0.5)
	_glow.scale = Vector3.ONE * size
	_sigil.scale = Vector3.ONE * lerpf(0.5, 1.1, c) * (1.0 + full_pulse * 0.3)
	_sigil_material.set_shader_parameter("fill", c)
	_sigil_material.set_shader_parameter("alpha", smoothstep(0.05, 0.25, c))
	_sigil_material.set_shader_parameter("spin", lerpf(1.5, 7.0, c))
	# Motes appear around the hand and are drawn in, faster as the charge builds.
	_motes.attract_point = global_position
	_motes.attraction = lerpf(12.0, 26.0, c)
	_mote_timer -= delta
	if _mote_timer <= 0.0 and _motes.auto_free == false:
		_mote_timer = 0.03
		_motes.shell(2 + int(c * 3.0), global_position, lerpf(0.8, 0.6, c), Vector2(0.03, 0.07), Vector2(0.35, 0.5))
	_arcs.count = 1 + int(c * 4.0)
	_arcs.reach = lerpf(0.2, 0.55, c)
	_light.light_energy = lerpf(0.5, 4.0, c) + full_pulse * 4.0
	if _hum and is_instance_valid(_hum):
		_hum.pitch_scale = lerpf(0.7, 1.6, c)
		_hum.volume_db = lerpf(-18.0, -8.0, c)
		_hum.global_position = global_position


func _place() -> void:
	if anchor.is_valid():
		global_position = anchor.call()


func _on_full() -> void:
	_full_age = 0.0
	if _glow_material:
		_glow_material.set_shader_parameter("rim_color", visual.core_color)
	if _sigil_material:
		_sigil_material.set_shader_parameter("color", visual.rim_color.lerp(Color.WHITE, 0.3))
	if visual.sound_set != &"" and is_inside_tree():
		SpellSfx.play_at(get_parent(), global_position, &"ping", -6.0)
	fully_charged.emit()


## Stops the hum and fades out quickly.
func finish() -> void:
	if _hum and is_instance_valid(_hum):
		_hum.stop()
		_hum.queue_free()
	_motes.auto_free = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.08)
	tween.tween_callback(queue_free)
