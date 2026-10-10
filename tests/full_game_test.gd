extends SceneTree
## Plays through everything built so far, in the real scenes with every
## autoload: a new character from the creation screen, the arcanist model and
## Millbrook's quest NPCs, the prologue's chores, loot and the inventory,
## a dungeon trip and back, and saving and loading.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/full_game_test.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var progression: Node = root.get_node("Progression")
	var items: Node = root.get_node("Items")
	var quests: QuestManager = root.get_node("Quests")

	# --- New game from the creation screen ---
	UiSession.character = {"name": "Wren Test", "sex": 1, "face": 1, "skin": 2, "hair": 3, "hair_color": 2, "eyes": 1, "build": 0}
	change_scene_to_file("res://scenes/world/world.tscn")
	await _frames(60)
	var world := current_scene
	_check(world != null and world.name == "World", "the world scene loads")
	var player: Player = world.get_node("Player")
	_check(progression.appearance.character_name == "Wren Test", "the created character is in play")
	_check(player.get_node_or_null("Model/Arcanist") != null, "the player is the arcanist model")
	_check(player.get_node_or_null("CharacterAnimationDriver") != null, "the player is animated")

	var story := world.get_node("MillbrookStory")
	for id in ["tam", "rook", "farmer_hollis", "innkeeper", "old_man", "home_bed", "children", "old_mill_floorboards"]:
		_check(story._npcs.has(StringName(id)), "%s is in Millbrook" % id)
	_check(quests.is_active(&"prologue"), "the prologue has started")
	_check(world.find_children("*", "Enemy", true, false).size() > 5, "monsters roam the meadow")
	_check(world.get_node("DungeonSites")._entrances.size() == 2, "two dungeon entrances are in the world")

	# --- Starting gear ---
	var gear: Array = items.equipment.slots.values().filter(func(i: Variant) -> bool: return i != null)
	_check(gear.size() >= 2, "the arcanist starts with gear (%d pieces)" % gear.size())

	# --- Chores: Nudge the spoon off the table and Spark the stove, then Tam ---
	var kitchen: QuestArea = story.get_node("Area_kitchen")
	player.global_position = kitchen.global_position + Vector3(0, 0.5, 0)
	await _frames(20)
	var caster: SpellCaster = player.get_node("SpellCaster")
	_check(quests.is_player_in(&"kitchen"), "walking into the yard counts as the kitchen")
	var tutorial: OpeningTutorial = story.get_node("OpeningTutorial")
	for chore: ChoreTarget in [tutorial.spoon, tutorial.stove]:
		var aim := chore.health.get_target_position()
		var away := player.global_position - aim
		away.y = 0.0
		player.global_position = aim + away.normalized() * 2.5
		await _frames(5)
		for spell in caster.get_action_bar() + [caster.get_cantrip()]:
			if spell != null and spell.id == chore.spell_id:
				caster.cast(spell, aim)
				await _frames(50)
				break
	var chores := quests.get_progress(&"prologue")
	_check(tutorial.spoon.is_done, "Nudge sends the spoon flying")
	_check(tutorial.stove.is_done, "Spark lights the stove")
	_check(chores.stage == &"show_tam", "the chores are done")
	_check(quests.has_dialogue_for(&"tam"), "Tam has something to say")

	# --- Combat and loot ---
	var enemies := world.find_children("*", "Enemy", true, false)
	var target: Enemy = enemies[0]
	for enemy in enemies:
		if enemy.global_position.distance_to(player.global_position) < target.global_position.distance_to(player.global_position):
			target = enemy
	var target_health: HealthComponent = target.get_node("HealthComponent")
	target_health.take_damage(Hit.new(99999.0, DamageType.Kind.FIRE, player))
	await _frames(20)
	_check(target_health.is_dead, "a monster dies")
	var pickups := world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.get_script() != null and str(n.get_script().resource_path).contains("pickup"))
	print("     %d pickups on the ground" % pickups.size())

	# --- Save, change things, load ---
	var xp_before: int = progression.progression.xp
	var session := world.get_node("GameSession")
	_check(session.save_game(false), "the game saves")
	progression.grant_xp(10, "test")
	_check(progression.progression.xp > xp_before, "XP changes after saving")
	_check(progression.load_game(0), "the save loads")
	await _frames(5)
	_check(progression.progression.xp == xp_before, "loading restores the XP (%d)" % progression.progression.xp)
	_check(quests.is_active(&"prologue"), "loading restores the quests")
	gear = items.equipment.slots.values().filter(func(i: Variant) -> bool: return i != null)
	_check(gear.size() >= 2, "loading restores the gear")

	# --- Down into the crypt and back up ---
	var entrance: Dictionary = world.get_node("DungeonSites")._entrances[0]
	session.enter_dungeon(entrance["recipe_path"], entrance["seed"], entrance["return"])
	await _frames(90)
	var run := current_scene
	_check(run != null and run.name == "DungeonRun", "entering an archway loads the dungeon")
	if run != null and run.name == "DungeonRun":
		var dungeon: Dungeon = run.get_node("Dungeon")
		var below: Player = run.get_node("Player")
		_check(below.global_position.distance_to(dungeon.player_start().origin) < 2.0, "the player starts at the dungeon entrance")
		_check(run.find_children("*", "Enemy", true, false).size() > 3, "the dungeon has monsters")
		_check(below.get_node("SpellCaster").get_cantrip() != null, "spells work in the dungeon")
		dungeon.exit_reached.emit(&"way_out")
		await _frames(90)
	var back := current_scene
	_check(back != null and back.name == "World", "leaving the dungeon returns to the world")
	if back != null and back.name == "World":
		var up: Player = back.get_node("Player")
		_check(up.global_position.distance_to(entrance["return"]) < 3.0, "the player comes out by the entrance")

	if _failures.is_empty():
		print("FULL GAME TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
