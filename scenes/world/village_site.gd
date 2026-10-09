@tool
extends Node3D
## Plans a village on the Terrain, shapes the ground for it, builds it and
## reserves its area so the vegetation leaves it clear. Must come after the
## Terrain and before Vegetation in the scene tree.

@export var terrain_path: NodePath = ^"../Terrain"
@export var recipe: VillageRecipe
@export var village_seed := 1
@export var center := Vector2(14, 40)
## The main road leaves the village heading toward this point.
@export var entry_toward := Vector2(0, 4)
## Moves this node to the village green when the scene starts (the player's home).
@export var spawn_node: NodePath

var plan: VillagePlan


func _ready() -> void:
	if recipe == null:
		return
	var terrain := get_node(terrain_path) as Terrain
	terrain.generate()

	# Settle the site so lots aren't on hillsides, then plan on the result.
	terrain.soften_disc(center, recipe.radius, terrain.height_at(center.x, center.y), 0.75)
	plan = VillagePlanner.plan(recipe, village_seed, center, terrain, entry_toward - center)
	if not plan.is_valid():
		push_warning("%s seed %d: %s" % [recipe.display_name, village_seed, ", ".join(plan.problems)])

	_shape_terrain(terrain)
	add_child(VillageBuilder.build(plan))

	if not spawn_node.is_empty():
		var spawn := get_node(spawn_node) as Node3D
		var spot := center + plan.main_direction * (plan.green_radius * 0.6 + 2.0)
		spawn.global_position = Vector3(spot.x, terrain.height_at(spot.x, spot.y) + 0.5, spot.y)


func _shape_terrain(terrain: Terrain) -> void:
	terrain.reserve_area(center, recipe.radius * 1.15)
	for road in plan.roads:
		terrain.paint_path(road, recipe.road_width * 0.5)
	# Pads for every building and field, then a second pass so a neighbour's
	# blend margin can't nudge a pad that was already levelled.
	for pass_index in 2:
		var margin := 3.0 if pass_index == 0 else 0.01
		for b in plan.buildings:
			terrain.flatten_rect(b.position, Vector2(b.size.x, b.size.z) * 0.5 + Vector2.ONE, b.yaw, b.ground, margin)
			if b.has_field():
				terrain.flatten_rect(b.field_center(), b.field_size * 0.5 + Vector2.ONE * 0.5, b.yaw, b.field_ground, margin)
	for b in plan.buildings:
		terrain.reserve_area(b.position, Vector2(b.size.x, b.size.z).length() * 0.5 + 0.5, true)
		if b.has_field():
			terrain.reserve_area(b.field_center(), b.field_size.length() * 0.5, true)
	terrain.rebuild()
	for prop in plan.props:
		prop.ground = terrain.height_at(prop.position.x, prop.position.y)
