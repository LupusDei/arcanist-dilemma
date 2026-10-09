extends SceneTree
## Headless tests for character progression, creation and save/load.
## Run: godot --headless --path . --script res://systems/progression/tests/test_progression.gd

const ServiceScript := preload("res://systems/progression/progression_service.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_xp_and_leveling()
	_test_kill_xp()
	_test_attributes()
	_test_auto_assign()
	_test_path_and_specialization()
	_test_talents()
	_test_spell_growth()
	_test_appearance()
	_test_save_and_load()
	_test_service()

	if _failures.is_empty():
		print("PROGRESSION TESTS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _test_xp_and_leveling() -> void:
	var p := CharacterProgression.new()
	var gained: Array[int] = []
	var xp_events: Array = []
	p.leveled_up.connect(func(l): gained.append(l))
	p.xp_gained.connect(func(a, s): xp_events.append([a, s]))
	_check(p.level == 1 and p.xp == 0, "starts at level 1 with 0 xp")
	p.add_xp(ProgressionData.xp_to_next(1) - 1, "quest")
	_check(p.level == 1, "one xp short stays level 1")
	_check(xp_events == [[ProgressionData.xp_to_next(1) - 1, "quest"]], "xp_gained carries amount and source")
	p.add_xp(1)
	_check(p.level == 2 and p.xp == 0, "exact xp levels up to 2")
	var big := ProgressionData.xp_to_next(2) + ProgressionData.xp_to_next(3) + 7
	p.add_xp(big)
	_check(p.level == 4 and p.xp == 7, "a big gain levels twice and carries the rest (level %d, xp %d)" % [p.level, p.xp])
	_check(gained == [2, 3, 4], "leveled_up fires once per level in order (%s)" % [gained])
	p.add_xp(10_000_000)
	_check(p.level == 20, "story cap is level 20")
	_check(p.add_xp(100) == 0 and p.xp == 0, "no xp at the cap")
	p.replay_unlocked = true
	p.add_xp(10_000_000)
	_check(p.level == 30, "Nightmare replay cap is level 30")


func _test_kill_xp() -> void:
	var p := CharacterProgression.new()
	p.set_level(10)
	_check(p.xp_for_kill(10, 100) == 100, "even level kill gives full xp")
	_check(p.xp_for_kill(8, 100) == 100, "2 levels below still gives full xp")
	_check(p.xp_for_kill(6, 100) == 60, "4 levels below gives 60%")
	_check(p.xp_for_kill(1, 100) == 5, "far below bottoms out at 5%")
	_check(p.xp_for_kill(12, 100) == 110, "2 levels above gives 110%")
	_check(p.xp_for_kill(20, 100) == 125, "far above caps at 125%")


func _test_attributes() -> void:
	var p := CharacterProgression.new()
	for a in ProgressionData.ATTRIBUTES:
		_check(p.get_attribute(a) == 10, "%s starts at 10" % a)
	_check(p.unspent_attribute_points() == 0, "no points at level 1")
	_check(not p.allocate(&"strength"), "cannot spend points you don't have")
	var unspent_events: Array[int] = []
	var stat_events := [0]
	p.attribute_points_changed.connect(func(u): unspent_events.append(u))
	p.stats_changed.connect(func(): stat_events[0] += 1)
	p.set_level(3)
	_check(p.unspent_attribute_points() == 10, "5 points per level (10 at level 3)")
	_check(p.allocate(&"intelligence", 4), "spend 4 on intelligence")
	_check(p.get_attribute(&"intelligence") == 14 and p.unspent_attribute_points() == 6, "intelligence 14, 6 left")
	_check(not p.allocate_many({&"vitality": 3, &"wisdom": 4}), "batch over budget is refused")
	_check(p.get_attribute(&"vitality") == 10, "refused batch changes nothing")
	_check(not p.allocate(&"charisma", 1), "unknown attribute is refused")
	_check(p.allocate_many({"vitality": 3, "wisdom": 3}), "batch within budget works (string keys too)")
	_check(p.unspent_attribute_points() == 0, "all points spent")
	_check(unspent_events.back() == 0 and stat_events[0] >= 3, "signals fire on spending")
	_check(is_equal_approx(p.max_health(), 40 + 10 * 3 + 5 * 13), "health from level and vitality (%.0f)" % p.max_health())
	_check(is_equal_approx(p.health_regen(), 1.3), "health regen 0.1 per vitality")
	_check(not p.reset_attributes(), "reset needs a Tome of Unlearning")
	p.grant_tome_of_unlearning()
	_check(p.reset_attributes() and p.unspent_attribute_points() == 10 and p.tomes_of_unlearning == 0, "tome resets attributes and is used up")


func _test_auto_assign() -> void:
	var p := CharacterProgression.new()
	p.set_level(20)
	p.choose_path("mage")
	p.choose_specialization("chronos")
	var plan := p.auto_assign()
	_check(p.unspent_attribute_points() == 0, "auto-assign spends every point")
	_check(p.get_attribute(&"strength") == 10 and p.get_attribute(&"intelligence") == 50,
			"Chronos auto build matches the doc's example (Int %d)" % p.get_attribute(&"intelligence"))
	_check(plan.size() == 4, "plan lists only attributes that got points")
	var q := CharacterProgression.new()
	q.set_level(2)
	q.auto_assign()
	var each_one := true
	for a in ProgressionData.ATTRIBUTES:
		each_one = each_one and q.get_attribute(a) == 11
	_check(each_one, "before a path, auto-assign spreads evenly")


func _test_path_and_specialization() -> void:
	var p := CharacterProgression.new()
	var choices: Array[StringName] = []
	p.choice_available.connect(func(k): choices.append(k))
	_check(not p.choose_path("mage"), "no path before level 5")
	p.add_xp(10_000 + 0 * 1)  # crosses level 5
	_check(p.level >= 5 and choices.has(&"path"), "reaching level 5 announces the path choice")
	_check(p.pending_choices().has(&"path"), "path shows in pending choices")
	_check(not p.choose_path("necromancer"), "unknown path refused")
	_check(p.choose_path("sorcerer"), "choose sorcerer")
	_check(not p.choose_path("wizard"), "path is permanent")
	_check(not p.choose_specialization("stormborn"), "no specialization before 10")
	p.set_level(10)
	_check(choices.has(&"specialization"), "level 10 announces specialization")
	_check(not p.choose_specialization("chronos"), "another path's specialization refused")
	_check(p.choose_specialization("stormborn"), "choose Stormborn")
	_check(not p.choose_crossing("mage"), "no crossing before 15")
	p.set_level(15)
	_check(choices.has(&"crossing"), "level 15 announces crossing")
	_check(not p.choose_crossing("sorcerer"), "cannot cross into your own path")
	_check(p.choose_crossing("mage") and p.crossing == "mage", "cross into mage")


func _test_talents() -> void:
	var p := CharacterProgression.new()
	p.set_level(14)
	p.choose_path("mage")
	_check(p.unlocked_talent_rows().is_empty(), "no talent rows without a specialization")
	p.choose_specialization("chronos")
	_check(p.unlocked_talent_rows() == [10, 12, 14], "rows 10, 12, 14 open at level 14")
	_check(p.open_talent_rows() == [10, 12, 14], "all three are unpicked")
	_check(p.choose_talent(10, "echo"), "pick Echo at 10")
	_check(not p.choose_talent(10, "wide_slow"), "row already filled")
	_check(not p.choose_talent(12, "echo"), "option from another row refused")
	_check(not p.choose_talent(16, "age"), "row 16 not open yet")
	_check(p.choose_talent(12, "stasis") and p.has_talent("stasis"), "pick Stasis at 12")
	p.reset_talent_row(10)
	_check(not p.has_talent("echo") and p.choose_talent(10, "wide_slow"), "a row can be reset and re-picked")
	p.reset_talents()
	_check(p.talents.is_empty(), "full talent reset")
	var s := CharacterProgression.new()
	s.set_level(12)
	s.choose_path("wizard")
	s.choose_specialization("archivist")
	_check(s.unlocked_talent_rows() == [10, 12] and s.open_talent_rows().is_empty(),
			"specs without a written tree unlock rows but offer nothing yet")


func _test_spell_growth() -> void:
	var w := CharacterProgression.new()
	w.set_level(5)
	w.choose_path("wizard")
	_check(w.spellbook_slots() == 5, "wizard gets all 5 slots at the path choice")
	_check(w.open_circle() == 2, "circles I and II open at level 5")
	w.set_level(19)
	_check(w.spellbook_slots() == 19 and w.open_circle() == 7, "level 19 wizard: 19 slots, circle VII")
	w.complete_key_quest("den")
	_check(w.rare_spellbooks_earned() == 1, "key quest owes a wizard a rare book")
	_check(not w.spend_spell_growth(1), "wizards don't spend slots")

	var m := CharacterProgression.new()
	m.set_level(5)
	m.choose_path("mage")
	_check(m.insight_earned() == 0, "mage has no Insight at 5")
	m.set_level(6)
	_check(m.insight_earned() == 1, "first Insight at 6")
	m.set_level(20)
	_check(m.insight_earned() == 8, "8 Insight from levels by 20")
	for q in ["a", "b", "c", "d", "e"]:
		m.complete_key_quest(q)
	_check(not m.complete_key_quest("a"), "a key quest counts once")
	_check(m.insight_earned() == 13, "about 13 Insight at 20 with key quests, as the doc says")
	_check(m.spend_spell_growth(2) and m.insight_available() == 11, "spending Insight")
	_check(not m.spend_spell_growth(12), "cannot overspend Insight")
	_check(m.compounds_unlocked(), "compounds open by 12")
	m.refund_spell_growth()
	_check(m.insight_available() == 13, "trainer refund returns all Insight")

	var s := CharacterProgression.new()
	s.set_level(7)
	s.choose_path("sorcerer")
	_check(s.spell_points_earned() == 6, "sorcerer chosen late at 7 still gets 4 + 2 points")
	_check(s.open_tree_rows() == 1, "one tree row open at 7")
	s.set_level(20)
	for q in ["a", "b", "c", "d", "e"]:
		s.complete_key_quest(q)
	_check(s.spell_points_earned() == 24 and s.open_tree_rows() == 6, "about 24 points and all 6 rows at 20")
	s.complete_control_trial("trial_1")
	_check(s.spell_points_available() == 25, "control trials add a point")
	_check(s.spend_spell_growth(3) and s.spell_points_available() == 22, "spending spell points")


func _test_appearance() -> void:
	var a := CharacterAppearance.create_default("girl")
	_check(a.validate().is_empty(), "default girl appearance is valid (%s)" % [a.validate()])
	_check(a.set_option("hair_style", "bun"), "girl can pick a bun")
	_check(not a.set_option("hair_style", "shaved_sides"), "body-specific hair is enforced")
	_check(a.set_option("body", "boy") and a.hair_style != "bun", "switching body fixes an invalid hair style")
	_check(not a.set_option("skin", "skin_99"), "unknown preset refused")
	_check(not a.set_character_name("   "), "blank name refused")
	_check(not a.set_character_name("A name much too long to fit"), "overlong name refused")
	_check(a.set_character_name("  Thale  ") and a.character_name == "Thale", "name is trimmed")
	var first := a.face
	var faces := a.options_for("face")
	_check(a.cycle_option("face", -1) == faces[faces.size() - 1] and a.cycle_option("face") == first, "cycling wraps both ways")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all_valid := true
	for i in 50:
		all_valid = all_valid and CharacterAppearance.create_random(rng).validate().is_empty()
	_check(all_valid, "random appearances are always valid")
	var bad := CharacterAppearance.from_dict({"body": "dragon", "name": "", "skin": "nope"})
	_check(bad.validate().is_empty(), "garbage save data falls back to a valid look")


func _test_save_and_load() -> void:
	var path := "user://test_saves/slot_test.json"
	var a := CharacterAppearance.create_default("girl")
	a.set_character_name("Maren")
	a.set_option("eyes", "amber")
	var p := CharacterProgression.new()
	p.set_level(12)
	p.add_xp(300)
	p.choose_path("mage")
	p.choose_specialization("chronos")
	p.allocate_many({&"intelligence": 30, &"dexterity": 10})
	p.choose_talent(10, "echo")
	p.complete_key_quest("den")
	p.spend_spell_growth(2)
	p.grant_tome_of_unlearning()
	var before := p.to_dict()
	_check(ProgressionSave.save_to_file(path, a, p, 125.0, {"inventory": {"gold": 40}}) == OK, "save writes")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")

	var a2 := CharacterAppearance.new()
	var p2 := CharacterProgression.new()
	var reloaded := [false]
	p2.reloaded.connect(func(): reloaded[0] = true)
	var extra = ProgressionSave.load_into(path, a2, p2)
	_check(extra is Dictionary and extra["inventory"]["gold"] == 40, "other systems' data round-trips")
	_check(p2.to_dict() == before, "progression round-trips exactly")
	_check(a2.to_dict() == a.to_dict(), "appearance round-trips exactly")
	_check(reloaded[0], "load emits reloaded on the same instance")
	_check(p2.talents.has(10) and p2.insight_available() == p.insight_available(), "talents and Insight survive")
	_check(ProgressionSave.load_into("user://test_saves/missing.json", a2, p2) == null, "missing file loads nothing")

	var cheat := CharacterProgression.from_dict({"level": 3, "attributes": {"intelligence": 99}, "talents": {"10": "echo"},
			"path": "mage", "insight_spent": 50})
	_check(cheat.get_attribute(&"intelligence") == 10 and cheat.unspent_attribute_points() == 10,
			"impossible attributes are reset on load")
	_check(cheat.talents.is_empty() and cheat.insight_spent == 0, "impossible talents and spending are dropped")
	DirAccess.remove_absolute(path)


func _test_service() -> void:
	var service: Node = ServiceScript.new()
	root.add_child(service)
	var levels: Array[int] = []
	var loads := [0]
	service.leveled_up.connect(func(l): levels.append(l))
	service.character_loaded.connect(func(): loads[0] += 1)
	var look := CharacterAppearance.create_default("boy")
	look.set_character_name("Aren")
	service.new_character(look)
	_check(service.appearance.character_name == "Aren" and service.progression.level == 1, "new character starts at level 1")
	service.grant_xp(ProgressionData.xp_to_next(1), "quest")
	_check(levels == [2], "service forwards leveled_up")
	var prog_before: CharacterProgression = service.progression
	_check(service.save_game(9, {"world": {"day": 3}}) == OK, "service saves to a slot")
	service.grant_xp(100000)
	_check(service.load_game(9), "service loads the slot")
	_check(service.progression == prog_before and service.progression.level == 2, "load keeps the same instance and restores level 2")
	_check(service.loaded_extra["world"]["day"] == 3 and loads[0] == 2, "extra data restored and character_loaded fired")
	var slots := ProgressionSave.list_slots()
	var found := false
	for s in slots:
		found = found or (s["slot"] == 9 and s["name"] == "Aren" and s["level"] == 2)
	_check(found, "slot list summarizes the save")
	_check(not service.load_game(8), "missing slot fails cleanly")
	ProgressionSave.delete_slot(9)
	service.queue_free()


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
