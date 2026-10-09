class_name CasterResource
extends RefCounted
## A path's casting resource. Wizards spend Arcana, mages spend Mana and
## sorcerers build Strain. SpellCaster asks `can_pay`, then `pay`, then `tick`s it.

signal changed(current: float, maximum: float)

var current := 0.0
var maximum := 100.0
## Multiplier on regeneration (Wisdom).
var regen_multiplier := 1.0


func get_display_name() -> String:
	return "Resource"


func can_pay(cost: float) -> bool:
	return cost <= 0.0 or current >= cost


## Spends `cost`. Returns false (and spends nothing) if it can't be paid.
func pay(cost: float) -> bool:
	if not can_pay(cost):
		return false
	if cost > 0.0:
		_set_current(current - cost)
	return true


## Called every frame by the caster. `in_combat` is true for a few seconds after
## casting or taking damage.
func tick(_delta: float, _in_combat: bool) -> void:
	pass


## Resting refills everything.
func refill() -> void:
	_set_current(maximum)


## Extra damage multiplier this resource currently grants (overstrain).
func get_power_multiplier() -> float:
	return 1.0


## 0 to 1 for a resource bar.
func get_fill() -> float:
	return current / maximum if maximum > 0.0 else 0.0


func set_maximum(value: float) -> void:
	maximum = maxf(value, 1.0)
	_set_current(minf(current, maximum))


func _set_current(value: float) -> void:
	if is_equal_approx(value, current):
		return
	current = value
	changed.emit(current, maximum)
