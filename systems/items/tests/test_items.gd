extends SceneTree
## Headless tests for items, loot, equipment, inventory and save/load.
## Run: godot --headless --path . --script res://systems/items/tests/test_items.gd

var _failures: PackedStringArray = []
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_database()
	_test_determinism()
	_test_rarity_affixes()
	_test_rarity_odds()
	_test_level_gating()
	_test_spellbooks()
	_test_loot_sources()
	_test_enemy_loot()
	_test_inventory_grid()
	_test_equipment_requirements()
	_test_item_stats()
	_test_serialization()
	await _test_service()
	await _test_pickup_and_chest()
	await _test_inventory_screen()

	if _failures.is_empty():
		print("ITEMS TESTS PASSED (%d checks)" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("ITEMS TESTS FAILED: %d of %d" % [_failures.size(), _checks])
		quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)


func _test_database() -> void:
	_check(ItemDatabase.all_bases().size() >= 40, "bases load (%d)" % ItemDatabase.all_bases().size())
	_check(ItemDatabase.all_affixes().size() >= 50, "affixes load")
	_check(ItemDatabase.all_uniques().size() >= 5, "uniques load")
	for b in ItemDatabase.all_bases():
		if b.is_gear():
			_check(not b.allowed_slots().is_empty(), "%s has a slot" % b.id)
	for u in ItemDatabase.all_uniques():
		_check(ItemDatabase.has_base(u.base_id), "unique %s base %s exists" % [u.id, u.base_id])
	for a in ItemDatabase.all_affixes():
		_check(a.stat == &"plus_spell" or ItemDefs.STAT_FORMAT.has(a.stat), "affix %s stat %s is known" % [a.id, a.stat])
		for c in a.categories:
			_check(ItemDefs.CATEGORY_SLOTS.has(StringName(c)), "affix %s category %s exists" % [a.id, c])
	# Every placeholder id the enemies drop is a real item.
	for id in [&"gold", &"bramble_thorn", &"hex_dust", &"arcane_scrap", &"hound_pelt", &"minor_health_potion"]:
		_check(ItemDatabase.has_base(id), "enemy loot id %s is an item" % id)


func _test_determinism() -> void:
	var a := LootRoller.roll(&"elite", &"dungeon", 12, LootRoller.rng_for(42, 7))
	var b := LootRoller.roll(&"elite", &"dungeon", 12, LootRoller.rng_for(42, 7))
	_check(_dump(a) == _dump(b), "same seed gives the same loot")
	var differs := false
	for s in 20:
		if _dump(LootRoller.roll(&"elite", &"dungeon", 12, LootRoller.rng_for(42, 100 + s))) != _dump(a):
			differs = true
	_check(differs, "different seeds give different loot")


func _test_rarity_affixes() -> void:
	var rng := LootRoller.rng_for(1)
	var staff := ItemDatabase.get_base(&"runed_staff")
	for i in 200:
		var magic := ItemGenerator.roll_gear(staff, 20, ItemDefs.Rarity.MAGIC, rng)
		_check(magic.affixes.size() >= 1 and magic.affixes.size() <= 2, "magic has 1-2 traits")
		var rare := ItemGenerator.roll_gear(staff, 20, ItemDefs.Rarity.RARE, rng)
		_check(rare.affixes.size() >= 3 and rare.affixes.size() <= 5, "rare has 3-5 traits (%d)" % rare.affixes.size())
		_check(not rare.rare_name.is_empty(), "rare has a name")
		var groups := {}
		var prefixes := 0
		for roll in rare.affixes:
			var def := ItemDatabase.get_affix(roll["id"])
			_check(not groups.has(def.group), "no two traits from one group")
			groups[def.group] = true
			_check(def.fits(staff.category, 20), "trait fits base and level")
			_check(roll["value"] >= def.value_min and roll["value"] <= def.value_max, "value in range")
			if def.type == AffixDef.Type.PREFIX:
				prefixes += 1
			if def.stat == &"plus_spell":
				_check(ItemDatabase.spell_pool(def.spell_path).has(String(roll["spell"])), "+spell names a pool spell")
		_check(prefixes <= 3, "at most 3 prefixes")
	var common := ItemGenerator.roll_gear(staff, 20, ItemDefs.Rarity.COMMON, rng)
	_check(common.affixes.is_empty(), "common has no traits")
	_check(common.get_display_name() == "Runed Staff", "common name is the base name")
	# Path off-hands only roll their own path's +spell.
	var grim := ItemDatabase.get_base(&"scholar_grimoire")
	for i in 200:
		for roll in ItemGenerator.roll_gear(grim, 25, ItemDefs.Rarity.RARE, rng).affixes:
			var def := ItemDatabase.get_affix(roll["id"])
			if def.stat == &"plus_spell":
				_check(def.spell_path == "wizard", "grimoire only rolls wizard spells")
	var magic := ItemInstance.new()
	magic.base_id = &"oak_staff"
	magic.rarity = ItemDefs.Rarity.MAGIC
	magic.affixes = [{"id": &"pre_power_1", "value": 3.0}, {"id": &"suf_intelligence_1", "value": 2.0}]
	_check(magic.get_display_name() == "Apprentice's Oak Staff of the Owl", "magic name: %s" % magic.get_display_name())
	var stats := magic.get_stats()
	_check(is_equal_approx(stats[&"spell_power"], 8.0), "implicit + rolled spell power sum")
	_check(is_equal_approx(stats[&"intelligence"], 2.0), "rolled attribute")


func _test_rarity_odds() -> void:
	var rng := LootRoller.rng_for(5)
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for i in 5000:
		counts[ItemGenerator.roll_rarity(10, rng)] += 1
	_check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3], "rarity tiers get rarer: %s" % counts)
	_check(counts[3] > 0, "uniques can drop")
	var mf := {0: 0, 1: 0, 2: 0, 3: 0}
	for i in 5000:
		mf[ItemGenerator.roll_rarity(10, rng, 1.0, 200.0)] += 1
	_check(mf[1] > counts[1] and mf[2] > counts[2], "magic find raises magic and rare odds")


func _test_level_gating() -> void:
	var rng := LootRoller.rng_for(9)
	for i in 400:
		var item := LootRoller.roll_gear(3, rng, "meadow")
		_check(item.get_base().level <= 3, "level 3 drop uses a low base")
		var u := item.get_unique()
		if u:
			_check(u.level <= 3 and not u.quest_only, "unique fits level and is not quest-only")
		for roll in item.affixes:
			_check(ItemDatabase.get_affix(roll["id"]).level <= 3, "affix level gated")
	var high_bases := {}
	for i in 400:
		high_bases[LootRoller.roll_gear(24, rng).base_id] = true
	_check(high_bases.has(&"elder_staff") or high_bases.has(&"archmage_robe"), "high level drops high bases")


func _test_spellbooks() -> void:
	var rng := LootRoller.rng_for(3)
	var max_seen := 0
	for i in 300:
		var low := ItemGenerator.roll_spellbook(3, rng)
		_check(low.circle == 1, "level 3 spellbooks are Circle I")
		var high := ItemGenerator.roll_spellbook(19, rng)
		_check(high.circle >= 1 and high.circle <= 7, "circle in range")
		max_seen = maxi(max_seen, high.circle)
		var pool := ItemDatabase.spell_pool("wizard") + ItemDatabase.spell_pool("wizard_variants")
		_check(pool.has(String(high.spell_id)), "spellbook names a wizard spell")
		if ItemDatabase.spell_pool("wizard_variants").has(String(high.spell_id)):
			_check(high.circle >= 3, "variant books are Circle III+")
	_check(max_seen == 7, "level 19 can drop Circle VII")
	var book := ItemGenerator.make_spellbook(&"frost_lance", 2)
	_check(book.get_display_name() == "Spellbook: Frost Lance (Circle II)", "spellbook name: %s" % book.get_display_name())


func _test_loot_sources() -> void:
	var boss_gear := 0
	var normal_nothing := 0
	for s in 300:
		var boss := LootRoller.roll(&"boss", &"dungeon", 10, LootRoller.rng_for(s))
		var gear := 0
		for item in boss:
			if item.is_gear():
				gear += 1
		_check(gear >= 2, "boss always drops 2+ gear")
		boss_gear += gear
		if LootRoller.roll(&"normal", &"meadow", 10, LootRoller.rng_for(s, 1)).is_empty():
			normal_nothing += 1
	_check(normal_nothing > 50 and normal_nothing < 250, "normal monsters often drop nothing (%d/300)" % normal_nothing)
	var village_mats := 0
	var ruins_books := 0
	var meadow_books := 0
	for s in 2000:
		for item in LootRoller.roll(&"normal", &"village", 5, LootRoller.rng_for(s, 2)):
			if item.get_kind() == ItemDefs.Kind.MATERIAL:
				village_mats += 1
		for item in LootRoller.roll(&"normal", &"ruins", 5, LootRoller.rng_for(s, 3)):
			if item.get_kind() == ItemDefs.Kind.SPELLBOOK:
				ruins_books += 1
		for item in LootRoller.roll(&"normal", &"meadow", 5, LootRoller.rng_for(s, 3)):
			if item.get_kind() == ItemDefs.Kind.SPELLBOOK:
				meadow_books += 1
			if item.get_kind() == ItemDefs.Kind.MATERIAL:
				_check([&"bramble_thorn", &"hound_pelt"].has(item.base_id), "meadow drops meadow materials")
	_check(village_mats == 0, "villages drop no materials")
	_check(ruins_books > meadow_books, "ruins drop more spellbooks (%d vs %d)" % [ruins_books, meadow_books])
	var g1 := 0
	var g20 := 0
	for s in 200:
		g1 += LootRoller.roll_gold(1, LootRoller.rng_for(s))
		g20 += LootRoller.roll_gold(20, LootRoller.rng_for(s))
	_check(g20 > g1 * 5, "gold scales with level")


func _test_enemy_loot() -> void:
	var items := LootRoller.from_enemy_loot([{"id": &"gold", "count": 12}, {"id": &"hex_dust", "count": 2}, {"id": &"minor_health_potion", "count": 1}])
	_check(items.size() == 3, "enemy loot converts")
	var inv := Inventory.new()
	for item in items:
		inv.add_item(item)
	_check(inv.gold == 12, "enemy gold goes to the purse")
	_check(inv.count_of(&"hex_dust") == 2, "materials stack in the bag")
	_check(LootRoller.source_for_enemy(null) == &"normal", "no enemy rolls normal")
	var elite := _FakeEnemy.new()
	elite.elite = true
	_check(LootRoller.source_for_enemy(elite) == &"elite", "elite enemies roll the elite table")
	elite.free()


func _test_inventory_grid() -> void:
	var inv := Inventory.new(Vector2i(4, 3))
	var robe := ItemInstance.create(&"linen_robe")  # 2x3
	_check(inv.add_item(robe) == null, "robe fits")
	_check(inv.get_position_of(robe) == Vector2i(0, 0), "first item goes top-left")
	var robe2 := ItemInstance.create(&"silk_robe")
	_check(inv.add_item(robe2) == null, "second robe fits")
	_check(inv.get_position_of(robe2) == Vector2i(2, 0), "second robe beside the first")
	_check(inv.add_item(ItemInstance.create(&"ring")) != null, "full bag returns the item")
	_check(not inv.can_fit(ItemInstance.create(&"ring")), "can_fit sees a full bag")
	inv.remove_item(robe)
	_check(inv.item_at(Vector2i(0, 1)) == null, "removed item frees cells")
	_check(inv.item_at(Vector2i(3, 2)) == robe2, "item_at finds a multi-cell item")
	var staff := ItemInstance.create(&"oak_staff")
	_check(not inv.place_at(staff, Vector2i(3, 0)), "cannot overlap")
	_check(inv.place_at(staff, Vector2i(0, 0)), "place in a free column")
	_check(inv.place_at(staff, Vector2i(1, 0)), "move an item over its own cells")
	_check(not inv.place_at(staff, Vector2i(2, 0)), "moving into another item fails")

	var bag := Inventory.new()
	bag.add_item(ItemInstance.create(&"minor_health_potion", 8))
	bag.add_item(ItemInstance.create(&"minor_health_potion", 5))
	_check(bag.count_of(&"minor_health_potion") == 13 and bag.entries.size() == 2, "stacks fill to 10 then split")
	var p: ItemInstance = bag.entries[1]["item"]
	bag.consume(p, 3)
	_check(bag.entries.size() == 1, "consuming a stack to zero removes it")


func _test_equipment_requirements() -> void:
	var eq := Equipment.new()
	var lvl1 := {"level": 1, "path": "", "attributes": {&"strength": 10, &"dexterity": 10, &"intelligence": 10, &"wisdom": 10, &"vitality": 10}}
	var heavy := ItemInstance.create(&"iron_shod_staff")
	_check(eq.check_equip(heavy, &"main_hand", lvl1) == &"level", "level requirement")
	var lvl10 := lvl1.duplicate(true)
	lvl10["level"] = 10
	_check(eq.check_equip(heavy, &"main_hand", lvl10) == &"strength", "strength requirement")
	lvl10["attributes"][&"strength"] = 22
	_check(eq.check_equip(heavy, &"main_hand", lvl10) == &"", "meets requirements")
	_check(eq.check_equip(heavy, &"hat", lvl10) == &"wrong_slot", "wrong slot")
	var grim := ItemInstance.create(&"worn_grimoire")
	lvl10["path"] = "mage"
	_check(eq.check_equip(grim, &"off_hand", lvl10) == &"path", "grimoire is wizard-only")
	lvl10["path"] = "wizard"
	_check(eq.check_equip(grim, &"off_hand", lvl10) == &"", "wizard can use a grimoire")
	_check(eq.check_equip(ItemInstance.create(&"minor_health_potion"), &"hat", lvl10) == &"not_gear", "potions are not gear")
	# Gear strength counts toward requirements (D2 style).
	lvl10["attributes"][&"strength"] = 20
	var ring := ItemInstance.new()
	ring.base_id = &"ring"
	ring.rarity = ItemDefs.Rarity.MAGIC
	ring.affixes = [{"id": &"suf_strength_1", "value": 2.0}]
	eq.equip(ring, &"ring_1")
	_check(eq.check_equip(heavy, &"main_hand", lvl10) == &"", "a +Str ring lets you wield it")
	_check(eq.best_slot_for(ItemInstance.create(&"ring")) == &"ring_2", "second ring goes in the free ring slot")
	var prev := eq.equip(ItemInstance.create(&"ring"), &"ring_1")
	_check(prev == ring, "equipping returns the old item")
	eq.equip(ItemInstance.create(&"linen_robe"), &"robe")
	_check(is_equal_approx(eq.total_stats().get(&"armor", 0.0), 6.0), "total armor from robe")


func _test_item_stats() -> void:
	var gear := {&"intelligence": 5.0, &"spell_power": 10.0, &"cast_speed": 90.0, &"max_resource": 20.0, &"max_health": 15.0, &"vitality": 2.0, &"resist_fire": 20.0, &"armor": 12.0}
	var attrs := ItemStats.attributes_with_gear({&"intelligence": 14}, gear)
	_check(attrs[&"intelligence"] == 19 and attrs[&"strength"] == 10, "gear attributes add to character attributes")
	var fake := _FakeStats.new()
	ItemStats.apply_to_combat_stats(fake, gear)
	_check(is_equal_approx(fake.spell_power, 1.1), "spell power percent applies")
	_check(is_equal_approx(fake.cast_speed, 0.75), "cast speed capped at 75%")
	_check(is_equal_approx(fake.bonus_resource, 20.0), "max resource applies")
	_check(is_equal_approx(ItemStats.bonus_health(gear), 25.0), "gear health includes 5 per vitality")
	var hc := _FakeHealth.new()
	hc.max_health = 100.0
	hc.health = 50.0
	ItemStats.apply_to_health(hc, gear, 100.0 + ItemStats.bonus_health(gear))
	_check(is_equal_approx(hc.max_health, 125.0), "health component max health")
	_check(is_equal_approx(hc.health, 62.5), "health fraction kept")
	_check(is_equal_approx(hc.resistances.get(1, 0.0), 0.2), "fire resistance keyed by DamageType.Kind.FIRE")
	_check(is_equal_approx(hc.armor, 12.0), "armor applies")
	var src := _FakeSource.new()
	ItemStats.apply_to_spell_source(src, {&"fireball": 2})
	_check(src.gear_bonus_ranks.get(&"fireball", 0) == 2, "+spell goes to gear_bonus_ranks")


func _test_serialization() -> void:
	var rng := LootRoller.rng_for(77)
	var inv := Inventory.new()
	for i in 12:
		inv.add_item(LootRoller.roll_gear(15, rng))
	inv.add_item(ItemGenerator.make_spellbook(&"fireball", 3))
	inv.add_item(ItemInstance.create(&"health_potion", 4))
	inv.add_gold(321)
	var eq := Equipment.new()
	eq.equip(ItemGenerator.make_unique(&"stormcrown"), &"hat")
	eq.equip(LootRoller.roll_gear(15, rng), &"ring_1")
	var data: Dictionary = JSON.parse_string(JSON.stringify({"inv": inv.to_dict(), "eq": eq.to_dict()}))
	var inv2 := Inventory.new()
	inv2.apply_dict(data["inv"])
	var eq2 := Equipment.new()
	eq2.apply_dict(data["eq"])
	_check(inv2.gold == 321, "gold saved")
	_check(inv2.entries.size() == inv.entries.size(), "all bag items saved")
	for i in inv.entries.size():
		var a: ItemInstance = inv.entries[i]["item"]
		var b: ItemInstance = inv2.entries[i]["item"]
		_check(a.get_display_name() == b.get_display_name(), "name survives save: %s" % a.get_display_name())
		_check(a.get_stats() == b.get_stats(), "stats survive save")
		_check(inv.entries[i]["pos"] == inv2.entries[i]["pos"], "grid position survives save")
	_check(eq2.get_item(&"hat").get_display_name() == "Stormcrown", "worn unique survives save")
	_check(eq2.spell_bonuses() == eq.spell_bonuses(), "+spell survives save")


func _test_service() -> void:
	var items := ItemsService.new()
	items.name = "Items"
	root.add_child(items)
	items.character_override = {"level": 30, "path": "wizard", "attributes": {&"strength": 40, &"dexterity": 40, &"intelligence": 40, &"wisdom": 40, &"vitality": 40}}
	items.give_starter_kit()
	_check(items.equipment.get_item(&"main_hand") != null and items.equipment.get_item(&"main_hand").base_id == &"oak_staff", "starter staff worn")
	_check(items.inventory.count_of(&"minor_health_potion") == 3, "starter potions")

	# Player stand-in with duck-typed combat nodes.
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var hc := _FakeHealthNode.new()
	hc.name = "HealthComponent"
	hc.max_health = 100.0
	hc.health = 40.0
	player.add_child(hc)
	var caster := _FakeCasterNode.new()
	player.add_child(caster)
	root.add_child(player)
	items.bind_player()
	_check(items.health == hc and items.caster == caster, "bind_player finds the combat nodes")
	_check(is_equal_approx(hc.armor, 8.0), "starter armor applied (robe 6 + sandals 2): %s" % hc.armor)

	var robe := ItemInstance.create(&"warded_robe")
	items.pick_up(robe)
	_check(items.equip(robe) == &"", "equip from bag")
	_check(items.equipment.get_item(&"robe") == robe, "robe worn")
	_check(items.inventory.count_of(&"linen_robe") == 1, "old robe back in the bag")
	_check(is_equal_approx(hc.armor, 30.0), "armor updated on equip: %s" % hc.armor)
	_check(hc.resistances.get(5, 0.0) > 0.0, "resist_all reaches arcane")

	var potion: ItemInstance
	for it in items.inventory.items():
		if it.base_id == &"minor_health_potion":
			potion = it
	_check(items.use_item(potion), "drink a potion")
	_check(hc.health > 40.0, "potion heals")
	_check(items.inventory.count_of(&"minor_health_potion") == 2, "potion consumed")

	var ley := ItemInstance.create(&"minor_ley_draught")
	items.pick_up(ley)
	caster.caster_resource.current = 10.0
	items.use_item(ley)
	_check(is_equal_approx(caster.caster_resource.current, 40.0), "ley draught restores the resource")

	var book := ItemGenerator.make_spellbook(&"fireball", 2)
	items.pick_up(book)
	_check(items.use_item(book), "wizard studies a spellbook")
	_check(caster.source.library.get(&"fireball", 0) == 2, "book added to the Library at its circle")
	items.character_override["path"] = "mage"
	var book2 := ItemGenerator.make_spellbook(&"frost_lance", 1)
	items.pick_up(book2)
	_check(not items.use_item(book2), "a mage cannot study a spellbook")
	_check(items.inventory.has_item(book2), "unstudied book stays in the bag")
	items.character_override["path"] = "wizard"

	var sb := ItemInstance.new()
	sb.base_id = &"worn_grimoire"
	sb.rarity = ItemDefs.Rarity.MAGIC
	sb.affixes = [{"id": &"pre_skill_wizard_1", "value": 1.0, "spell": &"fireball"}]
	items.pick_up(sb)
	items.equip(sb)
	_check(caster.source.gear_bonus_ranks.get(&"fireball", 0) == 1, "+1 to Fireball reaches the spell source")
	if ItemStats.combat_stats_script():
		_check(caster.stats_set_count > 0, "caster stats refreshed when CombatStats exists")

	items.collect_loot([{"id": &"gold", "count": 25}, {"id": &"hound_pelt", "count": 1}])
	_check(items.inventory.gold >= 35, "enemy gold collected")
	_check(items.inventory.count_of(&"hound_pelt") == 1, "enemy pelt collected")

	var path := "user://test_items_save.json"
	var before := JSON.stringify(items.to_dict())
	_check(items.save_to_file(path) == OK, "standalone save")
	items.reset()
	_check(items.equipment.slots.is_empty(), "reset clears gear")
	_check(items.load_from_file(path), "standalone load")
	_check(JSON.stringify(items.to_dict()) == before, "load restores everything")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Kill drops: an elite enemy stand-in.
	var enemy := _FakeEnemy.new()
	enemy.level = 8
	enemy.elite = true
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(enemy)
	var dropped := 0
	for i in 10:
		items.on_enemy_died(enemy, 10, [])
	await process_frame
	for n in world.get_children():
		if n is ItemPickup:
			dropped += 1
	_check(dropped > 0, "kills spawn item pickups (%d)" % dropped)
	world.queue_free()
	player.queue_free()
	await process_frame


func _test_pickup_and_chest() -> void:
	var items: ItemsService = root.get_node("Items")
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var pshape := CollisionShape3D.new()
	pshape.shape = CapsuleShape3D.new()
	pshape.position.y = 1.0
	player.add_child(pshape)
	world.add_child(player)
	player.global_position = Vector3(10, 0, 10)

	var gold_before := items.inventory.gold
	var pickup := ItemPickup.spawn(ItemInstance.create(&"gold", 50), world, Vector3(10, 0, 10))
	for i in 50:
		await physics_frame
	_check(not is_instance_valid(pickup), "walking over gold picks it up")
	_check(items.inventory.gold == gold_before + 50, "picked-up gold counted")

	var chest := LootChest.new()
	chest.loot_seed = 1234
	chest.biome = &"dungeon"
	chest.level = 9
	chest.source = &"chest_large"
	world.add_child(chest)
	chest.global_position = Vector3(-5, 0, -5)
	var expected := _dump(chest.roll_contents())
	var got := chest.open()
	_check(_dump(got) == expected, "chest contents are seeded")
	var has_gear := false
	for it in got:
		has_gear = has_gear or it.is_gear()
	_check(has_gear, "large chest always has gear")
	_check(chest.open().is_empty(), "a chest opens once")
	await process_frame
	var on_ground := 0
	for n in world.get_children():
		if n is ItemPickup:
			on_ground += 1
	_check(on_ground == got.size(), "chest items are on the ground")
	world.queue_free()
	await process_frame


func _test_inventory_screen() -> void:
	var items: ItemsService = root.get_node("Items")
	items.reset()
	items.give_starter_kit()
	var rng := LootRoller.rng_for(11)
	for i in 6:
		items.pick_up(LootRoller.roll_gear(12, rng))
	var screen: Control = load("res://ui/inventory/inventory_screen.gd").new()
	root.add_child(screen)
	screen.open()
	await process_frame
	_check(screen.visible, "inventory screen opens")
	_check(screen.get_slot_view(&"main_hand") != null, "equipment slot views exist")
	var staff := items.equipment.get_item(&"main_hand")
	_check(screen.get_slot_view(&"main_hand").item == staff, "slot view shows the worn staff")
	var lines: Array = screen.tooltip_lines_for(items.inventory.items()[0], true)
	_check(lines.size() >= 2, "tooltip has lines")
	# Equip a bag item through the screen's right click path.
	var ring := ItemInstance.create(&"ring")
	items.pick_up(ring)
	await process_frame
	screen.activate_bag_item(ring)
	_check(items.equipment.is_equipped(ring), "right click on a ring equips it")
	screen.close()
	_check(not screen.visible, "inventory screen closes")
	screen.queue_free()
	await process_frame


func _dump(items: Array) -> String:
	var parts: PackedStringArray = []
	for it in items:
		parts.append(JSON.stringify(it.to_dict()))
	return "|".join(parts)


class _FakeStats extends RefCounted:
	var spell_power := 1.0
	var force_power := 1.0
	var cast_speed := 0.0
	var crit_chance := 0.05
	var crit_multiplier := 1.5
	var bonus_resource := 0.0
	var resource_regen := 1.0
	var bonus_health := 0.0


class _FakeHealth extends RefCounted:
	var max_health := 100.0
	var health := 100.0
	var armor := 0.0
	var regen_per_second := 0.0
	var resistances := {}


class _FakeHealthNode extends Node:
	signal health_changed(current: float, maximum: float)
	var max_health := 100.0
	var health := 100.0
	var armor := 0.0
	var regen_per_second := 0.0
	var resistances := {}

	func take_damage(_hit) -> float:
		return 0.0

	func heal(amount: float) -> float:
		var before := health
		health = minf(health + amount, max_health)
		return health - before


class _FakeResource extends RefCounted:
	var current := 0.0
	var maximum := 100.0

	func _set_current(v: float) -> void:
		current = v


class _FakeSource extends RefCounted:
	signal changed
	var gear_bonus_ranks := {}
	var library := {}

	func add_book(id: StringName, circle := 1) -> void:
		library[id] = maxi(library.get(id, 0), circle)


class _FakeCasterNode extends Node:
	var caster_resource := _FakeResource.new()
	var source := _FakeSource.new()
	var stats_set_count := 0

	func set_stats(_s) -> void:
		stats_set_count += 1


class _FakeEnemy extends Node3D:
	var level := 1
	var elite := false
