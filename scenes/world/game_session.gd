extends Node
## Ties the game systems together for a play session in the world:
## - progression drives the player's combat stats, health and spell level
## - the level 5 path choice swaps the player's tricks for a path's spells
## - kills grant XP and gold pickups are counted
## - monsters are spawned across the meadow and around the hilltop ruins
## Each system works on its own; this is the only place that knows about all of them.

const SPAWN_TABLE := preload("res://actors/enemies/types/default_spawn_table.tres")
const PathChoice := preload("res://scenes/ui/path_choice.gd")
const WIZARD_STARTING_BOOKS: Array[StringName] = [&"fireball", &"frost_lance", &"arcane_ward"]
const SORCERER_STARTING_SPELLS: Array[StringName] = [&"spark_bolt", &"shove", &"barrier", &"static_field"]

@export var player_path: NodePath = ^"../Player"
@export var terrain_path: NodePath = ^"../Terrain"
@export var village_path: NodePath = ^"../Millbrook"
@export var monster_seed := 11
## Prototype shortcut: F8 grants XP so the path choice can be reached quickly.
@export var debug_xp_key := true

static var _started_character: Dictionary = {}

var gold := 0
var _player: Player
var _caster: SpellCaster
var _health: HealthComponent
var _progression: Node
var _path_choice: CanvasLayer


func _ready() -> void:
	add_to_group(&"enemy_listeners")
	add_to_group(&"loot_listeners")
	_player = get_node(player_path) as Player
	_caster = _player.get_node(^"SpellCaster") as SpellCaster
	_health = _player.get_node(^"HealthComponent") as HealthComponent
	_progression = get_node_or_null(^"/root/Progression")

	_path_choice = PathChoice.new()
	_path_choice.path_picked.connect(_on_path_picked)
	add_child(_path_choice)

	if _progression != null:
		# A character made on the creation screen starts a fresh game, once.
		if UiSession.has_character() and UiSession.character != _started_character:
			_started_character = UiSession.character.duplicate()
			_progression.new_character_from_ui(UiSession.character)
		_progression.stats_changed.connect(_apply_stats)
		_progression.leveled_up.connect(_on_leveled_up)
		_progression.path_chosen.connect(_set_path)
		_progression.choice_available.connect(_on_choice_available)
		_progression.character_loaded.connect(_on_character_loaded)
		_on_character_loaded()
	# Monster name and state labels are a debugging aid; hide them in the world.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Enemy:
			node.show_debug_label = false)
	_populate_monsters.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_P and _can_choose_path():
		_path_choice.open()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F8 and debug_xp_key and _progression != null:
		_progression.grant_xp(500, "debug")
		get_viewport().set_input_as_handled()


# --- progression -------------------------------------------------------------

func _on_character_loaded() -> void:
	var path: String = _progression.progression.path
	if path.is_empty():
		var tricks := TrickSet.new()
		tricks.level = mini(_progression.progression.level, 4)
		_caster.set_source(tricks)
	else:
		_set_path(path)
	_apply_stats()
	_health.revive()


func _apply_stats() -> void:
	var p: CharacterProgression = _progression.progression
	var stats := p.combat_stats() as CombatStats
	var bonus := 0.0
	if stats != null:
		_caster.set_stats(stats)
		bonus = stats.bonus_health
	_health.max_health = p.max_health() + bonus
	_health.regen_per_second = p.health_regen()


func _on_leveled_up(new_level: int) -> void:
	if _caster.source is TrickSet:
		_caster.source.level = mini(new_level, 4)
	elif _caster.source != null:
		_caster.source.level = new_level
	_health.revive()


func _on_choice_available(kind: StringName) -> void:
	if kind == &"path":
		_path_choice.open()


func _can_choose_path() -> bool:
	return _progression != null and _progression.progression.can_choose_path()


func _on_path_picked(path: String) -> void:
	if _progression != null:
		_progression.progression.choose_path(path)


## Gives the player the starting spells of a path.
func _set_path(path: String) -> void:
	var level: int = _progression.progression.level if _progression != null else 5
	match path:
		"wizard":
			var book := WizardSpellbook.new(level)
			var inscribed: Array[StringName] = []
			book.is_resting = true
			for id in WIZARD_STARTING_BOOKS:
				book.add_book(id)
				if book.inscribe(id):
					inscribed.append(id)
			book.prepare(inscribed)
			book.is_resting = false
			_caster.set_source(book)
		"mage":
			var codex := MageCodex.new(level)
			codex.grant_starting_kit()
			_caster.set_source(codex)
		"sorcerer":
			var tree := SorcererSpellTree.new(level)
			tree.grant_starting_points()
			for id in SORCERER_STARTING_SPELLS:
				tree.learn(id)
			_caster.set_source(tree)


# --- enemies and loot --------------------------------------------------------

func on_enemy_died(enemy: Node, xp_value: int, _loot: Array) -> void:
	if _progression != null:
		_progression.grant_kill_xp(int(enemy.get("level")), xp_value)


func on_loot_collected(loot: Array, _collector: Node) -> void:
	for entry in loot:
		if entry.get("id") == &"gold":
			gold += int(entry.get("count", 0))


func _populate_monsters() -> void:
	var terrain := get_node(terrain_path) as Terrain
	var monsters := Node3D.new()
	monsters.name = "Monsters"
	get_parent().add_child(monsters)

	var exclusions := PackedVector3Array()
	var spawn := _player.global_position
	exclusions.append(Vector3(spawn.x, spawn.z, 30.0))
	var village := get_node_or_null(village_path)
	if village != null and village.get("plan") != null:
		exclusions.append(Vector3(village.center.x, village.center.y, village.recipe.radius * 1.5))

	# Out in the meadow and woods: easy packs.
	var meadow := EnemySpawnRequest.new()
	meadow.area_seed = monster_seed
	meadow.biome = &"meadow"
	meadow.level_min = 1
	meadow.level_max = 3
	meadow.area_center = Vector3(0, 0, -15)
	meadow.area_size = Vector2(200, 190)
	meadow.density = 0.45
	meadow.min_spacing = 16.0
	meadow.elite_chance = 0.05
	meadow.respawn_delay = 90.0
	meadow.exclusion_zones = exclusions
	EnemyPopulator.populate(monsters, SPAWN_TABLE, meadow, terrain.height_at)

	# Guarding the ruins on the hill: tougher, with more elites.
	var ruins := EnemySpawnRequest.new()
	ruins.area_seed = monster_seed + 1
	ruins.biome = &"ruins"
	ruins.level_min = 3
	ruins.level_max = 5
	ruins.area_center = Vector3(terrain.hill_center.x, 0, terrain.hill_center.y)
	ruins.area_size = Vector2(40, 40)
	ruins.density = 2.0
	ruins.min_spacing = 9.0
	ruins.elite_chance = 0.2
	ruins.respawn_delay = 120.0
	EnemyPopulator.populate(monsters, SPAWN_TABLE, ruins, terrain.height_at)
