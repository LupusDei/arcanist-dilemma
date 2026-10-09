class_name SpellSource
extends RefCounted
## Where a caster's spells come from and how strong they are. Each path grows its
## magic differently, so each path subclasses this: WizardSpellbook, MageCodex,
## SorcererSpellTree. Before level 5 the arcanist uses TrickSet.

signal changed

const BAR_SIZE := 7

## Character level. Progression sets this on level-up.
var level := 1:
	set(value):
		level = value
		_on_level_changed()
		changed.emit()
## The free left-click spell every path keeps.
var cantrip: SpellData
## Gear "+1 to a spell": spell id -> extra ranks.
var gear_bonus_ranks: Dictionary = {}
## True while at a rest spot. Some changes (wizard preparing) need it.
var is_resting := false


func get_path() -> CombatStats.Path:
	return CombatStats.Path.NONE


## Creates the casting resource this path uses.
func create_resource(stats: CombatStats) -> CasterResource:
	var mana := ManaPool.new(50.0 + stats.bonus_resource)
	mana.regen_multiplier = stats.resource_regen
	return mana


## Spells for the 7 bar slots (1 to 6 and right click). Entries may be null.
func get_bar() -> Array[SpellData]:
	return []


## Multiplier on this spell's damage, healing and wards from path growth.
func get_power_multiplier(_spell: SpellData) -> float:
	return 1.0


func get_cost_multiplier(_spell: SpellData) -> float:
	return 1.0


## Empty if the spell can be cast now, otherwise a reason such as &"not_prepared".
func check_cast(_spell: SpellData) -> StringName:
	return &""


## True if this cast fizzles harmlessly (a mage's first raw experiment).
func rolls_misfire(_spell: SpellData, _rng: RandomNumberGenerator, _stats: CombatStats) -> bool:
	return false


## Called after every resolved cast (mage practice, bookkeeping).
func on_cast(_spell: SpellData) -> void:
	pass


## A short, readable line about how strong the spell is right now ("Circle II").
func describe_growth(_spell: SpellData) -> String:
	return ""


func _on_level_changed() -> void:
	pass


static func _pad_bar(spells: Array[SpellData]) -> Array[SpellData]:
	var bar: Array[SpellData] = []
	for i in BAR_SIZE:
		bar.append(spells[i] if i < spells.size() else null)
	return bar
