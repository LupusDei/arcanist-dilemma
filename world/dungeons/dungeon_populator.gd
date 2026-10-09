class_name DungeonPopulator
## Fills a dungeon's rooms with monsters from the enemies system's seeded spawn
## tables (res://actors/enemies). Each encounter in the plan becomes one
## EnemySpawnRequest over its room, and the groups the table plans are trimmed
## to the room's threat budget. The boss room's first group is led by an
## elite. Monsters are planned in the dungeon's local space, so the same seed
## gives the same monsters wherever the dungeon is placed.
##
## The enemies code is looked up by path rather than by class name, so this
## folder still loads (and the planner and its tests still run) in a project
## without it.

const DEFAULT_TABLE := "res://actors/enemies/types/default_spawn_table.tres"
const REQUEST_SCRIPT := "res://actors/enemies/core/enemy_spawn_request.gd"
const SPAWNER_SCRIPT := "res://actors/enemies/core/enemy_spawner.gd"
## Threat of an elite relative to an ordinary monster of the same level.
const ELITE_THREAT := 3.0


static func enemies_available(table_path := DEFAULT_TABLE) -> bool:
	return ResourceLoader.exists(table_path) and ResourceLoader.exists(REQUEST_SCRIPT) and ResourceLoader.exists(SPAWNER_SCRIPT)


## Pure data: one Dictionary per monster group,
##   encounter: DungeonPlan.Encounter, scene: PackedScene, position: Vector3
##   (through `xform`), count: int, elites: int, level: int, seed: int,
##   spawn_radius: float, threat: float
static func plan_spawns(plan: DungeonPlan, xform: Transform3D, table_path := DEFAULT_TABLE) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	if not enemies_available(table_path):
		return spawns
	var table: Resource = load(table_path)
	var request_script: Script = load(REQUEST_SCRIPT)
	for e in plan.encounters:
		var request: Resource = request_script.new()
		request.area_seed = e.seed_value
		request.biome = plan.recipe.biome
		request.level_min = e.level
		request.level_max = e.level
		var center := e.area.get_center()
		request.area_center = Vector3(center.x, 0, center.y)
		request.area_size = e.area.size
		# Density high enough that max_groups decides the count.
		request.density = 1000.0
		request.max_groups = 2 if e.boss or e.area.get_area() > 150.0 else 1
		request.min_spacing = 4.0
		request.elite_chance = 0.0 if e.boss else plan.recipe.elite_chance
		var remaining := e.budget
		var first := true
		for group in table.plan(request):
			var level: int = group["level"]
			var elites := 1 if (e.boss and first) or group["elite"] else 0
			var extra := elites * level * (ELITE_THREAT - 1.0)
			var count: int = group["count"]
			if e.boss and first:
				# The boss leads a bigger pack.
				count += 2
			count = mini(count, floori((remaining - extra) / level))
			if count < 1:
				# Can't afford an elite here: try the group without one.
				elites = 0
				extra = 0.0
				count = mini(group["count"], floori(remaining / level))
			if count < 1:
				continue
			var threat := count * level + extra
			remaining -= threat
			first = false
			var entry: Resource = group["entry"]
			spawns.append({
				"encounter": e,
				"scene": group["scene"],
				"position": xform * (group["position"] as Vector3),
				"count": count,
				"elites": elites,
				"level": level,
				"seed": group["seed"],
				"spawn_radius": minf(entry.spawn_radius, 2.5),
				"threat": threat,
			})
	return spawns


## Adds one EnemySpawner per planned group under `parent` (normally the
## dungeon's Monsters node) and returns them. Boss-room spawners are in the
## "dungeon_boss" group.
static func populate(plan: DungeonPlan, parent: Node3D, table_path := DEFAULT_TABLE) -> Array[Node3D]:
	var spawners: Array[Node3D] = []
	if not enemies_available(table_path):
		push_warning("DungeonPopulator: no enemy spawn table at %s; the dungeon stays empty" % table_path)
		return spawners
	var spawner_script: Script = load(SPAWNER_SCRIPT)
	for s in plan_spawns(plan, Transform3D.IDENTITY, table_path):
		var spawner: Node3D = spawner_script.new()
		var e: DungeonPlan.Encounter = s["encounter"]
		var scene: PackedScene = s["scene"]
		spawner.name = "%sRoom%d_%d" % [scene.resource_path.get_file().get_basename().to_pascal_case(), e.room, spawners.size()]
		spawner.enemy_scene = scene
		spawner.count = s["count"]
		spawner.elite_count = s["elites"]
		spawner.level = s["level"]
		spawner.spawn_seed = s["seed"]
		spawner.spawn_radius = s["spawn_radius"]
		spawner.position = (s["position"] as Vector3) + Vector3(0, 0.1, 0)
		if e.boss:
			spawner.add_to_group(&"dungeon_boss")
		parent.add_child(spawner)
		spawners.append(spawner)
	return spawners
