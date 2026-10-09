class_name InventoryScreen
extends Control
## The inventory and equipment screen: a paper doll with the ten gear slots,
## the bag grid, gold, gear totals, and tooltips that compare against what is worn.
##
## Diablo 2 handling: left click picks an item up onto the cursor and puts it
## down (swapping with what is there); right click drinks, studies or equips;
## clicking outside the panel drops the held item on the ground.
## I (or the "inventory" action) toggles it; Esc closes it.
##
## Reads everything from the Items autoload (res://systems/items/items_service.gd),
## or from [member items] when set directly.

signal opened
signal closed

## Pause the game while open, like the other panels.
@export var pause_game := true
## Toggle with I (or the "inventory" input action when it exists).
@export var handle_hotkey := true

const DOLL_LAYOUT := {
	# slot: [x, y, w, h] in cells
	&"main_hand": [0.0, 0.5, 2, 4],
	&"hat": [2.5, 0.0, 2, 2],
	&"amulet": [4.75, 0.25, 1, 1],
	&"off_hand": [5.0, 1.5, 2, 3],
	&"robe": [2.5, 2.25, 2, 3],
	&"ring_1": [1.25, 5.0, 1, 1],
	&"belt": [2.5, 5.5, 2, 1],
	&"ring_2": [4.75, 5.0, 1, 1],
	&"gloves": [0.0, 6.25, 2, 2],
	&"boots": [5.0, 6.25, 2, 2],
}

var items: ItemsService
var held: ItemInstance

var _panel: PanelContainer
var _grid: ItemGridView
var _slot_views := {}
var _gold_label: Label
var _stats_label: Label
var _message_label: Label
var _tooltip: PanelContainer
var _tooltip_box: VBoxContainer
var _compare: PanelContainer
var _compare_box: VBoxContainer
var _cursor: Control
var _hover_item: ItemInstance
var _was_paused := false
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _message_time := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	theme = InventoryStyle.get_theme()
	if items == null:
		items = get_node_or_null(^"/root/Items") as ItemsService
	_build()
	if items:
		bind(items)


func bind(service: ItemsService) -> void:
	items = service
	_grid.bind(items.inventory)
	_grid.usable_check = _is_usable
	for sig in ["inventory_changed", "equipment_changed", "gold_changed", "gear_stats_changed"]:
		if not items.is_connected(sig, _refresh_any):
			items.connect(sig, _refresh_any)
	if not items.message.is_connected(_show_message):
		items.message.connect(_show_message)
	_refresh()


# --- Open and close -----------------------------------------------------------

func open() -> void:
	if visible:
		return
	visible = true
	_refresh()
	if pause_game:
		_was_paused = get_tree().paused
		get_tree().paused = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close() -> void:
	if not visible:
		return
	_return_held()
	_hide_tooltip()
	visible = false
	if pause_game:
		get_tree().paused = _was_paused
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func get_slot_view(slot: StringName) -> ItemSlotView:
	return _slot_views.get(slot)


# --- Actions (also used by tests) -----------------------------------------------

## Right click on a bag item: drink, study or wear it.
func activate_bag_item(item: ItemInstance) -> void:
	if items and item:
		items.use_item(item)
		_refresh()


func pick_up_from_bag(item: ItemInstance) -> void:
	if held or not items.inventory.has_item(item):
		return
	items.inventory.remove_item(item)
	_set_held(item)


func put_in_bag(cell: Vector2i) -> bool:
	if held == null:
		return false
	var inv := items.inventory
	var origin := _grid.drop_origin(cell, held)
	var under := inv.items_in_area(origin, held.get_size())
	if under.size() == 1 and under[0].can_stack_with(held):
		var target := under[0]
		var moved := mini(held.quantity, target.get_max_stack() - target.quantity)
		target.quantity += moved
		held.quantity -= moved
		inv.changed.emit()
		if held.quantity <= 0:
			_set_held(null)
		return true
	if under.size() > 1:
		return false
	var swap: ItemInstance = under[0] if under.size() == 1 else null
	if not inv.is_area_free(origin, held.get_size(), swap):
		return false
	if swap:
		inv.remove_item(swap)
	inv.place_at(held, origin)
	_set_held(swap)
	return true


func put_in_slot(slot: StringName) -> bool:
	if held == null:
		return false
	var reason := items.check_equip(held, slot)
	if reason != &"":
		_show_message(ItemsService.describe_reason(reason, held))
		return false
	var previous := items.equipment.equip(held, slot)
	_set_held(previous)
	return true


func take_from_slot(slot: StringName) -> void:
	if held:
		return
	var item := items.equipment.unequip(slot)
	if item:
		_set_held(item)


## Builds tooltip lines; with [param compare], adds what changes if it were worn.
func tooltip_lines_for(item: ItemInstance, compare := false) -> Array[Dictionary]:
	var character := items.character_snapshot() if items else {}
	if items:
		character = character.duplicate()
		character["attributes"] = items.total_attributes()
	var lines := item.tooltip_lines(character)
	if compare and item.is_gear() and items and not items.equipment.is_equipped(item):
		var worn := items.equipment.get_item(items.equipment.best_slot_for(item))
		var mine := item.get_stats()
		var theirs: Dictionary = worn.get_stats() if worn else {}
		var keys := {}
		for k in mine:
			keys[k] = true
		for k in theirs:
			keys[k] = true
		var diffs: Array[Dictionary] = []
		for k in keys:
			var d := float(mine.get(k, 0.0)) - float(theirs.get(k, 0.0))
			if absf(d) < 0.05:
				continue
			var text := ItemDefs.format_stat(k, absf(d))
			if d < 0.0:
				text = "-" + text.trim_prefix("+")
			diffs.append({"text": text, "color": InventoryStyle.GOOD if d > 0.0 else InventoryStyle.BAD})
		if not diffs.is_empty():
			lines.append({"text": "If worn instead%s:" % ("" if worn == null else " of " + worn.get_display_name()), "color": InventoryStyle.MUTED})
			lines.append_array(diffs)
	return lines


# --- Input ----------------------------------------------------------------------

## Esc closes this screen before anything else (such as GameUI's pause menu) sees it.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not handle_hotkey:
		return
	var toggle_pressed := false
	if InputMap.has_action(&"inventory"):
		toggle_pressed = event.is_action_pressed(&"inventory")
	elif event is InputEventKey:
		toggle_pressed = event.pressed and not event.echo and event.physical_keycode == KEY_I
	if toggle_pressed:
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# Clicks that reach the backdrop are outside the panel.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held:
			items.drop_item(held)
			_set_held(null)
		accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	if _cursor.visible:
		_cursor.position = get_local_mouse_position() - _cursor.size / 2.0
	if _tooltip.visible:
		_place_tooltip()
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message_label.text = ""


func _on_grid_pressed(cell: Vector2i, button: MouseButton) -> void:
	var item := items.inventory.item_at(cell)
	if button == MOUSE_BUTTON_LEFT:
		if held:
			put_in_bag(cell)
		elif item:
			pick_up_from_bag(item)
	elif button == MOUSE_BUTTON_RIGHT and held == null and item:
		activate_bag_item(item)
	_hide_tooltip()


func _on_slot_pressed(slot: StringName, button: MouseButton) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if held:
			put_in_slot(slot)
		else:
			take_from_slot(slot)
	elif button == MOUSE_BUTTON_RIGHT and held == null:
		items.unequip(slot)
	_hide_tooltip()


func _on_item_hovered(item: ItemInstance) -> void:
	_hover_item = item
	if item == null or held:
		_hide_tooltip()
		return
	_fill_box(_tooltip_box, tooltip_lines_for(item, false))
	_tooltip.visible = true
	var worn: ItemInstance = null
	if item.is_gear() and not items.equipment.is_equipped(item):
		worn = items.equipment.get_item(items.equipment.best_slot_for(item))
		_fill_box(_tooltip_box, tooltip_lines_for(item, true))
	_compare.visible = worn != null
	if worn:
		var worn_lines := tooltip_lines_for(worn)
		worn_lines.push_front({"text": "Worn now", "color": InventoryStyle.MUTED})
		_fill_box(_compare_box, worn_lines)
	_tooltip.reset_size()
	_compare.reset_size()
	_place_tooltip()


func _on_slot_hovered(_slot: StringName, item: ItemInstance) -> void:
	_on_item_hovered(item)


# --- Drawing ----------------------------------------------------------------------

func _refresh_any(_a = null) -> void:
	_refresh()


func _refresh() -> void:
	if items == null or _grid == null:
		return
	var character := items.character_snapshot().duplicate()
	character["attributes"] = items.total_attributes()
	var unmet := items.equipment.unmet_items(character)
	for slot in _slot_views:
		var view: ItemSlotView = _slot_views[slot]
		view.item = items.equipment.get_item(slot)
		view.unmet = view.item != null and unmet.has(view.item)
		view.highlight = held != null and held.is_gear() and held.get_base().allowed_slots().has(slot)
	_grid.held = held
	_grid.queue_redraw()
	_gold_label.text = "Gold: %d" % items.inventory.gold
	_stats_label.text = _stats_text()


func _stats_text() -> String:
	var g := items.get_gear_stats()
	var attrs := items.total_attributes()
	var lines: PackedStringArray = []
	var attr_parts: PackedStringArray = []
	for a in ItemDefs.ATTRIBUTES:
		var bonus := int(g.get(a, 0.0))
		attr_parts.append("%s %d%s" % [String(a).substr(0, 3).capitalize(), attrs[a], " (+%d)" % bonus if bonus > 0 else ""])
	lines.append("  ".join(attr_parts))
	lines.append("Armor %d   Spell power +%d%%   Cast speed +%d%%   Crit +%d%%" % [
		roundi(g.get(&"armor", 0.0)), roundi(g.get(&"spell_power", 0.0)),
		roundi(g.get(&"cast_speed", 0.0)), roundi(g.get(&"crit_chance", 0.0))])
	var res: PackedStringArray = []
	for r in ItemDefs.RESISTANCE_STATS:
		res.append("%s %d%%" % [String(r).trim_prefix("resist_").capitalize(), roundi(g.get(r, 0.0))])
	lines.append("Resist: " + "  ".join(res))
	var spells := items.equipment.spell_bonuses()
	if not spells.is_empty():
		var parts: PackedStringArray = []
		for s in spells:
			parts.append("+%d %s" % [spells[s], ItemDatabase.spell_display_name(s)])
		lines.append(", ".join(parts))
	return "\n".join(lines)


func _set_held(item: ItemInstance) -> void:
	held = item
	_cursor.visible = held != null
	_cursor.custom_minimum_size = Vector2(held.get_size()) * InventoryStyle.CELL if held else Vector2.ZERO
	_cursor.size = _cursor.custom_minimum_size
	_cursor.queue_redraw()
	_refresh()


func _return_held() -> void:
	if held == null:
		return
	var item := held
	_set_held(null)
	if items.inventory.add_item(item) != null:
		var slot := items.equipment.best_slot_for(item)
		if slot != &"" and items.equipment.get_item(slot) == null and items.check_equip(item, slot) == &"":
			items.equipment.equip(item, slot)
		else:
			items.drop_item(item)


func _is_usable(item: ItemInstance) -> bool:
	if not item.is_gear() or items == null:
		return true
	var character := items.character_snapshot().duplicate()
	character["attributes"] = items.total_attributes()
	return items.equipment.check_requirements(item, character) == &""


func _show_message(text: String) -> void:
	if _message_label:
		_message_label.text = text
		_message_time = 2.5


func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false
		_compare.visible = false


func _place_tooltip() -> void:
	var mouse := get_local_mouse_position()
	var pos := mouse + Vector2(18, 18)
	var view := get_viewport_rect().size
	if pos.x + _tooltip.size.x > view.x:
		pos.x = mouse.x - _tooltip.size.x - 12
	pos.y = clampf(pos.y, 0.0, maxf(view.y - _tooltip.size.y, 0.0))
	_tooltip.position = pos
	if _compare.visible:
		var cpos := Vector2(pos.x - _compare.size.x - 8, pos.y)
		if cpos.x < 0:
			cpos.x = pos.x + _tooltip.size.x + 8
		_compare.position = cpos


func _fill_box(box: VBoxContainer, lines: Array) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]["text"]
		l.add_theme_color_override("font_color", lines[i]["color"])
		l.add_theme_font_size_override("font_size", 18 if i == 0 else 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 260
		box.add_child(l)


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "Inventory"
	title.theme_type_variation = &"HeaderLabel"
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	outer.add_child(body)

	var doll := Control.new()
	doll.custom_minimum_size = Vector2(7, 8.25) * InventoryStyle.CELL
	body.add_child(doll)
	for slot in DOLL_LAYOUT:
		var l: Array = DOLL_LAYOUT[slot]
		var view := ItemSlotView.new(slot, Vector2i(l[2], l[3]))
		view.position = Vector2(l[0], l[1]) * InventoryStyle.CELL
		view.pressed.connect(_on_slot_pressed)
		view.hovered.connect(_on_slot_hovered)
		doll.add_child(view)
		_slot_views[slot] = view

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_grid = ItemGridView.new()
	_grid.cell_pressed.connect(_on_grid_pressed)
	_grid.item_hovered.connect(_on_item_hovered)
	right.add_child(_grid)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", InventoryStyle.GOLD_BRIGHT)
	right.add_child(_gold_label)
	_stats_label = Label.new()
	_stats_label.theme_type_variation = &"SubtleLabel"
	_stats_label.custom_minimum_size.x = 10 * InventoryStyle.CELL
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_stats_label)
	var hint := Label.new()
	hint.theme_type_variation = &"SubtleLabel"
	hint.text = "Left click: pick up and place.  Right click: drink, study or wear.  Click outside to drop."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 10 * InventoryStyle.CELL
	right.add_child(hint)
	_message_label = Label.new()
	_message_label.add_theme_color_override("font_color", InventoryStyle.BAD)
	right.add_child(_message_label)

	_tooltip = _make_tooltip()
	_tooltip_box = _tooltip.get_child(0)
	_compare = _make_tooltip()
	_compare_box = _compare.get_child(0)

	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	_cursor.draw.connect(func() -> void:
		if held:
			InventoryStyle.draw_item(_cursor, Rect2(Vector2.ZERO, _cursor.size), held))
	add_child(_cursor)


func _make_tooltip() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", InventoryStyle.panel_style(Color(0.05, 0.04, 0.07, 0.97), InventoryStyle.GOLD, 1, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	p.z_index = 10
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)
	add_child(p)
	return p
