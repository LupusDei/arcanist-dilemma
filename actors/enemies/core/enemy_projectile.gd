class_name EnemyProjectile
extends Area3D
## A slow, visible bolt that flies straight and damages the first damageable body it hits.
## Dodging through it (player.is_invulnerable) lets it pass harmlessly.

signal hit(body: Node3D)

@export var lifetime := 3.0

var damage := 8.0
var speed := 14.0
var direction := Vector3.FORWARD
var source: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(from: Vector3, toward: Vector3, p_source: Node3D, p_damage: float, p_speed: float) -> void:
	global_position = from
	source = p_source
	damage = p_damage
	speed = p_speed
	direction = (toward - from).normalized()
	if direction.length_squared() < 0.5:
		direction = Vector3.FORWARD
	look_at(from + direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == source:
		return
	if body.get("is_invulnerable") == true:
		return
	var attacker: Node3D = source if is_instance_valid(source) else null
	EnemyDamage.apply(body, damage, attacker)
	hit.emit(body)
	queue_free()
