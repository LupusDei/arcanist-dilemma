class_name QuestNpc
extends Area3D
## Makes the parent (an NPC body or model) talkable. When the player is in
## range a prompt floats above it, and a gold "!" shows while it has a quest
## conversation waiting. Pressing interact plays its dialogue.
##
## Interact is the "interact" input action when project.godot has one, else E.

@export var npc_id: StringName
@export var interact_radius := 2.6
@export var prompt_height := 2.3
@export var verb := "Talk"

var player_in_range := false

var _manager: QuestManager
var _prompt: Label3D
var _marker: Label3D


func _ready() -> void:
	# Keeps the prompt in sync while dialogue pauses the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	shape.shape = sphere
	add_child(shape)
	_prompt = _make_label(prompt_height, 40, Color(0.93, 0.87, 0.74))
	_prompt.visible = false
	_marker = _make_label(prompt_height + 0.45, 96, Color(1.0, 0.85, 0.5))
	_marker.text = "!"
	_marker.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	var manager := _get_manager()
	if manager == null:
		return
	var dialogue := manager.pick_dialogue(npc_id)
	var talking := manager.is_in_dialogue()
	_marker.visible = dialogue != null and dialogue.priority > 0 and not talking
	_prompt.visible = player_in_range and dialogue != null and not talking
	if _prompt.visible:
		_prompt.text = "[%s] %s to %s" % [_interact_key_name(), verb, manager.speaker_name(npc_id)]


func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range or not _is_interact(event):
		return
	var manager := _get_manager()
	if manager and not manager.is_in_dialogue() and manager.talk_to(npc_id):
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = false


static func _is_interact(event: InputEvent) -> bool:
	if InputMap.has_action(&"interact"):
		return event.is_action_pressed(&"interact")
	return event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_E


static func _interact_key_name() -> String:
	if InputMap.has_action(&"interact"):
		for e in InputMap.action_get_events(&"interact"):
			if e is InputEventKey:
				return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return "E"


func _get_manager() -> QuestManager:
	if _manager == null:
		_manager = QuestManager.find(get_tree())
	return _manager


func _make_label(height: float, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.005
	label.font_size = font_size
	label.outline_size = 10
	label.modulate = color
	label.position.y = height
	add_child(label)
	return label
