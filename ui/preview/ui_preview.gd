extends Control
## UI preview: every screen running against the mock player, with buttons to
## fire the signals the real systems will send. Run with F6 on
## res://ui/preview/ui_preview.tscn, or:
##   godot --path . res://ui/preview/ui_preview.tscn
##
## In game: 1-6 cast bar spells, left/right click the mouse spells, C sheet,
## K talents, Esc pause.

var game_ui: GameUI
var main_menu: MainMenu
var creation: CharacterCreation
var dev_layer: CanvasLayer
var tabs: TabBar
var _game_view: Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_game_view = Control.new()
	_game_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game_view)
	var backdrop := TextureRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 0.56, 1.0])
	grad.colors = PackedColorArray([Color(0.32, 0.36, 0.58), Color(0.72, 0.6, 0.62), Color(0.3, 0.42, 0.24), Color(0.16, 0.24, 0.12)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	backdrop.texture = tex
	_game_view.add_child(backdrop)

	game_ui = load("res://ui/game_ui.tscn").instantiate()
	game_ui.force_mock = true
	add_child(game_ui)
	game_ui.mock.regen_enabled = true

	main_menu = MainMenu.new()
	main_menu.game_scene = ""
	main_menu.hide()
	main_menu.new_game_started.connect(func(c): _show_tab(0); game_ui.mock.character_name = c.name; game_ui.mock.stats_changed.emit(game_ui.mock.get_stats()))
	add_child(main_menu)

	creation = CharacterCreation.new()
	creation.hide()
	creation.confirmed.connect(func(c): game_ui.mock.character_name = c.name; game_ui.mock.stats_changed.emit(game_ui.mock.get_stats()); _show_tab(0))
	creation.cancelled.connect(_show_tab.bind(0))
	add_child(creation)

	_build_dev_panel()


func _show_tab(index: int) -> void:
	tabs.current_tab = index
	game_ui.visible = index == 0
	_game_view.visible = index == 0
	main_menu.visible = index == 1
	creation.visible = index == 2
	if index == 1:
		main_menu.close_creation()


func _unhandled_input(event: InputEvent) -> void:
	if not game_ui.visible or get_tree().paused:
		return
	var mock := game_ui.mock
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			mock.cast_slot(2 + k - KEY_1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mock.cast_slot(0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			mock.cast_slot(1)


func _build_dev_panel() -> void:
	dev_layer = CanvasLayer.new()
	dev_layer.layer = 50
	add_child(dev_layer)

	tabs = TabBar.new()
	tabs.add_tab("In game")
	tabs.add_tab("Main menu")
	tabs.add_tab("Character creation")
	tabs.position = Vector2(560, 8)
	tabs.tab_changed.connect(_show_tab)
	dev_layer.add_child(tabs)

	var panel := PanelContainer.new()
	panel.theme = UiTheme.get_theme()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.08, 0.85), UiTheme.GOLD_DIM, 1, 6))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -230
	panel.offset_right = -10
	panel.offset_top = 60
	dev_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Mock signals"
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(title)
	var m := func() -> UiMockPlayer: return game_ui.mock
	_dev(box, "+60 XP", func(): m.call().gain_xp(60))
	_dev(box, "Level up", func(): m.call().level_up())
	_dev(box, "Take 25 damage", func(): m.call().take_damage(25))
	_dev(box, "Heal 40", func(): m.call().heal(40))
	_dev(box, "Interrupt cast", func(): m.call().interrupt())
	_dev(box, "Path: wizard", func(): m.call().set_path(&"wizard"))
	_dev(box, "Path: mage", func(): m.call().set_path(&"mage"))
	_dev(box, "Path: sorcerer", func(): m.call().set_path(&"sorcerer"))
	_dev(box, "Character sheet (C)", func(): game_ui.open_panel(game_ui.character_sheet))
	_dev(box, "Talents (K)", func(): game_ui.open_panel(game_ui.talent_picker))
	_dev(box, "Pause (Esc)", func(): game_ui.pause_menu.open())
	var hint := Label.new()
	hint.theme_type_variation = &"SubtleLabel"
	hint.text = "1-6 and mouse buttons cast"
	box.add_child(hint)


func _dev(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
