class_name DungeonKey
extends Area3D
## A floating, glowing key. Walking into it gives its key to the Dungeon node
## above it, which opens the matching locked door when the player reaches it.

@export var key_id := 0
@export var key_color := Color(1.0, 0.7, 0.35)

var _visual: Node3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	shape.position.y = 1.0
	add_child(shape)
	_build()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_visual.rotation.y += delta * 1.8
	_visual.position.y = 1.2 + sin(Time.get_ticks_msec() / 400.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	var dungeon := Dungeon.find_for(self)
	if dungeon != null:
		dungeon.add_key(key_id)
	queue_free()


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Key"
	add_child(_visual)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = key_color
	glow.emission_enabled = true
	glow.emission = key_color
	glow.emission_energy_multiplier = 3.0
	var ring := TorusMesh.new()
	ring.inner_radius = 0.12
	ring.outer_radius = 0.22
	ring.material = glow
	var bow := MeshInstance3D.new()
	bow.mesh = ring
	bow.rotation.x = PI * 0.5
	bow.position.y = 0.3
	_visual.add_child(bow)
	for part in [[Vector3(0.07, 0.5, 0.07), Vector3(0, -0.05, 0)], [Vector3(0.18, 0.07, 0.07), Vector3(0.08, -0.22, 0)], [Vector3(0.14, 0.07, 0.07), Vector3(0.06, -0.08, 0)]]:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mesh.material = glow
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = part[1]
		_visual.add_child(instance)
	var light := OmniLight3D.new()
	light.light_color = key_color
	light.light_energy = 0.8
	light.omni_range = 4.0
	_visual.add_child(light)
