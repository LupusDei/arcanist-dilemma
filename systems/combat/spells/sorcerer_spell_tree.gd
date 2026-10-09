class_name SorcererSpellTree
extends SpellSource
## Sorcerer growth: the whole tree (3 branches x 6 rows) is visible from the
## path choice. One point per level learns a spell or raises its rank (1 to 5).
## Each rank adds 20% power and 10% strain; each rank of the synergy partner adds 5%.
##
## Spell power from Vitality comes in through CombatStats.spell_power.

const BRANCHES: Array[StringName] = [&"storm", &"force", &"surge"]
const MAX_RANK := 5
const RANK_POWER := 0.2
const RANK_COST := 0.1
const SYNERGY_POWER := 0.05
const FIRST_ROW_LEVEL := 5
const LEVELS_PER_ROW := 3

## Spell id -> rank (0 or missing means not learned).
var ranks: Dictionary = {}
var points := 0
## Learned spell ids in bar order.
var bar_order: Array[StringName] = []

var _point_level := 0


func _init(p_level := 5) -> void:
	_point_level = p_level
	level = p_level
	cantrip = SpellLibrary.get_spell(&"spark")


func get_path() -> CombatStats.Path:
	return CombatStats.Path.SORCERER


func create_resource(stats: CombatStats) -> CasterResource:
	var strain := StrainPool.new(100.0 + stats.bonus_strain_capacity)
	strain.regen_multiplier = stats.resource_regen
	return strain


## Every sorcerer spell in the library, the full tree.
func get_tree() -> Array[SpellData]:
	var tree: Array[SpellData] = []
	for spell in SpellLibrary.spells_for_path(SpellData.PathTag.SORCERER):
		if spell.tree_branch != &"":
			tree.append(spell)
	tree.sort_custom(func(a: SpellData, b: SpellData) -> bool:
		return a.tree_row < b.tree_row if a.tree_row != b.tree_row else BRANCHES.find(a.tree_branch) < BRANCHES.find(b.tree_branch))
	return tree


static func row_level(row: int) -> int:
	return FIRST_ROW_LEVEL + LEVELS_PER_ROW * row


func get_rank(spell_id: StringName) -> int:
	return ranks.get(spell_id, 0)


## Empty if a point can go into this spell now, otherwise why not.
func check_learn(spell_id: StringName) -> StringName:
	var spell := SpellLibrary.get_spell(spell_id)
	if spell == null or spell.tree_branch == &"":
		return &"not_in_tree"
	if points <= 0:
		return &"no_points"
	if get_rank(spell_id) >= MAX_RANK:
		return &"max_rank"
	if level < row_level(spell.tree_row):
		return &"row_locked"
	if spell.tree_row > 0 and get_rank(spell_id) == 0:
		var parent := _spell_at(spell.tree_branch, spell.tree_row - 1)
		if parent and get_rank(parent.id) == 0:
			return &"needs_previous"
	return &""


## Spends a point to learn or rank up a spell.
func learn(spell_id: StringName) -> bool:
	if check_learn(spell_id) != &"":
		return false
	points -= 1
	ranks[spell_id] = get_rank(spell_id) + 1
	if ranks[spell_id] == 1 and bar_order.size() < BAR_SIZE:
		bar_order.append(spell_id)
	changed.emit()
	return true


func get_bar() -> Array[SpellData]:
	var spells: Array[SpellData] = []
	for id in bar_order:
		spells.append(SpellLibrary.get_spell(id))
	return _pad_bar(spells)


func set_bar(ids: Array[StringName]) -> void:
	bar_order.clear()
	for id in ids:
		if get_rank(id) > 0 and id not in bar_order and bar_order.size() < BAR_SIZE:
			bar_order.append(id)
	changed.emit()


func get_effective_rank(spell: SpellData) -> int:
	var rank := get_rank(spell.id)
	return rank + int(gear_bonus_ranks.get(spell.id, 0)) if rank > 0 else 0


func get_power_multiplier(spell: SpellData) -> float:
	if spell == cantrip:
		return 1.0 + 0.1 * (level - 1)
	var rank := maxi(get_effective_rank(spell), 1)
	var synergy := get_rank(spell.synergy_id) if spell.synergy_id != &"" else 0
	return (1.0 + RANK_POWER * (rank - 1)) * (1.0 + SYNERGY_POWER * synergy)


func get_cost_multiplier(spell: SpellData) -> float:
	return 1.0 + RANK_COST * (maxi(get_effective_rank(spell), 1) - 1)


func check_cast(spell: SpellData) -> StringName:
	if spell == cantrip:
		return &""
	return &"" if get_rank(spell.id) > 0 else &"not_learned"


func describe_growth(spell: SpellData) -> String:
	return "Rank %d" % get_effective_rank(spell)


## One point per level gained.
func _on_level_changed() -> void:
	while _point_level < level:
		_point_level += 1
		points += 1



## The path choice at level 5 grants 4 points (one for each level so far).
func grant_starting_points() -> void:
	points += 4
	changed.emit()


func _spell_at(branch: StringName, row: int) -> SpellData:
	for spell in get_tree():
		if spell.tree_branch == branch and spell.tree_row == row:
			return spell
	return null
