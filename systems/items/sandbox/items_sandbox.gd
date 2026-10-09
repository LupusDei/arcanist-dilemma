extends Node3D
## Loot sandbox: a floor, a stand-in arcanist, two chests and hotkeys to rain
## loot. Open with F6 on items_sandbox.tscn.
##
## WASD move, I inventory, F roll a monster drop (Shift+F elite, Ctrl+F boss),
## E open a chest, R new chests, 1-5 biome, +/- item level, P cycle path,
## H drink a healing draught.

const BIOMES: Array[StringName] = [&"village", &"meadow", &"forest", &"ruins", &"dungeon"]
const PATHS: Array[String] = ["", "wizard", "mage", "sorcerer"]

var items: ItemsService
var level := 8
var biome_index := 3
var path_index := 1
var _player: CharacterBody3D
var _label: Label
var _chest_seed := 1
var _rolls := 0


func _ready() -> void:
	_build_world()
	items = get_node_or_null(^"/root/Items") as ItemsService
	if items == null:
		# Not yet an autoload: stand one in.
		items = ItemsService.new()
		items.name = "Items"
		get_tree().root.add_child.call_deferred(items)
		await get_tree().process_frame
	_apply_character()
	items.reset()
	items.give_starter_kit()
	items.bind_player(_player)
	items.message.connect(func(t: String) -> void: print(t))
	_spawn_chests()
	_update_label()


func _apply_character() -> void:
	var attrs := {}
	for a in ItemDefs.ATTRIBUTES:
		attrs[a] = 10 + level
	items.character_override = {"level": level, "path": PATHS[path_index], "attributes": attrs}
	items.current_biome = BIOMES[biome_index]
	items.refresh_stats()


func _physics_process(delta: float) -> void:
	if get_tree().paused or items == null:
		return
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var speed := 6.0 * ItemStats.move_speed_multiplier(items.get_gear_stats())
	_player.velocity = Vector3(input.x, 0, input.y).normalized() * speed + Vector3.DOWN * 4.0
	_player.move_and_slide()
	var cam := get_viewport().get_camera_3d()
	cam.global_position = cam.global_position.lerp(_player.global_position + Vector3(0, 11, 9), 1.0 - exp(-delta * 6.0))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if items == null or key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F:
			var source := &"boss" if key.ctrl_pressed else (&"elite" if key.shift_pressed else &"normal")
			_rolls += 1
			var drops := LootRoller.roll(source, BIOMES[biome_index], level, LootRoller.rng_for(_rolls, level),
					items.get_gear_stat(&"magic_find"), items.get_gear_stat(&"gold_find"))
			items.spawn_drops(drops, _player.global_position + Vector3(0, 0, -2.5), self)
		KEY_R:
			for chest in get_tree().get_nodes_in_group(&"loot_chests"):
				chest.queue_free()
			_chest_seed += 1
			_spawn_chests()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			biome_index = key.physical_keycode - KEY_1
		KEY_EQUAL, KEY_KP_ADD:
			level = mini(level + 1, 30)
		KEY_MINUS, KEY_KP_SUBTRACT:
			level = maxi(level - 1, 1)
		KEY_P:
			path_index = (path_index + 1) % PATHS.size()
		KEY_H:
			items.drink_health_potion()
		_:
			return
	_apply_character()
	_update_label()


func _update_label() -> void:
	_label.text = "Level %d   Biome: %s   Path: %s   Gold: %d\n" % [level, BIOMES[biome_index], PATHS[path_index] if PATHS[path_index] != "" else "arcanist", items.inventory.gold] \
			+ "WASD move   I inventory   F drop (Shift elite, Ctrl boss)   E open chest   R new chests\n1-5 biome   +/- level   P path   H drink"


func _spawn_chests() -> void:
	var specs := [[&"chest", Vector3(-4, 0, -4)], [&"chest_large", Vector3(4, 0, -4)]]
	for spec in specs:
		var chest := LootChest.new()
		chest.source = spec[0]
		chest.loot_seed = _chest_seed * 31 + specs.find(spec)
		chest.biome = BIOMES[biome_index]
		chest.level = level
		add_child(chest)
		chest.position = spec[1]


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.11, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.48, 0.55)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.36, 0.26)
	mesh.material_override = mat
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	add_child(ground)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.add_to_group(&"player")
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	body.mesh = capsule
	body.position.y = 1.0
	var robe := StandardMaterial3D.new()
	robe.albedo_color = Color(0.35, 0.38, 0.6)
	body.material_override = robe
	_player.add_child(body)
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.position.y = 1.0
	_player.add_child(col)
	add_child(_player)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 11, 9)
	add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override("font_color", InventoryStyle.PARCHMENT)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
