class_name CombatFeedback
extends Node
## Everything the player feels when their spells fire and land: the reticle,
## hit markers, damage numbers, camera kick and hit-stop on big hits, and the
## charge orb in the casting hand, and a camera kick when the caster is hurt.
## PlayerCombatInput adds one of these; any SpellCaster can be watched.
##
## Targets on the PROP_TEAM team (chore props in the opening) take spell hits
## quietly: no numbers, markers or hit-stop. The reticle turns red over an
## enemy and gold over a prop.

const PROP_TEAM := &"prop"
const ENEMY_TINT := Color(1.0, 0.3, 0.25)
const PROP_TINT := Color(1.0, 0.8, 0.3)
## How far from the aim ray a target's hit sphere may sit and still count.
const AIM_TOLERANCE := 0.35

@export var caster: SpellCaster
@export var show_reticle := true
@export var show_damage_numbers := true
@export var camera_shake := true
## Shake the camera when the caster's own HealthComponent takes damage.
@export var shake_when_hurt := true
## Aim at the mouse cursor instead of the screen centre (matches PlayerCombatInput).
var aim_at_cursor := false
## Returns the world point being aimed at; targets beyond it (behind a wall)
## don't tint the reticle. Optional.
var aim_provider: Callable

var reticle: SpellReticle
var kick: CameraKick

var _layer: CanvasLayer
var _orb: ChargeOrb


func _ready() -> void:
	if caster == null:
		caster = get_parent().get_node_or_null(^"SpellCaster") as SpellCaster
	if caster == null:
		return
	kick = CameraKick.new()
	add_child(kick)
	if show_reticle:
		_layer = CanvasLayer.new()
		_layer.layer = 5
		add_child(_layer)
		reticle = SpellReticle.new()
		_layer.add_child(reticle)
	caster.hit_landed.connect(_on_hit_landed)
	caster.spell_cast.connect(_on_spell_cast)
	caster.charge_started.connect(_on_charge_started)
	caster.charge_ended.connect(_on_charge_ended)
	if caster.health:
		caster.health.damaged.connect(_on_hurt)


func _process(_delta: float) -> void:
	if caster == null:
		return
	if reticle:
		reticle.charging = caster.is_charging()
		reticle.charge = caster.get_charge()
		var cantrip := caster.get_cantrip()
		if cantrip and cantrip.visual:
			reticle.accent = cantrip.visual.glow_color
			reticle.rim = cantrip.visual.rim_color
		reticle.target_tint = _tint_for(target_under_reticle()) if reticle.visible else Color.TRANSPARENT
	if _orb and is_instance_valid(_orb):
		_orb.charge = caster.get_charge()


func _on_spell_cast(spell: SpellData) -> void:
	if reticle:
		reticle.show_fire()
	if camera_shake and spell.visual:
		kick.add_trauma(spell.visual.launch_shake * (1.0 + 2.0 * caster.last_charge))


## The living, hostile-or-prop target the reticle is over, nearest first, or null.
func target_under_reticle() -> HealthComponent:
	var camera := get_viewport().get_camera_3d()
	if camera == null or caster == null:
		return null
	var screen := get_viewport().get_mouse_position() if aim_at_cursor else get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var limit := INF
	if aim_provider.is_valid():
		limit = (aim_provider.call() as Vector3 - from).dot(dir) + 1.0
	var own_team := caster.health.team if caster.health else &"player"
	var best: HealthComponent = null
	var best_depth := INF
	for node in get_tree().get_nodes_in_group(HealthComponent.GROUP):
		var target := node as HealthComponent
		if target == null or target.is_dead or target.team == own_team or not target.is_inside_tree():
			continue
		var to := target.get_target_position() - from
		var depth := to.dot(dir)
		if depth <= 0.0 or depth > limit or depth >= best_depth:
			continue
		if (to - dir * depth).length() <= target.hit_radius + AIM_TOLERANCE:
			best = target
			best_depth = depth
	return best


func _tint_for(target: HealthComponent) -> Color:
	if target == null:
		return Color.TRANSPARENT
	return PROP_TINT if target.team == PROP_TEAM else ENEMY_TINT


func _on_hurt(_hit: Hit, amount: float) -> void:
	if not shake_when_hurt or amount <= 0.0 or caster.health == null:
		return
	kick.add_trauma(clampf(amount / caster.health.max_health * 3.0, 0.2, 0.6))


func _on_hit_landed(target: HealthComponent, amount: float, crit: bool, killed: bool, spell: SpellData, charge: float) -> void:
	if is_instance_valid(target) and target.team == PROP_TEAM:
		if spell and spell.visual and camera_shake:
			kick.add_trauma(spell.visual.impact_shake * 0.5)
		return
	if reticle:
		reticle.show_hit(crit, killed)
	if show_damage_numbers and is_instance_valid(target):
		var color := spell.get_color() if spell else Color.WHITE
		DamageNumber.spawn(caster._get_effects_parent(), target.get_target_position() + Vector3.UP * (target.center_height * 0.6), amount, color, crit, killed)
	if spell and spell.visual and camera_shake:
		kick.add_trauma(spell.visual.impact_shake * (0.5 + charge * 1.5) + (0.25 if killed else 0.0))
	if charge >= 1.0 or (killed and charge > 0.5):
		CameraKick.hitstop(get_tree(), 0.07)


func _on_charge_started(spell: SpellData) -> void:
	if spell.visual == null:
		return
	if _orb and is_instance_valid(_orb):
		_orb.queue_free()
	_orb = ChargeOrb.new().setup(spell.visual, caster.get_launch_point)
	caster._get_effects_parent().add_child(_orb)


func _on_charge_ended(_spell: SpellData, _released: bool) -> void:
	if _orb and is_instance_valid(_orb):
		_orb.finish()
	_orb = null
