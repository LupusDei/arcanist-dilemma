class_name ArcanaPool
extends CasterResource
## Wizard Arcana: a large pool that refills slowly in a fight and fully a few
## seconds after it.

var combat_regen := 2.0
var rest_regen := 60.0


func _init(p_maximum := 150.0) -> void:
	maximum = p_maximum
	current = maximum


func get_display_name() -> String:
	return "Arcana"


func tick(delta: float, in_combat: bool) -> void:
	if current >= maximum:
		return
	var rate := combat_regen if in_combat else rest_regen
	_set_current(minf(current + rate * regen_multiplier * delta, maximum))
