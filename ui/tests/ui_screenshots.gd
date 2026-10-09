extends SceneTree
## Renders the preview scene's screens to res://ui/docs/*.png. Needs a display
## (or xvfb-run) and a renderer, so it is not part of the headless test run:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://ui/tests/ui_screenshots.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p: Node = load("res://ui/preview/ui_preview.tscn").instantiate()
	root.add_child(p)
	await _frames(10)
	var mock: UiMockPlayer = p.game_ui.mock
	mock.regen_enabled = false
	mock.take_damage(60)
	mock.cast_slot(3)
	mock.cast_slot(0)
	await _seconds(1.3)
	mock.cast_slot(5)
	mock.cast_slot(2)
	await _seconds(0.4)
	_hide_dev(p, false)
	await _shot("hud")
	mock.level_up()
	await _seconds(0.6)
	await _shot("level_up")
	await _seconds(3.5)
	p.game_ui.open_panel(p.game_ui.character_sheet)
	p.game_ui.character_sheet.add_point(&"intelligence", 3)
	p.game_ui.character_sheet.add_point(&"dexterity", 2)
	await _shot("character_sheet")
	p.game_ui.character_sheet.close()
	mock.choose_talent(0, 1)
	p.game_ui.open_panel(p.game_ui.talent_picker)
	await _shot("talents")
	p.game_ui.talent_picker.close()
	p.game_ui.pause_menu.open()
	await _shot("pause_menu")
	p.game_ui.pause_menu.close()
	mock.set_path(&"sorcerer")
	for i in 20:
		mock._cooldowns.clear()
		mock.cast_slot(2)
	await _seconds(0.3)
	await _shot("hud_sorcerer")
	p._show_tab(1)
	await _seconds(0.5)
	await _shot("main_menu")
	p._show_tab(2)
	p.creation.set_character_name("Ilsa")
	p.creation.set_option("sex", 1)
	p.creation.set_option("hair", 2)
	p.creation.set_option("hair_color", 2)
	p.creation.set_option("eyes", 2)
	await _shot("character_creation")
	quit(0)


func _hide_dev(p: Node, v: bool) -> void:
	p.dev_layer.visible = v


func _shot(name: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/docs"))
	img.save_png("res://ui/docs/%s.png" % name)
	print("saved ", name)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s, true).timeout
