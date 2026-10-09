class_name ItemSlotView
extends Control
## One equipment slot on the paper doll: an empty frame with the slot's name,
## or the worn item.

signal pressed(slot: StringName, button: MouseButton)
signal hovered(slot: StringName, item: ItemInstance)

var slot := &""
var item: ItemInstance:
	set(value):
		item = value
		queue_redraw()
## Glows when the held item could go here.
var highlight := false:
	set(value):
		highlight = value
		queue_redraw()
var unmet := false:
	set(value):
		unmet = value
		queue_redraw()
var _hover := false


func _init(p_slot := &"", cells := Vector2i(2, 2)) -> void:
	slot = p_slot
	custom_minimum_size = Vector2(cells) * InventoryStyle.CELL
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		pressed.emit(slot, event.button_index)
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			hovered.emit(slot, item)
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			hovered.emit(slot, null)
			queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, InventoryStyle.SLOT)
	if highlight:
		draw_rect(rect, Color(0.3, 0.8, 0.3, 0.2))
	if item:
		InventoryStyle.draw_item(self, rect, item, unmet)
	else:
		var font := ThemeDB.fallback_font
		var text: String = ItemDefs.SLOT_NAMES.get(slot, String(slot))
		if slot == &"main_hand":
			text = "Staff"
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2((size.x - w) / 2.0, size.y / 2.0 + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, InventoryStyle.MUTED)
	draw_rect(rect, InventoryStyle.GOLD_BRIGHT if _hover else InventoryStyle.GOLD_DIM, false, 2.0 if _hover else 1.0)
