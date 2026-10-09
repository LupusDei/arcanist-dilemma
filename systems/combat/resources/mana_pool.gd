class_name ManaPool
extends CasterResource
## Mage Mana: a medium pool. Regeneration depends on Wisdom and on how mana-rich
## the place is; standing on a ley line sets `ley_multiplier` high.

var base_regen := 4.0
## Set by ley lines and mana-rich zones; 1.0 is an ordinary place.
var ley_multiplier := 1.0


func _init(p_maximum := 100.0) -> void:
	maximum = p_maximum
	current = maximum


func get_display_name() -> String:
	return "Mana"


func tick(delta: float, _in_combat: bool) -> void:
	if current >= maximum:
		return
	_set_current(minf(current + base_regen * regen_multiplier * ley_multiplier * delta, maximum))
