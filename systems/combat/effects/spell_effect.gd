class_name SpellEffect
extends Resource
## Base class for what a spell does to one target. Subclass and override `apply`.


## Applies this effect to `target`. `impact` is where the spell landed.
func apply(_target: HealthComponent, _context: SpellContext, _impact: Vector3) -> void:
	pass


## One line for tooltips.
func describe(_context: SpellContext) -> String:
	return ""
