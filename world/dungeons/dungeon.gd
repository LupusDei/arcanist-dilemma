class_name Dungeon
extends Node3D
## Drop-in dungeon: set a recipe and a seed and it plans, builds, populates
## and bakes navigation for itself when it enters the tree. It also tracks
## the player's keys and relays what happens inside.
##
##   var dungeon := Dungeon.new()
##   dungeon.recipe = preload("res://world/dungeons/recipes/drowned_chapel.tres")
##   dungeon.seed_value = 7
##   add_child(dungeon)
##   player.global_transform = dungeon.player_start()

signal generated(plan: DungeonPlan)
signal key_collected(key_id: int)
signal door_opened(lock_id: int)
signal chest_opened(chest: DungeonChest, loot: Array[Dictionary])
## Every monster in the boss room is dead.
signal boss_defeated
## The player stepped into the portal behind the boss ("exit") or climbed the
## entrance stairs ("way_out").
signal exit_reached(which: StringName)

@export var recipe: DungeonRecipe
@export var seed_value := 1
## Override the recipe's monster levels (0 keeps the recipe's).
@export var level_min := 0
@export var level_max := 0
@export var generate_on_ready := true
@export var populate_monsters := true
@export var spawn_table_path := DungeonPopulator.DEFAULT_TABLE
## Bake a navmesh so monsters path around pillars and through doorways. Note
## this adds a region to the world's navigation map.
@export var bake_navigation := true

var plan: DungeonPlan
## Story state passed to the planner, e.g. {"cleared": true} or {"level_bonus": 2}.
var state := {}
var keys := {}

var _content: Node3D
var _navigation: NavigationRegion3D
var _boss_spawners := 0


func _ready() -> void:
	if generate_on_ready and recipe != null:
		generate()


func generate() -> void:
	if _content != null:
		_content.free()
	if _navigation != null:
		_navigation.free()
	keys.clear()
	plan = DungeonPlanner.plan(recipe, seed_value, state, level_min, level_max)
	_content = DungeonBuilder.build(plan)
	if bake_navigation:
		_navigation = NavigationRegion3D.new()
		_navigation.name = "Navigation"
		var mesh := NavigationMesh.new()
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		mesh.geometry_collision_mask = 1
		mesh.agent_radius = 0.5
		mesh.agent_height = 2.0
		mesh.agent_max_climb = 0.25
		mesh.cell_size = 0.25
		mesh.cell_height = 0.25
		_navigation.navigation_mesh = mesh
		add_child(_navigation)
		_navigation.add_child(_content)
	else:
		add_child(_content)

	for door in _content.get_node("Doors").get_children():
		door.opened.connect(func(d: DungeonDoor) -> void: door_opened.emit(d.lock_id))
	for chest in _content.get_node("Chests").get_children():
		chest.opened.connect(func(c: DungeonChest, loot: Array[Dictionary]) -> void: chest_opened.emit(c, loot))
	var exits := _content.get_node("Exits")
	exits.get_node("Exit").body_entered.connect(_on_exit_body.bind(&"exit"))
	exits.get_node("WayOut").body_entered.connect(_on_exit_body.bind(&"way_out"))

	_boss_spawners = 0
	if populate_monsters:
		for spawner in DungeonPopulator.populate(plan, _content.get_node("Monsters"), spawn_table_path):
			if spawner.is_in_group(&"dungeon_boss"):
				_boss_spawners += 1
				spawner.cleared.connect(_on_boss_group_cleared, CONNECT_ONE_SHOT)
	if bake_navigation and is_inside_tree():
		_navigation.bake_navigation_mesh(false)
		for door in _content.get_node("Doors").get_children():
			door.opened.connect(func(_d: DungeonDoor) -> void: _navigation.bake_navigation_mesh(true))
	generated.emit(plan)


## Global transform for the player: in the entrance room, facing the way in.
func player_start() -> Transform3D:
	return _content.get_node("Markers/PlayerStart").global_transform


## A named marker: PlayerStart, BossArena, Exit, or a story marker such as
## "scribe_ghost" or "spellbook_page".
func marker(marker_name: String) -> Marker3D:
	return _content.get_node_or_null("Markers/" + marker_name)


func has_key(key_id: int) -> bool:
	return keys.has(key_id)


func add_key(key_id: int) -> void:
	if not keys.has(key_id):
		keys[key_id] = true
		key_collected.emit(key_id)


## The Dungeon a node belongs to (nearest ancestor), or null.
static func find_for(node: Node) -> Dungeon:
	var at := node.get_parent()
	while at != null:
		if at is Dungeon:
			return at
		at = at.get_parent()
	return null


func _on_exit_body(body: Node3D, which: StringName) -> void:
	if body.is_in_group(&"player"):
		exit_reached.emit(which)


func _on_boss_group_cleared() -> void:
	_boss_spawners -= 1
	if _boss_spawners == 0:
		boss_defeated.emit()
