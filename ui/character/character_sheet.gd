class_name CharacterSheet
extends Control
## Character sheet: the five attributes with point allocation, and the stats
## they produce. Points are staged first (green), so the player can see the
## effect before pressing Apply, then sent to progression in one call.
## Shift-click spends or returns five at a time.

signal closed

var progression_source: Object

var title_label: Label
var subtitle_label: Label
var points_label: Label
var apply_button: Button
var undo_button: Button
var suggest_button: Button
var value_labels := {}
var plus_buttons := {}
var minus_buttons := {}
var derived_grid: GridContainer

var _stats: Dictionary = {}
var _pending := {}


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
	_pending.clear()
	_on_progress_stats_changed()
	show()
	apply_button.grab_focus.call_deferred()


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
	_refresh()


func _on_progress_leveled_up(_level: Variant = 0, _b: Variant = null, _c: Variant = null) -> void:
	_on_progress_stats_changed()


func unspent() -> int:
	return int(_stats.get("unspent_attribute_points", 0))


func pending_total() -> int:
	var t := 0
	for v in _pending.values():
		t += v
	return t


func remaining() -> int:
	return unspent() - pending_total()


func add_point(attr: StringName, count := 1) -> void:
	count = mini(count, remaining())
	if count <= 0:
		return
	_pending[attr] = int(_pending.get(attr, 0)) + count
	_refresh()


func remove_point(attr: StringName, count := 1) -> void:
	var have := int(_pending.get(attr, 0))
	count = mini(count, have)
	if count <= 0:
		return
	if have - count == 0:
		_pending.erase(attr)
	else:
		_pending[attr] = have - count
	_refresh()


func suggest() -> void:
	_pending.clear()
	var path := StringName(str(_stats.get("path", "arcanist")))
	_pending = UiStats.suggest(path, unspent())
	_refresh()


func undo() -> void:
	_pending.clear()
	_refresh()


func apply() -> bool:
	if _pending.is_empty() or progression_source == null or not progression_source.has_method("allocate_attributes"):
		return false
	var spend := _pending.duplicate()
	_pending.clear()
	var ok: bool = progression_source.allocate_attributes(spend)
	if not ok:
		_pending = spend
	_on_progress_stats_changed()
	return ok


func _attrs_with_pending() -> Dictionary:
	var attrs: Dictionary = _stats.get("attributes", {}).duplicate()
	for attr in UiStats.ATTRIBUTES:
		attrs[attr] = int(attrs.get(attr, attrs.get(String(attr), UiStats.BASE_VALUE))) + int(_pending.get(attr, 0))
	return attrs


func _refresh() -> void:
	if _stats.is_empty():
		return
	var level := int(_stats.get("level", 1))
	var path := StringName(str(_stats.get("path", "arcanist")))
	title_label.text = str(_stats.get("name", "Arcanist"))
	subtitle_label.text = "Level %d %s" % [level, GameHud.path_title(_stats)]
	var attrs := _attrs_with_pending()
	var left := remaining()
	points_label.text = "Points to spend: %d" % left
	points_label.add_theme_color_override("font_color", UiTheme.GOOD if left > 0 else UiTheme.MUTED)
	for attr in UiStats.ATTRIBUTES:
		var p := int(_pending.get(attr, 0))
		var lbl: Label = value_labels[attr]
		lbl.text = str(attrs[attr]) + ("  (+%d)" % p if p > 0 else "")
		lbl.add_theme_color_override("font_color", UiTheme.GOOD if p > 0 else UiTheme.PARCHMENT)
		plus_buttons[attr].disabled = left <= 0
		minus_buttons[attr].disabled = p <= 0
		var tip := UiStats.attribute_tooltip(attr, path)
		for c in [value_labels[attr].get_parent().get_child(0), lbl, plus_buttons[attr]]:
			c.tooltip_text = tip
	apply_button.disabled = _pending.is_empty()
	undo_button.disabled = _pending.is_empty()
	suggest_button.disabled = unspent() <= 0
	_refresh_derived(level, path, attrs)


func _refresh_derived(level: int, path: StringName, attrs: Dictionary) -> void:
	var before := UiStats.derived_rows(level, path, _stats.get("attributes", {}))
	var after := UiStats.derived_rows(level, path, attrs)
	for c in derived_grid.get_children():
		derived_grid.remove_child(c)
		c.queue_free()
	for i in after.size():
		var k := Label.new()
		k.text = after[i][0]
		k.add_theme_color_override("font_color", UiTheme.MUTED)
		derived_grid.add_child(k)
		var v := Label.new()
		v.text = after[i][1]
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if after[i][1] != before[i][1]:
			v.add_theme_color_override("font_color", UiTheme.GOOD)
		derived_grid.add_child(v)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
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

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	var attr_title := Label.new()
	attr_title.text = "Attributes"
	attr_title.add_theme_color_override("font_color", UiTheme.GOLD)
	left.add_child(attr_title)
	for attr in UiStats.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		left.add_child(row)
		var name_label := Label.new()
		name_label.text = UiStats.NAMES[attr]
		name_label.custom_minimum_size = Vector2(130, 0)
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_label)
		var value := Label.new()
		value.name = "Value"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(value)
		value_labels[attr] = value
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(36, 32)
		minus.pressed.connect(func(): remove_point(attr, 5 if Input.is_key_pressed(KEY_SHIFT) else 1))
		row.add_child(minus)
		minus_buttons[attr] = minus
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(36, 32)
		plus.pressed.connect(func(): add_point(attr, 5 if Input.is_key_pressed(KEY_SHIFT) else 1))
		row.add_child(plus)
		plus_buttons[attr] = plus
	points_label = Label.new()
	left.add_child(points_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left.add_child(actions)
	suggest_button = Button.new()
	suggest_button.text = "Suggested"
	suggest_button.tooltip_text = "Spend points along this path's suggested build"
	suggest_button.pressed.connect(suggest)
	actions.add_child(suggest_button)
	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.pressed.connect(undo)
	actions.add_child(undo_button)
	apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(apply)
	actions.add_child(apply_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var details_title := Label.new()
	details_title.text = "Details"
	details_title.add_theme_color_override("font_color", UiTheme.GOLD)
	right.add_child(details_title)
	derived_grid = GridContainer.new()
	derived_grid.columns = 2
	derived_grid.add_theme_constant_override("h_separation", 24)
	right.add_child(derived_grid)

	var hint := Label.new()
	hint.theme_type_variation = &"SubtleLabel"
	hint.text = "Hover an attribute to see what each point gives. Shift-click to move five points."
	root.add_child(hint)
