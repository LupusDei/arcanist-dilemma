class_name GameUI
extends CanvasLayer
## Everything the player sees in game: HUD, character sheet, talent picker and
## pause menu. Drop res://ui/game_ui.tscn into the game scene once.
##
## Sources: set the three paths, or leave them empty to auto-discover them
## under the node in the "player" group (a node with a health_changed signal,
## one with spell_cast, and one with get_stats or the "progression" group).
## Any role still missing is filled by a UiMockPlayer so the UI always works.
##
## Keys: C character sheet, K talents, Esc closes a panel or opens the pause
## menu. Any open panel pauses the game and frees the mouse.

@export var health_source_path: NodePath
@export var caster_source_path: NodePath
@export var progression_source_path: NodePath
@export var use_mock_when_missing := true

var hud: GameHud
var character_sheet: CharacterSheet
var talent_picker: TalentPicker
var pause_menu: PauseMenu
var mock: UiMockPlayer

var health_source: Object
var caster_source: Object
var progression_source: Object

var _game_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _panels_open := false


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	hud = GameHud.new()
	hud.name = "GameHud"
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	character_sheet = CharacterSheet.new()
	character_sheet.name = "CharacterSheet"
	character_sheet.hide()
	add_child(character_sheet)
	talent_picker = TalentPicker.new()
	talent_picker.name = "TalentPicker"
	talent_picker.hide()
	add_child(talent_picker)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

	hud.character_sheet_requested.connect(open_panel.bind(character_sheet))
	hud.talents_requested.connect(open_panel.bind(talent_picker))
	character_sheet.closed.connect(_sync_pause)
	talent_picker.closed.connect(_sync_pause)
	pause_menu.character_requested.connect(open_panel.bind(character_sheet))
	pause_menu.talents_requested.connect(open_panel.bind(talent_picker))

	_resolve_sources()
	bind_sources(health_source, caster_source, progression_source)


func bind_sources(health: Object, caster: Object, progression: Object) -> void:
	health_source = health
	caster_source = caster
	progression_source = progression
	hud.bind(health, caster, progression)
	character_sheet.bind(progression)
	talent_picker.bind(progression)


func _resolve_sources() -> void:
	health_source = get_node_or_null(health_source_path) if not health_source_path.is_empty() else null
	caster_source = get_node_or_null(caster_source_path) if not caster_source_path.is_empty() else null
	progression_source = get_node_or_null(progression_source_path) if not progression_source_path.is_empty() else null
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if health_source == null:
			health_source = _find_with_signal(player, &"health_changed")
		if caster_source == null:
			caster_source = _find_with_signal(player, &"spell_cast")
	if progression_source == null:
		progression_source = get_tree().get_first_node_in_group("progression")
		if progression_source == null and player:
			progression_source = _find_with_method(player, &"get_stats")
	if not use_mock_when_missing or (health_source and caster_source and progression_source):
		return
	mock = UiMockPlayer.new()
	mock.name = "MockPlayer"
	mock.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mock)
	if health_source == null:
		health_source = mock
	if caster_source == null:
		caster_source = mock
	if progression_source == null:
		progression_source = mock


static func _find_with_signal(root: Node, sig: StringName) -> Node:
	if root.has_signal(sig):
		return root
	for c in root.get_children():
		var found := _find_with_signal(c, sig)
		if found:
			return found
	return null


static func _find_with_method(root: Node, method: StringName) -> Node:
	if root.has_method(method):
		return root
	for c in root.get_children():
		var found := _find_with_method(c, method)
		if found:
			return found
	return null


func open_panel(panel: Control) -> void:
	for p in [character_sheet, talent_picker]:
		if p != panel and p.visible:
			p.hide()
	if pause_menu.visible:
		pause_menu.close()
	panel.call("open")
	_sync_pause()


func toggle_panel(panel: Control) -> void:
	if panel.visible:
		panel.call("close")
	else:
		open_panel(panel)


func any_panel_open() -> bool:
	return character_sheet.visible or talent_picker.visible


## Pauses the game and frees the mouse while a panel is open; restores both
## when the last one closes. The pause menu manages its own pause.
func _sync_pause() -> void:
	var open := any_panel_open()
	if open == _panels_open:
		return
	_panels_open = open
	if open:
		_game_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		get_tree().paused = false
		Input.mouse_mode = _game_mouse_mode


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if pause_menu.visible:
			pause_menu.close()
		elif character_sheet.visible:
			character_sheet.close()
		elif talent_picker.visible:
			talent_picker.close()
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if pause_menu.visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_C:
				toggle_panel(character_sheet)
				get_viewport().set_input_as_handled()
			KEY_K:
				toggle_panel(talent_picker)
				get_viewport().set_input_as_handled()
