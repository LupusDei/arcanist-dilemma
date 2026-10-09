class_name QuestArea
extends Area3D
## A named place quests can send the player to ("reach" objectives) or that
## casting objectives need ("where"). Reports the player walking in and out.
## Give it a CollisionShape3D child, or set [member size] and one is made.

@export var area_id: StringName
## Box size for the generated shape when the area has no CollisionShape3D child.
@export var size := Vector3(6, 4, 6)

var _manager: QuestManager


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not _has_shape():
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y * 0.5
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and _get_manager():
		_manager.notify_reached(area_id)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and _get_manager():
		_manager.notify_left(area_id)


func _get_manager() -> QuestManager:
	if _manager == null:
		_manager = QuestManager.find(get_tree())
	return _manager


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape3D:
			return true
	return false
