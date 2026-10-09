class_name LootRoller
extends RefCounted
## Seeded loot tables keyed by source, biome and level (res://data/items/loot.json).
##
##   var rng := LootRoller.rng_for(area_seed, chest_index)
##   var items := LootRoller.roll(&"chest", &"dungeon", 7, rng)
##
## Returns ItemInstances; gold comes back as one ItemInstance of base "gold"
## with the amount as its quantity. Same seed, same loot.

const SOURCES: Array[StringName] = [&"normal", &"elite", &"boss", &"chest", &"chest_large"]


## A generator seeded from any mix of values (area seed, chest index, enemy id).
static func rng_for(a: Variant, b: Variant = 0, c: Variant = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([a, b, c])
	return rng


## Rolls one loot source. [param magic_find] and [param gold_find] are whole
## percents from the player's gear (Items.get_gear_stat(&"magic_find")).
static func roll(source: StringName, biome: StringName, level: int, rng: RandomNumberGenerator,
		magic_find := 0.0, gold_find := 0.0) -> Array[ItemInstance]:
	var cfg := ItemDatabase.loot_config()
	var src: Dictionary = cfg.get("sources", {}).get(String(source), cfg.get("sources", {}).get("normal", {}))
	var biome_cfg: Dictionary = cfg.get("biomes", {}).get(String(biome), {})
	var mults: Dictionary = biome_cfg.get("multipliers", {})
	var weights := {}
	var base_weights: Dictionary = src.get("weights", {})
	for outcome in base_weights:
		weights[outcome] = float(base_weights[outcome]) * float(mults.get(outcome, 1.0))
	if biome_cfg.get("materials", {}).is_empty():
		weights.erase("material")
	var rarity_bonus := float(src.get("rarity_bonus", 1.0)) * float(biome_cfg.get("rarity_bonus", 1.0))
	level = maxi(level, 1)

	var outcomes: Array = []
	outcomes.append_array(src.get("guaranteed", []))
	for i in int(src.get("rolls", 1)):
		outcomes.append(ItemGenerator.weighted_pick(weights, rng))

	var gold := 0
	var out: Array[ItemInstance] = []
	for outcome in outcomes:
		match outcome:
			"gold":
				gold += roll_gold(level, rng, gold_find)
			"potion":
				_add(out, ItemGenerator.roll_potion(level, rng))
			"gear":
				_add(out, roll_gear(level, rng, String(biome), rarity_bonus, magic_find))
			"spellbook":
				_add(out, ItemGenerator.roll_spellbook(level, rng))
			"material":
				var id: Variant = ItemGenerator.weighted_pick(biome_cfg.get("materials", {}), rng)
				if id != null:
					_add(out, ItemInstance.create(StringName(id), rng.randi_range(1, 2)))
	if gold > 0:
		out.push_front(ItemInstance.create(&"gold", gold))
	return out


## One gear drop at [param level], rarity rolled first.
static func roll_gear(level: int, rng: RandomNumberGenerator, biome := "", rarity_bonus := 1.0, magic_find := 0.0) -> ItemInstance:
	var rarity := ItemGenerator.roll_rarity(level, rng, rarity_bonus, magic_find)
	if rarity == ItemDefs.Rarity.UNIQUE:
		var unique := ItemGenerator.roll_any_unique(level, rng)
		if unique:
			return unique
		rarity = ItemDefs.Rarity.RARE
	var base := ItemGenerator.pick_gear_base(level, rng, biome)
	if base == null:
		return null
	return ItemGenerator.roll_gear(base, level, rarity, rng)


static func roll_gold(level: int, rng: RandomNumberGenerator, gold_find := 0.0) -> int:
	var g: Dictionary = ItemDatabase.loot_config().get("gold", {})
	var mean := float(g.get("base", 3)) + float(g.get("per_level", 2.0)) * level
	var spread := float(g.get("spread", 0.5))
	return maxi(1, roundi(mean * rng.randf_range(1.0 - spread, 1.0 + spread) * (1.0 + gold_find / 100.0)))


## Turns the enemies' drop list ([{"id": &"gold", "count": 12}, {"id": &"hex_dust", "count": 1}])
## into items. Ids the item database does not know are skipped with a warning.
static func from_enemy_loot(loot: Array) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for entry in loot:
		var id := StringName(entry.get("id", ""))
		var count := int(entry.get("count", 1))
		if count <= 0:
			continue
		if not ItemDatabase.has_base(id):
			push_warning("LootRoller: unknown loot id %s" % id)
			continue
		out.append(ItemInstance.create(id, count))
	return out


## The source an enemy rolls on: boss, elite or normal.
static func source_for_enemy(enemy: Object) -> StringName:
	if enemy == null:
		return &"normal"
	if enemy.get("is_boss") == true:
		return &"boss"
	if enemy.get("elite") == true:
		return &"elite"
	return &"normal"


static func _add(out: Array[ItemInstance], item: ItemInstance) -> void:
	if item != null:
		out.append(item)
