class_name TalentPicker
extends Control
## WoW-style talent picker: six rows, one per even level from 10 to 20, three
## sideways choices each. Rows above the character's level are locked. A
## chosen talent can be swapped freely (the mechanics doc makes talent resets
## free at any rest; the game decides where that is allowed).

signal closed

var progression_source: Object
var title_label: Label
var subtitle_label: Label
var rows_box: VBoxContainer
var option_buttons: Array = []  # Array of Array[Button], one per row

var _stats: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func bind(progression: Object) -> void:
	if progression_source:
		UiBind.disconnect_all(progression_source, self, "_on_progress_")
	progression_source = progression
	UiBind.connect_all(progression_source, self, "_on_progress_")
	_on_progress_stats_changed()


func open() -> void:
	_on_progress_stats_changed()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _on_progress_stats_changed(stats: Variant = null, _b: Variant = null) -> void:
	if progression_source and progression_source.has_method("get_stats"):
		_stats = progression_source.get_stats()
	elif stats is Dictionary:
		_stats = stats
	_rebuild_rows()


func _on_progress_leveled_up(_level: Variant = 0, _b: Variant = null, _c: Variant = null) -> void:
	_on_progress_stats_changed()


func choose(row: int, choice: int) -> bool:
	if progression_source == null or not progression_source.has_method("choose_talent"):
		return false
	var ok: bool = progression_source.choose_talent(row, choice)
	_on_progress_stats_changed()
	return ok


func is_row_open(row: int) -> bool:
	var rows: Array = _stats.get("talent_tree", {}).get("rows", [])
	return row < rows.size() and int(_stats.get("level", 1)) >= int(rows[row].level)


func _rebuild_rows() -> void:
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	option_buttons.clear()
	var tree: Dictionary = _stats.get("talent_tree", {})
	var rows: Array = tree.get("rows", [])
	var choices: Array = _stats.get("talent_choices", [])
	var level := int(_stats.get("level", 1))
	title_label.text = "%s Talents" % tree.get("name", "") if tree.has("name") else "Talents"
	if rows.is_empty():
		subtitle_label.text = "Talents open at level 10, with your specialization."
		return
	var open_count := 0
	for i in rows.size():
		if level >= int(rows[i].level) and (i >= choices.size() or int(choices[i]) < 0):
			open_count += 1
	subtitle_label.text = ("%d talent choice%s waiting" % [open_count, "" if open_count == 1 else "s"]) if open_count > 0 else "Pick one talent per row. You can swap them for free at a rest."

	for i in rows.size():
		var row: Dictionary = rows[i]
		var unlocked := level >= int(row.level)
		var chosen := int(choices[i]) if i < choices.size() else -1
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		rows_box.add_child(line)
		var lvl := Label.new()
		lvl.text = "Level %d" % int(row.level)
		lvl.custom_minimum_size = Vector2(80, 0)
		lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lvl.add_theme_color_override("font_color", UiTheme.GOLD if unlocked else UiTheme.MUTED.darkened(0.3))
		line.add_child(lvl)
		var buttons: Array[Button] = []
		var options: Array = row.options
		for j in options.size():
			var b := _option_button(options[j], unlocked, chosen, j)
			b.pressed.connect(choose.bind(i, j))
			line.add_child(b)
			buttons.append(b)
		option_buttons.append(buttons)


func _option_button(option: Dictionary, unlocked: bool, chosen: int, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 78)
	b.disabled = not unlocked
	b.toggle_mode = true
	b.button_pressed = chosen == index
	b.tooltip_text = "%s\n%s" % [option.name, option.text] + ("" if unlocked else "\nLocked")
	if chosen == index:
		var s := UiTheme.panel_style(Color(0.24, 0.18, 0.1, 0.98), UiTheme.GOLD_BRIGHT, 2, 4)
		s.shadow_size = 0
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(state, s)
	elif chosen >= 0:
		b.modulate = Color(1, 1, 1, 0.65)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 6
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)
	var n := Label.new()
	n.text = option.name
	n.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT if unlocked else UiTheme.MUTED)
	box.add_child(n)
	var t := Label.new()
	t.text = option.text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", UiTheme.PARCHMENT if unlocked else UiTheme.MUTED.darkened(0.2))
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	box.add_child(t)
	return b


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PANEL, UiTheme.GOLD, 2, 8))
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	title_label = Label.new()
	title_label.theme_type_variation = &"HeaderLabel"
	titles.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = &"SubtleLabel"
	titles.add_child(subtitle_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Close (Esc)"
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	header.add_child(close_button)
	root.add_child(HSeparator.new())
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 8)
	root.add_child(rows_box)
