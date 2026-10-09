class_name StrainPool
extends CasterResource
## Sorcerer Strain: starts at 0, climbs as you cast and fades when you stop.
## It never blocks a cast. Past capacity (`maximum`) the sorcerer overstrains:
## spells deal 25% more but hurt the caster, and at 150% they collapse.

signal overstrain_started
signal overstrain_ended
signal collapsed

const OVERSTRAIN_BONUS := 1.25
const COLLAPSE_RATIO := 1.5

var fade_per_second := 10.0
## Seconds after the last cast before strain starts fading.
var fade_delay := 0.5
## Health lost per point of strain gained while overstrained.
var backlash_per_strain := 0.5
var collapse_stun := 2.0

var _since_cast := 0.0
var _was_overstrained := false


func _init(p_capacity := 100.0) -> void:
	maximum = p_capacity
	current = 0.0


func get_display_name() -> String:
	return "Strain"


func can_pay(_cost: float) -> bool:
	return true


func pay(cost: float) -> bool:
	_since_cast = 0.0
	if cost > 0.0:
		_set_current(current + cost)
	_update_overstrain()
	if current >= maximum * COLLAPSE_RATIO:
		collapsed.emit()
	return true


func tick(delta: float, _in_combat: bool) -> void:
	_since_cast += delta
	if _since_cast < fade_delay or current <= 0.0:
		return
	_set_current(maxf(current - fade_per_second * regen_multiplier * delta, 0.0))
	_update_overstrain()


## Resting clears strain.
func refill() -> void:
	_set_current(0.0)
	_update_overstrain()


func is_overstrained() -> bool:
	return current > maximum


func get_power_multiplier() -> float:
	return OVERSTRAIN_BONUS if is_overstrained() else 1.0


## Health the caster loses for gaining `cost` strain right now.
func get_backlash(cost: float) -> float:
	return cost * backlash_per_strain if is_overstrained() else 0.0


## Fill relative to the collapse point, so the bar shows how close the edge is.
func get_fill() -> float:
	return current / (maximum * COLLAPSE_RATIO)


func _update_overstrain() -> void:
	var over := is_overstrained()
	if over != _was_overstrained:
		_was_overstrained = over
		if over:
			overstrain_started.emit()
		else:
			overstrain_ended.emit()
