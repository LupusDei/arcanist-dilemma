extends Node3D
## Enemy test arena: three camps (brutes, hexlings, a hound pack) around a
## wall that forces pathing. Gives the player stand-in health and two debug
## attacks so the AI can be fought before the real combat system lands.
##
## Run: godot --path . res://actors/enemies/arena/enemy_arena.tscn

const BOLT_SCENE := preload("res://actors/enemies/core/enemy_projectile.tscn")
const BOLT_DAMAGE := 20.0
const NOVA_DAMAGE := 12.0
const NOVA_RADIUS := 5.0
const PLAYER_MAX_HEALTH := 150.0
const SPAWN_TABLE := preload("res://actors/enemies/types/default_spawn_table.tres")
const BIOMES: Array[StringName] = [&"meadow", &"forest", &"ruins", &"dungeon"]

var kills := 0
var xp := 0
var loot_totals := {}

var _player: Node3D
var _player_health: EnemyHealth
var _label: Label
var _message := ""
var _message_time := 0.0
var _generation := 0
var _generated: Node3D

@onready var _navigation: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	add_to_group(Enemy.LISTENER_GROUP)
	add_to_group(EnemyLootDrop.LISTENER_GROUP)
	_player = get_node_or_null("Player")
	if _player != null:
		_player_health = EnemyHealth.new()
		_player_health.name = EnemyDamage.HEALTH_NODE
		_player_health.max_health = PLAYER_MAX_HEALTH
		_player_health.team = &"player"
		_player.add_child(_player_health)
		_player_health.died.connect(_on_player_died)
	_build_hud()
	_bake_navigation.call_deferred()


func _bake_navigation() -> void:
	_navigation.bake_navigation_mesh(false)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	var bolt: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	if bolt:
		fire_bolt()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		nova()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		generate(randi())


## Debug attack: a bolt at the closest enemy in front of the camera.
func fire_bolt() -> void:
	var target := _pick_target()
	var from := _player.global_position + Vector3.UP * 1.3
	var aim: Vector3
	if target != null:
		aim = target.global_position + Vector3.UP * 0.8
	else:
		aim = from + _camera_forward() * 10.0
	var bolt := BOLT_SCENE.instantiate() as EnemyProjectile
	bolt.collision_mask = 1 | Enemy.BODY_LAYER
	add_child(bolt)
	bolt.launch(from, aim, _player, BOLT_DAMAGE, 22.0)


## Debug attack: damages every enemy close to the player.
func nova() -> void:
	for node in get_tree().get_nodes_in_group(Enemy.ENEMY_GROUP):
		var enemy := node as Enemy
		if enemy.global_position.distance_to(_player.global_position) <= NOVA_RADIUS:
			EnemyDamage.apply(enemy, NOVA_DAMAGE, _player)
	_flash("Nova!")


## Replaces the hand-placed camps with a population rolled from the default
## spawn table, cycling through biomes, the way a world generator would.
func generate(area_seed: int) -> Array[EnemySpawner]:
	for child in get_children():
		if child is EnemySpawner:
			child.queue_free()
	var request := EnemySpawnRequest.new()
	request.area_seed = area_seed
	request.biome = BIOMES[_generation % BIOMES.size()]
	request.level_min = 1 + _generation
	request.level_max = 3 + _generation
	request.area_size = Vector2(44, 44)
	request.density = 4.0
	request.min_spacing = 9.0
	request.elite_chance = 0.25
	request.exclusion_zones = PackedVector3Array([Vector3(_player.global_position.x, _player.global_position.z, 10.0)])
	_generation += 1
	var spawners := EnemyPopulator.populate(self, SPAWN_TABLE, request)
	_flash("Generated %d groups: %s, levels %d-%d" % [spawners.size(), request.biome, request.level_min, request.level_max])
	return spawners


func on_enemy_died(enemy: Enemy, xp_value: int, _loot: Array[Dictionary]) -> void:
	kills += 1
	xp += xp_value
	_flash("%s slain  +%d XP" % [enemy.display_title(), xp_value])


func on_loot_collected(loot: Array[Dictionary], _collector: Node3D) -> void:
	var parts: PackedStringArray = []
	for drop in loot:
		loot_totals[drop["id"]] = loot_totals.get(drop["id"], 0) + drop["count"]
		parts.append("%d %s" % [drop["count"], drop["id"]])
	_flash("Picked up " + ", ".join(parts))


func _process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	if _label == null:
		return
	var loot_parts: PackedStringArray = []
	for id in loot_totals:
		loot_parts.append("%s %d" % [id, loot_totals[id]])
	var hp := "-"
	if _player_health != null:
		hp = "%d / %d" % [ceili(_player_health.current_health), ceili(_player_health.max_health)]
	_label.text = "ENEMY ARENA\nHP %s    XP %d    Kills %d\nLoot: %s\n\nF / left click: arcane bolt    G: nova    N: generate new monsters    Esc: free mouse\n%s" % [
		hp, xp, kills, ", ".join(loot_parts) if not loot_parts.is_empty() else "none",
		_message if _message_time > 0.0 else ""]


func _on_player_died(_killer: Node) -> void:
	_flash("You were defeated. Respawning.")
	if _player.has_method("respawn"):
		_player.respawn()
	_player_health.reset()


func _pick_target() -> Enemy:
	var forward := _camera_forward()
	var best: Enemy
	var best_score := INF
	for node in get_tree().get_nodes_in_group(Enemy.ENEMY_GROUP):
		var enemy := node as Enemy
		var to_enemy := enemy.global_position - _player.global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > 25.0 or distance < 0.01:
			continue
		var alignment := forward.dot(to_enemy / distance)
		if alignment < 0.5:
			continue
		var score := distance * (2.0 - alignment)
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _camera_forward() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z if camera != null else Vector3.FORWARD
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _flash(text: String) -> void:
	_message = text
	_message_time = 3.0


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
