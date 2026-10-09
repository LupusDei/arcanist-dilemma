class_name EnemySpawner
extends Node3D
## Spawns a group of one enemy type around itself, relays their deaths and
## optionally respawns them. Enemies from one spawner form a pack.

signal enemy_spawned(enemy: Enemy)
signal enemy_died(enemy: Enemy, xp_value: int, loot: Array[Dictionary])
## Every enemy from the current wave is dead.
signal cleared

@export var enemy_scene: PackedScene
@export var count := 3
@export var spawn_radius := 3.0
@export var spawn_on_ready := true
## Seconds before a dead enemy is replaced (0 = never respawn).
@export var respawn_delay := 0.0
## Enemies from this spawner alert each other on aggro.
@export var as_pack := true

var alive: Array[Enemy] = []

var _spawned_total := 0


func _ready() -> void:
	if spawn_on_ready:
		spawn_all.call_deferred()


func spawn_all() -> void:
	while alive.size() < count:
		spawn_one()


func spawn_one() -> Enemy:
	if enemy_scene == null or not is_inside_tree():
		return null
	var enemy := enemy_scene.instantiate() as Enemy
	if as_pack:
		enemy.pack_id = get_instance_id()
	var angle := TAU * float(_spawned_total) / float(maxi(count, 1)) + randf_range(-0.3, 0.3)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * (spawn_radius if count > 1 else 0.0)
	_spawned_total += 1
	enemy.position = Vector3(offset.x, _ground_offset(offset), offset.z)
	add_child(enemy)
	alive.append(enemy)
	enemy.died.connect(_on_enemy_died)
	enemy_spawned.emit(enemy)
	return enemy


## Height above the spawner where the ground is at `offset`, so enemies don't
## spawn inside a slope.
func _ground_offset(offset: Vector3) -> float:
	var from := global_position + offset + Vector3.UP * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, 1)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return 0.1
	return result["position"].y - global_position.y + 0.1


func _on_enemy_died(enemy: Enemy, xp_value: int, loot: Array[Dictionary]) -> void:
	alive.erase(enemy)
	enemy_died.emit(enemy, xp_value, loot)
	if alive.is_empty():
		cleared.emit()
	if respawn_delay > 0.0:
		get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	if is_inside_tree() and alive.size() < count:
		spawn_one()
