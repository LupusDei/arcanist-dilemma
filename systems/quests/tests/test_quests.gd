extends SceneTree
## Headless tests for quests, dialogue, story flags, alignment, save/load and
## the dialogue UI. Plays the whole prologue and every route through
## The Hat and the Warden.
## Run: godot --headless --path . --script res://systems/quests/tests/test_quests.gd

const SAVE_PATH := "user://test_quests_save.json"
const SAVE_SLOT := 97

var _failures := 0
var _checks := 0
var _current := ""


func _initialize() -> void:
	# Nodes only get _ready once the tree is running, so start on the first frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var tests := [
		"test_data_loads_cleanly",
		"test_validation_catches_mistakes",
		"test_alignment_grid",
		"test_story_state_flags_and_save",
		"test_conditions",
		"test_prologue_playthrough",
		"test_cast_needs_the_right_place",
		"test_kills_and_loot_from_enemy_hooks",
		"test_key_quest_hand_over",
		"test_key_quest_hide_and_lie",
		"test_key_quest_refuse_and_fight",
		"test_old_man_name_stays_hidden",
		"test_dialogue_priority_once_and_locked_choices",
		"test_save_and_load_mid_quest",
		"test_progression_hookup",
		"test_dialogue_ui_and_tracker",
	]
	for test in tests:
		_current = test
		call(test)
	print("%d checks, %d failed" % [_checks, _failures])
	print("QUEST TESTS PASSED" if _failures == 0 else "QUEST TESTS FAILED")
	quit(1 if _failures else 0)


# --- Helpers -----------------------------------------------------------------

func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("  FAIL %s: %s" % [_current, what])


func make_manager(start := true) -> QuestManager:
	var m := QuestManager.new()
	m.use_progression = false
	m.start_on_ready = start
	root.add_child(m)
	return m


func free_manager(m: QuestManager) -> void:
	root.remove_child(m)
	m.free()


## Plays whatever dialogue is running (and any queued after it) to the end,
## picking choices from [param picks] in order (0 when it runs out).
func play_active(m: QuestManager, picks: Array = []) -> void:
	var guard := 0
	while m.active_dialogue != null and guard < 200:
		guard += 1
		var runner := m.active_dialogue
		if runner.has_choices():
			var index: int = picks.pop_front() if not picks.is_empty() else 0
			if not runner.choose(index):
				check(false, "choice %d locked in %s/%s" % [index, runner.dialogue.id, runner.line.id])
				runner.stop()
		else:
			runner.advance()
	check(guard < 200, "dialogue ran away")


func talk(m: QuestManager, npc: StringName, picks: Array = []) -> void:
	check(m.talk_to(npc), "can talk to %s (stage %s)" % [npc, m.get_quest_stage(&"prologue")])
	play_active(m, picks)


## Plays the prologue to the end. [param route] picks the Wardens answer
## (0 tell everything, 1 half truth, 2 lie).
func play_prologue(m: QuestManager, wardens_choice := 0) -> void:
	m.notify_reached(&"kitchen")
	m.notify_spell_cast(&"nudge")
	m.notify_spell_cast(&"spark")
	m.notify_left(&"kitchen")
	talk(m, &"tam")
	talk(m, &"rook", [1])
	talk(m, &"farmer_hollis")
	for i in 3:
		m.notify_killed(&"gloom_hound")
	talk(m, &"farmer_hollis", [1])
	m.notify_reached(&"tavern")
	talk(m, &"old_man", [2, 0, 0, 1, 0])
	m.notify_reached(&"hill_road")
	play_active(m, [0])
	talk(m, &"home_bed", [0, 0])
	talk(m, &"warden_sergeant", [wardens_choice])
	talk(m, &"children")
	m.notify_reached(&"village_square")


# --- Tests -------------------------------------------------------------------

func test_data_loads_cleanly() -> void:
	var db := QuestDatabase.load_from()
	for error in db.errors:
		printerr("    ", error)
	check(db.errors.is_empty(), "quest data has no errors")
	check(db.get_quest(&"prologue") != null, "prologue exists")
	check(db.get_quest(&"hat_and_warden") != null, "The Hat and the Warden exists")
	check(db.get_quest(&"hat_and_warden").key_quest, "The Hat and the Warden is a key quest")
	check(db.speakers.has(&"old_man"), "old man is a speaker")


func test_validation_catches_mistakes() -> void:
	var db := QuestDatabase.new()
	db.load_dict({
		"speakers": {"bob": {"name": "Bob"}},
		"quests": [{"id": "q", "stages": [
			{"id": "a", "next": "missing", "objectives": [{"id": "o", "type": "dance", "target": "x", "description": "Dance"}]},
		], "on_start": [{"teleport": true}, {"start_quest": "nope"}]}],
		"dialogues": [{"id": "d", "npc": "ghost", "lines": [
			{"text": "Hi", "choices": [{"text": "Bye", "next": "nowhere"}]},
			{"speaker": "nobody", "text": "?", "effects": [{"alignment": {"chaos": 5}}], "branches": [{"conditions": [{"quest": "q", "stage": "zzz"}], "next": "l0"}]},
		]}],
	})
	var errors := "\n".join(db.validate())
	for needle in ["stage 'missing' does not exist", "unknown type 'dance'", "unknown effect 'teleport'",
			"unknown quest 'nope'", "line 'nowhere' does not exist", "unknown speaker 'nobody'",
			"unknown speaker 'ghost'", "axis must be law or good", "has no stage 'zzz'"]:
		check(needle in errors, "validation reports: %s" % needle)


func test_alignment_grid() -> void:
	var a := Alignment.new()
	check(a.archetype() == &"true_neutral", "starts true neutral")
	var shifts := []
	a.changed.connect(func(l, g, s): shifts.append([l, g, s]))
	a.shift(30, -40, "test")
	check(a.archetype() == &"lawful_evil", "30/-40 is lawful evil")
	check(a.archetype_name() == "Lawful Evil", "display name")
	check(shifts.size() == 1 and shifts[0][2] == "test", "changed signal with source")
	a.shift(500, 500)
	check(a.law == 100.0 and a.good == 100.0, "clamped to 100")
	check(Alignment.archetype_for(-30, 0) == &"chaotic_neutral", "chaotic neutral")
	check(Alignment.archetype_display_name(&"neutral_good") == "Neutral Good", "neutral good name")
	check(Alignment.describe_shift(-2, 3) == "Chaotic, Good", "hint text")
	check(Alignment.describe_shift(0, 0) == "", "no hint without a shift")
	var b := Alignment.new()
	b.from_dict(a.to_dict())
	check(b.law == a.law and b.history.size() == a.history.size(), "alignment round-trips")


func test_story_state_flags_and_save() -> void:
	var s := StoryState.new()
	var changes := []
	s.flag_changed.connect(func(f, v, p): changes.append([f, v, p]))
	s.set_flag(&"hat_hidden")
	s.set_flag(&"hat_hidden")
	check(changes.size() == 1, "setting the same value twice signals once")
	s.add_to_flag(&"tam_bond", 2)
	s.add_to_flag(&"tam_bond", 1)
	check(s.get_flag(&"tam_bond") == 3 and typeof(s.get_flag(&"tam_bond")) == TYPE_INT, "counters stay ints")
	s.set_flag(&"rook_outcome", "jolted_cap")
	s.change_standing(&"wardens", 150)
	check(s.get_standing(&"wardens") == 100.0, "standing clamps")
	s.alignment.shift(-10, 5, "x")
	var copy := StoryState.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(copy.is_set(&"hat_hidden"), "bool flag survives JSON")
	check(copy.get_flag(&"tam_bond") == 3 and typeof(copy.get_flag(&"tam_bond")) == TYPE_INT, "int flag survives JSON")
	check(copy.get_flag(&"rook_outcome") == "jolted_cap", "string flag survives JSON")
	check(copy.alignment.law == -10.0 and copy.get_standing(&"wardens") == 100.0, "alignment and standing survive JSON")
	s.clear_flag(&"hat_hidden")
	check(not s.is_set(&"hat_hidden") and changes[-1][1] == null, "clear signals null")


func test_conditions() -> void:
	var m := make_manager(false)
	var s := m.story
	s.set_flag(&"count", 3)
	s.set_flag(&"name", "rook")
	s.alignment.shift(30, -5)
	s.change_standing(&"wardens", 12)
	var cases := [
		[[{"flag": "count"}], true],
		[[{"flag": "count", "min": 4}], false],
		[[{"flag": "count", "equals": 3}], true],
		[[{"flag": "name", "equals": "rook"}], true],
		[[{"flag": "missing"}], false],
		[[{"not_flag": "missing"}], true],
		[[{"alignment": "law", "min": 25}], true],
		[[{"alignment": "good", "max": -10}], false],
		[[{"lean": "lawful"}], true],
		[[{"lean": "evil"}], false],
		[[{"standing": "wardens", "min": 10}], true],
		[[{"quest": "hat_and_warden", "state": "not_started"}], true],
		[[{"quest": "hat_and_warden", "state": "active"}], false],
		[[{"quest": "prologue", "state": "started"}], true],
		[[{"quest": "prologue", "stage": "chores"}], true],
		[[{"level_min": 1}], true],
		[[{"level_min": 2}], false],
		[[{"any": [{"flag": "missing"}, {"flag": "count"}]}], true],
		[[{"not": [{"flag": "count"}]}], false],
		[[{"flag": "count"}, {"flag": "missing"}], false],
	]
	for c in cases:
		check(StoryConditions.check_all(c[0], m) == c[1], "condition %s is %s" % [JSON.stringify(c[0]), c[1]])
	free_manager(m)


func test_prologue_playthrough() -> void:
	var m := make_manager()
	var started := []
	var completed := []
	var events := []
	var items := {}
	var xp := [0]
	var flags := []
	var shifts := []
	m.quest_started.connect(func(id): started.append(id))
	m.quest_completed.connect(func(id): completed.append(id))
	m.story_event.connect(func(e): events.append(e))
	m.item_granted.connect(func(id, n): items[id] = items.get(id, 0) + n)
	m.xp_rewarded.connect(func(n, _s): xp[0] += n)
	m.flag_changed.connect(func(f, _v, _p): flags.append(f))
	m.alignment_changed.connect(func(l, g, _s): shifts.append([l, g]))

	check(m.is_active(&"prologue"), "prologue starts by itself")
	check(m.get_quest_stage(&"prologue") == &"chores", "starts with chores")
	check(not m.talk_to(&"old_man"), "the old man isn't there yet")

	m.notify_reached(&"kitchen")
	m.notify_spell_cast(&"nudge")
	check(m.get_progress(&"prologue").is_objective_done(&"spoon"), "spoon done")
	m.notify_spell_cast(&"spark")
	talk(m, &"tam")
	check(m.get_quest_stage(&"prologue") == &"bully", "chores done -> bully")
	talk(m, &"rook", [1])
	check(m.story.get_flag(&"rook_outcome") == "jolted_cap", "rook choice recorded")
	check(m.story.alignment.law == -2.0 and m.story.alignment.good == 2.0, "rook choice moved alignment")
	talk(m, &"farmer_hollis")
	check(m.get_quest_stage(&"prologue") == &"wolves", "-> wolves")
	m.notify_killed(&"gloom_hound")
	m.notify_killed(&"bramble_brute")
	m.notify_killed(&"gloom_hound")
	check(m.get_progress(&"prologue").get_count(&"hounds") == 2, "only hounds count")
	m.notify_killed(&"gloom_hound")
	check(m.get_quest_stage(&"prologue") == &"wolves_report", "three hounds -> report")
	talk(m, &"farmer_hollis", [1])
	check(items.get(&"farmhand_gloves") == 1, "Hollis gives gloves")
	m.notify_reached(&"tavern")
	check(m.get_quest_stage(&"prologue") == &"stranger", "-> stranger")
	talk(m, &"old_man", [2, 1, 1, 1])
	check(m.story.is_set(&"asked_old_man_name") and m.story.is_set(&"agreed_to_walk"), "old man talk flags")
	check(m.pick_dialogue(&"old_man") == null, "the tavern talk plays once")
	m.notify_reached(&"hill_road")
	check(m.is_in_dialogue() and m.active_dialogue.dialogue.id == &"lightning_strike", "lightning scene plays on the hill")
	play_active(m, [1])
	check(&"lightning_strike" in events and &"warden_rider_watches" in events, "lightning and rider events")
	check(items.get(&"old_mans_hat") == 1 and items.get(&"worn_staff") == 1, "hat and staff given")
	check(m.get_quest_stage(&"prologue") == &"dream", "-> dream")
	talk(m, &"home_bed", [0, 2])
	check(m.story.is_set(&"had_dream"), "the dream plays after sleeping")
	check(m.get_quest_stage(&"prologue") == &"wardens", "-> wardens")
	talk(m, &"warden_sergeant", [0])
	check(m.story.is_set(&"told_wardens") and m.story.get_standing(&"wardens") == 5.0, "told the wardens")
	check(m.get_quest_stage(&"prologue") == &"square", "-> square")
	m.notify_reached(&"village_square")
	check(m.get_quest_state(&"prologue") == QuestProgress.COMPLETED, "optional children talk doesn't hold it back")
	check(completed == [&"prologue"], "quest_completed fired")
	check(m.story.is_set(&"prologue_done"), "on_complete flag set")
	check(xp[0] == 190, "chores 40 + prologue 150 XP (got %d)" % xp[0])
	check(started == [&"hat_and_warden"], "key quest starts after the prologue")
	check(flags.has(&"old_man_struck") and not shifts.is_empty(), "flag_changed and alignment_changed fire")
	free_manager(m)


func test_cast_needs_the_right_place() -> void:
	var m := make_manager()
	m.notify_spell_cast(&"nudge")
	check(not m.get_progress(&"prologue").is_objective_done(&"spoon"), "nudge outside the kitchen doesn't count")
	m.notify_reached(&"kitchen")
	m.notify_spell_cast(&"jolt")
	check(not m.get_progress(&"prologue").is_objective_done(&"spoon"), "wrong spell doesn't count")
	m.notify_spell_cast(&"nudge")
	check(m.get_progress(&"prologue").is_objective_done(&"spoon"), "nudge in the kitchen counts")
	free_manager(m)


func test_kills_and_loot_from_enemy_hooks() -> void:
	var m := make_manager()
	check(m.is_in_group(QuestManager.ENEMY_LISTENER_GROUP), "listens for enemy deaths")
	check(m.is_in_group(QuestManager.LOOT_LISTENER_GROUP), "listens for loot")
	m.goto_stage(&"prologue", &"wolves")
	var hound := Node3D.new()
	hound.set_meta(&"quest_type", "gloom_hound")
	for listener in get_nodes_in_group(QuestManager.ENEMY_LISTENER_GROUP):
		listener.on_enemy_died(hound, 10, [])
	check(m.get_progress(&"prologue").get_count(&"hounds") == 1, "enemy hook counts a kill")
	hound.free()
	# Type from the EnemyData file name, as real enemies have it.
	var data := Resource.new()
	data.take_over_path("res://actors/enemies/types/gloom_hound.tres")
	var enemy := Node3D.new()
	enemy.set_script(_script_with_data())
	enemy.set("data", data)
	check(QuestManager.enemy_type_of(enemy) == &"gloom_hound", "type id from EnemyData path")
	enemy.free()
	var q := QuestDatabase.parse_quest({"id": "loot_q", "stages": [{"id": "s", "objectives": [
		{"id": "pelts", "type": "collect", "target": "hound_pelt", "count": 3, "description": "Pelts"}]}]})
	m.database.add_quest(q)
	m.start_quest(&"loot_q")
	m.on_loot_collected([{"id": &"hound_pelt", "count": 2}, {"id": &"gold", "count": 5}], null)
	check(m.get_progress(&"loot_q").get_count(&"pelts") == 2, "loot hook counts items")
	m.notify_collected(&"hound_pelt", 4)
	check(m.get_quest_state(&"loot_q") == QuestProgress.COMPLETED, "collect completes, count capped")
	free_manager(m)


func _script_with_data() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar data: Resource\n"
	script.reload()
	return script


func test_key_quest_hand_over() -> void:
	var m := make_manager()
	play_prologue(m, 0)
	check(m.get_quest_stage(&"hat_and_warden") == &"summons", "key quest at summons")
	var items_taken := {}
	m.item_removed.connect(func(id, n): items_taken[id] = n)
	var runner := m.start_dialogue(&"hale_summons", &"warden_lieutenant")
	check(runner.get_view()["speaker"] == "", "narration has no name")
	runner.advance()
	runner.advance()
	check(runner.line.id == &"knows", "Hale knows because you told the Wardens")
	play_active(m, [0])
	check(m.get_quest_stage(&"hat_and_warden") == &"decide", "-> decide")
	var law_before := m.story.alignment.law
	talk(m, &"warden_lieutenant", [0])
	check(items_taken.get(&"old_mans_hat") == 1 and items_taken.get(&"worn_staff") == 1, "hat and staff taken")
	check(m.story.is_set(&"varrow_trust") and m.story.is_set(&"warden_contact"), "Varrow's trust and a Warden contact")
	check(m.story.alignment.law == law_before + 12.0, "handing over is lawful")
	check(m.story.get_standing(&"wardens") == 20.0, "Warden standing up")
	check(m.get_quest_stage(&"hat_and_warden") == &"aftermath", "-> aftermath")
	talk(m, &"tam", [0, 0])
	check(m.get_quest_state(&"hat_and_warden") == QuestProgress.COMPLETED, "key quest complete")
	free_manager(m)


func test_key_quest_hide_and_lie() -> void:
	var m := make_manager()
	play_prologue(m, 2)
	talk(m, &"warden_lieutenant")
	check(m.active_dialogue == null, "summons over")
	# Lying without hiding first is shown but locked.
	check(m.talk_to(&"warden_lieutenant"), "Hale talks in decide")
	var view := m.active_dialogue.get_view()
	check(view["choices"][1]["enabled"] == false and view["choices"][1]["locked_text"] == "Hide them somewhere first", "lie locked until hidden")
	check(not m.active_dialogue.choose(1), "locked choice can't be picked")
	m.active_dialogue.choose(3)
	play_active(m)
	check(m.get_quest_stage(&"hat_and_warden") == &"decide", "walking away keeps the stage")
	talk(m, &"old_mill_floorboards", [0])
	check(m.story.is_set(&"belongings_hidden"), "hidden at the mill")
	check(m.get_quest_stage(&"hat_and_warden") == &"decide", "hiding alone doesn't finish it")
	check(m.pick_dialogue(&"old_mill_floorboards") == null, "nothing more to do at the mill")
	talk(m, &"warden_lieutenant", [1])
	check(m.story.is_set(&"lied_to_hale") and m.story.is_set(&"old_man_dreams_sooner"), "lie flags, dreams come sooner")
	check(m.story.alignment.law_lean() == &"neutral" or m.story.alignment.law < 0.0, "lying is chaotic")
	check(m.get_quest_stage(&"hat_and_warden") == &"aftermath", "-> aftermath")
	var runner := m.start_dialogue(&"tam_aftermath", &"tam")
	runner.advance()
	check(runner.line.id == &"lied", "Tam reacts to the lie")
	play_active(m, [0, 0])
	check(m.get_quest_state(&"hat_and_warden") == QuestProgress.COMPLETED, "key quest complete")
	free_manager(m)


func test_key_quest_refuse_and_fight() -> void:
	var m := make_manager()
	var events := []
	m.story_event.connect(func(e): events.append(e))
	play_prologue(m, 1)
	talk(m, &"warden_lieutenant")
	talk(m, &"warden_lieutenant", [2])
	check(&"warden_escort_attack" in events, "the escort attacks")
	check(m.get_quest_stage(&"hat_and_warden") == &"fight", "refusing -> fight")
	m.notify_killed(&"warden_escort", 2)
	check(m.story.is_set(&"drove_off_wardens") and m.story.get_standing(&"wardens") < -20.0, "Wardens hostile")
	check(&"wardens_retreat" in events, "retreat event")
	check(m.get_quest_stage(&"hat_and_warden") == &"aftermath", "-> aftermath")
	talk(m, &"tam", [1, 1])
	check(m.get_quest_state(&"hat_and_warden") == QuestProgress.COMPLETED, "key quest complete")
	check(m.story.alignment.law < -15.0, "fighting the Wardens is chaotic (law %.0f)" % m.story.alignment.law)
	free_manager(m)


func test_old_man_name_stays_hidden() -> void:
	var m := make_manager()
	check(m.speaker_name(&"old_man") == "The Old Man in Grey", "hidden name")
	check(m.format_text("Ask {speaker:old_man}, {player}.") == "Ask The Old Man in Grey, Arcanist.", "tokens")
	m.story.set_flag(&"greycloak_revealed")
	check(m.speaker_name(&"old_man") == "Ebon Thale", "revealed late")
	var all_text := ""
	for d: DialogueData in m.database.dialogues.values():
		for l: DialogueLine in d.lines.values():
			all_text += l.text + " "
			for c in l.choices:
				all_text += c.text + " "
	check(not "Thale" in all_text and not "Ebon" in all_text, "no early dialogue names him")
	free_manager(m)


func test_dialogue_priority_once_and_locked_choices() -> void:
	var m := make_manager()
	check(m.pick_dialogue(&"tam").id == &"tam_chores", "quest talk beats idle chatter")
	check(m.pick_dialogue(&"rook").id == &"rook_idle", "idle when nothing is due")
	talk(m, &"rook")
	check(m.get_quest_stage(&"prologue") == &"chores", "idle talk doesn't advance")
	check(m.start_dialogue(&"tam_idle") != null, "scripted start")
	check(m.start_dialogue(&"rook_idle") == null, "second dialogue is queued")
	play_active(m)
	check(m.seen_dialogues.has(&"rook_idle") and not m.is_in_dialogue(), "queued dialogue played")
	free_manager(m)


func test_save_and_load_mid_quest() -> void:
	var m := make_manager()
	m.notify_reached(&"kitchen")
	m.notify_spell_cast(&"nudge")
	m.notify_spell_cast(&"spark")
	talk(m, &"tam")
	talk(m, &"rook", [0])
	talk(m, &"farmer_hollis")
	m.notify_killed(&"gloom_hound")
	check(m.save_to_file(SAVE_PATH) == OK, "saved")
	var law := m.story.alignment.law
	free_manager(m)

	var n := make_manager()
	check(n.get_quest_stage(&"prologue") == &"chores", "fresh manager starts over")
	check(n.load_from_file(SAVE_PATH), "loaded")
	check(n.get_quest_stage(&"prologue") == &"wolves", "stage restored")
	check(n.get_progress(&"prologue").get_count(&"hounds") == 1, "kill count restored")
	check(n.story.alignment.law == law and n.story.get_flag(&"rook_outcome") == "jolted_hard", "story restored")
	check(n.seen_dialogues.has(&"tam_chores"), "seen dialogues restored")
	n.notify_killed(&"gloom_hound", 2)
	check(n.get_quest_stage(&"prologue") == &"wolves_report", "carries on after load")
	n.new_game()
	check(n.get_quest_stage(&"prologue") == &"chores" and n.story.flags.is_empty(), "new game resets")
	free_manager(n)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_progression_hookup() -> void:
	var progression: Node = root.get_node_or_null(^"Progression")
	check(progression != null, "Progression autoload is registered")
	if progression == null:
		return
	progression.new_character(CharacterAppearance.create_default())
	var m := QuestManager.new()
	root.add_child(m)
	var xp_before: int = progression.progression.total_xp
	m.complete_quest(&"hat_and_warden")
	check(progression.progression.total_xp == xp_before + 300, "quest XP reaches Progression")
	check("hat_and_warden" in progression.progression.key_quests_completed, "key quest bonus reaches Progression")
	check(m.get_player_level() == progression.progression.level, "level read from Progression")
	progression.appearance.character_name = "Wren"
	check(m.format_text("{player}") == "Wren", "player name from Progression")

	# Quests ride along in Progression's save file.
	check(progression.save_game(SAVE_SLOT, {QuestManager.SAVE_KEY: m.to_dict()}) == OK, "saved through Progression")
	m.story.set_flag(&"after_save")
	check(progression.load_game(SAVE_SLOT), "loaded through Progression")
	check(m.get_quest_state(&"hat_and_warden") == QuestProgress.COMPLETED and not m.story.is_set(&"after_save"), "story restored from the save")
	progression.new_character(CharacterAppearance.create_default())
	check(m.get_quest_state(&"hat_and_warden") == &"not_started" and m.is_active(&"prologue"), "a new character starts the story over")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressionSave.slot_path(SAVE_SLOT)))
	root.remove_child(m)
	m.free()


func test_dialogue_ui_and_tracker() -> void:
	var m := make_manager()
	var ui: QuestUI = load("res://ui/dialogue/quest_ui.tscn").instantiate()
	root.add_child(ui)
	ui.dialogue_box.chars_per_second = 0.0
	check(ui.manager == m, "UI finds the manager")
	var lines := ui.tracker.get_lines()
	check(lines.size() == 4 and lines[0] == "◆ Tricks", "tracker shows the prologue (%s)" % [lines])
	check(lines[1].begins_with("• Nudge the spoon"), "tracker shows objectives")

	m.goto_stage(&"prologue", &"wolves")
	m.notify_killed(&"gloom_hound")
	ui.tracker.refresh()
	lines = ui.tracker.get_lines()
	check(lines.size() == 2 and "(1/3)" in lines[1], "tracker counts kills (%s)" % [lines])

	m.goto_stage(&"prologue", &"bully")
	check(m.talk_to(&"rook"), "talk to rook")
	check(ui.dialogue_box.visible, "dialogue box opens")
	check(paused, "game paused during dialogue")
	ui.dialogue_box.advance()
	ui.dialogue_box.advance()
	var shown := ui.dialogue_box.get_shown()
	check(shown["choices"].size() == 3, "three choices on screen")
	check(shown["choices"][0].begins_with("1.  Jolt"), "numbered choices")
	check(ui.dialogue_box.pick(2), "pick by number")
	check(ui.get_notice() == "Your choice leans Lawful", "alignment hint notice (%s)" % ui.get_notice())
	ui.dialogue_box.advance()
	shown = ui.dialogue_box.get_shown()
	check(shown["speaker"] == "Tam", "speaker name shown (%s)" % shown["speaker"])
	ui.dialogue_box.advance()
	check(not ui.dialogue_box.visible and not paused, "box closes and the game resumes")

	# Typewriter: the first continue finishes the line, the next moves on.
	ui.dialogue_box.chars_per_second = 10.0
	m.start_dialogue(&"tam_idle")
	check(ui.dialogue_box.is_typing(), "typing")
	ui.dialogue_box.advance()
	check(not ui.dialogue_box.is_typing() and m.is_in_dialogue(), "first continue finishes the typing")
	ui.dialogue_box.advance()
	check(not m.is_in_dialogue(), "second continue ends it")

	root.remove_child(ui)
	ui.free()
	free_manager(m)
