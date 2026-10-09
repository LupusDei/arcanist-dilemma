class_name PlayerCombatInput
extends Node
## Reads casting input for the player and aims through the active camera.
##
## Add as a child of the Player next to its SpellCaster. Uses these input
## actions when project.godot defines them, and falls back to raw mouse and
## number keys until it does:
##   cast_cantrip (left click), cast_main (right click), spell_1 .. spell_6 (1-6)
## Bar slots 0-5 are keys 1-6; slot 6 is the right-click main spell.

const MAIN_SLOT := 6
const AIM_DISTANCE := 60.0

@export var caster: SpellCaster
## Aim at the screen center (third-person, captured mouse) or at the mouse cursor.
@export var aim_at_cursor := false


func _ready() -> void:
	if caster == null:
		caster = get_parent().get_node_or_null(^"SpellCaster") as SpellCaster


func _unhandled_input(event: InputEvent) -> void:
	if caster == null:
		return
	var slot := _slot_for(event)
	if slot == -2:
		return
	if slot == -1:
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


## The world point under the crosshair (or cursor), or a point far ahead.
func get_aim_point() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return caster.global_position - caster.global_basis.z * AIM_DISTANCE
	var screen := get_viewport().get_mouse_position() if aim_at_cursor else get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var body := caster.get_parent()
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := caster.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else to
