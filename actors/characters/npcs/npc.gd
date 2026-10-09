class_name Npc
extends CharacterBody3D
## A standing NPC: a collision capsule and a CharacterRig built from the
## catalog. Quests and dialogue can find NPCs in the "npcs" group by npc_id.
##
##   var npc := Npc.create("old_man")
##   npc.face_toward(player.global_position)
##   npc.talk()

## "old_man", "tam" or "villager".
@export_enum("old_man", "tam", "villager") var npc_id := "villager"
## Villager look and trade. The same seed always gives the same villager.
@export var villager_seed := 1
@export_enum("random", "farmer", "baker", "elder", "child", "militia", "merchant", "miller") var villager_role := "random"
## How fast the NPC turns to face someone, in radians per second.
@export var turn_speed := 5.0

var rig: CharacterRig
var display_name := ""

var _target_yaw := 0.0


static func create(id: String, seed_value := 1, role := "") -> Npc:
	var npc := Npc.new()
	npc.npc_id = id
	npc.villager_seed = seed_value
	npc.villager_role = role
	return npc


func _ready() -> void:
	add_to_group(&"npcs")
	var spec := NpcCatalog.spec_for(npc_id, villager_seed, villager_role, _player_appearance())
	display_name = spec.character_name
	rig = CharacterBuilder.build(spec)
	add_child(rig)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = maxf(rig.get_height(), 0.7)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	_target_yaw = rig.rotation.y
	# Stagger idle loops so a crowd doesn't breathe in sync.
	rig.anim_tree.advance(fmod(float(villager_seed) * 0.37, 4.0))


func _physics_process(delta: float) -> void:
	rig.update_locomotion(0.0, true)
	rig.rotation.y = rotate_toward(rig.rotation.y, _target_yaw, turn_speed * delta)


## Turns (smoothly) to look at a point in the world.
func face_toward(world_position: Vector3) -> void:
	var to := world_position - global_position
	if Vector2(to.x, to.z).length_squared() > 0.0001:
		_target_yaw = atan2(-to.x, -to.z) - global_rotation.y


## Plays the talking gesture, e.g. when a dialogue line starts.
func talk() -> void:
	rig.play_talk()


func _player_appearance():
	var progression := get_node_or_null("/root/Progression")
	if progression and progression.get("appearance") != null:
		return progression.appearance
	var ui := CharacterRig.ui_session_character()
	return ui if not ui.is_empty() else null
