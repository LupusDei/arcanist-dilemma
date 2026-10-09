extends Node3D
## Character preview: the arcanist as boy and girl in every outfit, the old
## man, Tam and a row of villagers, on a turntable under dusk light.
##
## Keys: 1 idle, 2 run, 3 jump, 4 fall, 5 dodge, 6 cast, 7 hit, 8 talk,
## R reroll the arcanists' looks and the villagers, T toggle the turntable,
## left/right orbit the camera, up/down zoom.
##
## Screenshots: godot --path . res://actors/characters/preview/character_preview.tscn -- --shot=user://lineup.png
##   [--view=lineup|close|npcs|faces] [--anim=cast] [--at=0.5 seconds into the animation] [--focus=x,y,z,distance,yaw]

const ANIMS := [&"idle", &"run", &"jump", &"fall", &"dodge", &"cast", &"hit", &"talk"]

var _rigs: Array[CharacterRig] = []
var _arcanists: Array[CharacterRig] = []
var _villagers: Array[CharacterRig] = []
var _stands: Array[Node3D] = []
var _anim := &"idle"
var _turntable := false
var _yaw := 0.0
var _distance := 9.0
var _target := Vector3(0, 0.9, 0)
var _camera: Camera3D
var _rng := RandomNumberGenerator.new()
var _label: Label
var _shot_path := ""
var _shot_frames := 0
var _view := "lineup"
## Seconds of animation to let play before the screenshot (after a warm-up while shaders compile).
var _shot_at := 0.5
var _shot_clock := -1.0


func _ready() -> void:
	_rng.seed = 7
	_build_stage()
	_build_cast()
	_build_hud()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
			_shot_frames = 40
		elif arg.begins_with("--view="):
			_view = arg.trim_prefix("--view=")
		elif arg.begins_with("--at="):
			_shot_at = float(arg.trim_prefix("--at="))
		elif arg.begins_with("--anim="):
			_anim = StringName(arg.trim_prefix("--anim="))
	_apply_view()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--focus="):
			var v := arg.trim_prefix("--focus=").split_floats(",")
			_target = Vector3(v[0], v[1], v[2])
			_distance = v[3]
			_yaw = v[4] if v.size() > 4 else 0.0


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3d5a8a")
	sky_mat.sky_horizon_color = Color("#e8b98a")
	sky_mat.ground_horizon_color = Color("#6b7a5a")
	sky_mat.ground_bottom_color = Color("#2f3a28")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-35), 0)
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	fill.light_color = Color("#8fb4ff")
	fill.light_energy = 0.35
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.material_override = CharacterStyle.material(Color("#5d7a45"), 0.0, 0.0)
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 40
	add_child(_camera)


func _build_cast() -> void:
	# Front row: boy and girl in farm clothes and each path's outfit.
	var x := -7.0
	for body in ["boy", "girl"]:
		for path in ["farm", "wizard", "mage", "sorcerer"]:
			var rig := _place(CharacterSpec.player(body, path), Vector3(x, 0, 0))
			_arcanists.append(rig)
			x += 2.0
	# Back row: the old man, Tam and villagers.
	_place(NpcCatalog.old_man(), Vector3(-6.0, 0, 3.2))
	_place(NpcCatalog.tam(_arcanists[0].spec), Vector3(-4.0, 0, 3.2))
	x = -2.0
	for i in NpcCatalog.ROLES.size():
		_villagers.append(_place(NpcCatalog.villager(100 + i, NpcCatalog.ROLES[i]), Vector3(x, 0, 3.2)))
		x += 1.6


func _place(spec: CharacterSpec, pos: Vector3) -> CharacterRig:
	var stand := Node3D.new()
	stand.position = pos
	add_child(stand)
	var rig := CharacterBuilder.build(spec)
	stand.add_child(rig)
	_rigs.append(rig)
	_stands.append(stand)
	return rig


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	layer.add_child(_label)


func _apply_view() -> void:
	match _view:
		"close":
			_target = Vector3(-4.0, 1.0, 0)
			_distance = 5.2
			_yaw = 0.0
		"npcs":
			_target = Vector3(-0.5, 0.9, 3.2)
			_distance = 11.5
			_yaw = 0.0
			for rig in _arcanists:
				rig.get_parent().visible = false
		"faces":
			_target = Vector3(-6.0, 1.45, 0)
			_distance = 2.4
			_yaw = 0.0
		_:
			_target = Vector3(0, 0.95, 1.4)
			_distance = 17.0
	_play(_anim)


func _process(delta: float) -> void:
	if _turntable:
		for stand in _stands:
			stand.rotation.y += delta * 0.6
	if Input.is_key_pressed(KEY_LEFT):
		_yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_RIGHT):
		_yaw += delta * 1.5
	if Input.is_key_pressed(KEY_UP):
		_distance = maxf(_distance - delta * 6.0, 1.5)
	if Input.is_key_pressed(KEY_DOWN):
		_distance = minf(_distance + delta * 6.0, 30.0)
	var offset := Vector3(sin(_yaw), 0.0, cos(_yaw)) * _distance
	# The characters face -Z, so the camera sits on -Z looking back at them.
	_camera.position = _target - offset + Vector3(0, _distance * 0.18, 0)
	_camera.look_at(_target)
	if _anim == &"run":
		for rig in _rigs:
			rig.update_locomotion(6.5, true)
	_label.text = "Animation: %s   (1-8 animations, R reroll, T turntable, arrows camera)" % _anim
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			# Warmed up: restart the animation and let it play for _shot_at seconds.
			_play(_anim)
			_shot_clock = _shot_at
	elif _shot_clock == 0.0:
		_shot_clock = -1.0
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("saved ", ProjectSettings.globalize_path(_shot_path))
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if _shot_clock > 0.0:
		_shot_clock = maxf(_shot_clock - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_8:
		_play(ANIMS[key - KEY_1])
	elif key == KEY_R:
		_reroll()
	elif key == KEY_T:
		_turntable = not _turntable


func _play(anim: StringName) -> void:
	_anim = anim
	for rig in _rigs:
		match anim:
			&"run", &"idle":
				rig.update_locomotion(6.5 if anim == &"run" else 0.0, true)
			&"jump":
				rig.update_locomotion(0.0, false, 5.0)
			&"fall":
				rig.update_locomotion(0.0, false, -5.0)
			&"dodge":
				rig.update_locomotion(0.0, true)
				rig.play_dodge(0.6)
			&"cast":
				rig.update_locomotion(0.0, true)
				rig.play_cast(0.8)
			&"hit":
				rig.play_hit()
			&"talk":
				rig.play_talk()


func _reroll() -> void:
	for rig in _arcanists:
		var s := rig.spec.duplicate_spec()
		s.face = _random_id(CharacterStyle.FACES)
		s.skin = _random_id(CharacterStyle.SKINS)
		s.hair_style = _random_id(CharacterStyle.HAIR_STYLES)
		s.hair_color = _random_id(CharacterStyle.HAIR_COLORS)
		s.eyes = _random_id(CharacterStyle.EYES)
		s.build = _random_id(CharacterStyle.BUILDS)
		s.dye = _random_id(CharacterStyle.DYES)
		rig.apply_appearance(s)
	for i in _villagers.size():
		_villagers[i].apply_appearance(NpcCatalog.villager(_rng.randi(), NpcCatalog.ROLES[i]))
	_play(_anim)


func _random_id(table) -> String:
	var keys := CharacterStyle.ids(table)
	return keys[_rng.randi_range(0, keys.size() - 1)]
