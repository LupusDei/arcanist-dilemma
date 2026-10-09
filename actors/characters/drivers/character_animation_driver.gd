class_name CharacterAnimationDriver
extends Node
## Feeds a CharacterRig from a CharacterBody3D so the player controller needs
## no animation code: add this as a child of the Player, next to its Model.
##
## - Every physics frame: horizontal speed, floor contact and vertical speed -> idle / run / jump / fall.
## - The body's `dodged` signal -> the roll, stretched to the body's `dodge_duration`.
## - A SpellCaster anywhere under the body (anything with a `cast_started(spell, cast_time)`
##   signal) -> the cast; its `cast_interrupted` cancels it.
## - A HealthComponent under the body (its `damaged` signal) -> the hit flinch. Other
##   health systems can call bind_hurt(object, signal_name).

## The body to read. Defaults to this node's parent.
@export var body_path: NodePath = ^".."
## The rig to drive. Defaults to the first CharacterRig found under the body.
@export var rig_path: NodePath

var body: CharacterBody3D
var rig: CharacterRig


func _ready() -> void:
	body = get_node_or_null(body_path) as CharacterBody3D
	rig = get_node_or_null(rig_path) as CharacterRig if not rig_path.is_empty() else null
	if rig == null and body:
		rig = _find_rig(body)
	if body == null or rig == null:
		push_warning("CharacterAnimationDriver: no %s to drive" % ("body" if body == null else "CharacterRig"))
		set_physics_process(false)
		return
	if "run_speed" in body:
		rig.run_speed_reference = body.run_speed
	if body.has_signal(&"dodged"):
		body.connect(&"dodged", _on_dodged)
	for node in body.find_children("*", "", true, false):
		if node.has_signal(&"cast_started"):
			bind_caster(node)
		elif node.has_signal(&"damaged") and node.has_signal(&"health_changed"):
			bind_hurt(node, &"damaged")


func _physics_process(_delta: float) -> void:
	# The rig can be rebuilt or replaced (new game, swapped model); find it again.
	if not is_instance_valid(rig):
		rig = _find_rig(body)
		if rig == null:
			return
	var v := body.velocity
	rig.update_locomotion(Vector2(v.x, v.z).length(), body.is_on_floor(), v.y)


## Plays the cast animation whenever [param caster] starts a spell.
func bind_caster(caster: Object) -> void:
	if not caster.is_connected(&"cast_started", _on_cast_started):
		caster.connect(&"cast_started", _on_cast_started)
	if caster.has_signal(&"cast_interrupted") and not caster.is_connected(&"cast_interrupted", _on_cast_interrupted):
		caster.connect(&"cast_interrupted", _on_cast_interrupted)


## Plays the hit flinch whenever [param source] emits [param signal_name] (any arguments).
func bind_hurt(source: Object, signal_name: StringName) -> void:
	source.connect(signal_name, _on_hurt_varargs)


func _on_dodged() -> void:
	rig.play_dodge(body.dodge_duration if "dodge_duration" in body else 0.22)


func _on_cast_started(_spell, cast_time: float) -> void:
	rig.play_cast(cast_time)


func _on_cast_interrupted(_spell) -> void:
	if rig.current_action() == &"cast":
		rig.cancel_action()


func _on_hurt_varargs(_a = null, _b = null, _c = null, _d = null) -> void:
	rig.play_hit()


static func _find_rig(root: Node) -> CharacterRig:
	for node in root.find_children("*", "", true, false):
		if node is CharacterRig:
			return node
	return null
