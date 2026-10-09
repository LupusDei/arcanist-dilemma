class_name DungeonLoot
## Seeded chest loot. Uses the same item format as enemy drops,
## {"id": StringName, "count": int} with gold under &"gold", and the same
## placeholder item ids, until the items system brings real loot tables.

const COMMON := [&"minor_health_potion", &"arcane_scrap", &"hex_dust"]
const RARE := [&"arcane_scrap", &"minor_health_potion", &"bramble_thorn", &"hound_pelt"]


## tier 0: an ordinary chest, 1: a side-room treasure, 2: the boss reward.
static func roll(tier: int, level: int, seed_value: int) -> Array[Dictionary]:
	var rng := GenRng.stream(seed_value, "chest")
	var loot: Array[Dictionary] = []
	var gold := roundi(rng.randf_range(8.0, 16.0) * level * (1.0 + tier * 1.5))
	loot.append({"id": &"gold", "count": gold})
	for i in 1 + tier:
		var table: Array = RARE if tier > 0 and rng.randf() < 0.5 else COMMON
		loot.append({"id": table[rng.randi_range(0, table.size() - 1)], "count": rng.randi_range(1, 2 + tier)})
	return loot
