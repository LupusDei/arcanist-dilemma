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

const WIDTH := 1120.0

var _backdrop: TextureRect
var _frame: VBoxContainer
var _nameplate: PanelContainer
var _panel: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _continue_label: Label
var _marker: _SpeakerMarker
var _typing := 0.0
var _choice_buttons: Array[Button] = []
var _choice_texts: Array[String] = []
var _speaker_id := ""
var _speaker_name := ""
var _speaker_node: Node3D
var _pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = QuestUiStyle.get_theme()
	_build()
	hide()


func _build() -> void:
	# A dark band along the bottom of the screen, so the conversation reads
	# as part of the scene (like a film's subtitles) rather than a floating box.
	_backdrop = TextureRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.anchor_top = 1.0
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.offset_top = -420
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.02, 0.01, 0.03, 0.55), Color(0.02, 0.01, 0.03, 0.85)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	_backdrop.texture = tex
	add_child(_backdrop)

	_marker = _SpeakerMarker.new()
	_marker.name = "SpeakerMarker"
	_marker.visible = false
	add_child(_marker)

	_frame = VBoxContainer.new()
	_frame.name = "Frame"
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 1.0
	_frame.anchor_bottom = 1.0
	_frame.offset_left = -WIDTH * 0.5
	_frame.offset_right = WIDTH * 0.5
	_frame.offset_bottom = -36
	_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_frame.add_theme_constant_override("separation", -2)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_nameplate = PanelContainer.new()
	_nameplate.name = "Nameplate"
	_nameplate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var plate := QuestUiStyle.panel_style(Color(0.1, 0.08, 0.1, 0.97), QuestUiStyle.GOLD, 2, 8)
	plate.corner_radius_bottom_left = 0
	plate.corner_radius_bottom_right = 0
	plate.border_width_bottom = 0
	plate.shadow_size = 0
	plate.content_margin_left = 24
	plate.content_margin_right = 28
	plate.content_margin_top = 8
	plate.content_margin_bottom = 6
	_nameplate.add_theme_stylebox_override("panel", plate)
	_frame.add_child(_nameplate)
	_name_label = Label.new()
	_name_label.name = "Speaker"
	_name_label.add_theme_font_override("font", QuestUiStyle.serif_font())
	_name_label.add_theme_font_size_override("font_size", 32)
	_name_label.add_theme_constant_override("outline_size", 6)
	_nameplate.add_child(_name_label)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(WIDTH, 150)
	var style := QuestUiStyle.panel_style(Color(0.055, 0.045, 0.07, 0.94), QuestUiStyle.GOLD, 2, 10)
	style.corner_radius_top_left = 0
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 22
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	_panel.gui_input.connect(_on_panel_input)
	_frame.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(WIDTH - 60, 40)
	_text.add_theme_font_size_override("normal_font_size", 27)
	_text.add_theme_constant_override("line_separation", 6)
	_text.add_theme_constant_override("outline_size", 2)
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_text.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.add_theme_constant_override("separation", 8)
	box.add_child(_choices)

	_continue_label = Label.new()
	_continue_label.text = "▼  Space to continue"
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.add_theme_font_size_override("font_size", 18)
	_continue_label.add_theme_color_override("font_color", QuestUiStyle.GOLD)
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
	return {"speaker": _name_label.text, "text": _text.text, "choices": _choice_texts.duplicate()}


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	_continue_label.modulate.a = 0.55 + 0.45 * sin(_pulse)
	_update_marker()
	if chars_per_second <= 0.0 or not is_typing():
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
	_nameplate.visible = not speaker.is_empty()
	_name_label.add_theme_color_override("font_color", view["speaker_color"])
	_set_speaker(str(view.get("speaker_id", "")), speaker, view["speaker_color"])
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
		var button := Button.new()
		button.name = "Choice%d" % (i + 1)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 52)
		button.text = "%d.  %s" % [i + 1, c["text"]]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 23)
		button.disabled = not c["enabled"]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(i))
		var hint: String = c["locked_text"] if not c["enabled"] else c["hint"]
		if not hint.is_empty():
			# The lean hint sits inside the button, on the right.
			var label := Label.new()
			label.text = "(%s)" % hint if not c["enabled"] else hint
			label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			label.offset_left = -260
			label.offset_right = -16
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", 19)
			label.add_theme_color_override("font_color", QuestUiStyle.MUTED if not c["enabled"] else QuestUiStyle.lean_color(hint))
			button.add_child(label)
			button.add_theme_constant_override("h_separation", 0)
		_choices.add_child(button)
		_choice_buttons.append(button)
		_choice_texts.append(button.text)


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_choice_buttons.clear()
	_choice_texts.clear()


func _on_finished(_id: StringName) -> void:
	# A choice can end this talk and start the next before this runs.
	if runner == null or not runner.is_finished:
		return
	if runner.line_changed.is_connected(_refresh):
		runner.line_changed.disconnect(_refresh)
		runner.finished.disconnect(_on_finished)
	runner = null
	_clear_choices()
	_set_speaker("", "", Color.WHITE)
	hide()
	closed.emit()


# --- Speaker in the world ---
# A marker floats over whoever is talking, and they play their talk gesture,
# so the words on screen are tied to a person in the scene.

func _set_speaker(id: String, display: String, color: Color) -> void:
	var changed := id != _speaker_id or display != _speaker_name
	_speaker_id = id
	_speaker_name = display
	_marker.color = color
	if changed:
		_speaker_node = _find_speaker()
	if _speaker_node and _speaker_node.has_method("talk"):
		_speaker_node.call("talk")
	if _speaker_node and _speaker_node.has_method("face_toward"):
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			_speaker_node.call("face_toward", player.global_position)
	_update_marker()


func _find_speaker() -> Node3D:
	if _speaker_id.is_empty() and _speaker_name.is_empty():
		return null
	for node in get_tree().get_nodes_in_group(&"npcs"):
		if not node is Node3D:
			continue
		var id := str(node.get("npc_id")) if node.get("npc_id") != null else ""
		var shown := str(node.get("display_name")) if node.get("display_name") != null else ""
		if (not _speaker_id.is_empty() and id == _speaker_id) or (not _speaker_name.is_empty() and shown == _speaker_name):
			return node
	return null


func _update_marker() -> void:
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if _speaker_node == null or not is_instance_valid(_speaker_node) or camera == null:
		_marker.visible = false
		return
	var height := 2.0
	var rig: Variant = _speaker_node.get("rig")
	if rig is Object and rig.has_method("get_height"):
		height = rig.get_height()
	var head := _speaker_node.global_position + Vector3.UP * (height + 0.35)
	if camera.is_position_behind(head):
		_marker.visible = false
		return
	# Camera coordinates are window pixels; convert to this control's space.
	var screen := camera.unproject_position(head)
	var local := get_global_transform_with_canvas().affine_inverse() * screen
	local.x = clampf(local.x, 40.0, size.x - 40.0)
	local.y = clampf(local.y, 40.0, size.y - 340.0)
	_marker.position = local
	_marker.visible = true


## Is the marker showing over a speaker in the world (for tests).
func get_marker_target() -> Node3D:
	return _speaker_node if _marker.visible else null


class _SpeakerMarker extends Control:
	var color := Color(1, 0.85, 0.5)
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t = fmod(_t + delta * 4.0, TAU)
		queue_redraw()

	func _draw() -> void:
		var bob := sin(_t) * 5.0
		# A speech bubble with three dots, and a pointer down to the head.
		var c := Vector2(0, -34 + bob)
		var bubble := Rect2(c - Vector2(30, 20), Vector2(60, 40))
		draw_rect(bubble.grow(3), Color(0, 0, 0, 0.55))
		draw_rect(bubble, Color(0.06, 0.05, 0.08, 0.95))
		draw_rect(bubble, color, false, 3.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 19), c + Vector2(10, 19), c + Vector2(0, 34)]), color)
		for i in 3:
			var a := 0.4 + 0.6 * maxf(0.0, sin(_t * 1.5 - i * 0.9))
			draw_circle(c + Vector2(-14 + i * 14, 0), 4.5, Color(color, a))
