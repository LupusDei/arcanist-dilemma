class_name Player
extends CharacterBody3D
## Third-person arcanist controller: camera-relative running, jumping and dodging.
##
## The body itself never rotates. The Model node turns to face movement, and the
## CameraPivot yaws/pitches independently, so movement is always relative to the camera.

signal dodged
signal died
signal respawned

@export_group("Movement")
@export var run_speed := 6.5
@export var ground_acceleration := 45.0
@export var ground_deceleration := 55.0
@export var air_acceleration := 14.0
@export var turn_speed := 14.0

@export_group("Jump")
@export var jump_velocity := 8.0
@export var gravity_multiplier := 2.0
## Extra gravity while falling, for a snappier arc.
@export var fall_multiplier := 1.6
## Upward velocity is scaled by this when jump is released early (short hop).
@export var jump_cut_multiplier := 0.5
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Dodge")
@export var dodge_speed := 16.0
@export var dodge_duration := 0.22
@export var dodge_cooldown := 0.6

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 3.0
@export_range(-89.0, 0.0) var min_pitch_degrees := -70.0
@export_range(0.0, 89.0) var max_pitch_degrees := 35.0

@export_group("Safety")
@export var kill_height := -20.0
@export var respawn_delay := 3.0

var is_dodging := false
var is_dead := false
## Set during a dodge. Nothing reads it yet; combat will.
var is_invulnerable := false
var dodge_cooldown_remaining := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _coyote_remaining := 0.0
var _jump_buffer_remaining := 0.0
var _dodge_remaining := 0.0
var _dodge_direction := Vector3.ZERO
var _air_dodge_available := true
var _spawn_transform: Transform3D

@onready var _model: Node3D = $Model
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
## Combat parts are optional so the controller also works on its own.
@onready var _health: Node = get_node_or_null(^"HealthComponent")
@onready var _caster: Node = get_node_or_null(^"SpellCaster")


func _ready() -> void:
	add_to_group("player")
	_spawn_transform = global_transform
	_spring_arm.add_excluded_object(get_rid())
	_camera_pivot.rotation.x = deg_to_rad(-15.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _health != null:
		_health.knocked_back.connect(func(impulse: Vector3) -> void: velocity += impulse)
		_health.died.connect(func(_killer: Node) -> void: _die())
	if _caster != null:
		# Turn to face where the spell is going.
		_caster.cast_started.connect(func(_spell: Resource, _time: float) -> void: _face_camera())
		_caster.spell_cast.connect(func(_spell: Resource) -> void: _face_camera())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_rotate_camera(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("reset"):
		respawn()


func _physics_process(delta: float) -> void:
	_rotate_camera_with_stick(delta)
	if is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	_tick_timers(delta)

	if is_on_floor():
		_coyote_remaining = coyote_time
		_air_dodge_available = true

	var wish_direction := _get_wish_direction()

	if Input.is_action_just_pressed("dodge") and not _is_held():
		_try_start_dodge(wish_direction)

	if is_dodging:
		_process_dodge(delta)
	else:
		_apply_gravity(delta)
		_process_jump()
		_process_run(wish_direction, delta)
		_face_direction(wish_direction, delta)

	move_and_slide()

	if global_position.y < kill_height:
		respawn()


## Makes the current position the respawn point (after a scene places the player).
func set_spawn_here() -> void:
	_spawn_transform = global_transform


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_end_dodge()
	dodge_cooldown_remaining = 0.0
	if is_dead:
		is_dead = false
		_model.rotation.x = 0.0
		if _health != null:
			_health.revive()
		respawned.emit()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_end_dodge()
	_model.rotation.x = -PI / 2.0  # topple over
	died.emit()
	await get_tree().create_timer(respawn_delay).timeout
	respawn()


func _face_camera() -> void:
	_model.rotation.y = _camera_pivot.global_rotation.y


## Stunned or rooted: no dodging out of it.
func _is_held() -> bool:
	return _health != null and _health.get_move_speed_multiplier() <= 0.0


func _tick_timers(delta: float) -> void:
	_coyote_remaining = maxf(_coyote_remaining - delta, 0.0)
	_jump_buffer_remaining = maxf(_jump_buffer_remaining - delta, 0.0)
	dodge_cooldown_remaining = maxf(dodge_cooldown_remaining - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_remaining = jump_buffer_time


func _get_wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw_basis := Basis(Vector3.UP, _camera_pivot.global_rotation.y)
	return yaw_basis * Vector3(input.x, 0.0, input.y)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity := _gravity * gravity_multiplier
	if velocity.y < 0.0:
		gravity *= fall_multiplier
	velocity.y -= gravity * delta
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier


func _process_jump() -> void:
	if _jump_buffer_remaining > 0.0 and _coyote_remaining > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0


func _process_run(wish_direction: Vector3, delta: float) -> void:
	var target := wish_direction * run_speed
	if _health != null:
		target *= _health.get_move_speed_multiplier()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := air_acceleration
	if is_on_floor():
		rate = ground_acceleration if wish_direction.length_squared() > 0.0 else ground_deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.01:
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_for(direction), 1.0 - exp(-turn_speed * delta))


func _try_start_dodge(wish_direction: Vector3) -> void:
	if is_dodging or dodge_cooldown_remaining > 0.0:
		return
	if not is_on_floor():
		if not _air_dodge_available:
			return
		_air_dodge_available = false

	# Dodge where the player is steering, or straight ahead if there's no input.
	if wish_direction.length_squared() > 0.01:
		_dodge_direction = wish_direction.normalized()
	else:
		_dodge_direction = -_model.global_basis.z
	_dodge_direction.y = 0.0
	_dodge_direction = _dodge_direction.normalized()

	is_dodging = true
	is_invulnerable = true
	_dodge_remaining = dodge_duration
	dodge_cooldown_remaining = dodge_duration + dodge_cooldown
	_model.rotation.y = _yaw_for(_dodge_direction)
	_model.scale = Vector3(1.15, 0.7, 1.15)
	dodged.emit()


func _process_dodge(delta: float) -> void:
	# Constant-speed dash with gravity suspended, so an air dodge can cross gaps.
	velocity = _dodge_direction * dodge_speed
	_dodge_remaining -= delta
	if _dodge_remaining <= 0.0:
		velocity = _dodge_direction * run_speed
		_end_dodge()


func _end_dodge() -> void:
	is_dodging = false
	is_invulnerable = false
	_dodge_remaining = 0.0
	_model.scale = Vector3.ONE


func _rotate_camera_with_stick(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_rotate_camera(-look.x * stick_sensitivity * delta, -look.y * stick_sensitivity * delta)


func _rotate_camera(yaw_delta: float, pitch_delta: float) -> void:
	_camera_pivot.rotation.y = wrapf(_camera_pivot.rotation.y + yaw_delta, -PI, PI)
	_camera_pivot.rotation.x = clampf(
		_camera_pivot.rotation.x + pitch_delta,
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)


## Yaw that points the model's forward (-Z) along `direction`.
func _yaw_for(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
