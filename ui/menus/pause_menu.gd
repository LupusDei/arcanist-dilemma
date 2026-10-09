class_name PauseMenu
extends Control
## Pause menu. Opening it pauses the tree and frees the mouse; closing it
## restores whatever mouse mode the game had.

signal resumed
signal character_requested
signal talents_requested
signal main_menu_requested
signal quit_requested

## Scene loaded by "Main menu". Empty means only the signal is emitted.
@export_file("*.tscn") var main_menu_scene := "res://ui/menus/main_menu.tscn"

var resume_button: Button
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func open() -> void:
	if visible:
		return
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	show()
	resume_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before
	resumed.emit()


func _go_to_main_menu() -> void:
	main_menu_requested.emit()
	if main_menu_scene != "":
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(main_menu_scene)


func _save_game() -> void:
	var session := get_tree().get_first_node_in_group(&"game_session")
	if session != null and session.has_method("save_game"):
		session.save_game()


func _quit() -> void:
	quit_requested.emit()
	get_tree().quit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PANEL, UiTheme.GOLD, 2, 8))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(HSeparator.new())
	resume_button = _button(box, "Resume", close)
	_button(box, "Character  (C)", func(): close(); character_requested.emit())
	_button(box, "Talents  (K)", func(): close(); talents_requested.emit())
	box.add_child(HSeparator.new())
	_button(box, "Save game  (F5)", _save_game)
	_button(box, "Main menu", _go_to_main_menu)
	_button(box, "Quit to desktop", _quit)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BigButton"
	b.text = text
	b.name = text.get_slice(" ", 0).capitalize() + "Button"
	b.pressed.connect(action)
	parent.add_child(b)
	return b
