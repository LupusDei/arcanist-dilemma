class_name EnemyLootDrop
extends Area3D
## Glowing pickup left by a dead enemy. Walking into it collects the loot.
##
## Collectors: the body's collect_loot(loot) is called if it has one, and nodes
## in the "loot_listeners" group get on_loot_collected(loot, collector).

signal collected(loot: Array[Dictionary], collector: Node3D)

const LISTENER_GROUP := &"loot_listeners"

@export var collector_group: StringName = &"player"
## Lets the drop pop out before it can be picked up.
@export var pickup_delay := 0.4

var loot: Array[Dictionary] = []

var _age := 0.0
var _taken := false

@onready var _gem: Node3D = $Gem


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_gem.scale = Vector3.ONE * 0.1
	create_tween().tween_property(_gem, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _physics_process(delta: float) -> void:
	_age += delta
	_gem.rotation.y += delta * 2.0
	_gem.position.y = 0.35 + sin(_age * 3.0) * 0.08
	if _age >= pickup_delay and not _taken:
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func _on_body_entered(body: Node3D) -> void:
	if _taken or _age < pickup_delay or not body.is_in_group(collector_group):
		return
	_taken = true
	if body.has_method("collect_loot"):
		body.collect_loot(loot)
	collected.emit(loot, body)
	get_tree().call_group(LISTENER_GROUP, "on_loot_collected", loot, body)
	queue_free()
