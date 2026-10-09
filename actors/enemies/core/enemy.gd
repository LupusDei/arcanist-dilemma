class_name Enemy
extends CharacterBody3D
## Diablo-style monster brain: a small state machine on top of a CharacterBody3D.
##
##   IDLE   wanders near home until the player comes inside aggro_range
##   AGGRO  short alert pause (and wakes the pack) so the player sees it coming
##   CHASE  closes in (melee) or holds a firing distance (ranged)
##   ATTACK telegraphed windup, then the hit lands or the projectile flies
##   FLEE   runs away once when health drops below flee_health_fraction
##   RETURN leashed: walks home, heals to full, goes back to IDLE
##   DEAD   emits died(enemy, xp_value, loot), drops loot, sinks and frees
##
## Health lives on the "HealthComponent" child (see EnemyHealth). Anything that
## damages that component, a spell or a projectile, makes the enemy react.
## Tuning lives in an EnemyData resource.

signal state_changed(previous: State, current: State)
## Fired when an attack resolves: a melee swing that connected, or a projectile launched.
signal attacked(target: Node3D, damage: float)
signal died(enemy: Enemy, xp_value: int, loot: Array[Dictionary])

enum State { IDLE, AGGRO, CHASE, ATTACK, FLEE, RETURN, DEAD }

const ENEMY_GROUP := &"enemies"
## Nodes in this group get on_enemy_died(enemy, xp_value, loot) for every kill,
## so progression or UI can listen without knowing about spawners.
const LISTENER_GROUP := &"enemy_listeners"
## Physics layer 3: enemies don't block the player's camera spring arm (layer 1).
const BODY_LAYER := 1 << 2
const LOOT_DROP_SCENE := preload("res://actors/enemies/core/enemy_loot_drop.tscn")

@export var data: EnemyData
@export var target_group: StringName = &"player"
## Enemies with the same non-zero pack id alert each other. Spawners set it.
@export var pack_id := 0
@export var drop_loot := true
## Monster level; health, damage and XP grow with it (see EnemyData's Scaling group).
@export_range(1, 60) var level := 1
## Elites are bigger and tougher and give more XP and loot.
@export var elite := false
@export var show_debug_label := true

var state: State = State.IDLE
var target: Node3D
var home_position: Vector3
var health_current := 0.0
var health_max := 0.0
## Level- and elite-scaled values, set in _ready. Use these, not the raw data.
var max_health := 0.0
var attack_damage := 0.0
var xp_value := 0
var rng := RandomNumberGenerator.new()

var _state_time := 0.0
var _attack_cooldown_remaining := 0.0
var _attack_resolved := false
var _has_fled := false
var _wander_point := Vector3.ZERO
var _wander_wait := 0.0
var _knockback := Vector3.ZERO
var _last_nav_target := Vector3.INF
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var health: Node = $HealthComponent
@onready var _model: Node3D = $Model
@onready var _nav: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
@onready var _muzzle: Node3D = get_node_or_null("Model/Muzzle")
@onready var _label: Label3D = get_node_or_null("DebugLabel")


func _ready() -> void:
	assert(data != null, "%s has no EnemyData" % name)
	add_to_group(ENEMY_GROUP)
	collision_layer = BODY_LAYER
	collision_mask = 1 | BODY_LAYER
	rng.randomize()
	home_position = global_position
	_wander_point = home_position
	_wander_wait = rng.randf_range(0.0, data.wander_pause_max)

	_apply_scaling()
	health.set("max_health", max_health)
	health.set("armor", data.armor)
	if elite:
		health.set("tier", 1) # HealthComponent tier ELITE
	health.set("team", &"enemy")
	if health.has_method("reset"):
		health.reset()
	health_current = max_health
	health_max = max_health
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if health.has_signal("knocked_back"):
		health.knocked_back.connect(_on_knocked_back)

	if _nav != null:
		_nav.path_desired_distance = 0.6
		_nav.target_desired_distance = 0.6
	if _label != null:
		_label.visible = show_debug_label
	_update_label()


func _physics_process(delta: float) -> void:
	_state_time += delta
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

	var desired := Vector3.ZERO
	if state != State.DEAD:
		if not _is_valid_target(target):
			target = _find_target()
		if not _is_stunned():
			desired = _tick_state(delta)

	_knockback = _knockback.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.x = desired.x + _knockback.x
	velocity.z = desired.z + _knockback.z
	if not is_on_floor():
		velocity.y -= _gravity * 2.0 * delta
	move_and_slide()
	_update_label()


func is_dead() -> bool:
	return state == State.DEAD


## Wakes this enemy up against `new_target`, e.g. from a packmate.
func alert(new_target: Node3D) -> void:
	if state in [State.IDLE, State.RETURN] and _is_valid_target(new_target):
		target = new_target
		_set_state(State.AGGRO)


func distance_to_target() -> float:
	if not _is_valid_target(target):
		return INF
	return _flat(target.global_position - global_position).length()


# --- States -----------------------------------------------------------------

func _tick_state(delta: float) -> Vector3:
	match state:
		State.IDLE:
			return _tick_idle(delta)
		State.AGGRO:
			if not _is_valid_target(target):
				_set_state(State.RETURN)
				return Vector3.ZERO
			_face_point(target.global_position, delta)
			if _state_time >= data.aggro_delay:
				_set_state(State.CHASE)
		State.CHASE:
			return _tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.FLEE:
			return _tick_flee(delta)
		State.RETURN:
			return _tick_return(delta)
	return Vector3.ZERO


func _tick_idle(delta: float) -> Vector3:
	if distance_to_target() <= data.aggro_range:
		_set_state(State.AGGRO)
		_alert_pack()
		return Vector3.ZERO
	if data.wander_radius <= 0.0:
		return Vector3.ZERO
	if _flat(_wander_point - global_position).length() < 0.6:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			var angle := rng.randf() * TAU
			_wander_point = home_position + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.5, data.wander_radius)
			_wander_wait = rng.randf_range(data.wander_pause_min, data.wander_pause_max)
		return Vector3.ZERO
	return _move_toward(_wander_point, data.move_speed * 0.4, delta)


func _tick_chase(delta: float) -> Vector3:
	if _should_leash():
		_set_state(State.RETURN)
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	var distance := to_target.length()
	var ranged := data.attack_style == EnemyData.AttackStyle.RANGED
	if ranged and distance < data.keep_away_distance:
		var retreat := global_position - to_target.normalized() * 3.0
		var away := _move_toward(retreat, data.move_speed, delta)
		_face_point(target.global_position, delta)
		return away
	if distance <= data.attack_range:
		_face_point(target.global_position, delta)
		if _attack_cooldown_remaining <= 0.0:
			_set_state(State.ATTACK)
		return Vector3.ZERO
	return _move_toward(target.global_position, data.move_speed, delta)


func _tick_attack(delta: float) -> void:
	var progress := clampf(_state_time / maxf(data.attack_windup, 0.01), 0.0, 1.0)
	# Track the target for most of the windup, then commit so a sidestep works.
	if progress < 0.7 and _is_valid_target(target):
		_face_point(target.global_position, delta)
	if not _attack_resolved:
		_model.scale = Vector3.ONE.lerp(Vector3(1.15, 0.85, 1.15), progress)
		if _state_time >= data.attack_windup:
			_attack_resolved = true
			_model.scale = Vector3(0.95, 1.1, 0.95)
			_resolve_attack()
	elif _state_time >= data.attack_windup + data.attack_recovery:
		_model.scale = Vector3.ONE
		_attack_cooldown_remaining = data.attack_cooldown
		_set_state(State.CHASE)


func _tick_flee(delta: float) -> Vector3:
	if _state_time >= data.flee_duration:
		_set_state(State.CHASE if _is_valid_target(target) else State.RETURN)
		return Vector3.ZERO
	var away := Vector3.FORWARD
	if _is_valid_target(target):
		away = _flat(global_position - target.global_position)
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	return _move_toward(global_position + away.normalized() * 4.0, data.move_speed * data.retreat_speed_multiplier, delta)


func _tick_return(delta: float) -> Vector3:
	if _flat(home_position - global_position).length() < 1.0:
		if health.has_method("reset"):
			health.reset()
		_has_fled = false
		_wander_point = home_position
		_set_state(State.IDLE)
		return Vector3.ZERO
	return _move_toward(home_position, data.move_speed * data.retreat_speed_multiplier, delta)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var previous := state
	state = new_state
	_state_time = 0.0
	if new_state == State.ATTACK:
		_attack_resolved = false
	elif previous == State.ATTACK:
		_model.scale = Vector3.ONE
	state_changed.emit(previous, new_state)


# --- Combat -----------------------------------------------------------------

func _resolve_attack() -> void:
	if not _is_valid_target(target):
		return
	if data.attack_style == EnemyData.AttackStyle.RANGED:
		_fire_projectile()
		attacked.emit(target, attack_damage)
	elif distance_to_target() <= data.attack_range + 0.6:
		if EnemyDamage.apply(target, attack_damage, self):
			attacked.emit(target, attack_damage)


func _fire_projectile() -> void:
	if data.projectile_scene == null:
		push_warning("%s is ranged but has no projectile_scene" % name)
		return
	var projectile := data.projectile_scene.instantiate() as EnemyProjectile
	get_parent().add_child(projectile)
	var from := _muzzle.global_position if _muzzle else global_position + Vector3.UP * 1.2
	var aim := target.global_position + Vector3.UP * 1.0
	projectile.launch(from, aim, self, attack_damage, data.projectile_speed)


func _alert_pack() -> void:
	if data.pack_alert_radius <= 0.0:
		return
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var other := node as Enemy
		if other == null or other == self:
			continue
		var same_pack := other.pack_id == pack_id if pack_id != 0 else other.data == data
		if same_pack and other.global_position.distance_to(global_position) <= data.pack_alert_radius:
			other.alert(target)


func _on_health_changed(current: float, maximum: float) -> void:
	health_current = current
	health_max = maximum


func _on_damaged(hit: Object, _amount: float) -> void:
	if state == State.DEAD:
		return
	var source: Variant = hit.get("source") if hit != null else null
	if source is Node3D and is_instance_valid(source) and (source as Node).is_in_group(target_group):
		target = source
	_flinch()
	if state in [State.IDLE, State.RETURN] and _is_valid_target(target):
		_set_state(State.AGGRO)
		_alert_pack()
	# Deferred so health_changed has updated health_current, whichever order
	# the health component emits its signals in.
	_check_flee.call_deferred()


func _check_flee() -> void:
	if state == State.DEAD or data.flee_health_fraction <= 0.0 or _has_fled or health_max <= 0.0:
		return
	if health_current > 0.0 and health_current / health_max <= data.flee_health_fraction:
		_has_fled = true
		_set_state(State.FLEE)


func _on_knocked_back(impulse: Vector3) -> void:
	_knockback += _flat(impulse)
	velocity.y += impulse.y


func _on_died(_killer: Node) -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	remove_from_group(ENEMY_GROUP)
	collision_layer = 0
	collision_mask = 1
	var loot: Array[Dictionary] = []
	if data.loot_table != null:
		loot = data.loot_table.roll(rng)
		if elite:
			loot.append_array(data.loot_table.roll(rng))
	died.emit(self, xp_value, loot)
	get_tree().call_group(LISTENER_GROUP, "on_enemy_died", self, xp_value, loot)
	if drop_loot and not loot.is_empty() and get_parent() != null:
		var drop := LOOT_DROP_SCENE.instantiate() as EnemyLootDrop
		drop.loot = loot
		get_parent().add_child(drop)
		drop.global_position = global_position + Vector3.UP * 0.3
	_play_death()


# --- Helpers ----------------------------------------------------------------

func _apply_scaling() -> void:
	var steps := float(level - 1)
	max_health = data.max_health * (1.0 + data.health_per_level * steps)
	attack_damage = data.attack_damage * (1.0 + data.damage_per_level * steps)
	xp_value = roundi(data.xp_value * (1.0 + data.xp_per_level * steps))
	if elite:
		max_health *= data.elite_health_multiplier
		attack_damage *= data.elite_damage_multiplier
		xp_value *= data.elite_xp_multiplier
		_grow(data.elite_model_scale)


## Makes the enemy bigger: the model through a wrapper node (so the flinch and
## windup tweens on Model keep working) and the collision capsule by resizing it.
func _grow(factor: float) -> void:
	var wrapper := Node3D.new()
	wrapper.name = "ModelRoot"
	remove_child(_model)
	add_child(wrapper)
	wrapper.add_child(_model)
	wrapper.scale = Vector3.ONE * factor
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D if shape_node != null else null
	if capsule != null:
		capsule = capsule.duplicate()
		capsule.radius *= factor
		capsule.height *= factor
		shape_node.shape = capsule
		shape_node.position *= factor
	if _label != null:
		_label.position *= factor


## Desired horizontal velocity toward `point`, following the navmesh when one exists.
func _move_toward(point: Vector3, speed: float, delta: float) -> Vector3:
	var to_point := _flat(point - global_position)
	if to_point.length() < 0.1:
		return Vector3.ZERO
	var direction := to_point.normalized()
	if _nav != null and _navigation_ready():
		if point.distance_squared_to(_last_nav_target) > 0.25:
			_nav.target_position = point
			_last_nav_target = point
		var step := _flat(_nav.get_next_path_position() - global_position)
		if step.length() > 0.05:
			direction = step.normalized()
	_face_point(global_position + direction, delta)
	return direction * speed * _speed_multiplier()


func _navigation_ready() -> bool:
	var map := _nav.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
		and not NavigationServer3D.map_get_regions(map).is_empty()


func _face_point(point: Vector3, delta: float) -> void:
	var direction := _flat(point - global_position)
	if direction.length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, yaw, 1.0 - exp(-10.0 * delta))


func _should_leash() -> bool:
	if not _is_valid_target(target):
		return true
	return _flat(target.global_position - home_position).length() > data.leash_range


func _find_target() -> Node3D:
	var candidate := get_tree().get_first_node_in_group(target_group) as Node3D
	return candidate if _is_valid_target(candidate) else null


func _is_valid_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	var target_health := EnemyDamage.find_health(node)
	if target_health == null:
		return true
	# EnemyHealth has is_dead(); combat's HealthComponent has an is_dead property.
	if target_health.has_method("is_dead"):
		return not target_health.is_dead()
	return not target_health.get("is_dead")


func _is_stunned() -> bool:
	return health.has_method("is_stunned") and health.is_stunned()


func _speed_multiplier() -> float:
	return health.get_move_speed_multiplier() if health.has_method("get_move_speed_multiplier") else 1.0


func _flinch() -> void:
	if state == State.ATTACK:
		return
	var tween := create_tween()
	_model.scale = Vector3(1.2, 0.8, 1.2)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.15)


func _play_death() -> void:
	if _label != null:
		_label.visible = false
	var tween := create_tween()
	tween.tween_property(_model, "rotation:z", deg_to_rad(80.0), 0.35).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(0.8)
	tween.tween_property(_model, "position:y", -1.5, 0.8)
	tween.tween_callback(queue_free)


func _update_label() -> void:
	if _label == null or not _label.visible:
		return
	_label.text = "%s\n%d / %d\n%s" % [display_title(), ceili(health_current), ceili(health_max), State.keys()[state]]


## "Elite Bramble Brute (Lv 4)" style name for labels and UI.
func display_title() -> String:
	return "%s%s (Lv %d)" % ["Elite " if elite else "", data.display_name, level]


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
