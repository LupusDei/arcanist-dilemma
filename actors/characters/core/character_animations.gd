class_name CharacterAnimations
extends RefCounted
## Keyframed animations for a CharacterRig, generated from poses, and the
## AnimationTree that blends them.
##
## A pose is a dictionary of joint name -> rotation offset from the rest pose
## (radians), plus optional "hips_y" (metres) for the hips height. Every
## animation keys every joint, so any animation can be swapped for a hand-made
## or mocap clip later as long as it uses the same joint paths
## ("Body/Hips/Spine/Chest:rotation" and so on).
##
## Sign conventions (the model faces -Z):
## - Shoulder, Thigh, Elbow +x swing the limb forward; Knee -x bends the knee.
## - Spine, Chest, Neck, Head -x lean forward; Foot +x lifts the toes.
## - ShoulderL -z / ShoulderR +z raise the arms out to the sides.

const NAMES: Array[StringName] = [&"idle", &"run", &"jump", &"fall", &"dodge", &"cast", &"hit", &"talk"]

## Joints that the upper-body layer (cast, hit, talk) owns, so legs keep running underneath.
const UPPER_JOINTS := ["Spine", "Chest", "Neck", "Head", "ShoulderL", "ElbowL", "HandL", "ShoulderR", "ElbowR", "HandR"]

## Run cycle length at the reference speed; the rig scales playback to the actual speed.
const RUN_CYCLE := 0.66
const DODGE_LENGTH := 0.5
const CAST_LENGTH := 1.0
## Fraction of the cast animation spent gathering before the release.
const CAST_RELEASE_AT := 0.62


static func build_library(rig: CharacterRig) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"RESET", _make(rig, [[0.0, {}]], 0.001, false))
	lib.add_animation(&"idle", _idle(rig))
	lib.add_animation(&"run", _run(rig))
	lib.add_animation(&"jump", _jump(rig))
	lib.add_animation(&"fall", _fall(rig))
	lib.add_animation(&"dodge", _dodge(rig))
	lib.add_animation(&"cast", _cast(rig))
	lib.add_animation(&"hit", _hit(rig))
	lib.add_animation(&"talk", _talk(rig))
	return lib


## The blend tree:
##   idle / run (time scaled) / jump / fall -> "loco" transition
##   -> "upper" one-shot (cast, hit, talk; upper body only)
##   -> "full" one-shot (dodge roll; whole body) -> output
static func build_tree(rig: CharacterRig) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()

	var loco := AnimationNodeTransition.new()
	loco.xfade_time = 0.14
	for state in ["idle", "run", "jump", "fall"]:
		loco.add_input(state)
	tree.add_node(&"loco", loco, Vector2(400, 0))
	tree.add_node(&"idle", _anim_node(&"idle"), Vector2(0, -100))
	tree.add_node(&"run", _anim_node(&"run"), Vector2(0, 0))
	tree.add_node(&"run_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	tree.add_node(&"jump", _anim_node(&"jump"), Vector2(0, 100))
	tree.add_node(&"fall", _anim_node(&"fall"), Vector2(0, 200))
	tree.connect_node(&"run_speed", 0, &"run")
	tree.connect_node(&"loco", 0, &"idle")
	tree.connect_node(&"loco", 1, &"run_speed")
	tree.connect_node(&"loco", 2, &"jump")
	tree.connect_node(&"loco", 3, &"fall")

	var pick := AnimationNodeTransition.new()
	pick.xfade_time = 0.05
	for action in ["cast", "hit", "talk"]:
		pick.add_input(action)
		tree.add_node(StringName(action), _anim_node(StringName(action)), Vector2(400, 300 + pick.get_input_count() * 100))
	tree.add_node(&"upper_pick", pick, Vector2(600, 400))
	for i in pick.get_input_count():
		tree.connect_node(&"upper_pick", i, StringName(pick.get_input_name(i)))
	tree.add_node(&"upper_speed", AnimationNodeTimeScale.new(), Vector2(800, 400))
	tree.connect_node(&"upper_speed", 0, &"upper_pick")

	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.08
	upper.fadeout_time = 0.18
	upper.filter_enabled = true
	for joint in UPPER_JOINTS:
		upper.set_filter_path(NodePath(rig.joint_path(joint) + ":rotation"), true)
	tree.add_node(&"upper", upper, Vector2(1000, 0))
	tree.connect_node(&"upper", 0, &"loco")
	tree.connect_node(&"upper", 1, &"upper_speed")

	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.04
	# No fade out: the roll ends a full turn round, and blending from 360 degrees back to 0 would spin it backwards.
	full.fadeout_time = 0.0
	tree.add_node(&"dodge", _anim_node(&"dodge"), Vector2(1000, 300))
	tree.add_node(&"dodge_speed", AnimationNodeTimeScale.new(), Vector2(1200, 300))
	tree.connect_node(&"dodge_speed", 0, &"dodge")
	tree.add_node(&"full", full, Vector2(1400, 0))
	tree.connect_node(&"full", 0, &"upper")
	tree.connect_node(&"full", 1, &"dodge_speed")
	tree.connect_node(&"output", 0, &"full")
	return tree


static func _anim_node(anim_name: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim_name
	return n


# --- The animations. Times are in seconds; poses are offsets from rest. ---

static func _idle(rig: CharacterRig) -> Animation:
	var calm := {"Chest": Vector3(0.0, 0, 0), "ShoulderL": Vector3(0, 0, 0.02), "ShoulderR": Vector3(0, 0, -0.02), "Head": Vector3(0, 0.0, 0)}
	var breathe := {
		"Chest": Vector3(0.035, 0, 0), "Head": Vector3(-0.03, 0.06, 0.02), "hips_y": -0.008,
		"ShoulderL": Vector3(0.02, 0, -0.05), "ShoulderR": Vector3(0.02, 0, 0.05), "ElbowL": Vector3(0.05, 0, 0), "ElbowR": Vector3(0.05, 0, 0),
	}
	var look := {"Chest": Vector3(0.0, 0.03, 0), "Head": Vector3(0.0, -0.08, -0.02), "ShoulderL": Vector3(0, 0, 0.0), "ShoulderR": Vector3(0, 0, 0.0)}
	return _make(rig, [[0.0, calm], [1.1, breathe], [2.2, look], [3.3, breathe], [4.4, calm]], 4.4, true)


static func _run(rig: CharacterRig) -> Animation:
	var q := RUN_CYCLE / 4.0
	var lean := -0.2
	# Contact with the left foot forward, then passing, then right foot forward, then passing.
	var contact_l := {
		"ThighL": Vector3(0.75, 0, 0), "KneeL": Vector3(-0.2, 0, 0), "FootL": Vector3(0.2, 0, 0),
		"ThighR": Vector3(-0.55, 0, 0), "KneeR": Vector3(-0.55, 0, 0), "FootR": Vector3(-0.3, 0, 0),
		"ShoulderL": Vector3(-0.6, 0, 0), "ShoulderR": Vector3(0.65, 0, 0), "ElbowL": Vector3(0.9, 0, 0), "ElbowR": Vector3(1.25, 0, 0),
		"Spine": Vector3(lean, 0, 0), "Chest": Vector3(0, -0.14, 0), "Head": Vector3(0.12, 0.08, 0), "hips_y": 0.0,
	}
	var pass_l := {
		"ThighL": Vector3(-0.05, 0, 0), "KneeL": Vector3(-0.5, 0, 0), "FootL": Vector3(0.0, 0, 0),
		"ThighR": Vector3(0.35, 0, 0), "KneeR": Vector3(-1.55, 0, 0), "FootR": Vector3(-0.2, 0, 0),
		"ShoulderL": Vector3(0.0, 0, 0), "ShoulderR": Vector3(0.0, 0, 0), "ElbowL": Vector3(1.1, 0, 0), "ElbowR": Vector3(1.1, 0, 0),
		"Spine": Vector3(lean - 0.03, 0, 0), "Chest": Vector3(0, 0, 0), "Head": Vector3(0.15, 0, 0), "hips_y": -0.055,
	}
	return _make(rig, [[0.0, contact_l], [q, pass_l], [2 * q, _mirror(contact_l)], [3 * q, _mirror(pass_l)], [4 * q, contact_l]], RUN_CYCLE, true)


static func _jump(rig: CharacterRig) -> Animation:
	var crouch := {"ThighL": Vector3(0.5, 0, 0), "ThighR": Vector3(0.5, 0, 0), "KneeL": Vector3(-0.9, 0, 0), "KneeR": Vector3(-0.9, 0, 0), "FootL": Vector3(0.3, 0, 0), "FootR": Vector3(0.3, 0, 0), "Spine": Vector3(-0.2, 0, 0), "ShoulderL": Vector3(-0.4, 0, 0), "ShoulderR": Vector3(-0.4, 0, 0), "hips_y": -0.05}
	var rise := {
		"ThighL": Vector3(0.9, 0, 0), "KneeL": Vector3(-1.4, 0, 0), "ThighR": Vector3(0.1, 0, 0), "KneeR": Vector3(-0.35, 0, 0),
		"FootL": Vector3(-0.3, 0, 0), "FootR": Vector3(-0.5, 0, 0), "Spine": Vector3(0.05, 0, 0), "Head": Vector3(0.12, 0, 0),
		"ShoulderL": Vector3(1.6, 0, -0.5), "ShoulderR": Vector3(1.4, 0, 0.6), "ElbowL": Vector3(0.4, 0, 0), "ElbowR": Vector3(0.6, 0, 0),
	}
	return _make(rig, [[0.0, crouch], [0.12, rise], [0.4, rise]], 0.4, false)


static func _fall(rig: CharacterRig) -> Animation:
	var a := {
		"ThighL": Vector3(0.45, 0, 0), "KneeL": Vector3(-0.7, 0, 0), "ThighR": Vector3(0.05, 0, 0), "KneeR": Vector3(-0.3, 0, 0),
		"FootL": Vector3(-0.2, 0, 0), "FootR": Vector3(-0.35, 0, 0),
		"ShoulderL": Vector3(0.3, 0, -1.0), "ShoulderR": Vector3(0.2, 0, 1.1), "ElbowL": Vector3(0.5, 0, 0), "ElbowR": Vector3(0.4, 0, 0),
		"Head": Vector3(-0.1, 0, 0),
	}
	var b := a.duplicate()
	b["ShoulderL"] = Vector3(0.2, 0, -1.15)
	b["ShoulderR"] = Vector3(0.35, 0, 0.95)
	b["ThighL"] = Vector3(0.35, 0, 0)
	b["ThighR"] = Vector3(0.15, 0, 0)
	return _make(rig, [[0.0, a], [0.4, b], [0.8, a]], 0.8, true)


## A tucked forward roll: the hips turn a full circle while the body balls up.
static func _dodge(rig: CharacterRig) -> Animation:
	var drop: float = -rig.dims.hip_y * 0.42
	var tuck := {
		"ThighL": Vector3(1.7, 0, 0), "ThighR": Vector3(1.6, 0, 0), "KneeL": Vector3(-2.2, 0, 0), "KneeR": Vector3(-2.2, 0, 0),
		"Spine": Vector3(-0.8, 0, 0), "Chest": Vector3(-0.2, 0, 0), "Neck": Vector3(-0.3, 0, 0), "Head": Vector3(-0.3, 0, 0),
		"ShoulderL": Vector3(1.2, 0, 0.1), "ShoulderR": Vector3(1.2, 0, -0.1), "ElbowL": Vector3(1.7, 0, 0), "ElbowR": Vector3(1.7, 0, 0),
	}
	var start := tuck.duplicate()
	start["hips_rot"] = 0.0
	start["hips_y"] = drop * 0.4
	var low := tuck.duplicate()
	low["hips_rot"] = -PI
	low["hips_y"] = drop
	var end := tuck.duplicate()
	end["hips_rot"] = -TAU * 0.92
	end["hips_y"] = drop * 0.5
	var up := {"hips_rot": -TAU, "Spine": Vector3(-0.15, 0, 0), "ThighL": Vector3(0.2, 0, 0), "KneeL": Vector3(-0.3, 0, 0)}
	return _make(rig, [[0.0, {}], [0.08, start], [0.25, low], [0.4, end], [DODGE_LENGTH, up]], DODGE_LENGTH, false)


## Gather magic in both hands, then thrust them forward. Played time-scaled to the spell's cast time.
static func _cast(rig: CharacterRig) -> Animation:
	var gather := {
		"Spine": Vector3(0.05, 0.25, 0), "Chest": Vector3(0.05, 0.2, 0), "Head": Vector3(0.0, -0.3, 0),
		"ShoulderR": Vector3(0.5, -0.3, 0.7), "ElbowR": Vector3(1.6, 0, 0), "HandR": Vector3(0.4, 0, 0),
		"ShoulderL": Vector3(1.0, 0.3, -0.2), "ElbowL": Vector3(0.7, 0, 0), "HandL": Vector3(-0.3, 0, 0),
	}
	var held := gather.duplicate()
	held["ShoulderR"] = Vector3(0.65, -0.3, 0.8)
	held["Chest"] = Vector3(0.08, 0.25, 0)
	var release := {
		"Spine": Vector3(-0.12, -0.12, 0), "Chest": Vector3(-0.05, -0.1, 0), "Head": Vector3(0.05, 0.1, 0),
		"ShoulderR": Vector3(1.55, 0.1, -0.05), "ElbowR": Vector3(0.08, 0, 0), "HandR": Vector3(-0.6, 0, 0),
		"ShoulderL": Vector3(1.45, -0.1, 0.05), "ElbowL": Vector3(0.1, 0, 0), "HandL": Vector3(-0.6, 0, 0),
	}
	var r := CAST_RELEASE_AT
	return _make(rig, [[0.0, {}], [0.2, gather], [r - 0.04, held], [r + 0.08, release], [0.86, release], [CAST_LENGTH, gather.duplicate().merged({"ShoulderR": Vector3(0.6, 0, 0.3), "ShoulderL": Vector3(0.6, 0, -0.2)}, true)]], CAST_LENGTH, false)


static func _hit(rig: CharacterRig) -> Animation:
	var flinch := {
		"Spine": Vector3(0.3, 0.1, 0.05), "Chest": Vector3(0.15, 0, 0), "Neck": Vector3(0.15, 0, 0), "Head": Vector3(0.25, 0.2, 0.15),
		"ShoulderL": Vector3(-0.35, 0, -0.5), "ShoulderR": Vector3(-0.3, 0, 0.55), "ElbowL": Vector3(0.6, 0, 0), "ElbowR": Vector3(0.7, 0, 0),
	}
	var recoil := {"Spine": Vector3(-0.08, 0, 0), "Head": Vector3(-0.08, 0, 0), "ShoulderL": Vector3(0.2, 0, 0), "ShoulderR": Vector3(0.2, 0, 0)}
	return _make(rig, [[0.0, {}], [0.07, flinch], [0.22, recoil], [0.4, {}]], 0.4, false)


## An explaining gesture for dialogue: right hand up, a couple of nods.
static func _talk(rig: CharacterRig) -> Animation:
	var a := {"ShoulderR": Vector3(0.6, 0, 0.15), "ElbowR": Vector3(1.3, 0, 0), "HandR": Vector3(0.3, 0, 0), "Head": Vector3(-0.05, 0.1, 0)}
	var b := {"ShoulderR": Vector3(0.85, 0.2, 0.3), "ElbowR": Vector3(1.0, 0, 0), "HandR": Vector3(-0.2, 0, 0), "Head": Vector3(0.06, 0.05, 0.05), "Chest": Vector3(0, 0.08, 0)}
	var c := {"ShoulderR": Vector3(0.55, -0.1, 0.1), "ElbowR": Vector3(1.4, 0, 0), "ShoulderL": Vector3(0.3, 0, 0.0), "ElbowL": Vector3(0.6, 0, 0), "Head": Vector3(-0.08, -0.08, 0)}
	return _make(rig, [[0.0, {}], [0.3, a], [0.8, b], [1.3, c], [1.7, a], [2.0, {}]], 2.0, false)


# --- Helpers ---

## Swaps left and right (and mirrors yaw and roll) for the second half of a cycle.
static func _mirror(pose: Dictionary) -> Dictionary:
	var out := {}
	for key in pose:
		var value = pose[key]
		var target: String = key
		if key.ends_with("L"):
			target = key.left(-1) + "R"
		elif key.ends_with("R"):
			target = key.left(-1) + "L"
		if value is Vector3:
			value = Vector3(value.x, -value.y, -value.z)
		out[target] = value
	return out


## Builds an animation keying every joint (and the hips height and roll) at each key time.
static func _make(rig: CharacterRig, keys: Array, length: float, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for entry in CharacterBuilder.JOINTS:
		var joint: String = entry[0]
		var track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, NodePath(rig.joint_path(joint) + ":rotation"))
		anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		var rest: Vector3 = rig.rest_rotation(joint)
		for k in keys:
			var pose: Dictionary = k[1]
			var value: Vector3 = rest + pose.get(joint, Vector3.ZERO)
			if joint == "Hips":
				value.x += float(pose.get("hips_rot", 0.0))
			anim.track_insert_key(track, float(k[0]), value)
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath(rig.joint_path("Hips") + ":position"))
	anim.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_CUBIC)
	var hips_rest: Vector3 = rig.rest_position("Hips")
	for k in keys:
		anim.track_insert_key(pos_track, float(k[0]), hips_rest + Vector3(0, float(k[1].get("hips_y", 0.0)), 0))
	return anim
