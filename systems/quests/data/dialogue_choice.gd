class_name DialogueChoice
extends Resource
## A reply the player can pick. Its alignment effects are shown as a hint
## ("Lawful", "Chaotic, Good") before the player commits.

@export_multiline var text := ""
@export var conditions: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []
@export var next: StringName
## Show it greyed out (with [member locked_text]) instead of hiding it when conditions fail.
@export var show_locked := false
@export var locked_text := ""
## Overrides the hint worked out from the effects; "-" hides it.
@export var hint := ""


## Total alignment shift this choice causes, as Vector2(law, good).
func alignment_shift() -> Vector2:
	var shift := Vector2.ZERO
	for effect in effects:
		var a: Variant = effect.get("alignment")
		if a is Dictionary:
			shift.x += float(a.get("law", 0.0))
			shift.y += float(a.get("good", 0.0))
	return shift


func lean_hint() -> String:
	if hint == "-":
		return ""
	if not hint.is_empty():
		return hint
	var shift := alignment_shift()
	return Alignment.describe_shift(shift.x, shift.y)
