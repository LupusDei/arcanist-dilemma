class_name CharacterBuilder
extends RefCounted
## Builds a cartoon-realism character out of primitives: a joint hierarchy
## (Hips, Spine, Chest, Neck, Head, shoulders, elbows, hands, thighs, knees,
## feet) with rigid mesh parts on each joint, so animations only rotate joints.
##
## The model faces -Z (the player controller's forward), stands on y = 0 and is
## about 1.65m tall for the player. Proportions follow the concept turnaround:
## big head and eyes, slim limbs, chunky boots.
##
##   var rig := CharacterBuilder.build(Progression.appearance)   # any CharacterSpec.from_any() source
##   $Model.add_child(rig)

## Joint names, parent first. Animations address these by name.
const JOINTS := [
	["Hips", ""], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"],
	["ShoulderL", "Chest"], ["ElbowL", "ShoulderL"], ["HandL", "ElbowL"],
	["ShoulderR", "Chest"], ["ElbowR", "ShoulderR"], ["HandR", "ElbowR"],
	["ThighL", "Hips"], ["KneeL", "ThighL"], ["FootL", "KneeL"],
	["ThighR", "Hips"], ["KneeR", "ThighR"], ["FootR", "KneeR"],
]


## A new rig built from any appearance source (see CharacterSpec.from_any).
static func build(source = null) -> CharacterRig:
	var rig := CharacterRig.new()
	rig.name = "Character"
	populate(rig, CharacterSpec.from_any(source))
	return rig


## Clears [param rig] and builds [param spec] into it. Used for live appearance changes.
static func populate(rig: CharacterRig, spec: CharacterSpec) -> void:
	rig.clear_model()
	rig.spec = spec
	var d := dimensions(spec)
	rig.dims = d
	var pal := CharacterOutfits.palette_for(spec)
	var model := Node3D.new()
	model.name = "Body"
	model.scale = Vector3.ONE * d.scale
	rig.add_child(model)
	rig.body_root = model
	_make_joints(rig, model, d)
	if not _build_sculpted(rig, spec, d, pal):
		_build_body(rig, spec, d, pal)
		_build_head(rig, spec, d)
		_build_hair(rig, spec, d)
	CharacterOutfits.dress(rig, spec, d, pal)
	CharacterOutfits.add_hat(rig, spec, d, pal)
	CharacterOutfits.add_prop(rig, spec, d)
	CharacterOutfits.add_magic(rig, spec, d)
	merge_parts(rig)
	rig.finish_build()


## Body measurements in metres before the overall scale. Children have shorter
## limbs and a bigger head; elders stoop.
static func dimensions(spec: CharacterSpec) -> Dictionary:
	var b: Dictionary = CharacterStyle.BUILDS.get(spec.build, CharacterStyle.BUILDS["average"])
	var girl := spec.body == "girl"
	var child := spec.age <= 0
	var limb := 0.86 if child else 1.0
	var d := {
		"scale": spec.height * (0.74 if child else (0.97 if spec.age >= 3 else 1.0)),
		"thigh": 0.38 * limb,
		"shin": 0.36 * limb,
		"foot": 0.08,
		"pelvis": 0.2,
		"chest": 0.27 * (0.9 if child else 1.0),
		"neck": 0.06,
		"head_r": 0.155 * (1.15 if child else 1.0) * (0.97 if girl else 1.0),
		"upper_arm": 0.27 * limb,
		"forearm": 0.25 * limb,
		"shoulder_x": 0.185 * float(b.shoulders) * (0.92 if girl else 1.0),
		"hip_x": 0.095 * (1.06 if girl else 1.0),
		"limb_r": 0.05 * float(b.limbs),
		"waist": float(b.waist) * (0.9 if girl else 1.0),
		"shoulders": float(b.shoulders) * (0.94 if girl else 1.0),
		"stoop": 0.22 if spec.age >= 3 else 0.0,
	}
	d["hip_y"] = d.thigh + d.shin + d.foot + 0.02
	d["height_m"] = (d.hip_y + d.pelvis + d.chest + d.neck + d.head_r * 2.1) * d.scale
	return d


static func _make_joints(rig: CharacterRig, model: Node3D, d: Dictionary) -> void:
	var pos := {
		"Hips": Vector3(0, d.hip_y, 0),
		"Spine": Vector3(0, 0.0, 0),
		"Chest": Vector3(0, d.pelvis, 0),
		"Neck": Vector3(0, d.chest, 0),
		"Head": Vector3(0, d.neck + d.head_r * 0.85, 0),
		"ShoulderL": Vector3(-d.shoulder_x, d.chest - 0.05, 0),
		"ShoulderR": Vector3(d.shoulder_x, d.chest - 0.05, 0),
		"ElbowL": Vector3(0, -d.upper_arm, 0),
		"ElbowR": Vector3(0, -d.upper_arm, 0),
		"HandL": Vector3(0, -d.forearm, 0),
		"HandR": Vector3(0, -d.forearm, 0),
		"ThighL": Vector3(-d.hip_x, -0.02, 0),
		"ThighR": Vector3(d.hip_x, -0.02, 0),
		"KneeL": Vector3(0, -d.thigh, 0),
		"KneeR": Vector3(0, -d.thigh, 0),
		"FootL": Vector3(0, -d.shin, 0),
		"FootR": Vector3(0, -d.shin, 0),
	}
	# Rest pose: arms slightly out and forward, elbows a touch bent, elders stooped.
	var rest := {
		"Spine": Vector3(-d.stoop * 0.6, 0, 0),
		"Neck": Vector3(d.stoop * 0.8, 0, 0),
		"ShoulderL": Vector3(0.05, 0, -0.16),
		"ShoulderR": Vector3(0.05, 0, 0.16),
		"ElbowL": Vector3(0.18, 0, 0),
		"ElbowR": Vector3(0.18, 0, 0),
	}
	for entry in JOINTS:
		var j := Node3D.new()
		j.name = entry[0]
		j.position = pos[entry[0]]
		j.rotation = rest.get(entry[0], Vector3.ZERO)
		var parent: Node3D = model if entry[1] == "" else rig.joints[entry[1]]
		parent.add_child(j)
		rig.joints[entry[0]] = j
	for side in ["L", "R"]:
		var socket := Node3D.new()
		socket.name = "ItemSocket" + side
		socket.position = Vector3(0, -0.06, -0.01)
		rig.joints["Hand" + side].add_child(socket)
		rig.sockets["item_" + side.to_lower()] = socket
		var cast := Marker3D.new()
		cast.name = "CastPoint" + side
		cast.position = Vector3(0, -0.08, -0.06)
		rig.joints["Hand" + side].add_child(cast)
		rig.sockets["cast_" + side.to_lower()] = cast
	var hat := Node3D.new()
	hat.name = "HatSocket"
	hat.position = Vector3(0, d.head_r * 0.62, 0.0)
	rig.joints["Head"].add_child(hat)
	rig.sockets["hat"] = hat
	var back := Node3D.new()
	back.name = "BackSocket"
	back.position = Vector3(0, d.chest * 0.55, 0.16)
	rig.joints["Chest"].add_child(back)
	rig.sockets["back"] = back


## The sculpted model (see CharacterMeshes): a smooth body skinned to the joints,
## and the head, eyes, brows and hair on the Head joint. Returns false when the
## meshes for this look aren't baked, so the primitive model is built instead.
static func _build_sculpted(rig: CharacterRig, spec: CharacterSpec, d: Dictionary, pal: Dictionary) -> bool:
	var body_mesh := CharacterMeshes.body(spec.body, spec.build, spec.age)
	var head_mesh := CharacterMeshes.head(spec.body, spec.face, spec.age)
	if body_mesh == null or head_mesh == null:
		return false
	var skin: Color = CharacterStyle.SKINS.get(spec.skin, CharacterStyle.SKINS["fair"])
	var hair_color := hair_color_for(spec)
	var girl := spec.body == "girl"
	var child := spec.age <= 0
	rig.sculpted = true
	# Skeleton mirroring the joints; CharacterRig copies the joints' poses onto it every frame.
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	rig.body_root.add_child(skel)
	rig.skeleton = skel
	for entry in JOINTS:
		var j: Node3D = rig.joints[entry[0]]
		var i := skel.add_bone(entry[0])
		if entry[1] != "":
			skel.set_bone_parent(i, skel.find_bone(entry[1]))
		# The meshes are sculpted standing straight; an elder's stoop is a pose on top.
		var rest_rot := Vector3.ZERO if entry[0] in ["Spine", "Neck"] else j.rotation
		skel.set_bone_rest(i, Transform3D(Basis.from_euler(rest_rot), j.position))
	skel.reset_bone_poses()
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.mesh = body_mesh
	skel.add_child(body)
	body.skeleton = NodePath("..")
	var body_mat := CharacterMeshes.body_material(skin, pal)
	body_mat.set_shader_parameter("vneck_y", float(body_mesh.get_meta("vneck_y", 10.0)) if spec.outfit == "farm" or spec.outfit == "villager" else 10.0)
	body_mat.set_shader_parameter("vneck_slope", float(body_mesh.get_meta("vneck_slope", 1.6)))
	var hand_mat := CharacterMeshes.skin_material(skin)
	for s in body_mesh.get_surface_count():
		body.set_surface_override_material(s, body_mat if body_mesh.surface_get_name(s) == "body" else hand_mat)
	rig.shader_materials.append_array([body_mat, hand_mat])
	rig.built_parts.append_array(["BodyMesh", "HandL", "HandR"])
	# Head, eyes, brows and lashes.
	var head_scale: float = d.head_r / CharacterMeshes.BASE_HEAD_R
	var head := MeshInstance3D.new()
	head.name = "HeadMesh"
	head.mesh = head_mesh
	head.scale = Vector3.ONE * head_scale
	var face_mat := CharacterMeshes.skin_material(skin, true, girl, child)
	face_mat.set_shader_parameter("mouth_y", float(head_mesh.get_meta("mouth_y", -0.5)))
	face_mat.set_shader_parameter("cheek_x", float(head_mesh.get_meta("cheek_x", 0.43)))
	var eye_mat := CharacterMeshes.eye_material(CharacterStyle.EYES.get(spec.eyes, CharacterStyle.EYES["brown"]))
	var brow_mat := CharacterMeshes.hair_material(hair_color.darkened(0.12))
	for s in head_mesh.get_surface_count():
		match head_mesh.surface_get_name(s):
			"skin": head.set_surface_override_material(s, face_mat)
			"eye": head.set_surface_override_material(s, eye_mat)
			"hair": head.set_surface_override_material(s, brow_mat)
			_: head.set_surface_override_material(s, CharacterMeshes.lash_material())
	rig.joints["Head"].add_child(head)
	rig.shader_materials.append_array([face_mat, eye_mat, brow_mat])
	rig.built_parts.append_array(["HeadMesh", "Eyes", "Brows"])
	# Hair, groomed on the round skull and widened to this face.
	var hair_mesh := CharacterMeshes.hair(spec.hair_style)
	if hair_mesh:
		var hair := MeshInstance3D.new()
		hair.name = "Hair"
		hair.mesh = hair_mesh
		hair.scale = Vector3(float(head_mesh.get_meta("cranium_w", 1.0)), 1, 1) * head_scale
		var hair_mat := CharacterMeshes.hair_material(hair_color)
		if spec.hair_style == "shaved":
			hair_mat.set_shader_parameter("stubble", 1.0)
		hair.material_override = hair_mat
		rig.joints["Head"].add_child(hair)
		rig.shader_materials.append(hair_mat)
		rig.built_parts.append("Hair")
	if spec.beard in ["full", "long"]:
		var beard_mesh := CharacterMeshes.beard(spec.face, spec.beard)
		if beard_mesh:
			var beard := MeshInstance3D.new()
			beard.name = "Beard"
			beard.mesh = beard_mesh
			beard.scale = Vector3.ONE * head_scale
			var beard_mat := CharacterMeshes.hair_material(hair_color)
			beard.material_override = beard_mat
			rig.joints["Head"].add_child(beard)
			rig.shader_materials.append(beard_mat)
			rig.built_parts.append("Beard")
	elif spec.beard == "stubble":
		face_mat.set_shader_parameter("stubble_color", hair_color)
		face_mat.set_shader_parameter("stubble", 0.6)
	return true


## Hair colour for a look; elders go grey.
static func hair_color_for(spec: CharacterSpec) -> Color:
	var color: Color = CharacterStyle.HAIR_COLORS.get(spec.hair_color, CharacterStyle.HAIR_COLORS["brown"])
	if spec.age >= 3:
		color = color.lerp(Color("#e8e6e0"), 0.85)
	return color


static func _build_body(rig: CharacterRig, spec: CharacterSpec, d: Dictionary, pal: Dictionary) -> void:
	var skin: Color = CharacterStyle.SKINS.get(spec.skin, CharacterStyle.SKINS["fair"])
	var top: Color = pal.top
	var bottom: Color = pal.bottom
	var w: float = d.waist
	var sh: float = d.shoulders
	var lr: float = d.limb_r
	# Pelvis and belly.
	part(rig, "Hips", "Pelvis", sphere(0.16), Vector3(0, 0.02, 0), bottom, Vector3(w * 1.02, 0.7, 0.78))
	part(rig, "Spine", "Waist", cylinder(0.13 * w, 0.14 * w, d.pelvis + 0.04), Vector3(0, d.pelvis * 0.5, 0), top, Vector3(1, 1, 0.78))
	# Chest: a wide, slightly flattened ellipsoid that gives the shoulders their line.
	part(rig, "Chest", "Torso", sphere(0.17), Vector3(0, d.chest * 0.5, 0.0), top, Vector3(1.18 * sh, 1.05, 0.78))
	part(rig, "Chest", "ShoulderPadL", sphere(0.062), Vector3(-d.shoulder_x, d.chest - 0.06, 0), top)
	part(rig, "Chest", "ShoulderPadR", sphere(0.062), Vector3(d.shoulder_x, d.chest - 0.06, 0), top)
	part(rig, "Neck", "NeckSkin", cylinder(0.045, 0.05, d.neck + 0.08), Vector3(0, 0.03, 0), skin)
	# Arms: sleeves to the wrist, skin hands.
	for side in ["L", "R"]:
		limb(rig, "Shoulder" + side, "UpperArm" + side, lr * 1.05, d.upper_arm, top)
		limb(rig, "Elbow" + side, "Forearm" + side, lr * 0.92, d.forearm, top)
		part(rig, "Elbow" + side, "Cuff" + side, cylinder(lr * 1.05, lr * 1.12, 0.05), Vector3(0, -d.forearm + 0.035, 0), top.darkened(0.12))
		var hand := part(rig, "Hand" + side, "Hand" + side + "Mesh", sphere(0.048), Vector3(0, -0.04, 0), skin, Vector3(0.9, 1.15, 0.7))
		part(rig, "Hand" + side, "Thumb" + side, sphere(0.02), Vector3(0.03 * (1 if side == "L" else -1), -0.03, -0.03), skin, Vector3(1, 1.6, 1))
		hand.set_meta("skin", true)
		# Legs: trousers to mid-shin, boots below.
		limb(rig, "Thigh" + side, "Thigh" + side + "Mesh", lr * 1.45, d.thigh, bottom)
		limb(rig, "Knee" + side, "Shin" + side, lr * 1.15, d.shin, bottom)
		part(rig, "Knee" + side, "Boot" + side, cylinder(lr * 1.3, lr * 1.42, d.shin * 0.48), Vector3(0, -d.shin * 0.76, 0), pal.boots)
		part(rig, "Foot" + side, "Toe" + side, sphere(0.07), Vector3(0, -d.foot * 0.45, -0.06), pal.boots, Vector3(0.9, 0.62, 1.55))
		part(rig, "Foot" + side, "Sole" + side, box(Vector3(0.12, 0.025, 0.24)), Vector3(0, -d.foot + 0.012, -0.04), Color("#3a2618"))


static func _build_head(rig: CharacterRig, spec: CharacterSpec, d: Dictionary) -> void:
	var r: float = d.head_r
	var f: Dictionary = CharacterStyle.FACES.get(spec.face, CharacterStyle.FACES["round"])
	var skin: Color = CharacterStyle.SKINS.get(spec.skin, CharacterStyle.SKINS["fair"])
	var hair: Color = CharacterStyle.HAIR_COLORS.get(spec.hair_color, CharacterStyle.HAIR_COLORS["brown"])
	if spec.age >= 3:
		hair = hair.lerp(Color("#e8e6e0"), 0.85)
	var eye: Color = CharacterStyle.EYES.get(spec.eyes, CharacterStyle.EYES["brown"])
	var girl := spec.body == "girl"
	var wx: float = float(f.width) * (0.95 if girl else 1.0)
	var hy: float = float(f.height)
	var jaw: float = float(f.jaw) + (0.08 if girl else 0.0)
	part(rig, "Head", "Skull", sphere(r), Vector3.ZERO, skin, Vector3(wx, hy, 1.0))
	part(rig, "Head", "Jaw", sphere(r * 0.74), Vector3(0, -r * 0.36, -r * 0.05), skin, Vector3(wx * (1.1 - jaw * 1.4), 0.86, 1.0))
	if jaw < -0.05:
		part(rig, "Head", "JawLine", box(Vector3(r * 1.25 * wx, r * 0.35, r * 1.0)), Vector3(0, -r * 0.62, -r * 0.08), skin)
	part(rig, "Head", "EarL", sphere(r * 0.2), Vector3(-r * wx * 0.98, -r * 0.05, r * 0.05), skin, Vector3(0.6, 1.1, 0.9))
	part(rig, "Head", "EarR", sphere(r * 0.2), Vector3(r * wx * 0.98, -r * 0.05, r * 0.05), skin, Vector3(0.6, 1.1, 0.9))
	# Big cartoon eyes sitting on the face's surface.
	var eye_x := r * 0.36 * wx
	var eye_y := r * 0.02
	for sx in [-1.0, 1.0]:
		var side := "L" if sx < 0 else "R"
		var surf := _surface_z(Vector2(eye_x * sx, eye_y), r, wx, hy)
		part(rig, "Head", "EyeWhite" + side, sphere(r * 0.24), Vector3(eye_x * sx, eye_y, surf + r * 0.1), Color("#f7f4ef"), Vector3(0.9, 1.1, 0.6))
		part(rig, "Head", "Iris" + side, sphere(r * 0.16), Vector3(eye_x * sx, eye_y - r * 0.01, surf - r * 0.02), eye, Vector3(0.9, 1.1, 0.5))
		part(rig, "Head", "Pupil" + side, sphere(r * 0.085), Vector3(eye_x * sx, eye_y - r * 0.01, surf - r * 0.07), Color("#100c0a"), Vector3(1, 1.1, 0.5))
		var shine := part(rig, "Head", "Shine" + side, sphere(r * 0.035), Vector3(eye_x * sx + r * 0.04, eye_y + r * 0.05, surf - r * 0.1), Color.WHITE)
		shine.material_override = CharacterStyle.glow(Color(1, 1, 1), 1.2)
		var brow := part(rig, "Head", "Brow" + side, box(Vector3(r * 0.36, r * 0.07, r * 0.08)), Vector3(eye_x * sx, eye_y + r * 0.3, surf + r * 0.02), hair.darkened(0.15))
		brow.rotation.z = -0.12 * sx
		if girl:
			for i in 2:
				var lash := part(rig, "Head", "Lash%s%d" % [side, i], box(Vector3(r * 0.13, r * 0.045, r * 0.05)), Vector3(eye_x * sx + r * (0.19 + i * 0.05) * sx, eye_y + r * (0.15 - i * 0.06), surf + r * 0.04), Color("#1a1210"))
				lash.rotation.z = (0.45 + i * 0.35) * sx
	var nose_z := _surface_z(Vector2(0, -r * 0.18), r, wx, hy)
	part(rig, "Head", "Nose", sphere(r * 0.11), Vector3(0, -r * 0.18, nose_z - r * 0.02), skin.darkened(0.04), Vector3(0.9, 0.8, 1.0))
	var lip := skin.darkened(0.45).lerp(Color("#8a3a36"), 0.5)
	var mouth := part(rig, "Head", "Mouth", capsule(r * 0.05, r * 0.34), Vector3(0, -r * 0.47, _surface_z(Vector2(0, -r * 0.47), r * 0.98, wx * 0.95, hy) + r * 0.01), lip)
	mouth.rotation.z = PI / 2
	# A gentle smile: the mouth's corners turned up.
	for sx in [-1.0, 1.0]:
		var corner := part(rig, "Head", "MouthCorner" + ("L" if sx < 0 else "R"), capsule(r * 0.045, r * 0.13), Vector3(r * 0.17 * sx, -r * 0.43, _surface_z(Vector2(r * 0.17, -r * 0.43), r * 0.98, wx * 0.95, hy) + r * 0.03), lip)
		corner.rotation.z = 0.9 * sx
	if girl or spec.age <= 0:
		for sx in [-1.0, 1.0]:
			var blush := part(rig, "Head", "Blush" + ("L" if sx < 0 else "R"), sphere(r * 0.16), Vector3(r * 0.5 * wx * sx, -r * 0.24, _surface_z(Vector2(r * 0.5 * wx, -r * 0.24), r, wx, hy) + r * 0.07), Color("#e07a6e"), Vector3(1.2, 0.7, 0.4))
			blush.transparency = 0.6
	if spec.beard != "":
		_build_beard(rig, spec.beard, r, wx, hair)


static func _build_beard(rig: CharacterRig, kind: String, r: float, wx: float, color: Color) -> void:
	match kind:
		"stubble":
			var stubble := part(rig, "Head", "Stubble", sphere(r * 0.74), Vector3(0, -r * 0.44, -r * 0.14), color.lerp(Color.BLACK, 0.2), Vector3(wx * 1.06, 0.82, 1.0))
			stubble.transparency = 0.6
		"full", "long":
			var length := 1.0 if kind == "full" else 1.6
			part(rig, "Head", "Beard", sphere(r * 0.62), Vector3(0, -r * (0.62 + length * 0.12), -r * 0.42), color, Vector3(wx * 1.15, 0.9 * length, 0.85))
			part(rig, "Head", "BeardSides", sphere(r * 0.74), Vector3(0, -r * 0.4, -r * 0.1), color, Vector3(wx * 1.1, 0.75, 0.95))
			for sx in [-1.0, 1.0]:
				var tash := part(rig, "Head", "Moustache" + ("L" if sx < 0 else "R"), capsule(r * 0.08, r * 0.42), Vector3(r * 0.16 * sx, -r * 0.33, -r * 0.88), color)
				tash.rotation.z = (PI / 2) + 0.35 * sx
			# Bushy brows to match.
			for side in ["L", "R"]:
				var brow: MeshInstance3D = rig.joints["Head"].get_node("Brow" + side)
				brow.scale = Vector3(1.3, 1.8, 1.4)
				(brow.material_override as StandardMaterial3D).albedo_color = color


static func _build_hair(rig: CharacterRig, spec: CharacterSpec, d: Dictionary) -> void:
	var r: float = d.head_r
	var f: Dictionary = CharacterStyle.FACES.get(spec.face, CharacterStyle.FACES["round"])
	var wx: float = float(f.width) * (0.95 if spec.body == "girl" else 1.0)
	var color: Color = CharacterStyle.HAIR_COLORS.get(spec.hair_color, CharacterStyle.HAIR_COLORS["brown"])
	if spec.age >= 3:
		color = color.lerp(Color("#e8e6e0"), 0.85)
	var style := spec.hair_style
	var thickness := 1.02 if style == "shaved" else 1.09
	# The cap: a dome tilted back so the hairline sits high on the forehead and low at the nape.
	var cap := part(rig, "Head", "HairCap", sphere(r * thickness, true), Vector3(0, r * 0.08, r * 0.04), color, Vector3(wx, 1.0, 1.04))
	cap.rotation.x = 0.42
	part(rig, "Head", "HairBack", sphere(r * thickness * 0.98), Vector3(0, -r * 0.05, r * 0.2), color, Vector3(wx * 0.98, 0.95, 0.82))
	if style == "shaved":
		cap.transparency = 0.25
		rig.joints["Head"].get_node("HairBack").transparency = 0.25
		return
	# Sideburns.
	for sx in [-1.0, 1.0]:
		part(rig, "Head", "Sideburn" + ("L" if sx < 0 else "R"), box(Vector3(r * 0.12, r * 0.42, r * 0.3)), Vector3(r * wx * 0.92 * sx, r * 0.1, -r * 0.18), color)
	match style:
		"short":
			part(rig, "Head", "Fringe", sphere(r * 0.5), Vector3(0, r * 0.66, -r * 0.62), color, Vector3(wx * 1.5, 0.5, 0.6))
		"tousled":
			# Spiky tufts like the concept boy's.
			var tufts := [
				Vector3(0.0, 0.98, -0.45), Vector3(-0.35, 0.9, -0.5), Vector3(0.38, 0.88, -0.42),
				Vector3(-0.15, 1.05, 0.0), Vector3(0.22, 1.0, 0.15), Vector3(-0.5, 0.75, 0.1),
				Vector3(0.55, 0.7, 0.05), Vector3(0.05, 0.85, 0.5), Vector3(-0.25, 0.65, -0.72),
				Vector3(0.18, 0.62, -0.78),
			]
			for i in tufts.size():
				var t: Vector3 = tufts[i]
				var tuft := part(rig, "Head", "Tuft%d" % i, prism(Vector3(r * 0.42, r * 0.5, r * 0.3)), Vector3(t.x * r * wx, t.y * r, t.z * r), color)
				tuft.rotation = Vector3(-t.z * 0.9 - 0.2, float(i) * 1.3, t.x * -1.1)
		"long":
			part(rig, "Head", "Fringe", sphere(r * 0.5), Vector3(r * 0.15, r * 0.62, -r * 0.62), color, Vector3(wx * 1.6, 0.5, 0.6))
			part(rig, "Head", "LongBack", capsule(r * 0.75, r * 2.6), Vector3(0, -r * 0.65, r * 0.42), color, Vector3(wx * 1.2, 1.0, 0.55))
			for sx in [-1.0, 1.0]:
				part(rig, "Head", "Lock" + ("L" if sx < 0 else "R"), capsule(r * 0.2, r * 1.9), Vector3(r * wx * 0.9 * sx, -r * 0.5, -r * 0.1), color)
		"braid":
			part(rig, "Head", "Fringe", sphere(r * 0.5), Vector3(-r * 0.2, r * 0.62, -r * 0.62), color, Vector3(wx * 1.5, 0.5, 0.6))
			# The braid hangs from the nape over the right shoulder, like the concept girl's.
			for i in 6:
				var t := float(i)
				part(rig, "Head", "Braid%d" % i, sphere(r * (0.3 - t * 0.025)), Vector3(r * (0.3 + t * 0.12), -r * (0.55 + t * 0.42), r * (0.75 - t * 0.2)), color)
			part(rig, "Head", "BraidTie", cylinder(r * 0.14, r * 0.14, r * 0.12), Vector3(r * 1.05, -r * 3.0, -r * 0.45), Color("#7a3b2a"))
			var tip := part(rig, "Head", "BraidTip", prism(Vector3(r * 0.3, r * 0.4, r * 0.2)), Vector3(r * 1.1, -r * 3.25, -r * 0.5), color)
			tip.rotation.x = PI
		"topknot":
			part(rig, "Head", "Bun", sphere(r * 0.38), Vector3(0, r * 1.12, r * 0.22), color)
			part(rig, "Head", "BunTie", cylinder(r * 0.25, r * 0.28, r * 0.1), Vector3(0, r * 0.88, r * 0.15), Color("#7a3b2a"))


## Merges the opaque parts on each joint into one mesh with vertex colours and
## one shared toon material, so a character costs about 20 draw calls instead
## of over 100. Glowing, see-through and prop parts stay separate.
static func merge_parts(rig: CharacterRig) -> void:
	var shared := CharacterStyle.material(Color.WHITE)
	shared.vertex_color_use_as_albedo = true
	shared.vertex_color_is_srgb = true
	rig.skin_material = shared
	for joint_name in rig.joints:
		var joint: Node3D = rig.joints[joint_name]
		var parts: Array[MeshInstance3D] = []
		for child in joint.get_children():
			if child is MeshInstance3D and _mergeable(child):
				parts.append(child)
		if parts.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in parts:
			var color: Color = (mi.material_override as StandardMaterial3D).albedo_color
			var xf := mi.transform
			var normal_basis := xf.basis.inverse().transposed()
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			st.set_color(color)
			if indices.is_empty():
				indices = PackedInt32Array(range(verts.size()))
			for i in indices:
				st.set_normal((normal_basis * normals[i]).normalized())
				st.add_vertex(xf * verts[i])
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = st.commit()
		merged.material_override = shared
		joint.add_child(merged)
		for mi in parts:
			joint.remove_child(mi)
			mi.free()


static func _mergeable(mi: MeshInstance3D) -> bool:
	var m := mi.material_override as StandardMaterial3D
	return m != null and not m.emission_enabled and m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and mi.transparency == 0.0 \
			and mi.mesh.get_surface_count() == 1 and not mi.has_meta("keep")


## Depth of the face's surface at a point on an ellipsoid head, for placing features.
static func _surface_z(at: Vector2, r: float, wx: float, hy: float) -> float:
	var u := at.x / (r * wx)
	var v := at.y / (r * hy)
	return -r * sqrt(maxf(1.0 - u * u - v * v, 0.05))


# --- Mesh helpers. Every part gets its own toon material, registered on the rig. ---

static func part(rig: CharacterRig, joint: String, part_name: String, mesh: Mesh, pos: Vector3, color: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.material_override = CharacterStyle.material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rig.built_parts.append(part_name)
	var parent: Node3D = rig.joints.get(joint, null)
	if parent == null:
		parent = rig.sockets[joint]
	parent.add_child(mi)
	return mi


## A limb segment hanging down from a joint.
static func limb(rig: CharacterRig, joint: String, part_name: String, radius: float, length: float, color: Color) -> MeshInstance3D:
	return part(rig, joint, part_name, capsule(radius, length + radius), Vector3(0, -length * 0.5, 0), color)


static func sphere(radius: float, hemisphere := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemisphere else 2.0)
	m.is_hemisphere = hemisphere
	m.radial_segments = 20
	m.rings = 10
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 14
	m.rings = 4
	return m


static func cylinder(top: float, bottom: float, height: float, sides := 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 8
	return m
