extends SceneTree
## Fuzz test for the dungeon factory: plans many seeds per recipe and checks
## every plan is valid, repeatable, and keeps its layout under story state.
## Also builds a few dungeons, and plans their monsters when the enemies
## spawn table is in the project.
## Run: godot --headless --path . --script res://world/dungeons/tests/dungeon_test.gd

const RECIPES := [
	"res://world/dungeons/recipes/ruined_crypt.tres",
	"res://world/dungeons/recipes/drowned_chapel.tres",
	"res://world/dungeons/recipes/old_mine.tres",
]
const SEEDS := 300
const BUILDS := 3


func _initialize() -> void:
	var failures := 0
	for path in RECIPES:
		var recipe: DungeonRecipe = load(path)
		var invalid := 0
		var retried := 0
		var rooms := 0
		var start := Time.get_ticks_usec()
		var fingerprints := {}
		for seed_value in SEEDS:
			var plan := DungeonPlanner.plan(recipe, seed_value)
			rooms += plan.rooms.size()
			fingerprints[plan.fingerprint()] = true
			if plan.attempts > 1:
				retried += 1
			if not plan.is_valid():
				invalid += 1
				if invalid <= 3:
					printerr("  %s seed %d: %s" % [recipe.display_name, seed_value, ", ".join(plan.problems)])
		var ms := (Time.get_ticks_usec() - start) / 1000.0
		print("%-16s %d/%d valid, %d needed a retry, %d distinct, %.1f rooms avg, %.2f ms per dungeon" % [
			recipe.display_name, SEEDS - invalid, SEEDS, retried, fingerprints.size(), float(rooms) / SEEDS, ms / SEEDS])
		if invalid > 0:
			failures += 1
		if fingerprints.size() < SEEDS * 0.95:
			printerr("  %s: only %d distinct dungeons from %d seeds" % [recipe.display_name, fingerprints.size(), SEEDS])
			failures += 1

		# Same seed, same dungeon. Story state changes monsters, not the layout.
		var a := DungeonPlanner.plan(recipe, 42)
		var b := DungeonPlanner.plan(recipe, 42)
		if a.fingerprint() != b.fingerprint():
			printerr("  %s: seed 42 gave two different dungeons" % recipe.display_name)
			failures += 1
		var cleared := DungeonPlanner.plan(recipe, 42, {"cleared": true})
		var harder := DungeonPlanner.plan(recipe, 42, {"level_bonus": 2})
		for other in [cleared, harder]:
			if other.rooms.size() != a.rooms.size() or str(other.cells) != str(a.cells) or other.chests.size() != a.chests.size():
				printerr("  %s: story state changed the layout" % recipe.display_name)
				failures += 1
		if not cleared.encounters.is_empty() or harder.encounters[0].level != a.encounters[0].level + 2:
			printerr("  %s: story state not applied to encounters" % recipe.display_name)
			failures += 1

		failures += _check_validator_catches(recipe)
		failures += _check_spawns(recipe)
		failures += _check_build(recipe)

	failures += await _check_play()
	print("DUNGEON TEST PASSED" if failures == 0 else "DUNGEON TEST FAILED")
	quit(1 if failures else 0)


## Breaks valid plans on purpose: the validator has to notice.
func _check_validator_catches(recipe: DungeonRecipe) -> int:
	var failures := 0
	var cases := {
		"key moved behind its lock": func(p: DungeonPlan) -> void:
			for r in p.rooms:
				if r.key_id >= 0:
					r.key_id = -1
			for r in p.rooms:
				if r.lock_id >= 0:
					r.key_id = r.lock_id,
		"doorway bricked up": func(p: DungeonPlan) -> void:
			p.doors.remove_at(p.doors.size() - 1),
		"boss room overlapping a room": func(p: DungeonPlan) -> void:
			p.rooms[p.boss_room].rect.position = p.rooms[p.entrance_room].rect.position,
		"monsters in the entrance": func(p: DungeonPlan) -> void:
			p.rooms[p.entrance_room].budget = 5.0,
	}
	for label in cases:
		var p := DungeonPlanner.plan(recipe, 11)
		if recipe.locks == 0 and label.begins_with("key"):
			continue
		cases[label].call(p)
		DungeonValidator.validate(p)
		if p.is_valid():
			printerr("  %s: validator missed a %s" % [recipe.display_name, label])
			failures += 1
	return failures


## With the enemies spawn table present, every planned monster group must be
## inside its room and the room's threat budget must not be overspent.
func _check_spawns(recipe: DungeonRecipe) -> int:
	if not DungeonPopulator.enemies_available():
		print("  (enemies not in this project; skipping spawn checks)")
		return 0
	var failures := 0
	var groups := 0
	var monsters := 0
	for seed_value in 50:
		var plan := DungeonPlanner.plan(recipe, seed_value)
		var spawns := DungeonPopulator.plan_spawns(plan, Transform3D.IDENTITY)
		var spent := {}
		for s in spawns:
			groups += 1
			monsters += s["count"]
			var e: DungeonPlan.Encounter = s["encounter"]
			var at: Vector3 = s["position"]
			if not e.area.grow(0.01).has_point(Vector2(at.x, at.z)):
				printerr("  %s seed %d: monsters outside room %d" % [recipe.display_name, seed_value, e.room])
				failures += 1
			spent[e] = spent.get(e, 0.0) + s["threat"]
		for e in plan.encounters:
			if spent.get(e, 0.0) > e.budget + 0.01:
				printerr("  %s seed %d: room %d overspent (%.1f of %.1f)" % [recipe.display_name, seed_value, e.room, spent[e], e.budget])
				failures += 1
			if spent.get(e, 0.0) <= 0.0:
				printerr("  %s seed %d: room %d got no monsters" % [recipe.display_name, seed_value, e.room])
				failures += 1
	print("  monsters: %.1f groups and %.1f monsters per dungeon" % [groups / 50.0, monsters / 50.0])
	return failures


## Plays a real dungeon with the real player: lands on the floor, monsters
## spawn, the key opens the locked door, a chest gives loot.
func _check_play() -> int:
	var failures := 0
	var dungeon := Dungeon.new()
	dungeon.recipe = load(RECIPES[0])
	dungeon.seed_value = 5
	root.add_child(dungeon)
	await process_frame
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.global_transform = dungeon.player_start()
	for i in 60:
		await physics_frame
	var start := dungeon.player_start().origin
	if player.global_position.y < -0.3 or Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() > 3.0:
		printerr("  play: player didn't land at the entrance (%s vs %s)" % [player.global_position, start])
		failures += 1
	var monsters := get_nodes_in_group(&"enemies").size()
	var events := []
	dungeon.key_collected.connect(func(id: int) -> void: events.append("key%d" % id))
	dungeon.door_opened.connect(func(id: int) -> void: events.append("door%d" % id))
	dungeon.chest_opened.connect(func(_c: DungeonChest, loot: Array[Dictionary]) -> void: events.append("chest:%d" % loot.size()))
	var content := dungeon.get_child(0).get_child(0) if dungeon.bake_navigation else dungeon.get_child(0)
	for key in content.get_node("Keys").get_children():
		player.global_position = key.global_position + Vector3(0, 0.2, 0)
		for i in 10:
			await physics_frame
	for door in content.get_node("Doors").get_children():
		player.global_position = door.global_position + Vector3(0, 0.2, 0) + door.global_basis.z * 1.5
		for i in 10:
			await physics_frame
	var chest: Node3D = content.get_node("Chests").get_child(0)
	player.global_position = chest.global_position + chest.global_basis.z * 1.3 + Vector3(0, 0.2, 0)
	for i in 10:
		await physics_frame
	var nav_ok := NavigationServer3D.map_get_regions(dungeon.get_world_3d().navigation_map).size() > 0
	print("  play: %d monsters spawned, events %s, navmesh %s" % [monsters, str(events), "baked" if nav_ok else "missing"])
	var locks := dungeon.plan.recipe.locks
	if monsters == 0 or not nav_ok or events.count("key0") != 1 or (locks > 0 and not "door0" in events) or not events.any(func(e: String) -> bool: return e.begins_with("chest")):
		printerr("  play: dungeon didn't play through (%s)" % str(events))
		failures += 1
	player.queue_free()
	dungeon.queue_free()
	return failures


func _check_build(recipe: DungeonRecipe) -> int:
	var failures := 0
	var ms := 0.0
	for seed_value in BUILDS:
		var plan := DungeonPlanner.plan(recipe, seed_value)
		var start := Time.get_ticks_usec()
		var dungeon := DungeonBuilder.build(plan)
		ms += (Time.get_ticks_usec() - start) / 1000.0
		if dungeon.get_node_or_null("Geometry") == null or dungeon.get_node_or_null("Chests").get_child_count() != plan.chests.size():
			printerr("  %s seed %d: build is missing parts" % [recipe.display_name, seed_value])
			failures += 1
		for marker in recipe.story_rooms:
			if dungeon.find_child(marker, true, false) == null:
				printerr("  %s seed %d: no %s marker" % [recipe.display_name, seed_value, marker])
				failures += 1
		dungeon.free()
	print("  built in %.1f ms per dungeon" % (ms / BUILDS))
	return failures
