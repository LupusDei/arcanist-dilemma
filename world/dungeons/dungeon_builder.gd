class_name DungeonBuilder
## DungeonPlan -> nodes. Everything is built in the dungeon's local space with
## the floor at Y 0, so the result can be dropped anywhere.
##
##   <Recipe name>
##     Geometry     merged floor, wall and prop meshes
##     Collision    one StaticBody3D with every wall, floor and solid prop
##     Lights       an OmniLight3D per brazier, lantern, candle cluster and crystal
##     Doors        a DungeonDoor on every locked doorway
##     Keys         a DungeonKey in every key room
##     Chests       a DungeonChest per planned chest
##     Markers      PlayerStart, BossArena, Exit, WayOut, plus one per story marker
##     Monsters     empty; DungeonPopulator fills it
##     Exits        Area3Ds: "Exit" (portal behind the boss) and "WayOut" (stairs at the entrance)

const KEY_COLORS := [Color(1.0, 0.78, 0.3), Color(0.4, 0.85, 1.0), Color(1.0, 0.45, 0.65)]


static func build(plan: DungeonPlan) -> Node3D:
	var root := Node3D.new()
	root.name = plan.recipe.display_name.to_pascal_case()
	var kit := DungeonKit.new(plan)

	var geometry := Node3D.new()
	geometry.name = "Geometry"
	root.add_child(geometry)
	kit.build(geometry)

	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	for entry in kit.shapes:
		var shape := CollisionShape3D.new()
		shape.shape = entry[0]
		shape.transform = entry[1]
		body.add_child(shape)

	var lights := _group(root, "Lights")
	for entry in kit.lights:
		var light := OmniLight3D.new()
		light.position = entry[0]
		light.light_color = entry[1]
		light.omni_range = entry[2]
		light.light_energy = entry[3]
		light.omni_attenuation = 0.8
		lights.add_child(light)

	var cs := plan.cell_size()
	var doors := _group(root, "Doors")
	for d in plan.doors:
		if d.lock_id < 0:
			continue
		var door := DungeonDoor.new()
		door.name = "LockedDoor%d" % d.lock_id
		door.lock_id = d.lock_id
		door.width = cs
		door.height = plan.recipe.wall_height
		door.key_color = KEY_COLORS[d.lock_id % KEY_COLORS.size()]
		var mid := (plan.cell_center(d.a) + plan.cell_center(d.b)) * 0.5
		door.position = Vector3(mid.x, 0, mid.y)
		# The gate spans the doorway, across the direction of travel.
		door.rotation.y = PI * 0.5 if d.a.y == d.b.y else 0.0
		doors.add_child(door)

	var keys := _group(root, "Keys")
	for r in plan.rooms:
		if r.key_id < 0:
			continue
		var key := DungeonKey.new()
		key.name = "Key%d" % r.key_id
		key.key_id = r.key_id
		key.key_color = KEY_COLORS[r.key_id % KEY_COLORS.size()]
		var at := plan.room_center(r) + Vector2(cs * 0.4, cs * 0.4)
		key.position = Vector3(at.x, 0, at.y)
		keys.add_child(key)

	var chests := _group(root, "Chests")
	for c in plan.chests:
		var chest := DungeonChest.new()
		chest.name = "Chest%d" % chests.get_child_count()
		chest.tier = c.tier
		chest.level = plan.level_max if c.tier == 2 else plan.level_min
		chest.loot_seed = c.seed_value
		chest.position = Vector3(c.position.x, 0, c.position.y)
		chest.rotation.y = c.yaw
		chests.add_child(chest)

	var markers := _group(root, "Markers")
	var start := plan.entrance_position()
	var facing := _first_door_direction(plan)
	# Between the entrance brazier and the way in, facing it, with the stairs out behind.
	_marker(markers, "PlayerStart", start + Vector3(facing.x, 0, facing.y) * cs * 0.9, facing)
	_marker(markers, "BossArena", _center3(plan, plan.boss_room), Vector2.ZERO)
	_marker(markers, "Exit", plan.exit_position(), Vector2.ZERO)
	for r in plan.rooms:
		if r.marker != "":
			_marker(markers, r.marker, _center3(plan, r.id) + Vector3(0, 0, cs * 0.6), Vector2.ZERO)

	_group(root, "Monsters")
	var exits := _group(root, "Exits")
	_exit_portal(exits, plan)
	_way_out(exits, plan, geometry, body)
	return root


static func _group(root: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	root.add_child(node)
	return node


static func _center3(plan: DungeonPlan, room: int) -> Vector3:
	var c := plan.room_center(plan.rooms[room])
	return Vector3(c.x, 0, c.y)


## Unit direction (x, z) from the entrance room toward its first doorway.
static func _first_door_direction(plan: DungeonPlan) -> Vector2:
	for d in plan.doors:
		if d.room == plan.entrance_room:
			return Vector2(d.b - d.a)
	return Vector2(0, 1)


static func _marker(parent: Node3D, marker_name: String, at: Vector3, facing: Vector2) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	if facing != Vector2.ZERO:
		# Node3D forward is -Z.
		marker.rotation.y = atan2(-facing.x, -facing.y)
	parent.add_child(marker)


## A glowing ring standing in the reward room: the way out after the boss.
static func _exit_portal(parent: Node3D, plan: DungeonPlan) -> void:
	var area := Area3D.new()
	area.name = "Exit"
	var at := plan.exit_position() + Vector3(0, 0, -plan.cell_size() * 0.6)
	area.position = at
	var glow := StandardMaterial3D.new()
	glow.albedo_color = plan.recipe.accent_color
	glow.emission_enabled = true
	glow.emission = plan.recipe.accent_color
	glow.emission_energy_multiplier = 3.0
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 1.25
	ring.material = glow
	var mesh := MeshInstance3D.new()
	mesh.mesh = ring
	mesh.rotation.x = PI * 0.5
	mesh.position.y = 1.4
	area.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = plan.recipe.accent_color
	light.omni_range = 6.0
	light.position.y = 1.4
	area.add_child(light)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.6, 0.8)
	shape.shape = box
	shape.position.y = 1.3
	area.add_child(shape)
	parent.add_child(area)


## Steps climbing into the entrance room's back wall, with a trigger over them:
## walking into the stairs is how the player leaves.
static func _way_out(parent: Node3D, plan: DungeonPlan, geometry: Node3D, body: StaticBody3D) -> void:
	var cs := plan.cell_size()
	var back := -_first_door_direction(plan)
	var r := plan.rooms[plan.entrance_room]
	var center := plan.room_center(r)
	var half := Vector2(r.rect.size) * cs * 0.5
	var wall := center + back * (half.x if back.x != 0 else half.y)
	var yaw := atan2(back.x, back.y)
	var basis := Basis(Vector3.UP, yaw)
	var batch := DungeonMeshBatch.new()
	batch.add_material("stairs", DungeonMeshBatch.opaque())
	var inset := DungeonKit.WALL_THICKNESS * 0.5
	for i in 5:
		var height := 0.3 * (i + 1)
		var step := wall - back * (inset + 0.25 + (4 - i) * 0.5)
		var xform := Transform3D(basis, Vector3(step.x, height * 0.5, step.y))
		batch.box("stairs", Vector3(cs * 0.6, height, 0.5), xform, plan.recipe.trim_color.lightened(0.04 * i))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(cs * 0.6, height, 0.5)
		shape.shape = box
		shape.transform = xform
		body.add_child(shape)
	batch.commit(geometry)
	var area := Area3D.new()
	area.name = "WayOut"
	var mid := wall - back * (inset + 1.4)
	area.position = Vector3(mid.x, 0, mid.y)
	area.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cs * 0.6, 2.5, 3.0)
	shape.shape = box
	shape.position.y = 1.25
	area.add_child(shape)
	parent.add_child(area)
