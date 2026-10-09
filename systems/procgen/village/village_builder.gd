class_name VillageBuilder
## VillagePlan -> nodes. Each building and prop becomes a Node3D placed on the
## ground at its planned height; all collision goes into one StaticBody3D.

const FLOATING_SCRIPT := preload("res://systems/procgen/village/floating.gd")


static func build(plan: VillagePlan) -> Node3D:
	var kit := BuildingKit.new(plan.recipe, plan.faction, plan.layout_seed)
	var root := Node3D.new()
	root.name = plan.recipe.display_name.to_pascal_case()
	var body := StaticBody3D.new()
	body.name = "Colliders"
	root.add_child(body)

	for b in plan.buildings:
		var node := kit.build_building(b)
		node.position = Vector3(b.position.x, b.ground + b.lift, b.position.y)
		node.rotation = Vector3(b.tilt.x, b.yaw, b.tilt.y)
		_place(root, body, node, kit.shapes, b.lift > 0.0)

	for prop in plan.props:
		var node := kit.build_prop(prop)
		node.position = Vector3(prop.position.x, prop.ground + prop.lift, prop.position.y)
		node.rotation.y = prop.yaw
		_place(root, body, node, kit.shapes, prop.lift > 0.0)
	return root


static func _place(root: Node3D, body: StaticBody3D, node: Node3D, shapes: Array, floating: bool) -> void:
	root.add_child(node)
	# Floating pieces bob, so they carry their own collision with them.
	var target: Node3D = body
	var parent_transform := node.transform
	if floating:
		node.set_script(FLOATING_SCRIPT)
		var own_body := StaticBody3D.new()
		node.add_child(own_body)
		target = own_body
		parent_transform = Transform3D.IDENTITY
	for entry in shapes:
		var collision := CollisionShape3D.new()
		collision.shape = entry[0]
		collision.transform = parent_transform * entry[1]
		target.add_child(collision)


## Flat dirt ribbons along the roads, for ground that can't paint its own paths
## (the lab). Terrain paints roads into its path mask instead.
static func build_roads(plan: VillagePlan, ground: Object) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := plan.recipe.road_width * 0.5
	for road in plan.roads:
		for i in road.size() - 1:
			var a := road[i]
			var b := road[i + 1]
			var side := (b - a).normalized().orthogonal() * half
			var quad := [a - side, a + side, b + side, b - side]
			for index in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = quad[index]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, ground.height_at(p.x, p.y) + 0.03, p.y))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.74, 0.48, 0.27)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = "Roads"
	instance.mesh = st.commit()
	instance.material_override = material
	return instance
