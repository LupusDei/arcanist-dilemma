class_name CharacterCreation
extends Control
## Character creation, kept short per the design doc: boy or girl, a name, and
## presets for face, skin, hair, eyes and build. Emits [signal confirmed] with
## the character dictionary (see UiCharacterPresets) and stores it in
## UiSession.character.

signal confirmed(character: Dictionary)
signal cancelled

var character: Dictionary = UiCharacterPresets.default_character()
var portrait: UiPortrait
var name_edit: LineEdit
var sex_buttons: Array[Button] = []
var value_labels := {}
var begin_button: Button

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build()
	_refresh()


func set_option(key: String, index: int) -> void:
	var count := UiCharacterPresets.option_count(key)
	character[key] = posmod(index, count)
	_refresh()


func step_option(key: String, delta: int) -> void:
	set_option(key, int(character.get(key, 0)) + delta)


func set_character_name(text: String) -> void:
	if name_edit.text != text:
		name_edit.text = text
	character["name"] = text.strip_edges()
	_refresh()


func randomize_look() -> void:
	character = UiCharacterPresets.random_character(_rng, character.get("name", ""))
	_refresh()


func confirm() -> bool:
	if not can_confirm():
		return false
	var result := character.duplicate()
	UiSession.character = result
	confirmed.emit(result)
	return true


func can_confirm() -> bool:
	return str(character.get("name", "")).length() >= 2


func _refresh() -> void:
	portrait.character = character.duplicate()
	for i in sex_buttons.size():
		sex_buttons[i].set_pressed_no_signal(int(character.sex) == i)
	for key in value_labels:
		value_labels[key].text = UiCharacterPresets.option_name(key, int(character.get(key, 0)))
	begin_button.disabled = not can_confirm()
	begin_button.tooltip_text = "" if can_confirm() else "Give your arcanist a name first"


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PANEL, UiTheme.GOLD, 2, 8))
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Who are you, young arcanist?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	root.add_child(body)
	portrait = UiPortrait.new()
	portrait.name = "Portrait"
	body.add_child(portrait)

	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(380, 0)
	form.add_theme_constant_override("separation", 10)
	body.add_child(form)

	var name_title := Label.new()
	name_title.text = "Name"
	name_title.add_theme_color_override("font_color", UiTheme.GOLD)
	form.add_child(name_title)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Enter a name"
	name_edit.max_length = 20
	name_edit.text_changed.connect(set_character_name)
	form.add_child(name_edit)

	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	form.add_child(sex_row)
	var group := ButtonGroup.new()
	for i in UiCharacterPresets.SEXES.size():
		var b := Button.new()
		b.text = UiCharacterPresets.SEXES[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_option.bind("sex", i))
		sex_row.add_child(b)
		sex_buttons.append(b)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	form.add_child(grid)
	for sel in UiCharacterPresets.SELECTORS:
		var key: String = sel[0]
		var label := Label.new()
		label.text = sel[1]
		label.custom_minimum_size = Vector2(110, 0)
		label.add_theme_color_override("font_color", UiTheme.MUTED)
		grid.add_child(label)
		var prev := Button.new()
		prev.text = "◀"
		prev.pressed.connect(step_option.bind(key, -1))
		grid.add_child(prev)
		var value := Label.new()
		value.custom_minimum_size = Vector2(150, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(value)
		value_labels[key] = value
		var next := Button.new()
		next.text = "▶"
		next.pressed.connect(step_option.bind(key, 1))
		grid.add_child(next)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(spacer)
	var random_button := Button.new()
	random_button.text = "Randomize look"
	random_button.pressed.connect(randomize_look)
	form.add_child(random_button)

	root.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var back := Button.new()
	back.text = "Back"
	back.theme_type_variation = &"BigButton"
	back.pressed.connect(func(): cancelled.emit())
	footer.add_child(back)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fill)
	begin_button = Button.new()
	begin_button.name = "BeginButton"
	begin_button.text = "Begin the journey"
	begin_button.theme_type_variation = &"BigButton"
	begin_button.pressed.connect(confirm)
	footer.add_child(begin_button)
