class_name EnemyHealth
extends Node
## Stand-in for the combat system's HealthComponent (res://systems/combat/).
##
## Mirrors the parts of its API the enemies use, so swapping this script for the
## real HealthComponent on the "HealthComponent" node of each enemy scene is the
## whole migration. take_damage() accepts a combat Hit (anything with an
## `amount` property and optionally `source`) or a plain number.

signal health_changed(current: float, maximum: float)
signal damaged(hit: Object, amount: float)
signal healed(amount: float)
signal died(killer: Node)

enum Tier { NORMAL, ELITE, BOSS }

@export var max_health := 100.0
@export var armor := 0.0
@export var team: StringName = &"enemy"
@export var tier: Tier = Tier.NORMAL

var current_health := 0.0


func _ready() -> void:
	current_health = max_health


func is_dead() -> bool:
	return current_health <= 0.0


## Returns the damage actually dealt after armor.
func take_damage(hit: Variant) -> float:
	if is_dead():
		return 0.0
	var hit_object: Object = hit if hit is Object else EnemyDamage.make_local_hit(float(hit), null)
	var raw: float = hit_object.get("amount")
	var amount := clampf(raw - armor, 0.0, current_health)
	if amount <= 0.0:
		return 0.0
	current_health -= amount
	damaged.emit(hit_object, amount)
	health_changed.emit(current_health, max_health)
	if is_dead():
		died.emit(hit_object.get("source") as Node)
	return amount


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	var healed_amount := minf(amount, max_health - current_health)
	if healed_amount <= 0.0:
		return
	current_health += healed_amount
	healed.emit(healed_amount)
	health_changed.emit(current_health, max_health)


## Back to full health, including from dead (used for respawns and leash resets).
func reset() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
