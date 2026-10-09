class_name ItemGridView
extends Control
## Draws an Inventory as a grid of cells and reports clicks and hovers.
## While the screen holds an item on the cursor, it shows where it would land.

signal cell_pressed(cell: Vector2i, button: MouseButton)
signal item_hovered(item: ItemInstance)

var inventory: Inventory
## The item on the cursor, if any (for the placement preview).
var held: ItemInstance
var hovered_cell := Vector2i(-1, -1)
## Returns false for items the character cannot use (drawn with a red tint).
var usable_check: Callable


func bind(p_inventory: Inventory) -> void:
	if inventory and inventory.changed.is_connected(queue_redraw):
		inventory.changed.disconnect(queue_redraw)
	inventory = p_inventory
	inventory.changed.connect(queue_redraw)
	custom_minimum_size = Vector2(inventory.size) * InventoryStyle.CELL
	queue_redraw()


## Top-left cell the held item would take with the mouse at [param cell].
func drop_origin(cell: Vector2i, item: ItemInstance) -> Vector2i:
	var s := item.get_size()
	return cell - Vector2i((s.x - 1) / 2, (s.y - 1) / 2)


func cell_at(local: Vector2) -> Vector2i:
	var c := Vector2i(floori(local.x / InventoryStyle.CELL), floori(local.y / InventoryStyle.CELL))
	if inventory == null or c.x < 0 or c.y < 0 or c.x >= inventory.size.x or c.y >= inventory.size.y:
		return Vector2i(-1, -1)
	return c


func _gui_input(event: InputEvent) -> void:
	if inventory == null:
		return
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != hovered_cell:
			hovered_cell = c
			item_hovered.emit(inventory.item_at(c) if c.x >= 0 else null)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var c := cell_at(event.position)
		if c.x >= 0:
			cell_pressed.emit(c, event.button_index)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hovered_cell = Vector2i(-1, -1)
		item_hovered.emit(null)
		queue_redraw()


func _draw() -> void:
	if inventory == null:
		return
	var cell := float(InventoryStyle.CELL)
	draw_rect(Rect2(Vector2.ZERO, Vector2(inventory.size) * cell), InventoryStyle.SLOT)
	for x in inventory.size.x:
		for y in inventory.size.y:
			draw_rect(Rect2(Vector2(x, y) * cell, Vector2(cell, cell)).grow(-1), Color(0.1, 0.09, 0.12, 0.9))
	if held and hovered_cell.x >= 0:
		var origin := drop_origin(hovered_cell, held)
		var rect := Rect2(Vector2(origin) * cell, Vector2(held.get_size()) * cell)
		var overlapping := inventory.items_in_area(origin, held.get_size())
		var fits := inventory.is_area_free(origin, held.get_size(), overlapping[0] if overlapping.size() == 1 else null)
		draw_rect(rect, Color(0.3, 0.8, 0.3, 0.25) if fits else Color(0.9, 0.2, 0.2, 0.25))
	elif hovered_cell.x >= 0:
		var item := inventory.item_at(hovered_cell)
		if item:
			draw_rect(Rect2(Vector2(inventory.get_position_of(item)) * cell, Vector2(item.get_size()) * cell), Color(1, 0.9, 0.6, 0.12))
	for e in inventory.entries:
		var item: ItemInstance = e["item"]
		var rect := Rect2(Vector2(e["pos"]) * cell, Vector2(item.get_size()) * cell)
		var usable: bool = usable_check.is_null() or usable_check.call(item)
		InventoryStyle.draw_item(self, rect, item, not usable)
	draw_rect(Rect2(Vector2.ZERO, Vector2(inventory.size) * cell), InventoryStyle.GOLD_DIM, false, 2.0)
