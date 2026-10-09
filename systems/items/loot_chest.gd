class_name LootChest
extends StaticBody3D
## A chest that rolls the loot tables once when opened. Dungeon and world
## generators place it and set the seed, biome and level:
##
##   var chest := LootChest.new()
##   chest.loot_seed = hash([dungeon_seed, room_index])
##   chest.biome = &"dungeon"; chest.level = 6; chest.source = &"chest_large"
##   room.add_child(chest)
##
## The player opens it by walking up and pressing the "interact" action (E if
## the action does not exist), or by touch when open_on_touch is set.
## Same seed, same loot.

signal opened(items: Array[ItemInstance])

@export var loot_seed := 0
@export var biome := &"dungeon"
@export_range(1, 60) var level := 1
## &"chest" or &"chest_large" (see res://data/items/loot.json).
@export var source := &"chest"
@export var open_on_touch := false
@export var interact_range := 2.2

var is_open := false
var _lid: Node3D
var _player_near := false


func _ready() -> void:
	add_to_group(&"loot_chests")
	_build()


func _process(_delta: float) -> void:
	if is_open:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	_player_near = player != null and player.global_position.distance_to(global_position) <= interact_range
	if _player_near and open_on_touch:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if is_open or not _player_near:
		return
	var pressed := false
	if InputMap.has_action(&"interact"):
		pressed = event.is_action_pressed(&"interact")
	elif event is InputEventKey:
		pressed = event.pressed and not event.echo and event.physical_keycode == KEY_E
	if pressed:
		open()
		get_viewport().set_input_as_handled()


## The items this chest holds. Rolling again gives the same list.
func roll_contents() -> Array[ItemInstance]:
	return LootRoller.roll(source, biome, level, LootRoller.rng_for(loot_seed, &"chest"))


func open() -> Array[ItemInstance]:
	if is_open:
		return []
	is_open = true
	var items := roll_contents()
	if _lid:
		create_tween().tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK)
	var service := get_node_or_null(^"/root/Items")
	if service:
		service.spawn_drops(items, global_position + global_basis.z * 1.0, get_parent())
	else:
		for i in items.size():
			ItemPickup.spawn(items[i], get_parent(), global_position + Vector3(cos(i * 1.3), 0, sin(i * 1.3)) * 1.2)
	opened.emit(items)
	return items


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.14) if source == &"chest" else Color(0.3, 0.2, 0.32)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.78, 0.62, 0.34)
	trim.metallic = 0.7
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.55, 0.65)
	body.mesh = box
	body.position.y = 0.275
	body.material_override = wood
	add_child(body)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, -0.325)
	add_child(_lid)
	var lid := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(1.04, 0.18, 0.67)
	lid.mesh = lid_box
	lid.position = Vector3(0, 0.09, 0.335)
	lid.material_override = trim if source == &"chest_large" else wood
	_lid.add_child(lid)
	var band := MeshInstance3D.new()
	var band_box := BoxMesh.new()
	band_box.size = Vector3(1.02, 0.08, 0.67)
	band.mesh = band_box
	band.position.y = 0.45
	band.material_override = trim
	add_child(band)
	var shape := CollisionShape3D.new()
	var col := BoxShape3D.new()
	col.size = Vector3(1.0, 0.7, 0.65)
	shape.shape = col
	shape.position.y = 0.35
	add_child(shape)
