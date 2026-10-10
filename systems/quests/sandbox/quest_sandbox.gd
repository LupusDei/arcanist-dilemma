extends Node3D
## Greybox Millbrook for playing the prologue and The Hat and the Warden end
## to end with the real player, spells, wolves, dialogue box and tracker.
## Open res://systems/quests/sandbox/quest_sandbox.tscn and press F6.
##
## Walk up to anyone with a "!" and press E. The chores' props live in the real
## Millbrook (systems/tutorial). Debug keys: G jumps to the next objective, F1
## to F3 count a cast of Spark, Nudge or Jolt and do its chore (stove, spoon, jar), F4 counts a wolf kill, F5 a Warden escort kill,
## F6 saves, F7 loads, F9 starts over.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const QUEST_UI_SCENE := preload("res://ui/dialogue/quest_ui.tscn")
const HOUND_SCENE := preload("res://actors/enemies/types/gloom_hound.tscn")
const SAVE_PATH := "user://quest_sandbox_save.json"

## Where everyone and everything stands. NPC ids, then QuestArea ids.
const NPCS := {
	&"tam": Vector3(-6, 0, -2),
	&"rook": Vector3(10, 0, -4),
	&"farmer_hollis": Vector3(0, 0, -18),
	&"innkeeper": Vector3(17, 0, 13),
	&"old_man": Vector3(13, 0, 15),
	&"home_bed": Vector3(-13, 0, -9),
	&"warden_sergeant": Vector3(-3, 0, 14),
	&"warden_lieutenant": Vector3(15, 0, 10),
	&"children": Vector3(3, 0, 16),
	&"old_mill_floorboards": Vector3(24, 0, -16),
}
const AREAS := {
	&"kitchen": [Vector3(-10, 0, -6), Vector3(7, 4, 7)],
	&"tavern": [Vector3(15, 0, 13), Vector3(9, 4, 9)],
	&"hill_road": [Vector3(-24, 0, 22), Vector3(6, 4, 6)],
	&"village_square": [Vector3(0, 0, 15), Vector3(10, 4, 8)],
	&"barley": [Vector3(0, 0, -26), Vector3(16, 4, 10)],
}
const BUILDINGS := {
	"Home": [Vector3(-10, 0, -7), Vector3(9, 0.2, 9)],
	"Mill Wheel Tavern": [Vector3(15, 0, 13), Vector3(11, 0.2, 11)],
	"Old Mill": [Vector3(24, 0, -16), Vector3(6, 0.2, 6)],
	"Barley": [Vector3(0, 0, -26), Vector3(16, 0.2, 10)],
	"Hill Road": [Vector3(-24, 0, 22), Vector3(6, 0.2, 6)],
	"Square": [Vector3(0, 0, 15), Vector3(10, 0.2, 8)],
}

var quests: QuestManager
var player: Player
var ui: QuestUI

var _npc_nodes: Dictionary = {}
var _debug_label: Label
var _flash: ColorRect
var _hounds: Array[Node] = []


func _ready() -> void:
	quests = QuestManager.find(get_tree())
	if quests == null:
		# Running without the Quests autoload: bring our own.
		quests = QuestManager.new()
		quests.name = "Quests"
		add_child(quests)
	_build_world()
	ui = QUEST_UI_SCENE.instantiate()
	add_child(ui)
	_build_debug_overlay()

	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 1, 4)
	add_child(player)
	var caster := player.get_node_or_null(^"SpellCaster") as SpellCaster
	if caster:
		caster.set_source(TrickSet.new())
		caster.spell_cast.connect(quests.on_spell_cast)

	quests.story_event.connect(_on_story_event)
	quests.quest_stage_changed.connect(_on_stage_changed)
	quests.flag_changed.connect(func(_f, _v, _p) -> void: _sync_npcs())
	quests.state_loaded.connect(_sync_npcs)
	_sync_npcs()


func _process(_delta: float) -> void:
	var a := quests.story.alignment
	var standing := []
	for faction in quests.story.standing:
		standing.append("%s %+d" % [faction, quests.story.standing[faction]])
	var flags := quests.story.flags.keys()
	var recent := flags.slice(maxi(flags.size() - 6, 0))
	_debug_label.text = "Alignment: %s  (law %+.0f, good %+.0f)\nStanding: %s\nFlags: %s\n\nG next objective   F1-F3 cast Spark/Nudge/Jolt   F4 wolf kill   F5 escort kill\nF6 save   F7 load   F9 new game   E talk" % [
		a.archetype_name(), a.law, a.good, ", ".join(standing) if standing else "-", ", ".join(recent)]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or quests.is_in_dialogue():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_G:
			_jump_to_next_objective()
		KEY_F1:
			quests.notify_spell_cast(&"spark")
			quests.notify_event(&"stove_lit")
		KEY_F2:
			quests.notify_spell_cast(&"nudge")
			quests.notify_event(&"spoon_moved")
		KEY_F3:
			quests.notify_spell_cast(&"jolt")
			quests.notify_event(&"jar_jolted")
		KEY_F4:
			quests.notify_killed(&"gloom_hound")
		KEY_F5:
			quests.notify_killed(&"warden_escort")
		KEY_F6:
			quests.save_to_file(SAVE_PATH)
			ui.show_notice("Saved")
		KEY_F7:
			if quests.load_from_file(SAVE_PATH):
				ui.show_notice("Loaded")
		KEY_F9:
			quests.new_game()
			player.position = Vector3(0, 1, 4)
		_:
			return
	get_viewport().set_input_as_handled()


## Teleports the player next to whatever the first unfinished objective points at.
func _jump_to_next_objective() -> void:
	for quest in quests.get_active_quests():
		var progress := quests.get_progress(quest.id)
		var stage := quest.get_stage(progress.stage)
		for objective in stage.objectives:
			if progress.is_objective_done(objective.id):
				continue
			var target := objective.where if objective.where != &"" else objective.target
			var spot: Variant = NPCS.get(target, AREAS.get(target, [null])[0])
			if objective.type == &"kill":
				spot = AREAS[&"barley"][0]
			if spot is Vector3:
				player.global_position = spot + Vector3(0, 1, 2.5)
				player.velocity = Vector3.ZERO
				return


func _on_stage_changed(quest_id: StringName, stage_id: StringName) -> void:
	if quest_id == &"prologue" and stage_id == &"wolves":
		_spawn_hounds()


func _spawn_hounds() -> void:
	for hound in _hounds:
		if is_instance_valid(hound):
			hound.queue_free()
	_hounds.clear()
	for i in 3:
		var hound := HOUND_SCENE.instantiate()
		hound.position = AREAS[&"barley"][0] + Vector3(-4 + i * 4, 0.5, -2)
		hound.set(&"pack_id", 7)
		add_child(hound)
		_hounds.append(hound)


func _on_story_event(event_name: StringName) -> void:
	match event_name:
		&"lightning_strike":
			_flash.color.a = 1.0
			var tween := create_tween()
			tween.tween_property(_flash, "color:a", 0.0, 1.2)
		&"warden_escort_attack":
			ui.show_notice("Hale's escort attacks! (F5 to count each kill)", QuestUiStyle.BAD)


## The old man disappears after the lightning; the Wardens only appear once they arrive.
func _sync_npcs() -> void:
	var s := quests.story
	_set_npc_visible(&"old_man", not s.is_set(&"old_man_struck"))
	_set_npc_visible(&"warden_sergeant", s.is_set(&"had_dream") and not s.is_set(&"prologue_done"))
	_set_npc_visible(&"warden_lieutenant", s.is_set(&"prologue_done"))


func _set_npc_visible(id: StringName, shown: bool) -> void:
	var npc: Node3D = _npc_nodes.get(id)
	if npc == null:
		return
	npc.visible = shown
	var talk := npc.get_node(^"QuestNpc") as QuestNpc
	talk.monitoring = shown
	if not shown:
		talk.player_in_range = false


# --- Greybox -----------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.68, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	_add_box(Vector3(0, -0.5, 0), Vector3(90, 1, 90), Color(0.36, 0.52, 0.28), true)
	for label in BUILDINGS:
		var spec: Array = BUILDINGS[label]
		var color := Color(0.78, 0.7, 0.42) if label == "Barley" else Color(0.55, 0.45, 0.35)
		_add_box(spec[0] + Vector3(0, 0.1, 0), spec[1], color, false)
		_add_sign(label, spec[0] + Vector3(0, 3.2, 0), 64)
	for id in AREAS:
		var area := QuestArea.new()
		area.name = "Area_%s" % id
		area.area_id = id
		area.size = AREAS[id][1]
		area.position = AREAS[id][0]
		add_child(area)
	# Props for the chores and the well.
	_add_box(Vector3(-10, 0.5, -6), Vector3(2, 1, 1.2), Color(0.45, 0.3, 0.2), true)
	_add_box(Vector3(-12, 0.6, -9.5), Vector3(1, 1.2, 1), Color(0.25, 0.25, 0.28), true)
	_add_box(Vector3(10, 0.5, -6), Vector3(1.6, 1, 1.6), Color(0.5, 0.5, 0.55), true)
	for id in NPCS:
		_add_npc(id, NPCS[id])

	var overlay := CanvasLayer.new()
	overlay.layer = 20
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_flash)
	add_child(overlay)


func _add_npc(id: StringName, at: Vector3) -> void:
	var body := Node3D.new()
	body.name = String(id).to_pascal_case()
	body.position = at
	var mesh := MeshInstance3D.new()
	var is_prop := id in [&"home_bed", &"old_mill_floorboards"]
	if is_prop:
		var box := BoxMesh.new()
		box.size = Vector3(2, 0.5, 1.2) if id == &"home_bed" else Vector3(1.6, 0.15, 1.6)
		mesh.mesh = box
		mesh.position.y = box.size.y * 0.5
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.0 if id == &"children" or id == &"tam" else 1.8
		mesh.mesh = capsule
		mesh.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.45, 0.3) if is_prop else quests.speaker_color(id)
	mesh.material_override = material
	body.add_child(mesh)
	if not is_prop:
		var name_label := _add_sign(quests.speaker_name(id), Vector3(0, mesh.position.y * 2 + 0.35, 0), 32, body)
		name_label.pixel_size = 0.006
	var talk := QuestNpc.new()
	talk.name = "QuestNpc"
	talk.npc_id = id
	talk.prompt_height = 1.4 if is_prop else 2.3
	talk.verb = "Use" if is_prop else "Talk"
	body.add_child(talk)
	add_child(body)
	_npc_nodes[id] = body


func _add_box(at: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	if solid:
		var body := StaticBody3D.new()
		body.position = at
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		body.add_child(mesh)
		add_child(body)
	else:
		mesh.position = at
		add_child(mesh)


func _add_sign(text: String, at: Vector3, font_size: int, parent: Node = self) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	parent.add_child(label)
	return label


func _build_debug_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	_debug_label = Label.new()
	_debug_label.position = Vector2(20, 20)
	_debug_label.theme = QuestUiStyle.get_theme()
	_debug_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(_debug_label)
	add_child(layer)
