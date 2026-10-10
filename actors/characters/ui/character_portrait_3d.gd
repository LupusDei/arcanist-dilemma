class_name CharacterPortrait3D
extends SubViewportContainer
## The live 3D character for the creation screen: the real game model, rebuilt
## whenever [member character] changes, lit like a portrait on a small stage.
## It turns gently on its own; dragging spins it, the mouse wheel zooms between
## the full figure and the face. Changing a face, hair or eye option glides the
## camera in to the face; changing the build or body glides back out.
##
##   var portrait := CharacterPortrait3D.new()
##   portrait.character = UiSession.character   # any CharacterSpec.from_any() source

## The look to show. Accepts the creation screen's index dictionary, a
## progression appearance, a dict of preset ids or a CharacterSpec.
var character: Variant = {}:
	set(v):
		var previous = character
		character = v.duplicate() if v is Dictionary else v
		_rebuild()
		_focus_for_change(previous, character)

var rig: CharacterRig
var viewport: SubViewport
var camera: Camera3D

## 0 = full figure, 1 = face.
var zoom := 0.25
var _zoom_target := 0.25
var _yaw := -0.35
var _spin := 0.0
var _dragging := false
var _idle_time := 0.0
var _stand: Node3D
## Turn gently on its own when left alone (off for screenshots).
var sway := true

const FULL := {"target": Vector3(0, 0.88, 0), "distance": 3.3}
const FACE := {"target": Vector3(0, 1.5, 0), "distance": 1.05}
const FACE_KEYS := ["face", "skin", "hair", "hair_color", "eyes", "hair_style"]


func _init() -> void:
	custom_minimum_size = Vector2(360, 470)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = false
	add_child(viewport)
	_build_stage()
	_rebuild()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#16121f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b3b4c8")
	e.ambient_light_energy = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	viewport.add_child(env)
	# Warm key high on the left so the face shows its shape, cool fill from the
	# right, a violet rim from behind.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(128), 0)
	key.light_color = Color("#fff0dc")
	key.light_energy = 0.4
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 4.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.shadow_normal_bias = 2.0
	key.shadow_opacity = 0.45
	key.shadow_blur = 2.5
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10), deg_to_rad(-140), 0)
	fill.light_color = Color("#9fb8ff")
	fill.light_energy = 0.14
	viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(20), 0)
	rim.light_color = Color("#c9a6ff")
	rim.light_energy = 0.16
	viewport.add_child(rim)
	# A round stone dais with a faint glowing ring.
	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.82
	cyl.height = 0.12
	cyl.radial_segments = 48
	dais.mesh = cyl
	dais.position.y = -0.06
	dais.material_override = CharacterStyle.material(Color("#4a4458"), 0.0, 0.1)
	viewport.add_child(dais)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.72
	torus.rings = 64
	ring.mesh = torus
	ring.position.y = 0.002
	ring.material_override = CharacterStyle.glow(Color("#ffd27a"), 1.6)
	viewport.add_child(ring)
	_stand = Node3D.new()
	viewport.add_child(_stand)
	camera = Camera3D.new()
	camera.fov = 32
	viewport.add_child(camera)


func _rebuild() -> void:
	if _stand == null:
		return
	var spec := CharacterSpec.from_any(character if not (character is Dictionary and character.is_empty()) else null)
	if rig == null:
		rig = CharacterBuilder.build(spec)
		rig.name = "Character"
		_stand.add_child(rig)
	else:
		rig.apply_appearance(spec)


func _focus_for_change(previous, current) -> void:
	if not (previous is Dictionary and current is Dictionary) or previous.is_empty():
		return
	for key in current:
		if previous.get(key) != current.get(key):
			if key in FACE_KEYS:
				_zoom_target = 0.85
			elif key in ["build", "sex", "body"]:
				_zoom_target = 0.1
			return


func _process(delta: float) -> void:
	if rig == null or not is_inside_tree():
		return
	_idle_time += delta
	if not _dragging:
		# A slow sway so the model reads as 3D without spinning away from the player.
		_spin = lerpf(_spin, 0.0, delta * 1.5)
		_yaw += _spin * delta
		if sway:
			_yaw = lerpf(_yaw, -0.35 + sin(_idle_time * 0.35) * 0.45, delta * 0.6)
	_stand.rotation.y = _yaw
	zoom = lerpf(zoom, _zoom_target, delta * 3.0)
	var target: Vector3 = (FULL.target as Vector3).lerp(FACE.target, zoom) * Vector3(1, rig.get_height() / 1.69, 1)
	var dist := lerpf(FULL.distance, FACE.distance, zoom)
	camera.look_at_from_position(target + Vector3(0, 0.08 + 0.12 * (1.0 - zoom), -dist), target, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target + 0.15, 0.0, 1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target - 0.15, 0.0, 1.0)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.01
		_spin = mm.velocity.x * 0.004
		accept_event()


## Snaps the view: 0 full figure, 1 face (for screenshots and tests).
func set_zoom(value: float, yaw := -0.35) -> void:
	zoom = value
	_zoom_target = value
	_yaw = yaw
	_idle_time = 0.0
