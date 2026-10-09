class_name WizardSpellbook
extends SpellSource
## Wizard growth: one spellbook slot per level, filled by copying spells from
## books; circles open every 3 levels and need that circle's book; 7 spells
## (plus Intelligence pages) are prepared for the bar at a rest.

const CIRCLE_POWER := 1.35
const CIRCLE_COST := 1.15
const GEAR_RANK_POWER := 0.15
const BASE_PREPARED := 7
const MAX_CIRCLE := 7

## Spell id -> circle currently inscribed in the spellbook (uses a slot).
var spellbook: Dictionary = {}
## Spell id -> highest circle book owned. The Library at home; never lost.
var library: Dictionary = {}
## Variant spell ids owned (Searing Fireball etc.).
var variant_books: Array[StringName] = []
## Base spell id -> chosen variant spell id.
var chosen_variants: Dictionary = {}
## Prepared spell ids in bar order.
var prepared: Array[StringName] = []
var bonus_prepared := 0


func _init(p_level := 5) -> void:
	level = p_level
	cantrip = SpellLibrary.get_spell(&"spark")


func get_path() -> CombatStats.Path:
	return CombatStats.Path.WIZARD


func create_resource(stats: CombatStats) -> CasterResource:
	bonus_prepared = stats.bonus_prepared_spells
	var arcana := ArcanaPool.new(150.0 + stats.bonus_resource)
	arcana.regen_multiplier = stats.resource_regen
	return arcana


func get_slot_count() -> int:
	return level


func get_free_slots() -> int:
	return get_slot_count() - spellbook.size()


## Highest circle the wizard's level allows: I at 1, II at 4 ... VII at 19.
func get_open_circle() -> int:
	return clampi(1 + floori((level - 1) / 3.0), 1, MAX_CIRCLE)


func get_max_prepared() -> int:
	return BASE_PREPARED + bonus_prepared


## A book was found, bought or stolen. Goes to the Library.
func add_book(spell_id: StringName, circle := 1) -> void:
	var spell := SpellLibrary.get_spell(spell_id)
	if spell and spell.variant_of != &"":
		if spell_id not in variant_books:
			variant_books.append(spell_id)
	else:
		library[spell_id] = maxi(library.get(spell_id, 0), circle)
	changed.emit()


## Copies a spell from the Library into a free spellbook slot. Needs a rest.
func inscribe(spell_id: StringName) -> bool:
	if not is_resting or not library.has(spell_id) or spellbook.has(spell_id) or get_free_slots() <= 0:
		return false
	spellbook[spell_id] = 1
	changed.emit()
	return true


func erase(spell_id: StringName) -> bool:
	if not is_resting or not spellbook.has(spell_id):
		return false
	spellbook.erase(spell_id)
	prepared.erase(spell_id)
	changed.emit()
	return true


## Raises an inscribed spell to the best circle that is both open and owned.
func upgrade(spell_id: StringName) -> bool:
	if not is_resting or not spellbook.has(spell_id):
		return false
	var spell := SpellLibrary.get_spell(spell_id)
	var cap := mini(get_open_circle(), spell.max_circle if spell else MAX_CIRCLE)
	var target := mini(int(library.get(spell_id, 1)), cap)
	if target <= spellbook[spell_id]:
		return false
	spellbook[spell_id] = target
	changed.emit()
	return true


## Picks which variant book a spell follows. Needs a rest and the book.
func choose_variant(base_id: StringName, variant_id: StringName) -> bool:
	if not is_resting or variant_id not in variant_books:
		return false
	var variant := SpellLibrary.get_spell(variant_id)
	if variant == null or variant.variant_of != base_id:
		return false
	chosen_variants[base_id] = variant_id
	changed.emit()
	return true


## Sets the bar. Only at a rest, only inscribed spells, up to the prepared limit.
func prepare(spell_ids: Array[StringName]) -> bool:
	if not is_resting:
		return false
	var limit := mini(get_max_prepared(), BAR_SIZE + bonus_prepared)
	var result: Array[StringName] = []
	for id in spell_ids:
		if spellbook.has(id) and id not in result and result.size() < limit:
			result.append(id)
	prepared = result
	changed.emit()
	return true


func get_circle(spell: SpellData) -> int:
	var base := _base_id(spell)
	return spellbook.get(base, 0)


func get_bar() -> Array[SpellData]:
	var spells: Array[SpellData] = []
	for id in prepared.slice(0, BAR_SIZE):
		spells.append(_resolve(id))
	return _pad_bar(spells)


func get_power_multiplier(spell: SpellData) -> float:
	if spell == cantrip:
		return 1.0 + 0.1 * (level - 1)
	var circle := maxi(get_circle(spell), 1)
	var gear: int = gear_bonus_ranks.get(_base_id(spell), 0)
	return pow(CIRCLE_POWER, circle - 1) * (1.0 + GEAR_RANK_POWER * gear)


func get_cost_multiplier(spell: SpellData) -> float:
	return pow(CIRCLE_COST, maxi(get_circle(spell), 1) - 1)


func check_cast(spell: SpellData) -> StringName:
	if spell == cantrip:
		return &""
	if _base_id(spell) not in prepared:
		return &"not_prepared"
	return &""


func describe_growth(spell: SpellData) -> String:
	return "Circle %s" % _roman(maxi(get_circle(spell), 1))


## The spell that actually fires for an inscribed id: a chosen variant once its
## circle is reached, otherwise the base spell.
func _resolve(id: StringName) -> SpellData:
	var variant_id: StringName = chosen_variants.get(id, &"")
	if variant_id != &"":
		var variant := SpellLibrary.get_spell(variant_id)
		if variant and spellbook.get(id, 0) >= variant.variant_circle:
			return variant
	return SpellLibrary.get_spell(id)


func _base_id(spell: SpellData) -> StringName:
	return spell.variant_of if spell.variant_of != &"" else spell.id


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII"][clampi(n, 0, 7)]
