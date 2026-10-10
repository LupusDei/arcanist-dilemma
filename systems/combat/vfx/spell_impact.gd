class_name SpellImpact
extends Node3D
## The moment a bolt lands: a blinding pop, a shock ring, a shower of sparks,
## branching lightning, a light flash, a crack, a scorch mark on surfaces and
## crackling arcs over whatever it hit. Frees itself when done.

const LIFETIME := 1.4

var visual: SpellVisual
var power_scale := 1.0

var _age := 0.0
var _flash: MeshInstance3D
var _flash_material: ShaderMaterial
var _ring: MeshInstance3D
var _ring_material: ShaderMaterial
var _light: OmniLight3D
var _crawl: LightningArcs
var _crawl_target: HealthComponent


## `normal` is the surface normal for wall and ground hits (zero for a body hit).
## `target` gets arcs crawling over it.
static func spawn(parent: Node, at: Vector3, normal: Vector3, p_visual: SpellVisual, p_power_scale := 1.0, target: HealthComponent = null) -> SpellImpact:
	if parent == null or not parent.is_inside_tree():
		return null
	var impact := SpellImpact.new()
	impact.visual = p_visual
	impact.power_scale = p_power_scale
	parent.add_child(impact)
	impact.global_position = at
	impact._build(normal, target)
	return impact


func _build(normal: Vector3, target: HealthComponent) -> void:
	var radius := visual.impact_radius * power_scale
	var facing := normal if normal.length_squared() > 0.01 else Vector3.ZERO

	_flash_material = VfxLib.shader_material(VfxLib.BOLT_GLOW, {
		"core_color": Color.WHITE,
		"glow_color": visual.glow_color,
		"rim_color": visual.rim_color,
		"intensity": visual.intensity * 1.1,
		"flicker": 0.6,
		"core_size": 0.3,
		"seed": randf() * 50.0,
	})
	_flash = VfxLib.add_quad(self, _flash_material, radius * 0.5)

	_ring_material = VfxLib.shader_material(VfxLib.SHOCKWAVE, {
		"color": visual.glow_color.lerp(visual.rim_color, 0.3),
		"intensity": visual.intensity,
		"progress": 0.0,
		"billboard": facing == Vector3.ZERO,
	})
	_ring = VfxLib.add_quad(self, _ring_material, radius * 2.4)
	if facing != Vector3.ZERO:
		_ring.position = facing * 0.04
		_ring.look_at(global_position + facing * 2.0, Vector3.UP if absf(facing.y) < 0.95 else Vector3.FORWARD)

	var sparks := SparkParticles.new().colors(Color.WHITE, visual.spark_color, visual.rim_color)
	sparks.gravity = Vector3(0, -14, 0)
	sparks.damping = 2.5
	add_child(sparks)
	sparks.burst(int(visual.impact_sparks * clampf(power_scale, 1.0, 2.5)), global_position,
		facing if facing != Vector3.ZERO else Vector3.UP, 75.0 if facing != Vector3.ZERO else 179.0,
		Vector2(3.0, 9.0) * sqrt(power_scale), Vector2(0.05, 0.13) * power_scale, Vector2(0.35, 0.75))

	if visual.impact_branches > 0:
		var burst := LightningArcs.new()
		burst.mode = LightningArcs.Mode.BURST
		burst.count = visual.impact_branches + int(power_scale > 1.3) * 3
		burst.reach = radius * 1.3
		burst.width = 0.05 * power_scale
		burst.lifetime = 0.22
		burst.center = global_position
		burst.style(visual, 2.6)
		add_child(burst)

	if target and is_instance_valid(target):
		var crawl := LightningArcs.new()
		crawl.mode = LightningArcs.Mode.AROUND
		crawl.count = 4
		crawl.reach = target.hit_radius * 1.8
		crawl.width = 0.03
		crawl.lifetime = 0.5 + 0.3 * power_scale
		crawl.center = target.get_target_position()
		crawl.style(visual, 2.0)
		add_child(crawl)
		_crawl = crawl
		_crawl_target = target

	_light = OmniLight3D.new()
	_light.light_color = visual.glow_color.lerp(Color.WHITE, 0.4)
	_light.light_energy = 6.0 * power_scale
	_light.omni_range = radius * 5.0
	add_child(_light)

	if visual.scorch and facing != Vector3.ZERO:
		ScorchMark.spawn(get_parent(), global_position + facing * 0.02, facing, visual, radius * 0.9)

	if visual.sound_set != &"":
		SpellSfx.play_at(self, global_position, &"crack", -2.0 + 3.0 * (power_scale - 1.0), randf_range(0.9, 1.1) / sqrt(power_scale))


func _process(delta: float) -> void:
	_age += delta
	var t := _age
	# Flash pops to full in 40ms and is gone by 220ms.
	var pop := minf(t / 0.04, 1.0) * (1.0 - smoothstep(0.04, 0.22, t))
	_flash.scale = Vector3.ONE * visual.impact_radius * power_scale * lerpf(0.4, 2.2, minf(t / 0.12, 1.0))
	_flash_material.set_shader_parameter("alpha", pop)
	_ring_material.set_shader_parameter("progress", clampf(t / 0.38, 0.0, 1.0))
	_light.light_energy = 6.0 * power_scale * maxf(1.0 - t / 0.3, 0.0)
	# Arcs ride the body they hit, centered on its middle.
	if is_instance_valid(_crawl) and is_instance_valid(_crawl_target):
		_crawl.center = _crawl_target.get_target_position()
	if _age >= LIFETIME:
		queue_free()
