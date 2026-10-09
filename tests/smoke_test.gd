extends SceneTree
## Headless smoke test for the movement prototype.
## Run: godot --headless --path . --script res://tests/smoke_test.gd

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/greybox_test.tscn").instantiate()
	root.add_child(main)
	var player: Player = main.get_node("Player")

	await _frames(60)
	_check(player.is_on_floor(), "player settles on the floor")

	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	_check(player.global_position.z < start.z - 4.0, "move_forward runs away from the camera (z %.2f -> %.2f)" % [start.z, player.global_position.z])
	await _frames(30)

	var ground_y := player.global_position.y
	var peak_y := ground_y
	Input.action_press("jump")
	for i in 30:
		await physics_frame
		peak_y = maxf(peak_y, player.global_position.y)
	Input.action_release("jump")
	_check(peak_y > ground_y + 1.0, "full jump rises over 1m (peak %.2f)" % (peak_y - ground_y))
	await _frames(60)
	_check(player.is_on_floor(), "player lands after jumping")

	var before_dodge := player.global_position
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(player.is_dodging, "dodge starts")
	await _frames(20)
	var dodge_distance := Vector2(player.global_position.x - before_dodge.x, player.global_position.z - before_dodge.z).length()
	_check(dodge_distance > 2.5, "dodge covers over 2.5m (%.2f)" % dodge_distance)
	_check(not player.is_dodging, "dodge ends")

	player.global_position = Vector3(0, -30, 0)
	await _frames(2)
	_check(player.global_position.y > -1.0, "falling out of the world respawns")

	main.queue_free()
	await _frames(2)
	await _check_world()

	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _check_world() -> void:
	var start := Time.get_ticks_msec()
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	print("     world generated in %d ms" % (Time.get_ticks_msec() - start))
	var player: Player = world.get_node("Player")
	var terrain: Terrain = world.get_node("Terrain")
	await _frames(90)
	_check(player.is_on_floor(), "player stands on the terrain")
	_check(absf(player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z)) < 0.3, "terrain collision matches the terrain mesh")
	var trees := 0
	for instance in world.get_node("Vegetation/Trees").get_children():
		trees += (instance as MultiMeshInstance3D).multimesh.instance_count
	print("     %d trees" % trees)
	_check(trees > 200, "trees are scattered")
	_check(world.get_node("Vegetation/Grass").get_child_count() > 20, "grass chunks are built")
	_check(world.get_node("Landmarks/Crystal") != null, "hilltop crystal exists")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)
