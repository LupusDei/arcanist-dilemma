extends Node3D
## Dungeon lab: generate dungeons from each recipe and reroll them by seed.
##   N / B        next / previous seed
##   1, 2, 3      switch recipe
##   C            toggle cleared (same layout, no monsters)
##   H            toggle harder (+2 monster levels, same layout)
##   P            play: drop the arcanist in at the entrance (Esc to come back)
##   Right drag   orbit      Wheel  zoom

const RECIPES := [
	"res://world/dungeons/recipes/ruined_crypt.tres",
	"res://world/dungeons/recipes/drowned_chapel.tres",
	"res://world/dungeons/recipes/old_mine.tres",
]
const PLAYER_SCENE := "res://scenes/player/player.tscn"

@export var seed_value := 1
@export var recipe_index := 0
@export var cleared := false
@export var harder := false

var _dungeon: Dungeon
var _player: Node3D
var _zoom := 90.0
var _keys_text := ""

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _label: Label = %InfoLabel


func _ready() -> void:
	# Monster name and state labels are a debugging aid; hide them here too.
	get_tree().node_added.connect(func(node: Node) -> void:
		if "show_debug_label" in node:
			node.set("show_debug_label", false))
	generate()


func generate() -> void:
	_leave_play()
	if _dungeon != null:
		_dungeon.free()
	_dungeon = Dungeon.new()
	_dungeon.name = "Dungeon"
	_dungeon.recipe = load(RECIPES[recipe_index])
	_dungeon.seed_value = seed_value
	_dungeon.generate_on_ready = false
	_dungeon.state = {"cleared": true} if cleared else ({"level_bonus": 2} if harder else {})
	add_child(_dungeon)
	var start := Time.get_ticks_usec()
	_dungeon.generate()
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	_dungeon.key_collected.connect(func(id: int) -> void: _note("picked up key %d" % id))
	_dungeon.door_opened.connect(func(id: int) -> void: _note("door %d opened" % id))
	_dungeon.chest_opened.connect(func(_c: DungeonChest, loot: Array[Dictionary]) -> void: _note("chest: %s" % _loot_text(loot)))
	_dungeon.boss_defeated.connect(func() -> void: _note("boss defeated"))
	_dungeon.exit_reached.connect(func(which: StringName) -> void: _note("reached %s" % which))
	var plan := _dungeon.plan
	var bounds := plan.bounds()
	var center := (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * plan.cell_size()
	_pivot.position = Vector3(center.x, 0, center.y)
	_zoom = maxf(bounds.size.x, bounds.size.y) * plan.cell_size() * 1.3
	_camera.position.z = _zoom
	_keys_text = ""
	_label.text = "%s   seed %d%s\n%s\nlevels %d-%d, planned and built in %.0f ms (%d attempt%s)   %s\nN/B seed   1-3 recipe   C cleared   H harder   P play   right-drag orbit   wheel zoom" % [
		plan.recipe.display_name, seed_value, "   [cleared]" if cleared else ("   [harder]" if harder else ""),
		plan.summary(), plan.level_min, plan.level_max, ms, plan.attempts, "" if plan.attempts == 1 else "s",
		"valid" if plan.is_valid() else "INVALID: " + ", ".join(plan.problems),
	]


func _note(text: String) -> void:
	_keys_text = text
	print("[dungeon] ", text)
	_label.text = _label.text.split("\n>")[0] + "\n> " + text


func _loot_text(loot: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for item in loot:
		parts.append("%d %s" % [item["count"], item["id"]])
	return ", ".join(parts)


func _play() -> void:
	if _player != null or not ResourceLoader.exists(PLAYER_SCENE):
		return
	_player = load(PLAYER_SCENE).instantiate()
	add_child(_player)
	_player.global_transform = _dungeon.player_start()
	_camera.current = false


func _leave_play() -> void:
	if _player == null:
		return
	_player.free()
	_player = null
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_N:
				seed_value += 1
			KEY_B:
				seed_value = maxi(seed_value - 1, 0)
			KEY_1, KEY_2, KEY_3:
				recipe_index = event.physical_keycode - KEY_1
			KEY_C:
				cleared = not cleared
			KEY_H:
				harder = not harder
			KEY_P:
				_play()
				return
			KEY_ESCAPE:
				_leave_play()
				return
			_:
				return
		generate()
	elif _player == null and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_pivot.rotation.y -= event.relative.x * 0.005
		_pivot.rotation.x = clampf(_pivot.rotation.x - event.relative.y * 0.005, -1.5, -0.3)
	elif _player == null and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom * 0.9, 10.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, 250.0)


func _process(delta: float) -> void:
	_camera.position.z = lerpf(_camera.position.z, _zoom, 1.0 - exp(-8.0 * delta))
