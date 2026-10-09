class_name DungeonTrip
extends RefCounted
## Carries a dungeon visit across the scene change: which dungeon to build in
## the dungeon run scene, and where to put the player back in the world.

const RUN_SCENE := "res://scenes/world/dungeon_run.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

static var recipe_path := ""
static var seed_value := 0
## Where the player stood outside the entrance; INF when not returning from a dungeon.
static var return_position := Vector3.INF


static func enter(tree: SceneTree, p_recipe_path: String, p_seed: int, from: Vector3) -> void:
	recipe_path = p_recipe_path
	seed_value = p_seed
	return_position = from
	tree.change_scene_to_file.call_deferred(RUN_SCENE)


static func leave(tree: SceneTree) -> void:
	recipe_path = ""
	tree.change_scene_to_file.call_deferred(WORLD_SCENE)


## Returns and clears the spot to put the player back in the world.
static func take_return_position() -> Vector3:
	var at := return_position
	return_position = Vector3.INF
	return at
