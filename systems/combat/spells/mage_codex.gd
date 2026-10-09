class_name MageCodex
extends SpellSource
## Mage growth: words (verbs and nouns) are learned in the world; any known pair
## can be cast raw as an experiment (half power, double mana, a first-time
## misfire chance), which writes it into the Codex; an Insight every second level
## formulates a Codex pair into a true spell. Practice raises word mastery.
##
## Spell power from Intelligence comes in through CombatStats.spell_power.

const VERBS: Array[StringName] = [&"move", &"burn", &"chill", &"bind", &"break", &"mend", &"reveal", &"shape"]
const NOUNS: Array[StringName] = [&"air", &"water", &"earth", &"metal", &"wood", &"flesh", &"mind", &"light"]
const RAW_POWER := 0.5
const RAW_COST := 2.0
const MASTERY_BONUS := 0.04
## Casts needed to reach mastery 2, 3, 4 and 5.
const MASTERY_THRESHOLDS: Array[int] = [10, 30, 70, 150]

var known_words: Array[StringName] = []
## Pair key ("burn+air") -> true once cast at least once.
var discovered: Dictionary = {}
## Pair key -> true once formulated with Insight.
var formulated: Dictionary = {}
## Word -> number of casts that used it.
var practice: Dictionary = {}
var insight := 0
## Formulated pair keys in bar order.
var bar_order: Array[StringName] = []

var _insight_level := 0


func _init(p_level := 5) -> void:
	_insight_level = p_level
	level = p_level
	cantrip = SpellLibrary.get_spell(&"spark")


func get_path() -> CombatStats.Path:
	return CombatStats.Path.MAGE


func create_resource(stats: CombatStats) -> CasterResource:
	var mana := ManaPool.new(100.0 + stats.bonus_resource)
	mana.regen_multiplier = stats.resource_regen
	return mana


## The three tricks become the mage's starting spells at the path choice.
func grant_starting_kit() -> void:
	for word in [&"burn", &"air", &"move", &"metal", &"bind", &"mind"]:
		learn_word(word)
	for pair in [[&"burn", &"air"], [&"move", &"metal"], [&"bind", &"mind"]]:
		var key := pair_key(pair[0], pair[1])
		discovered[key] = true
		formulated[key] = true
		bar_order.append(key)
	changed.emit()


func learn_word(word: StringName) -> bool:
	if word in known_words or not (word in VERBS or word in NOUNS):
		return false
	known_words.append(word)
	changed.emit()
	return true


func knows_pair(verb: StringName, noun: StringName) -> bool:
	return verb in known_words and noun in known_words and verb in VERBS and noun in NOUNS


## The spell for a pair: the authored one in data/spells/mage/, or one built from
## the verb and noun rules. Null if the mage doesn't know both words.
func get_pair_spell(verb: StringName, noun: StringName) -> SpellData:
	if not knows_pair(verb, noun):
		return null
	var spell := SpellLibrary.find_pair(verb, noun)
	if spell == null:
		spell = MagePairRules.build(verb, noun)
		SpellLibrary.register(spell)
	return spell


## Spends one Insight to turn a discovered pair into a true spell. Needs a rest.
func formulate(verb: StringName, noun: StringName) -> bool:
	var key := pair_key(verb, noun)
	if not is_resting or insight <= 0 or not discovered.has(key) or formulated.has(key):
		return false
	insight -= 1
	formulated[key] = true
	if bar_order.size() < BAR_SIZE:
		bar_order.append(key)
	changed.emit()
	return true


func is_formulated(spell: SpellData) -> bool:
	return formulated.has(pair_key(spell.verb, spell.noun))


func get_mastery(word: StringName) -> int:
	var casts: int = practice.get(word, 0)
	var mastery := 1
	for threshold in MASTERY_THRESHOLDS:
		if casts >= threshold:
			mastery += 1
	return mastery


func get_bar() -> Array[SpellData]:
	var spells: Array[SpellData] = []
	for key in bar_order:
		var words := String(key).split("+")
		spells.append(get_pair_spell(StringName(words[0]), StringName(words[1])))
	return _pad_bar(spells)


## Rearranges the bar. Mages can do this any time out of combat.
func set_bar(keys: Array[StringName]) -> void:
	bar_order.clear()
	for key in keys:
		if formulated.has(key) and key not in bar_order and bar_order.size() < BAR_SIZE:
			bar_order.append(key)
	changed.emit()


func get_power_multiplier(spell: SpellData) -> float:
	if spell == cantrip:
		return 1.0 + 0.1 * (level - 1)
	var mastery := 1.0 + MASTERY_BONUS * (get_mastery(spell.verb) - 1 + get_mastery(spell.noun) - 1)
	return mastery * (1.0 if is_formulated(spell) else RAW_POWER)


func get_cost_multiplier(spell: SpellData) -> float:
	if spell == cantrip or is_formulated(spell):
		return 1.0
	return RAW_COST


func check_cast(spell: SpellData) -> StringName:
	if spell == cantrip:
		return &""
	if not knows_pair(spell.verb, spell.noun):
		return &"unknown_words"
	return &""


func rolls_misfire(spell: SpellData, rng: RandomNumberGenerator, stats: CombatStats) -> bool:
	if spell == cantrip or discovered.has(pair_key(spell.verb, spell.noun)):
		return false
	return rng.randf() < stats.misfire_chance


func on_cast(spell: SpellData) -> void:
	if spell == cantrip or spell.verb == &"":
		return
	var key := pair_key(spell.verb, spell.noun)
	var is_new := not discovered.has(key)
	discovered[key] = true
	practice[spell.verb] = int(practice.get(spell.verb, 0)) + 1
	practice[spell.noun] = int(practice.get(spell.noun, 0)) + 1
	if is_new:
		changed.emit()


func describe_growth(spell: SpellData) -> String:
	var state := "Formulated" if is_formulated(spell) else "Raw experiment"
	return "%s · %s %d, %s %d" % [state, spell.verb.capitalize(), get_mastery(spell.verb), spell.noun.capitalize(), get_mastery(spell.noun)]


## Every second level from 6 gives one Insight, granted as `level` rises.
func _on_level_changed() -> void:
	while _insight_level < level:
		_insight_level += 1
		if _insight_level >= 6 and _insight_level % 2 == 0:
			insight += 1


static func pair_key(verb: StringName, noun: StringName) -> StringName:
	return StringName("%s+%s" % [verb, noun])
