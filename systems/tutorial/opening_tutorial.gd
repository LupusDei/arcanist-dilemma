class_name OpeningTutorial
extends Node
## Teaches the game inside the prologue's first scenes, one thing at a time,
## at the moment the story needs it:
##   waking up       move and look
##   Ma's chores     Nudge the spoon (2), Spark the stove (left click)
##   Tam             talk (E), then Jolt the jar on the fence post (3)
##   Rook            choices move your alignment
##   the barley      fight: Spark, Nudge when they're close, Dodge when hit,
##                   Jolt to stun, drink a draught when low
##   after           pick up loot, open the bag (I), spend points on level-up (C)
## Each lesson is a HintCard that turns green when the player does it, and is
## remembered in the save (story flag "tutorial_<id>"), so it never repeats.
## The chores light up (ChoreTarget.active) only when the story reaches them,
## and Tam reacts out loud to each trick.
##
## MillbrookStory creates this and calls setup() with the props it placed.

const MOVE_DISTANCE := 4.0
const NEAR_YARD := 14.0
const NEAR_BARLEY := 16.0
const HOUND_CLOSE := 3.5

var spoon: ChoreTarget
var stove: ChoreTarget
var jar: ChoreTarget
var tam: Node3D
var barley_center := Vector3.ZERO
var yard_center := Vector3.ZERO
var card: HintCard
## Hints in the order they were shown (tests read it).
var shown: Array[StringName] = []

var _quests: QuestManager
var _player: Node3D
var _caster: SpellCaster
var _health: HealthComponent
var _start_position := Vector3.INF
var _hurt_in_fight := false
var _spark_hits := 0
var _picked_item := false
var _alignment_moved := false
var _choice_timer := 0.0
var _barley_beacon: Node3D
var _hound_loot := false
var _intro_layer: CanvasLayer


func setup(p_spoon: ChoreTarget, p_stove: ChoreTarget, p_jar: ChoreTarget, p_tam: Node3D, p_yard: Vector3, p_barley: Vector3) -> void:
	spoon = p_spoon
	stove = p_stove
	jar = p_jar
	tam = p_tam
	yard_center = p_yard
	barley_center = p_barley


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = HintCard.new()
	card.name = "HintCard"
	add_child(card)
	_quests = QuestManager.find(get_tree())
	if _quests != null:
		_quests.alignment_changed.connect(_on_alignment_changed)
		_quests.state_loaded.connect(_sync_chores)
		_quests.quest_stage_changed.connect(func(_q: StringName, _s: StringName) -> void: _sync_chores())
	for target in [spoon, stove, jar]:
		if target != null:
			target.done.connect(_on_chore_done.bind(target))
			target.wrong_spell.connect(_on_wrong_spell.bind(target))
	var items := get_node_or_null(^"/root/Items")
	if items != null:
		items.item_picked_up.connect(func(_item: Variant) -> void: _picked_item = true)
	_bind_player.call_deferred()
	_sync_chores.call_deferred()
	_build_barley_beacon.call_deferred()


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	_start_position = _player.global_position
	_caster = _player.get_node_or_null(^"SpellCaster") as SpellCaster
	_health = _player.get_node_or_null(^"HealthComponent") as HealthComponent
	if _health != null:
		_health.damaged.connect(func(_hit: Hit, amount: float) -> void:
			if amount > 0.0 and _stage() == &"wolves":
				_hurt_in_fight = true)
	if _player.has_signal(&"dodged"):
		_player.dodged.connect(func() -> void: _finish(&"dodge"))
	if _caster != null:
		_caster.spell_cast.connect(_on_spell_cast)
	get_tree().node_added.connect(_on_node_added)
	if is_new_game():
		_play_intro()


func is_new_game() -> bool:
	return _stage() == &"chores" and not seen(&"move") and spoon != null and not spoon.is_done and not stove.is_done


# --- the lessons ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _quests == null or _player == null:
		return
	if card.is_showing() and _is_finished(card.hint_id):
		_finish(card.hint_id)
		return
	if _quests.is_in_dialogue() or get_tree().paused:
		if card.is_showing():
			card.dismiss()
		return
	if _choice_timer > 0.0:
		_choice_timer -= delta
	var want := _pick()
	if want != card.hint_id:
		if want == &"":
			card.dismiss()
		elif not card._completing:
			_show(want)
	_update_barley_beacon()


## The lesson that fits this moment, or none.
func _pick() -> StringName:
	match _stage():
		&"chores":
			if not seen(&"move"):
				return &"move"
			if _distance_to(yard_center) > NEAR_YARD:
				return &"" if seen(&"spoon") else &"to_yard"
			if not spoon.is_done:
				return &"spoon"
			if not stove.is_done:
				return &"stove"
		&"show_tam":
			if not seen(&"talk"):
				return &"talk"
		&"jar":
			if not jar.is_done:
				return &"jolt"
		&"bully", &"wolves_start":
			if _alignment_moved and _choice_timer > 0.0:
				return &"choice"
		&"wolves":
			return _pick_fight()
	if _alignment_moved and _choice_timer > 0.0:
		return &"choice"
	if not seen(&"loot") and _hound_loot and not _picked_item:
		return &"loot"
	if _picked_item and not seen(&"bag"):
		return &"bag"
	if _unspent_points() > 0 and not seen(&"points") and not _fighting():
		return &"points"
	return &""


func _pick_fight() -> StringName:
	var hounds := _hounds()
	if hounds.is_empty():
		return &""
	if _distance_to(barley_center) > NEAR_BARLEY and not _fighting():
		return &"to_barley"
	if _health != null and _health.health < _health.max_health * 0.4 and _potions() > 0 and not seen(&"heal"):
		return &"heal"
	if _hurt_in_fight and not seen(&"dodge"):
		return &"dodge"
	if not seen(&"fight"):
		return &"fight"
	if not seen(&"nudge_fight") and _nearest_hound(hounds) < HOUND_CLOSE:
		return &"nudge_fight"
	if seen(&"nudge_fight") and not seen(&"jolt_fight"):
		return &"jolt_fight"
	if card.hint_id == &"nudge_fight":
		return &"nudge_fight"
	return &""


func _show(id: StringName) -> void:
	var lesson := lesson_for(id)
	if lesson.is_empty():
		return
	card.show_hint(id, lesson["title"], lesson["text"], lesson.get("keys", []), _slot_for(lesson.get("spell", &"")))
	if not shown.has(id):
		shown.append(id)
	if id == &"move" or id == &"to_yard":
		_set_chore_beacons()


## The title, text, keys and spell of a lesson.
static func lesson_for(id: StringName) -> Dictionary:
	match id:
		&"move":
			return {"title": "Ma's chores", "keys": ["W", "A", "S", "D"],
				"text": "Walk with W A S D and look around with the mouse. Ma left the chores in the yard: follow the gold arrows."}
		&"to_yard":
			return {"title": "Back to the yard", "keys": [],
				"text": "The chores are in the yard by your front door. Follow the gold arrows."}
		&"spoon":
			return {"title": "Nudge", "keys": ["2"], "spell": &"nudge",
				"text": "A shove of force straight ahead. Walk up to the table, face the spoon and press 2."}
		&"stove":
			return {"title": "Spark", "keys": ["Left click"], "spell": &"spark",
				"text": "Your finger spark. It's free and never runs out. Put the crosshair on the stove and click."}
		&"talk":
			return {"title": "Talk", "keys": ["E"],
				"text": "A gold ! means someone has something for you. Walk up to Tam and press E."}
		&"jolt":
			return {"title": "Jolt", "keys": ["3"], "spell": &"jolt",
				"text": "A shock that leaps to whatever you aim at and stuns it. Aim at the jar on the fence post and press 3."}
		&"choice":
			return {"title": "Your choices shape you", "keys": [],
				"text": "What you choose moves you Lawful or Chaotic, Good or Evil. People remember, and the story bends with it."}
		&"to_barley":
			return {"title": "Wolves in the barley", "keys": [],
				"text": "Farmer Hollis's field is past the houses. Follow the gold arrow, and get ready."}
		&"fight":
			return {"title": "Spark them", "keys": ["Left click"], "spell": &"spark",
				"text": "Spark costs nothing. Keep the crosshair on a wolf and keep clicking. Numbers show every hit."}
		&"nudge_fight":
			return {"title": "Too close!", "keys": ["2"], "spell": &"nudge",
				"text": "Nudge shoves every wolf in front of you away and knocks them off their feet."}
		&"dodge":
			return {"title": "Dodge", "keys": ["Shift"],
				"text": "Dash out of the way. Nothing can hurt you in the middle of a dodge."}
		&"jolt_fight":
			return {"title": "Stun one", "keys": ["3"], "spell": &"jolt",
				"text": "Jolt the wolf that's on you. While it's stunned it can't bite, so finish it with sparks."}
		&"heal":
			return {"title": "You're hurt", "keys": ["Q"],
				"text": "Drink a healing draught from your bag."}
		&"loot":
			return {"title": "Loot", "keys": [],
				"text": "The wolves dropped something. Walk over it to pick it up."}
		&"bag":
			return {"title": "Your bag", "keys": ["I"],
				"text": "Open your bag to see what you found and wear anything better."}
		&"points":
			return {"title": "You grew stronger", "keys": ["C"],
				"text": "Each level gives you attribute points. Open your character sheet and spend them."}
	return {}


func _is_finished(id: StringName) -> bool:
	match id:
		&"move":
			return _start_position != Vector3.INF and _flat_distance(_player.global_position, _start_position) > MOVE_DISTANCE
		&"to_yard":
			return _distance_to(yard_center) <= NEAR_YARD
		&"spoon":
			return spoon.is_done
		&"stove":
			return stove.is_done
		&"talk":
			return _stage() != &"show_tam"
		&"jolt":
			return jar.is_done
		&"choice":
			return _choice_timer <= 0.0
		&"to_barley":
			return _distance_to(barley_center) <= NEAR_BARLEY or _fighting()
		&"fight":
			return _spark_hits >= 3 or _hounds().size() < 3
		&"heal":
			return _health.health >= _health.max_health * 0.6
		&"loot", &"bag":
			return _picked_item if id == &"loot" else _bag_open()
		&"points":
			return _unspent_points() == 0 or _sheet_open()
		&"nudge_fight", &"dodge", &"jolt_fight":
			return seen(id) or _hounds().is_empty()
	return false


## Marks a lesson learned and checks it off on the card.
func _finish(id: StringName) -> void:
	if id.is_empty():
		return
	if not seen(id):
		_quests.story.set_flag(StringName("tutorial_%s" % id), true)
	if card.hint_id == id:
		card.complete()


func seen(id: StringName) -> bool:
	return _quests != null and _quests.story.is_set(StringName("tutorial_%s" % id))


func _on_spell_cast(spell: SpellData) -> void:
	if spell == null or _stage() != &"wolves":
		return
	match spell.id:
		&"nudge":
			if card.hint_id == &"nudge_fight" or _nearest_hound(_hounds()) < HOUND_CLOSE * 1.5:
				_finish(&"nudge_fight")
		&"jolt":
			_finish(&"jolt_fight")


func _on_alignment_changed(_law: float, _good: float, source: String) -> void:
	if source in ["reset", "load"] or seen(&"choice"):
		return
	_alignment_moved = true
	_choice_timer = 7.0
	_quests.story.set_flag(&"tutorial_choice", true)


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		(node as Enemy).died.connect(func(_e: Enemy, _xp: int, loot: Array) -> void:
			if not loot.is_empty():
				_hound_loot = true)
	var health := node as HealthComponent
	if health != null and _stage() == &"wolves":
		health.damaged.connect(func(hit: Hit, _amount: float) -> void:
			if hit != null and hit.spell != null and hit.spell.id == &"spark" and health.team == &"enemy":
				_spark_hits += 1)


# --- the chores ----------------------------------------------------------------

## Lights up the chores the story has reached; shows done ones as done.
func _sync_chores() -> void:
	if _quests == null or spoon == null:
		return
	var stage := _stage()
	var progress := _quests.get_progress(&"prologue")
	var past_chores := progress != null and (progress.state != &"active" or stage != &"chores")
	for pair in [[spoon, &"spoon"], [stove, &"stove"]]:
		var target: ChoreTarget = pair[0]
		var done_already: bool = past_chores or (progress != null and progress.is_objective_done(pair[1]))
		if done_already:
			target.set_done_quietly()
		else:
			target.active = stage == &"chores"
	var jar_past := progress != null and (progress.state != &"active" or stage not in [&"chores", &"show_tam", &"jar"])
	if jar_past:
		jar.set_done_quietly()
	else:
		jar.active = stage == &"jar"


func _set_chore_beacons() -> void:
	for target in [spoon, stove]:
		if not target.is_done:
			target.active = true


func _on_chore_done(target: ChoreTarget) -> void:
	var line := ""
	match target.kind:
		ChoreTarget.Kind.SPOON:
			line = "Ha! Right off the table!"
		ChoreTarget.Kind.STOVE:
			line = "Ma's going to think the stove lit itself."
		ChoreTarget.Kind.JAR:
			line = "AGAIN! Do it AGAIN!"
	say(tam, line)


func _on_wrong_spell(spell: SpellData, target: ChoreTarget) -> void:
	var line := ""
	match target.kind:
		ChoreTarget.Kind.SPOON:
			line = "It wobbled! Shove it. The pushy one, 2."
		ChoreTarget.Kind.STOVE:
			line = "It needs a spark. Left click!"
		ChoreTarget.Kind.JAR:
			line = "The zappy one! 3!"
	if spell != null:
		say(tam, line)


## A speech bubble over someone's head for a few seconds.
func say(who: Node3D, text: String, seconds := 3.0) -> Label3D:
	if who == null or not is_instance_valid(who) or text.is_empty():
		return null
	var old := who.get_node_or_null(^"SpeechBubble")
	if old != null:
		old.free()
	var bubble := Label3D.new()
	bubble.name = "SpeechBubble"
	bubble.text = text
	bubble.font_size = 44
	bubble.outline_size = 12
	bubble.modulate = Color(1, 1, 1)
	bubble.outline_modulate = Color(0.1, 0.07, 0.05, 0.95)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.fixed_size = true
	bubble.no_depth_test = true
	bubble.pixel_size = 0.0006
	bubble.position = Vector3(0, 2.75, 0)
	bubble.width = 700
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(bubble)
	var tween := bubble.create_tween()
	bubble.scale = Vector3.ONE * 0.3
	tween.tween_property(bubble, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(seconds)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.4)
	tween.tween_callback(bubble.queue_free)
	return bubble


# --- the barley ----------------------------------------------------------------

func _build_barley_beacon() -> void:
	_barley_beacon = Node3D.new()
	_barley_beacon.name = "BarleyBeacon"
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.6
	cone.bottom_radius = 0.0
	cone.height = 1.2
	cone.radial_segments = 4
	arrow.mesh = cone
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.82, 0.3)
	gold.no_depth_test = true
	arrow.material_override = gold
	_barley_beacon.add_child(arrow)
	var text := Label3D.new()
	text.text = "Wolves"
	text.font_size = 48
	text.outline_size = 12
	text.modulate = Color(1.0, 0.9, 0.6)
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.fixed_size = true
	text.pixel_size = 0.0008
	text.position = Vector3(0, 1.1, 0)
	_barley_beacon.add_child(text)
	_barley_beacon.visible = false
	var parent := get_parent()
	parent.add_child(_barley_beacon)
	_barley_beacon.global_position = barley_center + Vector3(0, 5.0, 0)


func _update_barley_beacon() -> void:
	if _barley_beacon == null:
		return
	var show := _stage() == &"wolves" and not _fighting() and not _hounds().is_empty()
	_barley_beacon.visible = show
	if show:
		_barley_beacon.rotation.y += get_process_delta_time() * 2.0
		_barley_beacon.position.y = barley_center.y + 5.0 + 0.3 * sin(Time.get_ticks_msec() * 0.003)


# --- the opening ---------------------------------------------------------------

## Fades in from black over the village with the prologue's name.
func _play_intro() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 20
	add_child(_intro_layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(black)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(box)
	var s := GameFeedback.ui_scale(self)
	for line in [["Prologue", 26, Color(0.8, 0.72, 0.55)], ["Tricks", 72, Color(1.0, 0.86, 0.5)], ["Millbrook, the morning after the harvest fair", 24, Color(0.93, 0.89, 0.8)]]:
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", HintCard._serif())
		label.add_theme_font_size_override("font_size", int(line[1] * s))
		label.add_theme_color_override("font_color", line[2])
		box.add_child(label)
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(black, "color:a", 0.0, 1.4)
	tween.tween_property(box, "modulate:a", 0.0, 0.8)
	tween.tween_callback(_intro_layer.queue_free)


# --- reading the world ---------------------------------------------------------

func _stage() -> StringName:
	return _quests.get_quest_stage(&"prologue") if _quests != null else &""


func _hounds() -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Enemy and node.has_meta(&"barley_wolf"):
			found.append(node)
	return found


func _nearest_hound(hounds: Array[Node]) -> float:
	var best := INF
	for hound in hounds:
		best = minf(best, _flat_distance((hound as Node3D).global_position, _player.global_position))
	return best


func _fighting() -> bool:
	for hound in _hounds():
		if hound.get(&"state") in [Enemy.State.AGGRO, Enemy.State.CHASE, Enemy.State.ATTACK] or _flat_distance((hound as Node3D).global_position, _player.global_position) < 12.0:
			return true
	return false


func _distance_to(point: Vector3) -> float:
	return _flat_distance(_player.global_position, point)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _potions() -> int:
	var items := get_node_or_null(^"/root/Items")
	if items == null:
		return 0
	var count := 0
	for item in items.inventory.items():
		var base: Variant = item.get_base()
		if base != null and base.kind == ItemDefs.Kind.POTION and base.heal_amount > 0.0:
			count += item.quantity
	return count


func _unspent_points() -> int:
	var progression := get_node_or_null(^"/root/Progression")
	return progression.progression.unspent_attribute_points() if progression != null else 0


func _bag_open() -> bool:
	for screen in get_tree().root.find_children("*", "InventoryScreen", true, false):
		if (screen as Control).is_visible_in_tree():
			return true
	return false


func _sheet_open() -> bool:
	for sheet in get_tree().root.find_children("*", "CharacterSheet", true, false):
		if (sheet as Control).is_visible_in_tree():
			return true
	return false


## The HUD spell slot that casts this spell, to pulse while its lesson shows.
func _slot_for(spell_id: StringName) -> Control:
	if spell_id.is_empty():
		return null
	for hud in get_tree().root.find_children("*", "GameHud", true, false):
		var slots: Array = hud.get(&"slots")
		for slot in slots:
			var spell: Variant = slot.get(&"spell")
			if spell is SpellData and spell.id == spell_id:
				return slot
	return null
