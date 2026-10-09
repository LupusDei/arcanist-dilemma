class_name CharacterRig
extends Node3D
## A built character model and the animation interface the player controller
## (or an NPC brain) drives. Build one with CharacterBuilder.build(source), or
## drop actors/characters/arcanist.tscn into a scene.
##
## Driving it:
##   rig.update_locomotion(horizontal_speed, is_on_floor, vertical_velocity)   # every physics frame
##   rig.play_dodge(duration)   rig.play_cast(cast_time)   rig.play_hit()   rig.play_talk()
##   rig.get_cast_point()       # Marker3D on the right hand for spawning spell effects
##   rig.get_socket(&"item_r")  # attach a staff or weapon
## CharacterAnimationDriver does the update_locomotion call for a CharacterBody3D.

signal action_started(action: StringName)
signal action_finished(action: StringName)
## The cast animation reached the moment the hands thrust forward.
signal cast_released
signal appearance_applied

## Build from the running game's character: the Progression autoload's
## appearance and path when it exists, otherwise the creation screen's
## UiSession.character, otherwise the default boy. Follows later changes.
@export var follow_player_appearance := false
## Default look when not following the player: "boy" or "girl".
@export_enum("boy", "girl") var default_body := "boy"
## Outfit when not following the player: farm clothes or a path's.
@export_enum("farm", "wizard", "mage", "sorcerer") var default_path := "farm"
## Speed at which the run animation plays at 1x (the player's run_speed).
@export var run_speed_reference := 6.5
## Below this horizontal speed the character idles.
@export var idle_speed_threshold := 0.35

var spec: CharacterSpec
var dims: Dictionary = {}
var joints: Dictionary = {}
var sockets: Dictionary = {}
var body_root: Node3D
var magic_fx: Array[Node3D] = []
var magic_lights: Array[OmniLight3D] = []
var flickers: Array[Node3D] = []
var flicker_lights: Array[OmniLight3D] = []
var anim_tree: AnimationTree
## The shared vertex-coloured material of the merged body parts (see CharacterBuilder.merge_parts).
var skin_material: StandardMaterial3D
## Names of every part built, including ones merged away (for tests and debugging).
var built_parts := PackedStringArray()

var _rest_rot: Dictionary = {}
var _rest_pos: Dictionary = {}
var _materials: Array[StandardMaterial3D] = []
var _loco_state := &"idle"
var _action := &""
var _action_left := 0.0
var _cast_release_left := -1.0
var _magic := 0.0
var _magic_target := 0.0
var _magic_hold := 0.0
var _flash := 0.0
var _flicker_timer := 0.0
var _rng := RandomNumberGenerator.new()
## Tree parameters set before the tree's first update are lost when it initializes, so hold them until then.
var _pending_params: Dictionary = {}
var _tree_ready := false


func _ready() -> void:
	if follow_player_appearance and not Engine.is_editor_hint():
		_bind_player_appearance()
	elif spec == null:
		CharacterBuilder.populate(self, CharacterSpec.player(default_body, default_path))


## Rebuilds the model from any appearance source (see CharacterSpec.from_any).
## [param path] switches the outfit to that path's clothes ("" keeps farm clothes).
func apply_appearance(source, path := "", specialization := "") -> void:
	var s := CharacterSpec.from_any(source)
	if path != "" or s.outfit == "":
		s.set_path(path, specialization)
	CharacterBuilder.populate(self, s)


## Changes only the outfit, keeping the look.
func set_path(path: String, specialization := "") -> void:
	var s := spec.duplicate_spec() if spec else CharacterSpec.new()
	s.set_path(path, specialization)
	CharacterBuilder.populate(self, s)


# --- Animation interface ---

## Call every physics frame. Picks idle, run (sped up or slowed to match), jump or fall.
func update_locomotion(horizontal_speed: float, on_floor: bool, vertical_velocity := 0.0) -> void:
	var state := &"idle"
	if not on_floor:
		state = &"jump" if vertical_velocity > 0.5 else &"fall"
	elif horizontal_speed > idle_speed_threshold:
		state = &"run"
		_set_param(&"run_speed/scale", clampf(horizontal_speed / run_speed_reference, 0.55, 1.6))
	if state != _loco_state:
		_loco_state = state
		_set_param(&"loco/transition_request", String(state))


## The forward roll, stretched to the dodge's duration.
func play_dodge(duration := 0.22) -> void:
	_set_param(&"dodge_speed/scale", CharacterAnimations.DODGE_LENGTH / maxf(duration, 0.05))
	_fire(&"full")
	_start_action(&"dodge", duration)


## Gather and release. [param cast_time] is the spell's cast time; instant spells
## (0) still get a short flick. cast_released fires when the hands thrust out.
func play_cast(cast_time := 0.0) -> void:
	var total := maxf(cast_time / CharacterAnimations.CAST_RELEASE_AT, 0.32) + 0.12
	_set_param(&"upper_pick/transition_request", "cast")
	_set_param(&"upper_speed/scale", CharacterAnimations.CAST_LENGTH / total)
	_fire(&"upper")
	_start_action(&"cast", total)
	_cast_release_left = total * CharacterAnimations.CAST_RELEASE_AT
	_magic_target = 1.0
	_magic_hold = total


## Flinch and flash. Interrupts a cast.
func play_hit() -> void:
	_cast_release_left = -1.0
	_set_param(&"upper_pick/transition_request", "hit")
	_set_param(&"upper_speed/scale", 1.0)
	_fire(&"upper")
	_start_action(&"hit", 0.4)
	_flash = 1.0
	_magic_hold = 0.0


## A dialogue gesture.
func play_talk() -> void:
	_set_param(&"upper_pick/transition_request", "talk")
	_set_param(&"upper_speed/scale", 1.0)
	_fire(&"upper")
	_start_action(&"talk", 2.0)


## Stops a cast or gesture early (e.g. the spell was interrupted).
func cancel_action() -> void:
	if _action == &"":
		return
	var oneshot := &"full" if _action == &"dodge" else &"upper"
	_set_param(StringName(String(oneshot) + "/request"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_cast_release_left = -1.0
	_magic_hold = 0.0
	_finish_action()


func is_busy() -> bool:
	return _action != &""


func current_action() -> StringName:
	return _action


func locomotion_state() -> StringName:
	return _loco_state


## Shows or hides the magic in the hands (0 to 1), e.g. while aiming.
func set_magic_level(level: float) -> void:
	_magic_target = clampf(level, 0.0, 1.0)


## Where spells come from: the right hand (or "l" for the left).
func get_cast_point(hand := "r") -> Marker3D:
	return sockets.get("cast_" + hand)


## Named attachment points: item_r, item_l, cast_r, cast_l, hat, back.
func get_socket(socket_name: StringName) -> Node3D:
	return sockets.get(String(socket_name))


func get_joint(joint_name: String) -> Node3D:
	return joints.get(joint_name)


## Path of a joint from this node, as animation tracks use it.
func joint_path(joint_name: String) -> String:
	var parts: Array[String] = [joint_name]
	var parent_of := {}
	for entry in CharacterBuilder.JOINTS:
		parent_of[entry[0]] = entry[1]
	var p: String = parent_of[joint_name]
	while p != "":
		parts.push_front(p)
		p = parent_of[p]
	return "Body/" + "/".join(parts)


func rest_rotation(joint_name: String) -> Vector3:
	return _rest_rot.get(joint_name, Vector3.ZERO)


func rest_position(joint_name: String) -> Vector3:
	return _rest_pos.get(joint_name, Vector3.ZERO)


## Height of the top of the head in metres (scaled), for nameplates and camera framing.
func get_height() -> float:
	return dims.get("height_m", 1.65)


# --- Building (called by CharacterBuilder) ---

func clear_model() -> void:
	for child in get_children():
		if child == body_root or child == anim_tree:
			remove_child(child)
			child.queue_free()
	body_root = null
	anim_tree = null
	joints.clear()
	sockets.clear()
	magic_fx.clear()
	magic_lights.clear()
	flickers.clear()
	flicker_lights.clear()
	_materials.clear()
	built_parts.clear()
	_rest_rot.clear()
	_rest_pos.clear()
	_action = &""
	_loco_state = &"idle"
	_tree_ready = false
	_pending_params.clear()


func finish_build() -> void:
	for joint_name in joints:
		_rest_rot[joint_name] = joints[joint_name].rotation
		_rest_pos[joint_name] = joints[joint_name].position
	for mi in body_root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m and not m.emission_enabled and m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not m in _materials:
			_materials.append(m)
	for fx in magic_fx:
		fx.visible = false
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.add_animation_library(&"", CharacterAnimations.build_library(self))
	anim_tree.tree_root = CharacterAnimations.build_tree(self)
	anim_tree.root_node = NodePath("..")
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	add_child(anim_tree)
	anim_tree.active = true
	_rng.seed = hash(spec.to_dict())
	appearance_applied.emit()


# --- Per-frame ---

func _physics_process(delta: float) -> void:
	if body_root == null:
		return
	if not _tree_ready:
		_tree_ready = true
		for param in _pending_params:
			anim_tree.set(param, _pending_params[param])
		_pending_params.clear()
	if _action != &"":
		_action_left -= delta
		if _cast_release_left >= 0.0:
			_cast_release_left -= delta
			if _cast_release_left < 0.0:
				_magic = 1.4
				cast_released.emit()
		if _action_left <= 0.0:
			_finish_action()
	_tick_magic(delta)
	_tick_flash(delta)


func _tick_magic(delta: float) -> void:
	if _magic_hold > 0.0:
		_magic_hold -= delta
		if _magic_hold <= 0.0:
			_magic_target = 0.0
	_magic = move_toward(_magic, _magic_target, delta * (4.0 if _magic_target > _magic else 2.5))
	var shown := _magic > 0.02
	for fx in magic_fx:
		fx.visible = shown
		if shown:
			fx.scale = Vector3.ONE * clampf(0.4 + _magic * 0.6, 0.4, 1.3)
			fx.rotate_object_local(Vector3.FORWARD, delta * 2.5)
	for light in magic_lights:
		light.light_energy = _magic * 0.45
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = _rng.randf_range(0.04, 0.09)
		for bolt in flickers:
			bolt.visible = _rng.randf() < 0.7
			bolt.rotation.y = _rng.randf_range(-PI, PI)
		for light in flicker_lights:
			light.light_energy = _rng.randf_range(0.3, 1.1)


func _tick_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta * 5.0, 0.0)
	for m in _materials:
		m.emission_enabled = _flash > 0.0
		m.emission = Color(1.0, 0.35, 0.3)
		m.emission_energy_multiplier = _flash * 1.2


func _start_action(action: StringName, duration: float) -> void:
	if _action != &"" and _action != action:
		action_finished.emit(_action)
	_action = action
	_action_left = duration
	action_started.emit(action)


func _finish_action() -> void:
	var done := _action
	_action = &""
	_action_left = 0.0
	if done != &"":
		action_finished.emit(done)


func _fire(oneshot: StringName) -> void:
	_set_param(StringName(String(oneshot) + "/request"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _set_param(param: StringName, value) -> void:
	if anim_tree == null:
		return
	var full := StringName("parameters/" + String(param))
	if _tree_ready:
		anim_tree.set(full, value)
	else:
		_pending_params[full] = value


# --- Following the player's character ---

func _bind_player_appearance() -> void:
	var progression := get_node_or_null("/root/Progression")
	if progression:
		for sig in [&"appearance_changed", &"character_loaded"]:
			if progression.has_signal(sig):
				progression.connect(sig, _refresh_from_player)
		for sig in [&"path_chosen", &"specialization_chosen"]:
			if progression.has_signal(sig):
				progression.connect(sig, _refresh_from_player.unbind(1))
	_refresh_from_player()


func _refresh_from_player() -> void:
	var progression := get_node_or_null("/root/Progression")
	if progression and progression.get("appearance") != null:
		var path := ""
		var specialization := ""
		var p = progression.get("progression")
		if p != null:
			path = str(p.get("path"))
			specialization = str(p.get("specialization"))
		apply_appearance(progression.appearance, path, specialization)
		return
	var ui_character := ui_session_character()
	apply_appearance(ui_character if not ui_character.is_empty() else CharacterSpec.player(default_body, default_path), default_path)


## UiSession.character from the UI branch, read without depending on the class at parse time.
static func ui_session_character() -> Dictionary:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == &"UiSession":
			var script: Script = load(c["path"])
			var value = script.get("character") if script else null
			return value if value is Dictionary else {}
	return {}
