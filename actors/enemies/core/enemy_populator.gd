class_name EnemyPopulator
extends RefCounted
## Turns a spawn table and a request into spawners in the scene, so world,
## village and dungeon generators never hand-place monsters.
##
##   var request := EnemySpawnRequest.new()
##   request.area_seed = area_seed
##   request.biome = &"forest"
##   request.level_min = 3
##   request.level_max = 5
##   request.area_center = Vector3(40, 0, -60)
##   request.area_size = Vector2(80, 80)
##   request.exclusion_zones = PackedVector3Array([Vector3(0, 0, 14)])
##   EnemyPopulator.populate(monsters_node, preload(".../default_spawn_table.tres"), request, terrain.height_at)


## Adds one EnemySpawner per planned group under `parent` and returns them.
## `height_at(x, z) -> float` places groups on the ground; without it a
## downward ray against physics layer 1 is used, falling back to the area height.
static func populate(parent: Node3D, table: EnemySpawnTable, request: EnemySpawnRequest,
		height_at := Callable()) -> Array[EnemySpawner]:
	var spawners: Array[EnemySpawner] = []
	for group in table.plan(request):
		var spawner := EnemySpawner.new()
		var scene: PackedScene = group["scene"]
		spawner.name = "%s%d" % [scene.resource_path.get_file().get_basename().to_pascal_case(), spawners.size()]
		spawner.enemy_scene = scene
		spawner.count = group["count"]
		spawner.spawn_radius = (group["entry"] as EnemySpawnEntry).spawn_radius
		spawner.level = group["level"]
		spawner.elite_count = 1 if group["elite"] else 0
		spawner.spawn_seed = group["seed"]
		spawner.respawn_delay = request.respawn_delay
		var position: Vector3 = group["position"]
		position.y = _ground_height(parent, position, height_at)
		parent.add_child(spawner)
		spawner.global_position = position
		spawners.append(spawner)
	return spawners


static func _ground_height(parent: Node3D, at: Vector3, height_at: Callable) -> float:
	if height_at.is_valid():
		return height_at.call(at.x, at.z)
	if parent.is_inside_tree():
		var from := Vector3(at.x, at.y + 500.0, at.z)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1000.0, 1)
		var hit := parent.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit["position"].y
	return at.y
