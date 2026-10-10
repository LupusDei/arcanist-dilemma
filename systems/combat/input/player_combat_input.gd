class_name PlayerCombatInput
extends Node
## Reads casting input for the player and aims through the active camera.
##
## Add as a child of the Player next to its SpellCaster. Uses these input
## actions when project.godot defines them, and falls back to raw mouse and
## number keys until it does:
##   cast_cantrip (left click), cast_main (right click), spell_1 .. spell_6 (1-6)
## Bar slots 0-5 are keys 1-6; slot 6 is the right-click main spell.
## A chargeable cantrip (Spark) charges while the button is held and fires on
## release; a quick click fires at once. Adds a CombatFeedback for the
## reticle, hit markers, damage numbers and camera kick.

const MAIN_SLOT := 6
const AIM_DISTANCE := 60.0

@export var caster: SpellCaster
## Aim at the screen center (third-person, captured mouse) or at the mouse cursor.
@export var aim_at_cursor := false
## Reticle, hit markers, damage numbers and camera kick.
@export var feedback := true
## Soft aim assist: spells snap to the target nearest the crosshair when one
## is within assist_radius pixels (at 720p; scaled with the screen) and in sight.
@export var aim_assist := true
@export var assist_radius := 60.0

var combat_feedback: CombatFeedback


func _ready() -> void:
	if caster == null:
		caster = get_parent().get_node_or_null(^"SpellCaster") as SpellCaster
	if feedback and caster:
		combat_feedback = CombatFeedback.new()
		combat_feedback.caster = caster
		combat_feedback.aim_at_cursor = aim_at_cursor
		combat_feedback.target_provider = get_aim_target
		add_child(combat_feedback)


func _unhandled_input(event: InputEvent) -> void:
	if caster == null:
		return
	if caster.is_charging() and _released(event, &"cast_cantrip", MOUSE_BUTTON_LEFT):
		caster.release_charge(get_aim_point())
		get_viewport().set_input_as_handled()
		return
	var slot := _slot_for(event)
	if slot == -2:
		return
	if slot == -1:
		var cantrip := caster.get_cantrip()
		if cantrip and cantrip.chargeable:
			caster.begin_charge(cantrip)
		else:
			caster.cast_cantrip(get_aim_point())
	else:
		caster.cast_slot(slot, get_aim_point())
	get_viewport().set_input_as_handled()


## Returns -1 for the cantrip, 0-6 for a bar slot, -2 for no cast.
func _slot_for(event: InputEvent) -> int:
	if _pressed(event, &"cast_cantrip", MOUSE_BUTTON_LEFT, KEY_NONE):
		return -1
	if _pressed(event, &"cast_main", MOUSE_BUTTON_RIGHT, KEY_NONE):
		return MAIN_SLOT
	for i in 6:
		if _pressed(event, StringName("spell_%d" % (i + 1)), MOUSE_BUTTON_NONE, KEY_1 + i):
			return i
	return -2


func _released(event: InputEvent, action: StringName, button: MouseButton) -> bool:
	if InputMap.has_action(action):
		return event.is_action_released(action)
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return not mouse.pressed and mouse.button_index == button
	return false


func _notification(what: int) -> void:
	# Losing focus mid-charge would leave the button "held" forever: fire it.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and caster and caster.is_charging():
		caster.release_charge(get_aim_point())


func _pressed(event: InputEvent, action: StringName, button: MouseButton, key: Key) -> bool:
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	if button != MOUSE_BUTTON_NONE and event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		# Left click also recaptures the mouse in the player script; only cast while captured.
		return mouse.pressed and mouse.button_index == button and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if key != KEY_NONE and event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == key
	return false


## The world point under the crosshair (or cursor): the assisted target's
## centre when there is one, else what the ray hits, else a point far ahead.
func get_aim_point() -> Vector3:
	var target := get_aim_target()
	if target:
		return target.get_target_position()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return caster.global_position - caster.global_basis.z * AIM_DISTANCE
	var from := camera.project_ray_origin(_aim_screen_point())
	var to := from + camera.project_ray_normal(_aim_screen_point()) * AIM_DISTANCE
	var hit := _ray(from, to)
	return hit["position"] if not hit.is_empty() else to


## The target soft aim assist would snap to, or null: the living non-ally
## (enemy or prop) nearest the crosshair on screen, within assist_radius,
## in range and not hidden behind a wall.
func get_aim_target() -> HealthComponent:
	if not aim_assist or caster == null:
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen := _aim_screen_point()
	var reach := assist_radius * maxf(get_viewport().get_visible_rect().size.y / 720.0, 1.0)
	var own_team := caster.health.team if caster.health else &"player"
	var best: HealthComponent = null
	var best_distance := reach
	for node in get_tree().get_nodes_in_group(HealthComponent.GROUP):
		var target := node as HealthComponent
		if target == null or target.is_dead or target.team == own_team or not target.is_inside_tree():
			continue
		var point := target.get_target_position()
		if camera.is_position_behind(point) or camera.global_position.distance_to(point) > AIM_DISTANCE:
			continue
		var distance := camera.unproject_position(point).distance_to(screen)
		if distance > best_distance or not _in_sight(camera.global_position, target):
			continue
		best = target
		best_distance = distance
	return best


func _aim_screen_point() -> Vector2:
	return get_viewport().get_mouse_position() if aim_at_cursor else get_viewport().get_visible_rect().size * 0.5


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var body := caster.get_parent()
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	return caster.get_world_3d().direct_space_state.intersect_ray(query)


func _in_sight(from: Vector3, target: HealthComponent) -> bool:
	var point := target.get_target_position()
	var hit := _ray(from, point)
	if hit.is_empty():
		return true
	if HealthComponent.find_on(hit["collider"]) == target:
		return true
	return from.distance_to(hit["position"]) >= from.distance_to(point) - target.hit_radius
