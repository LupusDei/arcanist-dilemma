extends SceneTree
## Items in the real world scene with combat, progression and enemies wired in:
## gear changes the player's CombatStats and HealthComponent, a wizard studies
## a spellbook into the real WizardSpellbook, "+1 to a spell" reaches the spell
## source, kills drop items, and the bag saves and loads with the character.
## Run: godot --headless --path . --fixed-fps 60 --script res://systems/items/tests/test_items_in_world.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Stand in for the "Items" autoload the integrator adds to project.godot.
	var items: ItemsService = root.get_node_or_null("Items")
	if items == null:
		items = ItemsService.new()
		items.name = "Items"
		root.add_child(items)
	var prog_service: Node = root.get_node("Progression")
	var progression: CharacterProgression = prog_service.progression
	prog_service.new_character(CharacterAppearance.create_default())

	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	await _frames(30)
	var player: Player = world.get_node("Player")
	var caster: SpellCaster = player.get_node("SpellCaster")
	var health: HealthComponent = player.get_node("HealthComponent")
	var session := world.get_node("GameSession")

	_check(items.player == player, "Items finds the player on its own")
	_check(items.caster == caster and items.health == health, "Items finds the SpellCaster and HealthComponent")
	_check(items.screen != null, "the inventory screen is added")
	var staff := items.equipment.get_item(&"main_hand")
	_check(staff != null and staff.base_id == &"oak_staff", "a new character starts with the oak staff")
	_check(is_equal_approx(caster.stats.spell_power, 1.05), "the staff's +5%% spell power reaches CombatStats (%.3f)" % caster.stats.spell_power)
	_check(is_equal_approx(health.armor, 8.0), "robe and sandals give armor (%.1f)" % health.armor)

	# Spending a point rebuilds stats in the game session; gear must survive it.
	progression.set_level(3)
	progression.allocate(&"intelligence", 1)
	await _frames(2)
	_check(is_equal_approx(caster.stats.spell_power, 1.05), "gear survives a progression stat rebuild (%.3f)" % caster.stats.spell_power)

	var before_max := health.max_health
	var ring := ItemInstance.new()
	ring.base_id = &"ring"
	ring.rarity = ItemDefs.Rarity.MAGIC
	ring.item_level = 5
	ring.affixes = [{"id": &"suf_vitality_1", "value": 3.0}, {"id": &"pre_res_fire_1", "value": 10.0}]
	items.pick_up(ring)
	_check(items.equip(ring) == &"", "equip a ring of the Ox")
	await _frames(2)
	_check(is_equal_approx(health.max_health, before_max + 15.0), "+3 Vitality on gear adds 15 health (%.0f -> %.0f)" % [before_max, health.max_health])
	_check(is_equal_approx(health.get_mitigation(DamageType.Kind.FIRE), 0.1) or health.resistances.get(DamageType.Kind.FIRE, 0.0) == 0.1, "fire resistance reaches the HealthComponent")

	# Become a wizard and study a book.
	while progression.level < 6:
		prog_service.grant_xp(500, "test")
	await _frames(2)
	var picker: CanvasLayer = session._path_choice
	if picker.visible:
		picker.close()
	session._on_path_picked("wizard")
	await _frames(3)
	_check(caster.source is WizardSpellbook, "the player is a wizard")
	var book := ItemGenerator.make_spellbook(&"frost_lance", 2)
	items.pick_up(book)
	_check(items.use_item(book), "a wizard studies a spellbook")
	_check((caster.source as WizardSpellbook).library.get(&"frost_lance", 0) == 2, "Frost Lance Circle II is in the Library")
	_check(not items.inventory.has_item(book), "the studied book is used up")

	var fireball := SpellLibrary.get_spell(&"fireball")
	var power_before := caster.source.get_power_multiplier(fireball)
	var grimoire := ItemInstance.new()
	grimoire.base_id = &"worn_grimoire"
	grimoire.rarity = ItemDefs.Rarity.MAGIC
	grimoire.affixes = [{"id": &"pre_skill_wizard_1", "value": 1.0, "spell": &"fireball"}]
	items.pick_up(grimoire)
	_check(items.equip(grimoire) == &"", "a wizard wears a grimoire")
	await _frames(2)
	_check(caster.source.gear_bonus_ranks.get(&"fireball", 0) == 1, "+1 to Fireball reaches the spellbook")
	_check(is_equal_approx(caster.source.get_power_multiplier(fireball), power_before * 1.15), "+1 to Fireball adds 15% power on a wizard")

	# Kills: the enemies' gem loot and the item tables.
	var gold_before := items.inventory.gold
	items.on_loot_collected([{"id": &"gold", "count": 7}, {"id": &"bramble_thorn", "count": 1}], player)
	_check(items.inventory.gold == gold_before + 7, "enemy gold goes to the bag")
	var enemies := world.get_node("Monsters").find_children("*", "Enemy", true, false)
	_check(not enemies.is_empty(), "monsters are in the world")
	if not enemies.is_empty():
		var enemy: Enemy = enemies[0]
		enemy.elite = true
		var parent := enemy.get_parent()
		var pickups_before := _count_pickups(world)
		for i in 5:
			items.on_enemy_died(enemy, 10, [])
		await _frames(2)
		_check(_count_pickups(world) > pickups_before, "elite kills drop items on the ground")

	# Save with the character, wipe, load.
	var slot := 97
	_check(items.save_game(slot) == OK, "items save with the character")
	var saved := JSON.stringify(items.to_dict())
	items.reset()
	_check(prog_service.load_game(slot), "the slot loads")
	await _frames(2)
	_check(JSON.stringify(items.to_dict()) == saved, "bag and gear come back from the save")
	_check(caster.stats.spell_power > 1.0, "loaded gear is applied again")
	ProgressionSave.delete_slot(slot)

	if _failures.is_empty():
		print("ITEMS IN WORLD TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)


func _count_pickups(node: Node) -> int:
	return node.find_children("*", "ItemPickup", true, false).size()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
