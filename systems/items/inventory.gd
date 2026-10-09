class_name Inventory
extends RefCounted
## A Diablo-style bag: a grid where each item takes width x height cells, plus
## a gold count. Stackable items (potions, materials) merge into existing stacks.

signal changed
signal gold_changed(gold: int)

const DEFAULT_SIZE := Vector2i(10, 5)

var size := DEFAULT_SIZE
var gold := 0:
	set(value):
		gold = maxi(value, 0)
		gold_changed.emit(gold)
## Each entry: {"item": ItemInstance, "pos": Vector2i}.
var entries: Array[Dictionary] = []


func _init(p_size := DEFAULT_SIZE) -> void:
	size = p_size


func add_gold(amount: int) -> void:
	gold += amount


## Spends gold if there is enough.
func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	return true


## Adds an item, merging into stacks first, then placing it in the first free
## spot (column by column, as in Diablo 2). Gold goes to the gold count.
## Returns what did not fit (null if everything fit).
func add_item(item: ItemInstance) -> ItemInstance:
	if item == null:
		return null
	if item.get_kind() == ItemDefs.Kind.GOLD:
		add_gold(item.quantity)
		return null
	if item.get_max_stack() > 1:
		for e in entries:
			var other: ItemInstance = e["item"]
			if other.can_stack_with(item) and other.quantity < other.get_max_stack():
				var moved := mini(item.quantity, other.get_max_stack() - other.quantity)
				other.quantity += moved
				item.quantity -= moved
				if item.quantity <= 0:
					changed.emit()
					return null
	var pos := find_space(item.get_size())
	if pos.x < 0:
		changed.emit()
		return item
	entries.append({"item": item, "pos": pos})
	changed.emit()
	return null


## Places an item at a cell if the area is free. Returns false otherwise.
func place_at(item: ItemInstance, pos: Vector2i) -> bool:
	if not is_area_free(pos, item.get_size(), item):
		return false
	var existing := find_entry(item)
	if existing.is_empty():
		entries.append({"item": item, "pos": pos})
	else:
		existing["pos"] = pos
	changed.emit()
	return true


func remove_item(item: ItemInstance) -> bool:
	for i in entries.size():
		if entries[i]["item"] == item:
			entries.remove_at(i)
			changed.emit()
			return true
	return false


## Takes [param count] from a stack. Removes the item when it runs out.
func consume(item: ItemInstance, count := 1) -> void:
	item.quantity -= count
	if item.quantity <= 0:
		remove_item(item)
	else:
		changed.emit()


func has_item(item: ItemInstance) -> bool:
	return not find_entry(item).is_empty()


func find_entry(item: ItemInstance) -> Dictionary:
	for e in entries:
		if e["item"] == item:
			return e
	return {}


func get_position_of(item: ItemInstance) -> Vector2i:
	var e := find_entry(item)
	return e.get("pos", Vector2i(-1, -1))


func item_at(cell: Vector2i) -> ItemInstance:
	for e in entries:
		if Rect2i(e["pos"], e["item"].get_size()).has_point(cell):
			return e["item"]
	return null


## Items overlapping an area, ignoring [param ignore].
func items_in_area(pos: Vector2i, area: Vector2i, ignore: ItemInstance = null) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var rect := Rect2i(pos, area)
	for e in entries:
		if e["item"] != ignore and rect.intersects(Rect2i(e["pos"], e["item"].get_size())):
			out.append(e["item"])
	return out


func is_area_free(pos: Vector2i, area: Vector2i, ignore: ItemInstance = null) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x + area.x > size.x or pos.y + area.y > size.y:
		return false
	return items_in_area(pos, area, ignore).is_empty()


func find_space(area: Vector2i) -> Vector2i:
	for x in size.x - area.x + 1:
		for y in size.y - area.y + 1:
			if is_area_free(Vector2i(x, y), area):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func can_fit(item: ItemInstance) -> bool:
	if item.get_kind() == ItemDefs.Kind.GOLD:
		return true
	if item.get_max_stack() > 1:
		var room := 0
		for e in entries:
			if e["item"].can_stack_with(item):
				room += e["item"].get_max_stack() - e["item"].quantity
		if room >= item.quantity:
			return true
	return find_space(item.get_size()).x >= 0


func items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for e in entries:
		out.append(e["item"])
	return out


## Total count of a base across stacks.
func count_of(base_id: StringName) -> int:
	var n := 0
	for e in entries:
		if e["item"].base_id == base_id:
			n += e["item"].quantity
	return n


func clear() -> void:
	entries.clear()
	gold = 0
	changed.emit()


func to_dict() -> Dictionary:
	var list := []
	for e in entries:
		var d: Dictionary = e["item"].to_dict()
		d["x"] = e["pos"].x
		d["y"] = e["pos"].y
		list.append(d)
	return {"w": size.x, "h": size.y, "gold": gold, "items": list}


func apply_dict(d: Dictionary) -> void:
	entries.clear()
	size = Vector2i(int(d.get("w", DEFAULT_SIZE.x)), int(d.get("h", DEFAULT_SIZE.y)))
	for item_data in d.get("items", []):
		var item := ItemInstance.from_dict(item_data)
		if item.get_base() == null:
			push_warning("Inventory: dropping unknown item %s from save" % item.base_id)
			continue
		var pos := Vector2i(int(item_data.get("x", -1)), int(item_data.get("y", -1)))
		if is_area_free(pos, item.get_size()):
			entries.append({"item": item, "pos": pos})
		else:
			var free := find_space(item.get_size())
			if free.x >= 0:
				entries.append({"item": item, "pos": free})
	gold = int(d.get("gold", 0))
	changed.emit()
