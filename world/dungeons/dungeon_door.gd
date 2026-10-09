class_name DungeonDoor
extends StaticBody3D
## A locked iron gate across a doorway. It sinks into the floor when the
## player walks up holding its key (keys are tracked by the Dungeon node above
## it), and stays shut otherwise.

signal opened(door: DungeonDoor)

@export var lock_id := 0
@export var width := 4.0
@export var height := 3.4
@export var key_color := Color(1.0, 0.7, 0.35)

var is_open := false
var _gate: Node3D


func _ready() -> void:
	_build()
	var area := Area3D.new()
	area.name = "Reach"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.0, 4.0)
	shape.shape = box
	shape.position.y = 1.0
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if is_open or not body.is_in_group(&"player"):
		return
	var dungeon := Dungeon.find_for(self)
	if dungeon != null and dungeon.has_key(lock_id):
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	if is_inside_tree():
		create_tween().tween_property(_gate, "position:y", -height - 0.2, 0.8).set_ease(Tween.EASE_IN_OUT)
	opened.emit(self)


func _build() -> void:
	_gate = Node3D.new()
	_gate.name = "Gate"
	add_child(_gate)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.2, 0.22)
	iron.metallic = 0.6
	iron.roughness = 0.45
	var bars := maxi(5, int(width / 0.45))
	for i in bars:
		var x := lerpf(-width * 0.5 + 0.25, width * 0.5 - 0.25, float(i) / (bars - 1))
		_box(Vector3(0.1, height, 0.1), Vector3(x, height * 0.5, 0), iron)
	for y in [0.4, height * 0.5, height - 0.3]:
		_box(Vector3(width, 0.14, 0.14), Vector3(0, y, 0), iron)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = key_color
	glow.emission_enabled = true
	glow.emission = key_color
	glow.emission_energy_multiplier = 2.0
	_box(Vector3(0.5, 0.6, 0.2), Vector3(0, 1.3, 0), glow)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.3)
	collision.shape = shape
	collision.position.y = height * 0.5
	add_child(collision)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	_gate.add_child(instance)
