extends SceneTree
## Plays the opening and saves a screenshot at each beat, to check the lessons
## and effects by eye. Needs a display (xvfb-run in the cloud):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . --resolution 1600x900 --script res://systems/tutorial/tests/opening_screenshots.gd -- <out_dir>

var _out := "user://opening"
var _player: Player
var _caster: SpellCaster
var _quests: QuestManager
var _tutorial: OpeningTutorial


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_quests = root.get_node("Quests")
	UiSession.character = {"name": "Ash", "sex": 0, "face": 1, "skin": 1, "hair": 2, "hair_color": 1, "eyes": 1, "build": 0}
	change_scene_to_file("res://scenes/world/world.tscn")
	await _frames(25)
	_player = current_scene.get_node("Player")
	_caster = _player.get_node("SpellCaster")
	_tutorial = current_scene.get_node("MillbrookStory/OpeningTutorial")
	await _shot("01_title")
	await _frames(200)
	_look_at(_tutorial.stove.global_position)
	await _frames(30)
	await _shot("02_move_hint")

	_walk_to(_tutorial.yard_center)
	await _frames(150)
	_stand_facing(_tutorial.spoon.health.get_target_position(), 2.6, 1.2)
	await _frames(40)
	await _shot("03_spoon_hint")
	_cast(&"nudge", _tutorial.spoon.health.get_target_position())
	await _frames(14)
	await _shot("04_spoon_flies")
	await _frames(60)
	await _shot("05_spoon_done")

	await _frames(80)
	_stand_facing(_tutorial.stove.health.get_target_position(), 4.5, -0.8)
	await _frames(30)
	await _shot("06_stove_hint")
	_cast(&"spark", _tutorial.stove.health.get_target_position())
	await _frames(25)
	await _shot("07_stove_lit")
	await _frames(70)
	await _shot("08_talk_hint")
	_quests.talk_to(&"tam")
	_play_dialogue()
	await _frames(120)
	_stand_facing(_tutorial.jar.health.get_target_position(), 6.0, 1.5)
	await _frames(30)
	await _shot("09_jolt_hint")
	_cast(&"jolt", _tutorial.jar.health.get_target_position())
	await _frames(12)
	await _shot("10_jar_jolted")
	_play_dialogue()
	_quests.talk_to(&"rook")
	_play_dialogue([1])
	await _frames(40)
	await _shot("11_choice")
	_quests.talk_to(&"farmer_hollis")
	_play_dialogue()
	await _frames(120)
	_look_at(_tutorial.barley_center)
	await _frames(20)
	await _shot("12_to_barley")

	var health: HealthComponent = _player.get_node("HealthComponent")
	_stand_facing(_tutorial.barley_center, 11.0, 0.0)
	await _frames(60)
	await _shot("13_fight_hint")
	var shots := 0
	var guard := 0
	while not _tutorial._hounds().is_empty() and guard < 600:
		guard += 1
		health.heal(1000.0)
		var target := _nearest(_tutorial._hounds())
		var aim: Vector3 = target.get_node("HealthComponent").get_target_position()
		_stand_facing(aim, 6.0, 0.0)
		_cast(&"spark", aim)
		await _frames(8)
		if guard == 6 and shots == 0:
			shots += 1
			await _shot("14_hits")
		if _tutorial._hounds().size() == 1 and shots == 1:
			shots += 1
			await _shot("15_kill_xp")
	await _frames(10)
	await _shot("16_level_up")
	await _frames(40)
	await _shot("17_level_up_after")
	quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)


func _spell(id: StringName) -> SpellData:
	for spell in _caster.get_action_bar() + [_caster.get_cantrip()]:
		if spell != null and spell.id == id:
			return spell
	return null


func _cast(id: StringName, aim: Vector3) -> void:
	_caster.cast(_spell(id), aim)


## Stands `distance` from `at` on the current side, shifted `side` metres, camera on it.
func _stand_facing(at: Vector3, distance: float, side: float) -> void:
	var away := _player.global_position - at
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	away = away.normalized()
	var spot := at + away * distance + away.cross(Vector3.UP) * side
	_walk_to(spot)
	_look_at(at)


func _look_at(at: Vector3) -> void:
	var d := at - _player.global_position
	var pivot := _player.get_node("CameraPivot") as Node3D
	pivot.rotation.y = atan2(-d.x, -d.z)
	pivot.rotation.x = deg_to_rad(-12.0)


func _walk_to(spot: Vector3) -> void:
	var terrain: Terrain = current_scene.get_node("Terrain")
	_player.global_position = Vector3(spot.x, terrain.height_at(spot.x, spot.z) + 0.1, spot.z)
	_player.velocity = Vector3.ZERO


func _nearest(nodes: Array[Node]) -> Node3D:
	var best: Node3D
	for node in nodes:
		var n := node as Node3D
		if best == null or n.global_position.distance_to(_player.global_position) < best.global_position.distance_to(_player.global_position):
			best = n
	return best


func _play_dialogue(picks: Array = []) -> void:
	var guard := 0
	while _quests.active_dialogue != null and guard < 100:
		guard += 1
		var runner := _quests.active_dialogue
		if runner.has_choices():
			runner.choose(picks.pop_front() if not picks.is_empty() else 0)
		else:
			runner.advance()
	paused = false


func _frames(count: int) -> void:
	for i in count:
		await process_frame
