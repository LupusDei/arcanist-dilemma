extends CanvasLayer
## The first great dilemma: at level 5 the arcanist chooses to become a wizard,
## a mage or a sorcerer. Pauses the game and frees the mouse while open.
## Emits path_picked with "wizard", "mage" or "sorcerer"; "Decide later" closes
## it, and P reopens it from the game session while the choice is still open.

signal path_picked(path: String)

const PATHS := [
	{
		"id": "wizard", "title": "Wizard", "tradition": "The Book",
		"text": "Magic written down and passed on. Learn spells from spellbooks, inscribe them and prepare the best for the fight ahead. Precise and powerful; Arcana fuels it.",
		"home": "Archivist Pell, the Athenaeum in Vell",
		"color": Color(0.35, 0.55, 1.0),
	},
	{
		"id": "mage", "title": "Mage", "tradition": "Understanding",
		"text": "Magic as the way the world works. Discover verbs and nouns by studying storms, clocks and rivers, then combine them into spells. Draws Mana from the world.",
		"home": "Old Saro, among the Wayfarers",
		"color": Color(0.35, 0.85, 0.6),
	},
	{
		"id": "sorcerer", "title": "Sorcerer", "tradition": "Inner Power",
		"text": "Magic born inside you. Fast, raw spells that build Strain; push past the limit for more power, and risk it tearing loose.",
		"home": "Lady Corra Ashvane, the Ember Houses",
		"color": Color(1.0, 0.5, 0.3),
	},
]

var _root: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()


func open() -> void:
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ClassDB.class_exists("UiTheme") or ResourceLoader.exists("res://ui/theme/ui_theme.gd"):
		_root.theme = load("res://ui/theme/ui_theme.gd").get_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.1, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := Label.new()
	title.text = "Choose your path"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Three sparks burn in you. Only one can lead. This choice is permanent."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.75)
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	for path in PATHS:
		row.add_child(_card(path))

	var later := Button.new()
	later.text = "Decide later (press P)"
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(close)
	column.add_child(later)


func _card(path: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 330)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.16, 0.95)
	style.border_color = path["color"]
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = path["title"]
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", path["color"])
	box.add_child(name_label)
	var tradition := Label.new()
	tradition.text = path["tradition"]
	tradition.modulate = Color(1, 1, 1, 0.7)
	box.add_child(tradition)
	var text := Label.new()
	text.text = path["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var mentor := Label.new()
	mentor.text = "Mentor: " + path["home"]
	mentor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mentor.modulate = Color(1, 1, 1, 0.6)
	box.add_child(mentor)
	var choose := Button.new()
	choose.text = "Become a " + path["title"]
	choose.pressed.connect(func() -> void:
		close()
		path_picked.emit(path["id"]))
	box.add_child(choose)
	return panel
