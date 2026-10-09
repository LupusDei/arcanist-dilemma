extends Node3D
## Dungeon entrances in the meadow: a stone archway over stairs into the
## ground. Walk up and press E (interact) to go down. Levels the ground and
## reserves the spot so trees stay clear, so it must come before Vegetation.

const SITES := [
	{"recipe": "res://world/dungeons/recipes/ruined_crypt.tres", "seed": 101, "at": Vector2(46, -8), "facing": Vector2(-1, 0)},
	{"recipe": "res://world/dungeons/recipes/drowned_chapel.tres", "seed": 202, "offset_from_hill": Vector2(11, 7), "facing": Vector2(0, 1)},
]

@export var terrain_path: NodePath = ^"../Terrain"

var _terrain: Terrain
var _stone: StandardMaterial3D
var _entrances: Array[Dictionary] = []


func _ready() -> void:
	_terrain = get_node(terrain_path) as Terrain
	_terrain.generate()
	_stone = StandardMaterial3D.new()
	_stone.albedo_color = Color(0.55, 0.54, 0.56)
	_stone.roughness = 0.95
	for site in SITES:
		var at: Vector2 = site.get("at", Vector2.ZERO)
		if site.has("offset_from_hill"):
			at = _terrain.hill_center + site["offset_from_hill"]
		var height := _terrain.height_at(at.x, at.y)
		_terrain.flatten_rect(at, Vector2(4.5, 4.5), 0.0, height, 3.0)
		_terrain.reserve_area(at, 7.0, true)
		var recipe: DungeonRecipe = load(site["recipe"])
		_build_entrance(at, height, site["facing"], recipe, site)
	_terrain.rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_interact(event):
		return
	for entrance in _entrances:
		if entrance["area"].overlaps_body(_player()):
			get_viewport().set_input_as_handled()
			var session := get_tree().get_first_node_in_group(&"game_session")
			if session != null:
				session.enter_dungeon(entrance["recipe_path"], entrance["seed"], entrance["return"])
			return


func _process(_delta: float) -> void:
	var player := _player()
	for entrance in _entrances:
		entrance["prompt"].visible = player != null and entrance["area"].overlaps_body(player)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


static func _is_interact(event: InputEvent) -> bool:
	if InputMap.has_action(&"interact"):
		return event.is_action_pressed(&"interact")
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E


func _build_entrance(at: Vector2, height: float, facing: Vector2, recipe: DungeonRecipe, site: Dictionary) -> void:
	var root := Node3D.new()
	root.name = recipe.display_name.to_pascal_case() + "Entrance"
	root.position = Vector3(at.x, height, at.y)
	root.rotation.y = atan2(facing.x, facing.y)
	add_child(root)
	var body := StaticBody3D.new()
	root.add_child(body)

	# Two pillars and a lintel over a dark stairwell, ringed by fallen stones.
	for x in [-1.7, 1.7]:
		_solid(root, body, Vector3(0.9, 4.2, 0.9), Vector3(x, 2.1, 0))
	_solid(root, body, Vector3(4.6, 0.8, 1.1), Vector3(0, 4.5, 0))
	_box(root, Vector3(2.4, 0.06, 3.0), Vector3(0, 0.03, -1.2), Color(0.04, 0.03, 0.05))
	for i in 4:
		_box(root, Vector3(2.4, 0.25, 0.6), Vector3(0, -0.15 - i * 0.25, -0.2 - i * 0.6), Color(0.35, 0.34, 0.36))
	for side in [-1.0, 1.0]:
		_solid(root, body, Vector3(0.5, 0.9, 3.4), Vector3(side * 1.45, 0.45, -1.4))
	var rune := _box(root, Vector3(1.4, 0.5, 0.1), Vector3(0, 4.5, 0.58), Color(0.45, 0.8, 1.0))
	var glow := rune.material_override as StandardMaterial3D
	glow.emission_enabled = true
	glow.emission = Color(0.4, 0.8, 1.0)
	glow.emission_energy_multiplier = 2.5
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.75, 1.0)
	light.light_energy = 1.5
	light.omni_range = 6.0
	light.position = Vector3(0, 2.0, -1.0)
	root.add_child(light)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 5.0)
	shape.shape = box
	shape.position = Vector3(0, 1.5, 0.5)
	area.add_child(shape)
	root.add_child(area)

	var prompt := Label3D.new()
	prompt.text = "%s  (levels %d to %d)\nPress %s to enter" % [recipe.display_name, recipe.level_min, recipe.level_max, "E"]
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.font_size = 48
	prompt.outline_size = 12
	prompt.pixel_size = 0.006
	prompt.position = Vector3(0, 5.6, 0)
	prompt.visible = false
	root.add_child(prompt)

	var sign_label := Label3D.new()
	sign_label.text = recipe.display_name
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.font_size = 40
	sign_label.outline_size = 10
	sign_label.pixel_size = 0.008
	sign_label.position = Vector3(0, 6.6, 0)
	root.add_child(sign_label)

	var outside := Vector3(at.x, height, at.y) + Vector3(facing.x, 0, facing.y) * 3.5
	_entrances.append({"area": area, "prompt": prompt, "recipe_path": site["recipe"], "seed": site["seed"], "return": outside + Vector3.UP * 0.5})


func _solid(root: Node3D, body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _stone
	mesh.position = at
	root.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = at
	body.add_child(shape)


func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	mesh.position = at
	root.add_child(mesh)
	return mesh
