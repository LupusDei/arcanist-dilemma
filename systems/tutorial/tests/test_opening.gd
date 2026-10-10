extends SceneTree
## Plays the opening in the real world scene with real spells and checks that
## each lesson shows at the right moment, that only the right trick does each
## chore (with its effect), that the feedback layer answers every action, and
## that the first fight ends in the first level-up.
## Run: godot --headless --path . --fixed-fps 60 --script res://systems/tutorial/tests/test_opening.gd

var _failures: PackedStringArray = []
var _player: Player
var _caster: SpellCaster
var _quests: QuestManager
var _tutorial: OpeningTutorial
var _feedback: GameFeedback


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_quests = root.get_node("Quests")
	var progression: Node = root.get_node("Progression")
	UiSession.character = {"name": "Ash Test", "sex": 0, "face": 1, "skin": 1, "hair": 1, "hair_color": 1, "eyes": 1, "build": 0}
	change_scene_to_file("res://scenes/world/world.tscn")
	await _frames(60)
	var world := current_scene
	_player = world.get_node("Player")
	_caster = _player.get_node("SpellCaster")
	_tutorial = world.get_node("MillbrookStory/OpeningTutorial")
	_feedback = world.find_children("*", "GameFeedback", true, false)[0]
	_check(_tutorial != null and _feedback != null, "the opening and the feedback layer are in the world")
	_check(_quests.get_quest_stage(&"prologue") == &"chores", "a new game starts on the chores")
	_check(_tutorial.is_new_game(), "the opening knows it's a new game")
	var spoon := _tutorial.spoon
	var stove := _tutorial.stove
	var jar := _tutorial.jar
	print("     spawn %s, yard %s (%.1f m), barley %s" % [_player.global_position, _tutorial.yard_center, _flat(_player.global_position, _tutorial.yard_center), _tutorial.barley_center])

	# --- Waking up: move ---
	await _frames(10)
	await _await_hint(&"move")
	_check(_tutorial.card.hint_id == &"move", "the first lesson is how to move (%s)" % _tutorial.card.hint_id)
	_check(spoon.active and stove.active and not jar.active, "the spoon and stove light up, the jar waits")
	_check(spoon.beacon.visible and stove.beacon.visible, "gold arrows mark the chores")
	_check(spoon.health.is_in_group(HealthComponent.GROUP) and not jar.health.is_in_group(HealthComponent.GROUP), "only active chores can be hit")
	_walk_to(_tutorial.yard_center + Vector3(0, 0, 0))
	await _frames(20)
	_check(_tutorial.seen(&"move"), "walking over checks off the move lesson")

	# --- Nudge the spoon ---
	await _frames(90)
	await _await_hint(&"spoon")
	_check(_tutorial.card.hint_id == &"spoon", "next: Nudge the spoon (%s)" % _tutorial.card.hint_id)
	_check(_tutorial.card.highlight != null, "the Nudge slot on the spell bar pulses")
	_stand_facing(spoon.global_position, 2.0)
	await _frames(5)
	_cast(&"spark", spoon.health.get_target_position())
	await _frames(30)
	_check(not spoon.is_done, "a spark doesn't move the spoon")
	_check(_tam_says() != "", "Tam tells you which trick (\"%s\")" % _tam_says())
	await _frames(int(60 * 2.5))  # Spark's cooldown is short, Nudge's is 2 s; just let things settle.
	var spoon_before: Vector3 = (spoon.get_node("Spoon") as Node3D).global_position
	_cast(&"nudge", spoon.health.get_target_position())
	await _frames(90)
	_check(spoon.is_done, "Nudge moves the spoon")
	var spoon_after: Vector3 = (spoon.get_node("Spoon") as Node3D).global_position
	_check(spoon_after.distance_to(spoon_before) > 1.5 and spoon_after.y < spoon_before.y - 0.5, "the spoon flies off the table (%.1f m)" % spoon_after.distance_to(spoon_before))
	_check(_quests.get_progress(&"prologue").is_objective_done(&"spoon"), "the quest hears the spoon")
	_check(_feedback.toasts_shown.any(func(t: String) -> bool: return "Nudge the spoon" in t and "✓" in t), "a check toast confirms the chore")
	_check(not spoon.beacon.visible and not spoon.health.is_in_group(HealthComponent.GROUP), "the spoon's arrow goes away")

	# --- Spark the stove ---
	await _frames(90)
	await _await_hint(&"stove")
	_check(_tutorial.card.hint_id == &"stove", "next: Spark the stove (%s)" % _tutorial.card.hint_id)
	_stand_facing(stove.health.get_target_position(), 4.0)
	await _frames(5)
	_cast(&"spark", stove.health.get_target_position())
	await _frames(40)
	_check(stove.is_done, "a spark lights the stove")
	_check(stove.get_node("Stove/Fire").visible, "fire and smoke show in the stove")
	await _frames(5)
	_check(_quests.get_quest_stage(&"prologue") == &"show_tam", "chores done -> show Tam")
	_check(progression.progression.xp == 40, "the chores give 40 XP (%d)" % progression.progression.xp)
	_check(_feedback.popups_shown.has("+40 XP"), "a +40 XP popup shows")

	# --- Tam: talk, then Jolt the jar ---
	await _frames(90)
	await _await_hint(&"talk")
	_check(_tutorial.card.hint_id == &"talk", "next: talk to Tam (%s)" % _tutorial.card.hint_id)
	_check(_quests.talk_to(&"tam"), "Tam has something to say")
	_play_dialogue()
	await _frames(90)
	_check(_quests.get_quest_stage(&"prologue") == &"jar", "Tam asks for the jar")
	_check(jar.active and jar.beacon.visible, "the jar lights up")
	await _await_hint(&"jolt")
	_check(_tutorial.card.hint_id == &"jolt", "next: Jolt the jar (%s)" % _tutorial.card.hint_id)
	_stand_facing(jar.health.get_target_position(), 6.0)
	await _frames(5)
	_cast(&"jolt", jar.health.get_target_position())
	await _frames(30)
	_check(jar.is_done, "Jolt makes the jar leap")
	_check(_quests.is_in_dialogue() and _quests.active_dialogue.dialogue.id == &"tam_promise", "Tam's promise follows")
	_play_dialogue()
	await _frames(10)
	_check(_quests.get_quest_stage(&"prologue") == &"bully", "-> Rook at the well")

	# --- Rook: a choice that moves alignment ---
	_check(_quests.talk_to(&"rook"), "Rook is waiting")
	_play_dialogue([1])
	await _frames(20)
	await _await_hint(&"choice")
	_check(_tutorial.card.hint_id == &"choice", "after the choice: choices shape you (%s)" % _tutorial.card.hint_id)
	_check(_quests.talk_to(&"farmer_hollis"), "Hollis has a job")
	_play_dialogue()
	await _frames(30)
	_check(_quests.get_quest_stage(&"prologue") == &"wolves", "-> wolves in the barley")

	# --- The first fight ---
	var hounds := _tutorial._hounds()
	_check(hounds.size() == 3, "three wolves wait in the barley")
	if _flat(_player.global_position, _tutorial.barley_center) > OpeningTutorial.NEAR_BARLEY:
		await _frames(20)
		await _await_hint(&"to_barley")
		_check(_tutorial.card.hint_id == &"to_barley", "far away: head for the barley (%s)" % _tutorial.card.hint_id)
	_stand_facing(_tutorial.barley_center, 12.0)
	await _frames(90)
	await _await_hint(&"fight")
	_check(_tutorial.card.hint_id == &"fight", "in sight of the wolves: Spark them (%s)" % _tutorial.card.hint_id)
	var health: HealthComponent = _player.get_node("HealthComponent")
	var guard := 0
	while not _tutorial._hounds().is_empty() and guard < 60 * 60:
		guard += 1
		health.heal(1000.0)  # this test is about the lessons, not survival
		var target := _nearest(_tutorial._hounds())
		if target != null:
			var aim: Vector3 = target.get_node("HealthComponent").get_target_position()
			_stand_facing(aim, minf(_flat(_player.global_position, aim), 8.0))
			if _flat(_player.global_position, aim) < 3.0 and _caster.get_cooldown_remaining(_spell(&"nudge")) <= 0.0:
				_cast(&"nudge", aim)
			elif _tutorial.seen(&"nudge_fight") and _caster.get_cooldown_remaining(_spell(&"jolt")) <= 0.0:
				_cast(&"jolt", aim)
			else:
				_cast(&"spark", aim)
		await _frames(6)
	_check(_tutorial._hounds().is_empty(), "the wolves are dealt with (%d frames)" % (guard * 6))
	await _frames(30)
	print("     lessons shown: %s" % [_tutorial.shown])
	_check(_tutorial.shown.has(&"fight"), "the fight lesson showed")
	_check(_feedback.popups_shown.any(func(t: String) -> bool: return t.is_valid_int()), "damage numbers show on hits")
	_check(_feedback.popups_shown.any(func(t: String) -> bool: return t.begins_with("+") and t.ends_with(" XP") and t != "+40 XP"), "kills show XP")
	_check(_quests.get_quest_stage(&"prologue") == &"wolves_report", "-> report to Hollis")
	_check(progression.progression.level == 2, "the first fight ends in level 2 (xp %d, level %d)" % [progression.progression.xp, progression.progression.level])
	if not _tutorial.shown.has(&"loot") and _tutorial._hound_loot:
		print("     (loot dropped; the loot lesson waits for the fight to end)")

	# --- After the fight: spend points ---
	var waited := 0
	while not _tutorial.card.hint_id in [&"points", &"loot", &"bag"] and waited < 600:
		await _frames(10)
		waited += 10
	_check(_tutorial.card.hint_id in [&"points", &"loot", &"bag"], "the loot, bag and character sheet lessons follow the fight (%s)" % _tutorial.card.hint_id)

	# --- Lessons are remembered ---
	for id in [&"move", &"spoon", &"stove", &"talk", &"jolt", &"choice", &"fight"]:
		_check(_tutorial.seen(id), "the %s lesson is saved as learned" % id)

	if _failures.is_empty():
		print("OPENING TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


# --- helpers -------------------------------------------------------------------

func _spell(id: StringName) -> SpellData:
	for spell in _caster.get_action_bar() + [_caster.get_cantrip()]:
		if spell != null and spell.id == id:
			return spell
	return null


func _cast(id: StringName, aim: Vector3) -> bool:
	return _caster.cast(_spell(id), aim)


## Puts the player `distance` metres from `at`, on the side they're already on, facing it.
func _stand_facing(at: Vector3, distance: float) -> void:
	var away := _player.global_position - at
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	var spot := at + away.normalized() * distance
	_walk_to(spot)


func _walk_to(spot: Vector3) -> void:
	var terrain: Terrain = current_scene.get_node("Terrain")
	_player.global_position = Vector3(spot.x, terrain.height_at(spot.x, spot.z) + 0.1, spot.z)
	_player.velocity = Vector3.ZERO


func _nearest(nodes: Array[Node]) -> Node3D:
	var best: Node3D
	for node in nodes:
		if best == null or _flat((node as Node3D).global_position, _player.global_position) < _flat(best.global_position, _player.global_position):
			best = node
	return best


func _tam_says() -> String:
	var bubble := _tutorial.tam.get_node_or_null("SpeechBubble") as Label3D
	return bubble.text if bubble != null else ""


func _play_dialogue(picks: Array = []) -> void:
	var guard := 0
	while _quests.active_dialogue != null and guard < 100:
		guard += 1
		var runner := _quests.active_dialogue
		if runner.has_choices():
			runner.choose(picks.pop_front() if not picks.is_empty() else 0)
		else:
			runner.advance()
	paused = false


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Waits until the card shows this lesson (a finished one takes a moment to leave).
func _await_hint(id: StringName, max_frames := 180) -> void:
	var waited := 0
	while _tutorial.card.hint_id != id and waited < max_frames:
		await physics_frame
		waited += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
