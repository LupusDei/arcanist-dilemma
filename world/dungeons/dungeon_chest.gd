class_name DungeonChest
extends StaticBody3D
## A loot chest. Opens when the player walks up to it (or presses "interact"
## when the project has that action), tips its lid back and hands out loot
## through the same contract enemy drops use: the player's collect_loot(loot)
## if it has one, and on_loot_collected(loot, collector) on every node in the
## "loot_listeners" group.

signal opened(chest: DungeonChest, loot: Array[Dictionary])

const LISTENER_GROUP := &"loot_listeners"
const OPEN_RANGE := 1.8

@export_range(0, 2) var tier := 0
@export var level := 1
@export var loot_seed := 0

var is_open := false
var _lid: Node3D
var _player: Node3D


func _ready() -> void:
	_build()
	var area := Area3D.new()
	area.name = "Reach"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = OPEN_RANGE
	shape.shape = sphere
	area.add_child(shape)
	area.position.y = 0.5
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(func(body: Node3D) -> void:
		if body == _player:
			_player = null)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or is_open:
		return
	_player = body
	if not InputMap.has_action(&"interact"):
		open(body)


func _unhandled_input(event: InputEvent) -> void:
	if _player != null and not is_open and InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		open(_player)


func open(collector: Node = null) -> void:
	if is_open:
		return
	is_open = true
	var loot := DungeonLoot.roll(tier, level, loot_seed)
	if _lid != null and is_inside_tree():
		create_tween().tween_property(_lid, "rotation:x", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if collector != null and collector.has_method("collect_loot"):
		collector.collect_loot(loot)
	if is_inside_tree():
		get_tree().call_group(LISTENER_GROUP, "on_loot_collected", loot, collector)
	opened.emit(self, loot)


func _build() -> void:
	var wood := Color(0.5, 0.3, 0.16) if tier < 2 else Color(0.35, 0.18, 0.4)
	var band := Color(0.3, 0.28, 0.26) if tier == 0 else Color(0.9, 0.7, 0.25)
	var size := Vector3(1.2, 0.7, 0.8) * (1.0 + 0.15 * tier)
	_box(self, size, Vector3(0, size.y * 0.5, 0), wood)
	for x in [-0.35, 0.35]:
		_box(self, Vector3(0.1, size.y + 0.02, size.z + 0.04), Vector3(x * size.x, size.y * 0.5, 0), band)
	# The lid pivots on its back edge (local -Z).
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0, size.y, -size.z * 0.5)
	add_child(_lid)
	_box(_lid, Vector3(size.x + 0.04, 0.3, size.z + 0.04), Vector3(0, 0.15, size.z * 0.5), wood.lightened(0.08))
	_box(_lid, Vector3(0.22, 0.26, 0.08), Vector3(0, 0.02, size.z + 0.04), band)
	if tier > 0:
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.8, 0.35)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.75, 0.3)
		glow.emission_energy_multiplier = 1.5
		var gem := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.08
		mesh.height = 0.16
		mesh.material = glow
		gem.mesh = mesh
		gem.position = Vector3(0, 0.04, size.z + 0.1)
		_lid.add_child(gem)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + Vector3(0, 0.3, 0)
	collision.shape = shape
	collision.position.y = (size.y + 0.3) * 0.5
	add_child(collision)


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
