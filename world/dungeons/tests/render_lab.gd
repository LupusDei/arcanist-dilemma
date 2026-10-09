extends SceneTree
## Renders the dungeon lab to a PNG (needs a display; xvfb-run works headless):
##   godot --path . --script res://world/dungeons/tests/render_lab.gd -- <recipe 0-2> <seed> <out.png> [play | marker name]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lab: Node = load("res://world/dungeons/lab/dungeon_lab.tscn").instantiate()
	lab.recipe_index = int(args[0])
	lab.seed_value = int(args[1])
	root.add_child(lab)
	for i in 30:
		await process_frame
	if args.size() > 3 and args[3] == "play":
		lab._play()
		for i in 90:
			await process_frame
	elif args.size() > 3:
		var dungeon: Dungeon = lab.get_node("Dungeon")
		var cam: Camera3D = lab.get_node("CameraPivot/Camera3D")
		var target := dungeon.marker(args[3]).global_position if args[3] != "start" else dungeon.player_start().origin
		cam.global_position = target + Vector3(9, 11, 12)
		cam.look_at(target + Vector3(0, 1, 0))
		lab.set_process(false)
		for i in 20:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[2])
	quit()
