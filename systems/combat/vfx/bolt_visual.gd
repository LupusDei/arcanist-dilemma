class_name BoltVisual
extends Node3D
## The look of a projectile in flight: a white-hot core in a flickering halo,
## lightning tendrils, a comet trail, shed embers, a light and a crackle.
## Lives under a SpellProjectile; `detach` lets the trail and embers linger
## after the projectile is gone.

var visual: SpellVisual
## 1 for a normal cast, up to visual.charge_scale for a full charge.
var power_scale := 1.0

var _wobble_root: Node3D
var _glow: MeshInstance3D
var _glow_material: ShaderMaterial
var _core: MeshInstance3D
var _light: OmniLight3D
var _embers: SparkParticles
var _arcs: LightningArcs
var _trail: BoltTrail
var _crackle: AudioStreamPlayer3D
var _age := 0.0
var _seed := 0.0


func setup(p_visual: SpellVisual, p_power_scale: float, effects_parent: Node) -> BoltVisual:
	visual = p_visual
	power_scale = p_power_scale
	_seed = randf() * 100.0
	_wobble_root = Node3D.new()
	add_child(_wobble_root)

	var size := visual.size * power_scale
	_glow_material = VfxLib.shader_material(VfxLib.BOLT_GLOW, {
		"core_color": visual.core_color,
		"glow_color": visual.glow_color,
		"rim_color": visual.rim_color,
		"intensity": visual.intensity,
		"flicker": visual.flicker,
		"core_size": 0.2,
		"seed": _seed,
	})
	_glow = VfxLib.add_quad(_wobble_root, _glow_material, size)
	# A second, tighter sprite keeps the center blinding at any angle.
	_core = VfxLib.add_quad(_wobble_root, VfxLib.shader_material(VfxLib.BOLT_GLOW, {
		"core_color": Color.WHITE,
		"glow_color": visual.core_color,
		"rim_color": visual.glow_color,
		"intensity": visual.intensity * 0.9,
		"flicker": 0.2,
		"core_size": 0.35,
		"seed": _seed + 3.0,
	}), size * 0.45)

	_light = OmniLight3D.new()
	_light.light_color = visual.glow_color.lerp(Color.WHITE, 0.3)
	_light.light_energy = visual.light_energy * power_scale
	_light.omni_range = visual.light_range * sqrt(power_scale)
	_light.shadow_enabled = false
	_wobble_root.add_child(_light)

	_embers = _make_embers()
	if effects_parent:
		effects_parent.add_child(_embers)

	if visual.arc_count > 0:
		_arcs = LightningArcs.new()
		_arcs.mode = LightningArcs.Mode.AROUND
		_arcs.count = visual.arc_count + int(power_scale > 1.3) * 2
		_arcs.reach = visual.arc_reach * power_scale
		_arcs.width = 0.06 * power_scale
		_arcs.follow = _wobble_root
		_arcs.style(visual)
		add_child(_arcs)

	_trail = BoltTrail.new().setup(_wobble_root, visual, power_scale)
	if effects_parent:
		effects_parent.add_child(_trail)

	if visual.sound_set != &"":
		_crackle = SpellSfx.play_at(self, global_position if is_inside_tree() else Vector3.ZERO, &"crackle", -14.0, randf_range(0.9, 1.15))
	return self


func _process(delta: float) -> void:
	_age += delta
	if _wobble_root == null:
		return
	var w := visual.wobble * power_scale
	_wobble_root.position = Vector3(sin(_age * 31.0 + _seed) * w, cos(_age * 23.0 + _seed * 2.0) * w, 0.0)
	# Quick swell on launch, then a slow breathing pulse.
	var swell := minf(_age / 0.06, 1.0)
	var pulse := 1.0 + 0.12 * sin(_age * 40.0 + _seed)
	_glow.scale = Vector3.ONE * visual.size * power_scale * swell * pulse
	_light.light_energy = visual.light_energy * power_scale * (0.8 + 0.4 * randf())


## Lets the trail and embers (which live in the world) fade out naturally.
func detach() -> void:
	if _trail and is_instance_valid(_trail):
		_trail.release()
	if _embers and is_instance_valid(_embers):
		_embers.emitting = false
	if _crackle and is_instance_valid(_crackle):
		_crackle.stop()


func _make_embers() -> SparkParticles:
	var p := SparkParticles.new().colors(visual.core_color, visual.spark_color, visual.trail_outer)
	p.follow = _wobble_root
	p.rate = visual.ember_rate * power_scale
	p.emitting = true
	p.emit_radius = 0.08 * power_scale
	p.emit_speed = Vector2(0.3, 1.6)
	p.emit_size = Vector2(0.04, 0.11) * power_scale
	p.emit_life = Vector2(0.3, 0.6)
	p.gravity = Vector3(0, -2.5, 0)
	p.damping = 2.0
	return p
