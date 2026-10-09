class_name VillageValidator
## Independent checks on a finished VillagePlan. The planner tries to obey the
## same rules; this catches anything it got wrong and is what the fuzz test and
## the retry loop rely on.


static func validate(p: VillagePlan, ground: Object) -> void:
	p.problems.clear()
	var recipe := p.recipe

	for anchor in recipe.anchors:
		if not p.has_kind(anchor):
			p.problems.append("missing anchor: %s" % anchor)

	var homes := p.count_kinds(["house", "farm"])
	var needed := ceili(recipe.house_count * 0.6)
	if homes < needed:
		p.problems.append("only %d of %d homes fit (need %d)" % [homes, recipe.house_count, needed])

	var shapes: Array[PackedVector2Array] = []
	for b in p.buildings:
		shapes.append(b.footprint())
		if b.has_field():
			shapes.append(b.field_footprint())
	for i in shapes.size():
		for road in p.roads:
			if GenGeometry.rect_distance_to_polyline(shapes[i], road) < recipe.road_width * 0.5:
				p.problems.append("building or field on a road")
				break
		for j in range(i + 1, shapes.size()):
			if GenGeometry.rects_overlap(shapes[i], shapes[j]):
				p.problems.append("overlapping buildings")

	for b in p.buildings:
		if b.position.distance_to(p.center) > recipe.radius * 1.1:
			p.problems.append("%s outside the village" % b.kind)
		for corner in b.footprint():
			if ground.is_water(corner.x, corner.y):
				p.problems.append("%s in water" % b.kind)
				break
