class_name TrickSet
extends SpellSource
## Levels 1 to 4, before the path choice: Spark, Nudge and Jolt, which grow
## stronger on their own (10% per level).

const TRICK_IDS: Array[StringName] = [&"spark", &"nudge", &"jolt"]


func _init() -> void:
	cantrip = SpellLibrary.get_spell(&"spark")


func get_bar() -> Array[SpellData]:
	var spells: Array[SpellData] = []
	for id in TRICK_IDS:
		var spell := SpellLibrary.get_spell(id)
		if spell:
			spells.append(spell)
	return _pad_bar(spells)


func get_power_multiplier(_spell: SpellData) -> float:
	return 1.0 + 0.1 * (level - 1)


func describe_growth(_spell: SpellData) -> String:
	return "Grows with level (+%d%%)" % roundi(10 * (level - 1))
