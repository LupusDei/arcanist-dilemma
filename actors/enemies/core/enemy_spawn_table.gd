class_name EnemySpawnTable
extends Resource
## Weighted list of monster groups, filtered by biome and level. Generators
## call plan() for pure data or EnemyPopulator.populate() to build spawners.

@export var entries: Array[EnemySpawnEntry] = []


func entries_for(biome: StringName, level: int) -> Array[EnemySpawnEntry]:
	var fitting: Array[EnemySpawnEntry] = []
	for entry in entries:
		if entry == null or entry.enemy_scene == null or entry.weight <= 0.0:
			continue
		if level < entry.min_level or level > entry.max_level:
			continue
		if not entry.biomes.is_empty() and not entry.biomes.has(biome):
			continue
		fitting.append(entry)
	return fitting


func pick(rng: RandomNumberGenerator, biome: StringName, level: int) -> EnemySpawnEntry:
	var fitting := entries_for(biome, level)
	if fitting.is_empty():
		return null
	var total := 0.0
	for entry in fitting:
		total += entry.weight
	var roll := rng.randf() * total
	for entry in fitting:
		roll -= entry.weight
		if roll < 0.0:
			return entry
	return fitting[-1]


## Deterministic placement plan for `request`. Each group is a Dictionary:
##   entry: EnemySpawnEntry, scene: PackedScene, position: Vector3 (y = area centre),
##   count: int, level: int, elite: bool, seed: int
func plan(request: EnemySpawnRequest) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([request.area_seed, request.biome, request.area_center, request.area_size])
	var area := request.area_size.x * request.area_size.y
	var target := roundi(area / 1000.0 * request.density)
	if request.max_groups > 0:
		target = mini(target, request.max_groups)

	var groups: Array[Dictionary] = []
	var points: Array[Vector3] = []
	var attempts := target * 30
	while groups.size() < target and attempts > 0:
		attempts -= 1
		var point := request.area_center + Vector3(
			rng.randf_range(-0.5, 0.5) * request.area_size.x, 0.0,
			rng.randf_range(-0.5, 0.5) * request.area_size.y)
		if not _is_free(point, points, request):
			continue
		var level := rng.randi_range(request.level_min, maxi(request.level_min, request.level_max))
		var entry := pick(rng, request.biome, level)
		if entry == null:
			continue
		points.append(point)
		groups.append({
			"entry": entry,
			"scene": entry.enemy_scene,
			"position": point,
			"count": rng.randi_range(entry.group_min, maxi(entry.group_min, entry.group_max)),
			"level": level,
			"elite": rng.randf() < request.elite_chance,
			"seed": rng.randi(),
		})
	return groups


func _is_free(point: Vector3, taken: Array[Vector3], request: EnemySpawnRequest) -> bool:
	for other in taken:
		if Vector2(point.x - other.x, point.z - other.z).length() < request.min_spacing:
			return false
	for zone in request.exclusion_zones:
		if Vector2(point.x - zone.x, point.z - zone.y).length() < zone.z:
			return false
	return true
