class_name DialogueBox
extends Control
## The conversation panel along the bottom of the screen: speaker name, the
## line typed out, and numbered choices with a hint of where each one leans.
##
## Space, Enter, E or a click continues (or finishes the typing first);
## 1 to 9 or a click picks a choice. Locked choices show greyed with a reason.

signal closed

## Characters per second for the typewriter; 0 shows lines at once.
@export var chars_per_second := 70.0

var runner: DialogueRunner

var _panel: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _continue_label: Label
var _typing := 0.0
var _choice_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = QuestUiStyle.get_theme()
	_build()
	hide()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -460
	_panel.offset_right = 460
	_panel.offset_bottom = -28
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(920, 170)
	_panel.add_theme_stylebox_override("panel", QuestUiStyle.panel_style(QuestUiStyle.PANEL, QuestUiStyle.GOLD, 2, 8))
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	_name_label = Label.new()
	_name_label.name = "Speaker"
	_name_label.add_theme_font_override("font", QuestUiStyle.serif_font())
	_name_label.add_theme_font_size_override("font_size", 24)
	box.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(880, 52)
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.add_theme_constant_override("separation", 6)
	box.add_child(_choices)

	_continue_label = Label.new()
	_continue_label.text = "Space to continue"
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.add_theme_font_size_override("font_size", 14)
	_continue_label.add_theme_color_override("font_color", QuestUiStyle.MUTED)
	box.add_child(_continue_label)


func open(p_runner: DialogueRunner) -> void:
	if runner and runner.line_changed.is_connected(_refresh):
		runner.line_changed.disconnect(_refresh)
		runner.finished.disconnect(_on_finished)
	runner = p_runner
	runner.line_changed.connect(_refresh)
	runner.finished.connect(_on_finished)
	show()
	if runner.line != null:
		_refresh()


func is_open() -> bool:
	return visible and runner != null


func is_typing() -> bool:
	return _text.visible_ratio < 1.0


## Continue: finishes the typing, or moves past a line without choices.
func advance() -> void:
	if runner == null:
		return
	if is_typing():
		_text.visible_ratio = 1.0
		_show_choices()
		return
	if not runner.has_choices():
		runner.advance()


## Picks the choice with this index (0-based) if it is on screen and enabled.
func pick(index: int) -> bool:
	if runner == null or is_typing() or index >= _choice_buttons.size():
		return false
	return runner.choose(index)


## The speaker name and text currently shown (for tests and screenshots).
func get_shown() -> Dictionary:
	var choice_texts: Array[String] = []
	for b in _choice_buttons:
		choice_texts.append(b.text)
	return {"speaker": _name_label.text, "text": _text.text, "choices": choice_texts}


func _process(delta: float) -> void:
	if not visible or chars_per_second <= 0.0 or not is_typing():
		return
	_typing += delta * chars_per_second
	var total := maxi(_text.get_total_character_count(), 1)
	_text.visible_characters = int(_typing)
	if _typing >= total:
		_text.visible_ratio = 1.0
		_show_choices()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_9:
			pick(key - KEY_1)
			get_viewport().set_input_as_handled()
		elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			advance()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		advance()
		get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()


func _refresh() -> void:
	var view := runner.get_view()
	if view.is_empty():
		return
	var speaker: String = view["speaker"]
	_name_label.text = speaker
	_name_label.visible = not speaker.is_empty()
	_name_label.add_theme_color_override("font_color", view["speaker_color"])
	# Narration is a softer colour than speech.
	var narration: bool = speaker.is_empty()
	_text.add_theme_color_override("default_color", QuestUiStyle.MUTED.lightened(0.25) if narration else QuestUiStyle.PARCHMENT)
	_text.text = view["text"]
	_clear_choices()
	if chars_per_second > 0.0:
		_typing = 0.0
		_text.visible_characters = 0
		_continue_label.hide()
	else:
		_text.visible_ratio = 1.0
		_show_choices()


func _show_choices() -> void:
	if runner == null or not _choice_buttons.is_empty():
		_continue_label.visible = runner != null and not runner.has_choices()
		return
	var view := runner.get_view()
	var choices: Array = view.get("choices", [])
	_continue_label.visible = choices.is_empty()
	for i in choices.size():
		var c: Dictionary = choices[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%d.  %s" % [i + 1, c["text"]]
		button.disabled = not c["enabled"]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(i))
		row.add_child(button)
		var hint: String = c["locked_text"] if not c["enabled"] else c["hint"]
		if not hint.is_empty():
			var label := Label.new()
			label.text = "(%s)" % hint if not c["enabled"] else hint
			label.add_theme_font_size_override("font_size", 15)
			label.add_theme_color_override("font_color", QuestUiStyle.MUTED if not c["enabled"] else QuestUiStyle.lean_color(hint))
			row.add_child(label)
		_choices.add_child(row)
		_choice_buttons.append(button)


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_choice_buttons.clear()


func _on_finished(_id: StringName) -> void:
	# A choice can end this talk and start the next before this runs.
	if runner == null or not runner.is_finished:
		return
	if runner.line_changed.is_connected(_refresh):
		runner.line_changed.disconnect(_refresh)
		runner.finished.disconnect(_on_finished)
	runner = null
	_clear_choices()
	hide()
	closed.emit()
