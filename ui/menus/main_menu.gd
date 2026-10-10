class_name MainMenu
extends Control
## Title screen: New game (into character creation), Continue (no saves yet),
## Options (not built yet) and Quit. After creation it loads [member game_scene].

signal new_game_started(character: Dictionary)

## Loaded once a character is created. Empty means only the signal is emitted.
@export_file("*.tscn") var game_scene := "res://scenes/world/world.tscn"

var menu: Control
var creation: CharacterCreation
var new_game_button: Button
var continue_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build()


func _ready() -> void:
	UiScale.fit(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	new_game_button.grab_focus.call_deferred()


func open_creation() -> void:
	menu.hide()
	creation.show()
	creation.name_edit.grab_focus.call_deferred()


func close_creation() -> void:
	creation.hide()
	menu.show()
	new_game_button.grab_focus.call_deferred()


## Loads the saved game (slot 0) and goes into the world.
func _continue_game() -> void:
	var progression := get_node_or_null(^"/root/Progression")
	if progression == null or not progression.load_game(0):
		return
	if game_scene != "" and ResourceLoader.exists(game_scene):
		get_tree().change_scene_to_file(game_scene)


func _on_character_confirmed(character: Dictionary) -> void:
	new_game_started.emit(character)
	if game_scene != "" and ResourceLoader.exists(game_scene):
		get_tree().change_scene_to_file(game_scene)


func _build() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(0.2, 0.14, 0.32), Color(0.08, 0.06, 0.14), Color(0.02, 0.015, 0.03)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.35)
	tex.fill_to = Vector2(1.1, 1.1)
	bg.texture = tex
	add_child(bg)
	var stars := _Stars.new()
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stars)

	menu = CenterContainer.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	menu.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Arcanist's Dilemma"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Every spell is a choice. Every choice shapes the arcanist."
	subtitle.theme_type_variation = &"SubtleLabel"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.custom_minimum_size = Vector2(320, 0)
	box.add_child(buttons)
	new_game_button = _button(buttons, "New game", open_creation)
	continue_button = _button(buttons, "Continue", _continue_game)
	var saves: Array = ProgressionSave.list_slots(1)
	continue_button.disabled = saves.is_empty()
	if saves.is_empty():
		continue_button.tooltip_text = "No saved game yet"
	else:
		var save: Dictionary = saves[0]
		continue_button.tooltip_text = "%s, level %d" % [save.get("name", ""), save.get("level", 1)]
	var options := _button(buttons, "Options", func(): pass)
	options.disabled = true
	options.tooltip_text = "Coming soon"
	_button(buttons, "Quit", func(): get_tree().quit())

	creation = CharacterCreation.new()
	creation.name = "CharacterCreation"
	creation.hide()
	creation.cancelled.connect(close_creation)
	creation.confirmed.connect(_on_character_confirmed)
	add_child(creation)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BigButton"
	b.text = text
	b.name = text.replace(" ", "") + "Button"
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Slowly drifting motes behind the title.
class _Stars extends Control:
	var _points: Array[Vector3] = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 90:
			_points.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.5, 2.5)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for p in _points:
			var pos := Vector2(p.x * size.x, fposmod(p.y - _t * 0.01 * p.z, 1.0) * size.y)
			var a := 0.25 + 0.25 * sin(_t * p.z + p.x * 20.0)
			draw_circle(pos, p.z, Color(1.0, 0.85, 0.55, a))
