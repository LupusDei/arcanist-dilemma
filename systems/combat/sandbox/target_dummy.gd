class_name TargetDummy
extends Node3D
## A practice target for the combat sandbox and tests: a capsule with a
## HealthComponent, a floating readout, knockback sliding and auto-respawn.

@export var max_health := 200.0
@export var armor := 0.0
@export var tier := HealthComponent.Tier.NORMAL
@export var resistances: Dictionary = {}
## Seconds after death before it stands back up. 0 never respawns.
@export var respawn_delay := 2.0

var health: HealthComponent
var last_damage := 0.0
var total_damage := 0.0

var _velocity := Vector3.ZERO
var _home := Vector3.ZERO
var _label: Label3D
var _material: StandardMaterial3D
var _respawn_timer := 0.0


func _ready() -> void:
	_home = position
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = max_health
	health.armor = armor
	health.tier = tier
	health.resistances = resistances
	health.team = &"enemy"
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.knocked_back.connect(func(impulse: Vector3) -> void: _velocity += impulse)
	health.died.connect(_on_died)
	_build_visual()


func _physics_process(delta: float) -> void:
	if not _velocity.is_zero_approx():
		position += Vector3(_velocity.x, 0.0, _velocity.z) * delta
		_velocity = _velocity.move_toward(Vector3.ZERO, 25.0 * delta)
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			reset()
	_update_label()


func reset() -> void:
	position = _home
	_velocity = Vector3.ZERO
	health.revive()
	total_damage = 0.0
	visible = true
	_material.albedo_color = Color(0.75, 0.65, 0.5)


func _on_damaged(_hit: Hit, amount: float) -> void:
	total_damage += amount
	if amount >= 1.0:  # Skip burn ticks in the readout.
		last_damage = amount


func _on_died(_killer: Node) -> void:
	_material.albedo_color = Color(0.3, 0.3, 0.3)
	if respawn_delay > 0.0:
		_respawn_timer = respawn_delay


func _build_visual() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.9
	body.mesh = capsule
	body.position.y = 0.95
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.75, 0.65, 0.5)
	body.material_override = _material
	add_child(body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.4
	_label.font_size = 48
	_label.outline_size = 8
	add_child(_label)
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var text := "%d / %d" % [ceili(health.health), roundi(health.max_health)]
	if health.ward > 0.0:
		text += "  (+%d ward)" % roundi(health.ward)
	for kind in health.statuses:
		text += "\n" + Status.name_of(kind)
	if last_damage > 0.0:
		text += "\n-%d" % roundi(last_damage)
	_label.text = text
