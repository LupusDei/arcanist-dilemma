class_name CombatFeedback
extends Node
## Everything the player feels when their spells fire and land: the reticle,
## hit markers, damage numbers, camera kick and hit-stop on big hits, and the
## charge orb in the casting hand. PlayerCombatInput adds one of these; any
## SpellCaster can be watched.

@export var caster: SpellCaster
@export var show_reticle := true
@export var show_damage_numbers := true
@export var camera_shake := true

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
	if _orb and is_instance_valid(_orb):
		_orb.charge = caster.get_charge()


func _on_spell_cast(spell: SpellData) -> void:
	if reticle:
		reticle.show_fire()
	if camera_shake and spell.visual:
		kick.add_trauma(spell.visual.launch_shake * (1.0 + 2.0 * caster.last_charge))


func _on_hit_landed(target: HealthComponent, amount: float, crit: bool, killed: bool, spell: SpellData, charge: float) -> void:
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
