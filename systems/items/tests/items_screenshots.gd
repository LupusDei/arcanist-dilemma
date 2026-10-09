extends SceneTree
## Screenshots for the README: loot on the ground and the inventory screen.
## Run (needs a display): xvfb-run godot --path . --rendering-driver opengl3 --script res://systems/items/tests/items_screenshots.gd

const OUT := "res://systems/items/docs/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var sandbox: Node = load("res://systems/items/sandbox/items_sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await _frames(10)
	var items: ItemsService = root.get_node("Items")
	sandbox.level = 18
	sandbox.biome_index = 4
	sandbox._apply_character()
	sandbox._update_label()

	# A boss's worth of loot and an open chest on the ground.
	var drops := LootRoller.roll(&"boss", &"dungeon", 18, LootRoller.rng_for(5, 18))
	drops.append(ItemGenerator.make_unique(&"stormcrown"))
	items.spawn_drops(drops, Vector3(0, 0, -2.5), sandbox)
	for chest in get_nodes_in_group(&"loot_chests"):
		chest.level = 18
		chest.open()
	await _frames(20)
	var cam := root.get_camera_3d()
	cam.set_physics_process(false)
	sandbox.set_physics_process(false)
	cam.look_at_from_position(Vector3(0, 6.5, 5.5), Vector3(0, 0, -3))
	await _frames(20)
	_save("items-loot.png")

	# Kit the arcanist out and open the bag.
	for pickup in sandbox.find_children("*", "ItemPickup", true, false):
		if pickup.item.get_kind() == ItemDefs.Kind.GOLD:
			items.pick_up(pickup.item)
		elif items.inventory.can_fit(pickup.item):
			items.pick_up(pickup.item)
		pickup.queue_free()
	var rng := LootRoller.rng_for(77)
	for slot in [&"hat", &"amulet", &"gloves", &"belt", &"boots", &"ring_1"]:
		for i in 200:
			var item := LootRoller.roll_gear(18, rng)
			if item.get_base().allowed_slots().has(slot) and item.rarity != ItemDefs.Rarity.COMMON and items.check_equip(item, slot) == &"":
				items.equipment.equip(item, slot)
				break
	items.equipment.equip(ItemGenerator.make_unique(&"band_of_seven_circles"), &"ring_2")
	var grim := ItemGenerator.roll_gear(ItemDatabase.get_base(&"scholar_grimoire"), 18, ItemDefs.Rarity.RARE, rng)
	items.equipment.equip(grim, &"off_hand")
	var staff := ItemGenerator.roll_gear(ItemDatabase.get_base(&"runed_staff"), 18, ItemDefs.Rarity.MAGIC, rng)
	items.equipment.equip(staff, &"main_hand")
	items.inventory.add_item(ItemGenerator.make_spellbook(&"fireball_searing", 4))
	var compare := ItemGenerator.roll_gear(ItemDatabase.get_base(&"elder_staff"), 22, ItemDefs.Rarity.RARE, rng)
	items.inventory.add_item(compare)
	var screen: InventoryScreen = items.screen
	screen.open()
	await _frames(5)
	var cell := items.inventory.get_position_of(compare)
	var grid_pos: Vector2 = screen._grid.get_global_rect().position + (Vector2(cell) + Vector2(0.5, 1.0)) * InventoryStyle.CELL
	Input.warp_mouse(grid_pos)
	screen._grid.hovered_cell = cell
	screen._on_item_hovered(compare)
	await _frames(5)
	screen._place_tooltip()
	await _frames(3)
	_save("inventory.png")
	quit(0)


func _save(file: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("saved ", OUT + file)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
