class_name ItemGenerator
extends RefCounted
## Rolls items. Every function takes the RandomNumberGenerator to use, so the
## same seed always gives the same item (see LootRoller for seeding).


## A gear item of [param base] at [param item_level] and [param rarity], with
## random traits from affixes.json. Asking for UNIQUE picks a unique built on
## that base if one fits the level, otherwise rolls a rare.
static func roll_gear(base: ItemBase, item_level: int, rarity: int, rng: RandomNumberGenerator) -> ItemInstance:
	var item := ItemInstance.new()
	item.base_id = base.id
	item.item_level = maxi(item_level, 1)
	if rarity == ItemDefs.Rarity.UNIQUE:
		var unique := _pick_unique(item_level, rng, base.id)
		if unique:
			item.rarity = ItemDefs.Rarity.UNIQUE
			item.unique_id = unique.id
			return item
		rarity = ItemDefs.Rarity.RARE
	item.rarity = rarity
	var count_range: Vector2i = ItemDefs.RARITY_AFFIX_COUNT[rarity]
	if count_range.y > 0:
		item.affixes = _roll_affixes(base, item_level, rng.randi_range(count_range.x, count_range.y),
				1 if rarity == ItemDefs.Rarity.MAGIC else 3, rng)
		if item.affixes.is_empty():
			item.rarity = ItemDefs.Rarity.COMMON
	if item.rarity == ItemDefs.Rarity.RARE:
		item.rare_name = _rare_name(base.category, rng)
	return item


## Picks a rarity for a drop. [param bonus] multiplies the odds of anything
## above common; [param magic_find] is a whole percent (50 = +50%).
static func roll_rarity(item_level: int, rng: RandomNumberGenerator, bonus := 1.0, magic_find := 0.0) -> int:
	var cfg: Dictionary = ItemDatabase.loot_config().get("rarity", {})
	var w: Dictionary = cfg.get("weights", {"common": 60, "magic": 32, "rare": 6, "unique": 1.2})
	var level_mult := 1.0 + float(cfg.get("level_bonus", 0.02)) * item_level
	var mf := maxf(magic_find, 0.0) / 100.0
	var k := float(cfg.get("magic_find_diminish", 2.5))
	var mf_rare := mf * k / (mf + k) if mf > 0.0 else 0.0
	var weights := {
		ItemDefs.Rarity.COMMON: float(w.get("common", 60)),
		ItemDefs.Rarity.MAGIC: float(w.get("magic", 32)) * level_mult * bonus * (1.0 + mf),
		ItemDefs.Rarity.RARE: float(w.get("rare", 6)) * level_mult * bonus * (1.0 + mf_rare),
		ItemDefs.Rarity.UNIQUE: float(w.get("unique", 1.2)) * level_mult * bonus * (1.0 + mf_rare),
	}
	return weighted_pick(weights, rng)


## A random gear base that can drop at [param item_level] in [param biome].
static func pick_gear_base(item_level: int, rng: RandomNumberGenerator, biome := "") -> ItemBase:
	var weights := {}
	for base in ItemDatabase.bases_of_kind(ItemDefs.Kind.GEAR):
		if base.level <= item_level and (base.biomes.is_empty() or biome.is_empty() or base.biomes.has(biome)):
			# Bases far below the item level fade out, so a level 20 area mostly drops level 12+ gear.
			var gap := item_level - base.level
			weights[base] = base.drop_weight * (1.0 if gap <= 8 else maxf(0.15, 1.0 - (gap - 8) * 0.12))
	return weighted_pick(weights, rng)


## The best healing or ley potion for the level.
static func roll_potion(item_level: int, rng: RandomNumberGenerator) -> ItemInstance:
	var health := rng.randf() < float(ItemDatabase.loot_config().get("potion", {}).get("health_chance", 0.65))
	var best: ItemBase
	for base in ItemDatabase.bases_of_kind(ItemDefs.Kind.POTION):
		if (base.heal_amount > 0.0) != health or base.level > item_level:
			continue
		if best == null or base.level > best.level:
			best = base
	if best == null:
		return null
	var item := ItemInstance.create(best.id)
	item.item_level = item_level
	return item


## A wizard spellbook. The circle goes up to the highest open at [param item_level]
## (I at 1, II at 4 ... VII at 19), tilted toward the top. Variant books
## (Searing Fireball) can drop from circle III.
static func roll_spellbook(item_level: int, rng: RandomNumberGenerator) -> ItemInstance:
	var cfg: Dictionary = ItemDatabase.loot_config().get("spellbook", {})
	var max_circle := clampi(1 + floori((item_level - 1) / 3.0), 1, 7)
	var circle := 1
	if max_circle > 1:
		var bias := float(cfg.get("high_circle_bias", 0.55))
		circle = max_circle if rng.randf() < bias else rng.randi_range(1, max_circle)
	var pool: Array = ItemDatabase.spell_pool("wizard")
	var variants: Array = ItemDatabase.spell_pool("wizard_variants")
	if circle >= 3 and not variants.is_empty() and rng.randf() < float(cfg.get("variant_chance", 0.12)):
		pool = variants
	if pool.is_empty():
		return null
	return make_spellbook(StringName(pool[rng.randi() % pool.size()]), circle, item_level)


static func make_spellbook(spell_id: StringName, circle: int, item_level := 1) -> ItemInstance:
	var item := ItemInstance.create(&"spellbook")
	item.spell_id = spell_id
	item.circle = clampi(circle, 1, 7)
	item.item_level = maxi(item_level, 1)
	return item


## A unique by id at its own level (quest rewards such as Greycloak's staff).
static func make_unique(unique_id: StringName) -> ItemInstance:
	var unique := ItemDatabase.get_unique(unique_id)
	if unique == null:
		push_error("ItemGenerator: no unique %s" % unique_id)
		return null
	var item := ItemInstance.new()
	item.base_id = unique.base_id
	item.rarity = ItemDefs.Rarity.UNIQUE
	item.unique_id = unique_id
	item.item_level = unique.level
	return item


## Picks a key from {key: weight}. Returns null when nothing has weight.
static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k in weights:
		total += maxf(float(weights[k]), 0.0)
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	var last: Variant = null
	for k in weights:
		var w := maxf(float(weights[k]), 0.0)
		if w <= 0.0:
			continue
		last = k
		if r < w:
			return k
		r -= w
	return last


static func _roll_affixes(base: ItemBase, item_level: int, count: int, max_per_type: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var rolls: Array[Dictionary] = []
	var used_groups := {}
	var per_type := {AffixDef.Type.PREFIX: 0, AffixDef.Type.SUFFIX: 0}
	var path := base.required_path()
	for i in count:
		var weights := {}
		for def in ItemDatabase.all_affixes():
			if used_groups.has(def.group) or per_type[def.type] >= max_per_type or not def.fits(base.category, item_level):
				continue
			if def.stat == &"plus_spell" and (ItemDatabase.spell_pool(def.spell_path).is_empty() \
					or (not path.is_empty() and def.spell_path != path)):
				continue
			weights[def] = def.weight
		var def: AffixDef = weighted_pick(weights, rng)
		if def == null:
			break
		used_groups[def.group] = true
		per_type[def.type] += 1
		var roll := {"id": def.id, "value": def.roll_value(rng)}
		if def.stat == &"plus_spell":
			var pool := ItemDatabase.spell_pool(def.spell_path)
			roll["spell"] = StringName(pool[rng.randi() % pool.size()])
		rolls.append(roll)
	return rolls


static func _pick_unique(item_level: int, rng: RandomNumberGenerator, base_id := &"") -> UniqueDef:
	var weights := {}
	for u in ItemDatabase.all_uniques():
		if u.quest_only or u.level > item_level or (base_id != &"" and u.base_id != base_id):
			continue
		weights[u] = u.weight
	return weighted_pick(weights, rng)


## Any random-drop unique at the level, on any base.
static func roll_any_unique(item_level: int, rng: RandomNumberGenerator) -> ItemInstance:
	var u := _pick_unique(item_level, rng)
	return make_unique(u.id) if u else null


static func _rare_name(category: StringName, rng: RandomNumberGenerator) -> String:
	var words := ItemDatabase.rare_name_words()
	var first: Array = words.get("first", ["Grim"])
	var second_map: Dictionary = words.get("second", {})
	var second: Array = (second_map.get("_any", []) as Array) + (second_map.get(String(category), []) as Array)
	if second.is_empty():
		second = ["Whisper"]
	return "%s %s" % [first[rng.randi() % first.size()], second[rng.randi() % second.size()]]
