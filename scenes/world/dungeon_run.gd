extends Node3D
## A trip below ground: builds the dungeon DungeonTrip asked for, drops the
## player at its entrance with the same HUD, quests and session wiring as the
## world, and sends them back up when they take the exit portal behind the
## boss or climb the entrance stairs.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GAME_UI_SCENE := preload("res://ui/game_ui.tscn")
const QUEST_UI_SCENE := preload("res://ui/dialogue/quest_ui.tscn")
const SESSION_SCRIPT := preload("res://scenes/world/game_session.gd")
const FALLBACK_RECIPE := "res://world/dungeons/recipes/ruined_crypt.tres"

var dungeon: Dungeon
var player: Player


func _ready() -> void:
	var recipe_path := DungeonTrip.recipe_path if DungeonTrip.recipe_path != "" else FALLBACK_RECIPE
	_build_environment()

	dungeon = Dungeon.new()
	dungeon.name = "Dungeon"
	dungeon.recipe = load(recipe_path)
	dungeon.seed_value = DungeonTrip.seed_value
	add_child(dungeon)

	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	add_child(player)
	player.global_transform = dungeon.player_start()
	player.set_spawn_here()
	# Rooms are below the world's kill height in some layouts; only fall out far below.
	player.kill_height = player.global_position.y - 30.0

	var session: Node = SESSION_SCRIPT.new()
	session.name = "GameSession"
	session.set("fixed_biome", dungeon.recipe.biome)
	session.set("debug_xp_key", true)
	add_child(session)

	var ui := GAME_UI_SCENE.instantiate()
	ui.set("use_mock_when_missing", false)
	add_child(ui)
	add_child(QUEST_UI_SCENE.instantiate())

	dungeon.exit_reached.connect(_on_exit_reached)
	dungeon.boss_defeated.connect(func() -> void: _notice("The guardian falls. The way out is open."))
	_notice.call_deferred(dungeon.recipe.display_name)


func _on_exit_reached(_which: StringName) -> void:
	var session := get_node_or_null(^"GameSession")
	if session != null:
		session.save_game(false)
	DungeonTrip.leave(get_tree())


func _notice(text: String) -> void:
	for node in find_children("*", "QuestUI", true, false):
		node.show_notice(text)
		return


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.03, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.42, 0.55)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.ssao_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.12, 0.1, 0.16)
	environment.fog_density = 0.02
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
