extends SceneTree
## Headless tests for the UI, run against the mock player.
## Run: godot --headless --path . --script res://ui/tests/ui_test.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stats()
	_test_orb_geometry()
	await _test_hud()
	await _test_character_sheet()
	await _test_talents()
	await _test_pause_and_keys()
	await _test_creation()
	await _test_main_menu()
	await _test_preview_loads()

	if _failures.is_empty():
		print("UI TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _test_stats() -> void:
	var attrs := {&"strength": 10, &"vitality": 30, &"dexterity": 10, &"intelligence": 20, &"wisdom": 10}
	_check(UiStats.max_health(1, attrs) == 180.0, "vitality adds 5 health per point")
	_check(UiStats.spell_power(&"mage", attrs) == 10.0, "mage spell power scales with intelligence")
	_check(UiStats.spell_power(&"sorcerer", attrs) == 20.0, "sorcerer spell power scales with vitality")
	_check(UiStats.resource_kind(&"wizard") == &"arcana" and UiStats.resource_kind(&"sorcerer") == &"strain", "each path has its resource")
	_check(UiStats.cast_speed(&"mage", {&"dexterity": 500}) == UiStats.CAST_SPEED_CAP, "cast speed is capped")
	var s := UiStats.suggest(&"mage", 5)
	var total := 0
	for v in s.values():
		total += v
	_check(total == 5 and s.get(&"intelligence", 0) == 3, "suggested build spends every point (got %s)" % s)
	_check(UiStats.attribute_tooltip(&"vitality", &"sorcerer").contains("strain capacity"), "tooltip shows the path bonus")


func _test_orb_geometry() -> void:
	var full := UiOrb.segment(Vector2.ZERO, 10.0, 1.0)
	var half := UiOrb.segment(Vector2.ZERO, 10.0, 0.5)
	var max_y := -INF
	var min_y := INF
	for p in half:
		max_y = maxf(max_y, p.y)
		min_y = minf(min_y, p.y)
	_check(is_equal_approx(min_y, 0.0) and is_equal_approx(max_y, 10.0), "half orb fills the lower half")
	var top := INF
	for p in full:
		top = minf(top, p.y)
	_check(is_equal_approx(top, -10.0), "full orb reaches the top")


func _test_hud() -> void:
	var ui := _make_ui()
	await _frames(3)
	var hud := ui.hud
	var mock := ui.mock
	_check(mock != null, "GameUI falls back to the mock player")
	_check(hud.health_label.text == "%d / %d" % [roundi(mock.current_health), roundi(mock.max_health)], "health label shows current / max (%s)" % hud.health_label.text)
	_check(hud.name_label.text == "Ilsa" and hud.level_label.text == "Level 12 · Chronos Mage", "character frame (%s)" % hud.level_label.text)
	_check(hud.slots[0].spell == mock.action_bar[0], "hotbar shows the action bar")
	_check(hud.slots[0].key_hint == "LMB" and hud.slots[2].key_hint == "1", "hotbar key hints")
	_check(hud.points_button.visible, "unspent points button shows")
	_check(hud.talent_button.visible, "talent ready button shows at level 12 with no picks")

	var before := hud.health_orb.ratio
	mock.take_damage(30)
	_check(hud.health_orb.ratio < before, "damage lowers the health orb")
	_check(hud._vignette.modulate.a > 0.0, "damage flashes the screen edge")

	var res_before := hud.resource_orb.ratio
	mock.cast_slot(3)  # Mend Flesh: 1.2s cast, 25 mana, 8s cooldown.
	_check(hud.cast_bar.visible and hud.cast_label.text == "Mend Flesh", "long casts show the cast bar")
	await _seconds(1.4)
	_check(not hud.cast_bar.visible, "cast bar hides when the spell goes off")
	_check(hud.slots[3].cooldown_remaining > 6.0, "cooldown sweep starts (%.2f)" % hud.slots[3].cooldown_remaining)
	_check(hud.resource_orb.ratio < res_before, "casting spends mana")
	mock.cast_slot(3)
	_check(hud.slots[3]._failed > 0.0, "casting on cooldown flashes the slot")

	mock.cast_slot(2)
	await _frames(2)
	mock.interrupt()
	_check(hud.cast_label.text == "Interrupted", "interrupts show on the cast bar")

	var xp_before := hud.xp_bar.value
	mock.gain_xp(50)
	_check(hud.xp_bar.value == xp_before + 50, "XP bar fills")
	var level := mock.level
	mock.level_up()
	_check(mock.level == level + 1, "mock levels up")
	_check(hud.banner.visible and hud.banner_title.text == "Level %d" % (level + 1), "level-up banner shows")
	_check(hud.level_label.text.begins_with("Level %d" % (level + 1)), "level label updates")
	_check(hud.points_button.text.begins_with("+10"), "points button counts new points (%s)" % hud.points_button.text)

	mock.set_path(&"sorcerer")
	_check(hud.resource_orb.fill_color == UiTheme.resource_color(&"strain"), "sorcerer shows strain")
	_check(UiBind.spell_name(hud.slots[1].spell) == "Chain Lightning", "path change swaps the bar")
	for i in 25:
		mock._cooldowns.clear()
		mock.cast_slot(2)
	_check(hud.resource_orb.overfill, "overstrain pulses the orb")
	ui.free()


func _test_character_sheet() -> void:
	var ui := _make_ui()
	await _frames(2)
	var sheet := ui.character_sheet
	var mock := ui.mock
	ui.open_panel(sheet)
	_check(sheet.visible and paused, "sheet opens and pauses")
	_check(sheet.points_label.text == "Points to spend: 5", "sheet shows unspent points")
	sheet.plus_buttons[&"intelligence"].pressed.emit()
	sheet.plus_buttons[&"intelligence"].pressed.emit()
	sheet.plus_buttons[&"vitality"].pressed.emit()
	_check(sheet.points_label.text == "Points to spend: 2", "pending points count down")
	_check(sheet.value_labels[&"intelligence"].text == "42  (+2)", "pending points show (%s)" % sheet.value_labels[&"intelligence"].text)
	_check(mock.attributes[&"intelligence"] == 40, "nothing is spent before Apply")
	sheet.minus_buttons[&"vitality"].pressed.emit()
	_check(sheet.remaining() == 3, "minus returns a point")
	sheet.add_point(&"dexterity", 99)
	_check(sheet.remaining() == 0, "cannot stage more than unspent")
	_check(sheet.plus_buttons[&"wisdom"].disabled, "plus disables at zero points")
	var spell_power_cell: Label = sheet.derived_grid.get_child(5)
	_check(spell_power_cell.text == "+32%", "derived stats preview pending points (%s)" % spell_power_cell.text)
	sheet.apply_button.pressed.emit()
	_check(mock.attributes[&"intelligence"] == 42 and mock.attributes[&"dexterity"] == 28, "Apply spends points on progression")
	_check(mock.unspent_attribute_points == 0 and sheet.remaining() == 0, "unspent points drop to zero")
	_check(not ui.hud.points_button.visible, "HUD points button hides")
	sheet.close()
	_check(not paused, "closing the sheet unpauses")

	mock.level_up()
	ui.open_panel(sheet)
	sheet.suggest_button.pressed.emit()
	_check(sheet.remaining() == 0 and int(sheet._pending.get(&"intelligence", 0)) == 3, "Suggested spends along the mage build")
	sheet.undo_button.pressed.emit()
	_check(sheet.remaining() == 5, "Undo clears staged points")
	sheet.close()
	ui.free()


func _test_talents() -> void:
	var ui := _make_ui()
	await _frames(2)
	var picker := ui.talent_picker
	var mock := ui.mock
	ui.open_panel(picker)
	_check(picker.title_label.text == "Chronos Talents", "talent tree title")
	_check(picker.option_buttons.size() == 6, "six talent rows")
	_check(picker.is_row_open(1) and not picker.is_row_open(2), "rows open by level")
	_check(picker.option_buttons[2][0].disabled, "locked rows are disabled")
	picker.option_buttons[0][1].pressed.emit()
	_check(mock.talent_choices[0] == 1, "picking a talent tells progression")
	_check(picker.option_buttons[0][1].button_pressed, "picked talent is highlighted")
	_check(not picker.choose(2, 0), "locked rows cannot be picked")
	picker.option_buttons[0][2].pressed.emit()
	_check(mock.talent_choices[0] == 2, "a talent can be swapped")
	picker.option_buttons[1][0].pressed.emit()
	_check(not ui.hud.talent_button.visible, "HUD talent prompt hides once all open rows are picked")
	picker.close()
	ui.free()


func _test_pause_and_keys() -> void:
	var ui := _make_ui()
	await _frames(2)
	ui._unhandled_input(_action("ui_cancel"))
	_check(ui.pause_menu.visible and paused, "Esc opens the pause menu and pauses")
	ui._unhandled_input(_action("ui_cancel"))
	_check(not ui.pause_menu.visible and not paused, "Esc again resumes")
	ui._unhandled_input(_key(KEY_C))
	_check(ui.character_sheet.visible and paused, "C opens the character sheet")
	ui._unhandled_input(_key(KEY_K))
	_check(ui.talent_picker.visible and not ui.character_sheet.visible, "K swaps to talents")
	ui._unhandled_input(_action("ui_cancel"))
	_check(not ui.talent_picker.visible and not paused and not ui.pause_menu.visible, "Esc closes a panel before pausing")
	ui.pause_menu.open()
	ui.pause_menu.find_child("CharacterButton", true, false).pressed.emit()
	_check(ui.character_sheet.visible and not ui.pause_menu.visible and paused, "pause menu opens the character sheet")
	ui.character_sheet.close()
	_check(not paused, "game resumes after leaving the sheet")
	ui.free()


func _test_creation() -> void:
	var c: CharacterCreation = load("res://ui/menus/character_creation.tscn").instantiate()
	root.add_child(c)
	await _frames(1)
	_check(c.begin_button.disabled, "Begin needs a name")
	c.name_edit.text_changed.emit("Ilsa")
	_check(not c.begin_button.disabled, "Begin enables with a name")
	c.sex_buttons[1].pressed.emit()
	_check(c.character.sex == 1 and c.portrait.character.sex == 1, "girl choice reaches the portrait")
	c.step_option("skin", 1)
	_check(c.character.skin == 2 and c.value_labels["skin"].text == "Olive", "skin preset steps")
	c.step_option("build", -2)
	_check(c.character.build == 2, "presets wrap around")
	c.randomize_look()
	_check(c.character.name == "Ilsa", "randomize keeps the name")
	var got := []
	c.confirmed.connect(func(d): got.append(d))
	c.begin_button.pressed.emit()
	_check(got.size() == 1 and got[0].name == "Ilsa", "confirm emits the character")
	_check(UiSession.has_character() and UiSession.character.name == "Ilsa", "character is stored for the game scene")
	c.free()


func _test_main_menu() -> void:
	var m: MainMenu = load("res://ui/menus/main_menu.tscn").instantiate()
	m.game_scene = ""
	root.add_child(m)
	await _frames(1)
	_check(m.continue_button.disabled, "Continue is disabled without saves")
	m.new_game_button.pressed.emit()
	_check(m.creation.visible and not m.menu.visible, "New game opens character creation")
	m.creation.cancelled.emit()
	_check(m.menu.visible and not m.creation.visible, "Back returns to the menu")
	m.free()


func _test_preview_loads() -> void:
	var p: Node = load("res://ui/preview/ui_preview.tscn").instantiate()
	root.add_child(p)
	await _frames(2)
	_check(p.game_ui.mock != null, "preview scene loads with the mock")
	p._show_tab(1)
	_check(p.main_menu.visible and not p.game_ui.visible, "preview switches to the main menu")
	p.free()


func _make_ui() -> GameUI:
	paused = false
	var ui: GameUI = load("res://ui/game_ui.tscn").instantiate()
	ui.force_mock = true
	root.add_child(ui)
	return ui


func _action(action: String) -> InputEvent:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func _key(code: Key) -> InputEvent:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s, true).timeout


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
