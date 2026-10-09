class_name EnemyLootTable
extends Resource
## What an enemy can drop. roll() returns a list of {"id": StringName, "count": int}.
## Gold is reported under the id &"gold".

@export var gold_min := 0
@export var gold_max := 0
@export var entries: Array[EnemyLootEntry] = []


func roll(rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var drops: Array[Dictionary] = []
	if gold_max > 0:
		var gold := rng.randi_range(gold_min, gold_max)
		if gold > 0:
			drops.append({"id": &"gold", "count": gold})
	for entry in entries:
		if entry != null and rng.randf() < entry.chance:
			drops.append({"id": entry.item_id, "count": rng.randi_range(entry.count_min, maxi(entry.count_min, entry.count_max))})
	return drops
