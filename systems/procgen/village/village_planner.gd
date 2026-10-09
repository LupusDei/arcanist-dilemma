class_name VillagePlanner
## Recipe + seed + ground -> VillagePlan. No nodes are created here.
##
## Stages, each with its own random stream (see GenRng):
##   roads   lay out the street network for the recipe's layout
##   lots    walk the roads and mark candidate building lots on both sides
##   anchors place the story buildings the recipe requires, best lot first
##   fill    fill remaining lots with houses and farms
##   props   wells, notice boards, lamps, crates
##   story   lift, tilt and damage from the story state (bleed, war)
## If the result fails validation, the planner retries with a derived seed.

const MAX_ATTEMPTS := 10
const PROP_RADII := {"well": 1.3, "notice_board": 1.0, "lamp": 0.3, "crate": 0.5, "barrel": 0.45, "banner": 0.3, "rubble": 0.6}


## `entry` points from the village centre toward where the main road should
## leave the village (for example toward the nearest trail).
## `state` overrides the recipe's story fields: faction, bleed, damage.
static func plan(recipe: VillageRecipe, seed_value: int, center: Vector2, ground: Object, entry := Vector2.ZERO, state := {}) -> VillagePlan:
	var best: VillagePlan = null
	for attempt in MAX_ATTEMPTS:
		var attempt_seed := seed_value if attempt == 0 else GenRng.derive(seed_value, "retry%d" % attempt)
		var candidate := _plan_once(recipe, attempt_seed, center, ground, entry)
		candidate.seed_value = seed_value
		candidate.attempts = attempt + 1
		VillageValidator.validate(candidate, ground)
		if best == null or candidate.problems.size() < best.problems.size():
			best = candidate
		if candidate.is_valid():
			break
	_apply_story_state(best, state)
	return best


static func _plan_once(recipe: VillageRecipe, attempt_seed: int, center: Vector2, ground: Object, entry: Vector2) -> VillagePlan:
	var p := VillagePlan.new()
	p.recipe = recipe
	p.layout_seed = attempt_seed
	p.center = center
	var road_rng := GenRng.stream(attempt_seed, "roads")
	p.main_direction = entry.normalized() if entry.length() > 0.1 else Vector2.from_angle(road_rng.randf() * TAU)
	_build_roads(p, road_rng)

	var lots := _collect_lots(p, GenRng.stream(attempt_seed, "lots"))
	var placed: Array[PackedVector2Array] = []
	_place_anchors(p, lots, placed, ground, GenRng.stream(attempt_seed, "anchors"))
	_place_prop_anchors(p, placed, ground, GenRng.stream(attempt_seed, "prop_anchors"))
	_fill_houses(p, lots, placed, ground, GenRng.stream(attempt_seed, "fill"))
	_place_props(p, placed, ground, GenRng.stream(attempt_seed, "props"))
	return p


# --- roads -------------------------------------------------------------------

static func _build_roads(p: VillagePlan, rng: RandomNumberGenerator) -> void:
	var r := p.recipe.radius
	var c := p.center
	var dir := p.main_direction
	var side := dir.orthogonal()
	match p.recipe.layout:
		VillageRecipe.Layout.GREEN:
			var g := r * 0.3
			p.green_radius = g - p.recipe.road_width * 0.5 - 0.5
			var spokes := rng.randi_range(3, 4)
			var start := dir.angle()
			var angles: Array[float] = [start]
			p.roads.append(_wiggle(c + dir * g, c + dir * r * 1.1, rng, 1.2))
			for i in range(1, spokes):
				var angle := start + TAU * i / spokes + rng.randf_range(-0.35, 0.35)
				angles.append(angle)
				var d := Vector2.from_angle(angle)
				p.roads.append(_wiggle(c + d * g, c + d * r * rng.randf_range(0.8, 1.05), rng, 1.2))
			# Back lanes linking neighbouring spokes further out.
			for i in spokes:
				if rng.randf() < 0.65:
					var a0 := angles[i]
					var a1 := angles[(i + 1) % spokes] + (TAU if i == spokes - 1 else 0.0)
					var lane := PackedVector2Array()
					var lane_radius := r * rng.randf_range(0.62, 0.72)
					for k in 9:
						lane.append(c + Vector2.from_angle(lerpf(a0, a1, k / 8.0)) * lane_radius)
					p.roads.append(lane)
			var ring := PackedVector2Array()
			for i in 21:
				ring.append(c + Vector2.from_angle(start + TAU * i / 20.0) * g)
			p.roads.append(ring)
		VillageRecipe.Layout.CROSSROADS:
			p.green_radius = p.recipe.road_width * 1.4
			p.roads.append(_wiggle(c - dir * r * 1.05, c + dir * r * 1.1, rng, 1.5))
			p.roads.append(_wiggle(c - side * r * 0.85, c + side * r * 0.85, rng, 1.5))
		VillageRecipe.Layout.STREET:
			p.green_radius = 0.0
			var main := _wiggle(c - dir * r * 1.1, c + dir * r * 1.1, rng, 4.0, 6.0)
			p.roads.append(main)
			for i in rng.randi_range(1, 2):
				var at := main[clampi(int(main.size() * rng.randf_range(0.3, 0.7)), 1, main.size() - 2)]
				var lane_side := side * (1.0 if rng.randf() < 0.5 else -1.0)
				p.roads.append(_wiggle(at, at + lane_side * r * rng.randf_range(0.45, 0.65), rng, 1.0))


## A road from `from` to `to` that meanders sideways but keeps its end points.
static func _wiggle(from: Vector2, to: Vector2, rng: RandomNumberGenerator, amplitude: float, step := 5.0) -> PackedVector2Array:
	var line := PackedVector2Array()
	var count := maxi(2, ceili(from.distance_to(to) / step))
	var normal := (to - from).normalized().orthogonal()
	var offset := 0.0
	for i in count + 1:
		var t := float(i) / count
		offset = clampf(offset + rng.randf_range(-1.0, 1.0) * amplitude * 0.6, -amplitude, amplitude)
		line.append(from.lerp(to, t) + normal * offset * sin(t * PI))
	return line


# --- lots --------------------------------------------------------------------

class Lot:
	var point: Vector2
	## Points away from the road, toward where the building sits.
	var normal: Vector2
	var distance: float
	var used := false


static func _collect_lots(p: VillagePlan, rng: RandomNumberGenerator) -> Array[Lot]:
	var lots: Array[Lot] = []
	for road in p.roads:
		var walked := rng.randf_range(2.0, 5.0)
		var next := walked
		for i in road.size() - 1:
			var a := road[i]
			var b := road[i + 1]
			var length := a.distance_to(b)
			var tangent := (b - a) / length
			while next <= walked + length:
				var point := a + tangent * (next - walked)
				for side_sign in [-1.0, 1.0]:
					var lot := Lot.new()
					lot.point = point
					lot.normal = tangent.orthogonal() * side_sign
					lot.distance = point.distance_to(p.center)
					lots.append(lot)
				# Dense candidates; overlap checks thin them out as lots fill up.
				next += rng.randf_range(2.0, 3.0)
			walked += length
	lots.sort_custom(func(x: Lot, y: Lot) -> bool: return x.distance < y.distance)
	return lots


# --- buildings ---------------------------------------------------------------

static func _place_anchors(p: VillagePlan, lots: Array[Lot], placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> void:
	var r := p.recipe.radius
	var gate := p.center + p.main_direction * r * 0.85
	# Most important anchors first, so they get the best lots.
	var order := ["tavern", "warden_post", "shrine", "bakery", "smithy", "home_farm"]
	for kind in order:
		if not kind in p.recipe.anchors:
			continue
		var ranked := lots.duplicate()
		match kind:
			"warden_post":
				ranked.sort_custom(func(x: Lot, y: Lot) -> bool: return x.point.distance_to(gate) < y.point.distance_to(gate))
			"shrine":
				ranked.sort_custom(func(x: Lot, y: Lot) -> bool: return absf(x.distance - r * 0.55) < absf(y.distance - r * 0.55))
			"home_farm":
				# Partway out, facing away from the centre so the field runs into open country.
				var score := func(lot: Lot) -> float:
					var outward := lot.normal.dot((lot.point - p.center).normalized())
					return absf(lot.distance - r * 0.5) - outward * r * 0.3
				ranked.sort_custom(func(x: Lot, y: Lot) -> bool: return score.call(x) < score.call(y))
		for lot in ranked:
			if lot.used:
				continue
			var building := _try_building(p, kind, lot, placed, ground, rng)
			if building != null:
				p.buildings.append(building)
				break


static func _fill_houses(p: VillagePlan, lots: Array[Lot], placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> void:
	var count := 0
	for lot in lots:
		if count >= p.recipe.house_count:
			return
		if lot.used:
			continue
		var kind := "house"
		if lot.distance > p.recipe.radius * 0.6 and rng.randf() < p.recipe.farm_share:
			kind = "farm"
		var building := _try_building(p, kind, lot, placed, ground, rng)
		if building == null and kind == "farm":
			building = _try_building(p, "house", lot, placed, ground, rng)
		if building != null:
			p.buildings.append(building)
			count += 1


static func _try_building(p: VillagePlan, kind: String, lot: Lot, placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> VillagePlan.Building:
	var b := VillagePlan.Building.new()
	b.kind = kind
	_size_building(b, p.recipe, rng)
	var setback := rng.randf_range(1.2, 2.4)
	b.position = lot.point + lot.normal * (p.recipe.road_width * 0.5 + setback + b.size.z * 0.5)
	b.yaw = atan2(-lot.normal.x, -lot.normal.y)
	if b.has_field():
		b.field_offset = -(b.size.z * 0.5 + 1.5 + b.field_size.y * 0.5)

	var shapes: Array[PackedVector2Array] = [b.footprint(0.6)]
	if b.has_field():
		shapes.append(b.field_footprint(0.3))
	for i in shapes.size():
		# Fields may reach a little past the houses, into the farmland.
		if not _shape_is_clear(p, shapes[i], placed, ground, 1.05 if i == 0 else 1.45):
			return null
	if _height_spread(b.footprint(), ground) > 2.5:
		return null

	b.ground = _average_height(b.footprint(), ground)
	if b.has_field():
		b.field_ground = _average_height(b.field_footprint(), ground)
	placed.append_array(shapes)
	lot.used = true
	return b


static func _size_building(b: VillagePlan.Building, recipe: VillageRecipe, rng: RandomNumberGenerator) -> void:
	var wealth := recipe.prosperity
	match b.kind:
		"tavern":
			b.size = Vector3(rng.randf_range(9.0, 11.0), 3.0, rng.randf_range(8.0, 9.5))
			b.floors = 2
		"bakery", "smithy":
			b.size = Vector3(rng.randf_range(6.0, 7.0), 2.9, rng.randf_range(6.0, 7.5))
		"shrine":
			b.size = Vector3(rng.randf_range(5.0, 6.0), 3.6, rng.randf_range(8.0, 9.0))
		"warden_post":
			b.size = Vector3(5.0, 7.0, 5.0)
		"home_farm":
			b.size = Vector3(7.0, 2.8, 7.5)
			b.field_size = Vector2(rng.randf_range(14.0, 18.0), rng.randf_range(11.0, 14.0))
		_:
			b.size = Vector3(rng.randf_range(4.8, 6.0) + wealth * 1.2, 2.8, rng.randf_range(5.5, 7.0) + wealth)
			b.floors = 2 if rng.randf() < wealth * 0.35 else 1
			if b.kind == "farm":
				b.field_size = Vector2(rng.randf_range(10.0, 14.0), rng.randf_range(8.0, 11.0))


static func _shape_is_clear(p: VillagePlan, shape: PackedVector2Array, placed: Array[PackedVector2Array], ground: Object, radius_scale: float) -> bool:
	for corner in shape:
		if corner.distance_to(p.center) > p.recipe.radius * radius_scale:
			return false
		if corner.distance_to(p.center) < p.green_radius:
			return false
		if ground.is_water(corner.x, corner.y):
			return false
	for road in p.roads:
		if GenGeometry.rect_distance_to_polyline(shape, road) < p.recipe.road_width * 0.5 + 0.3:
			return false
	for other in placed:
		if GenGeometry.rects_overlap(shape, other):
			return false
	return true


static func _height_spread(corners: PackedVector2Array, ground: Object) -> float:
	var low := INF
	var high := -INF
	for c in corners:
		var h: float = ground.height_at(c.x, c.y)
		low = minf(low, h)
		high = maxf(high, h)
	return high - low


static func _average_height(corners: PackedVector2Array, ground: Object) -> float:
	var total := 0.0
	for c in corners:
		total += ground.height_at(c.x, c.y)
	return total / corners.size()


# --- props -------------------------------------------------------------------

## Wells and notice boards claim their spots before houses fill the lots.
static func _place_prop_anchors(p: VillagePlan, placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> void:
	var half_road := p.recipe.road_width * 0.5
	var side := p.main_direction.orthogonal()

	if "well" in p.recipe.anchors:
		var spots: Array[Vector2] = []
		match p.recipe.layout:
			VillageRecipe.Layout.GREEN:
				spots = [p.center]
			VillageRecipe.Layout.CROSSROADS:
				for diagonal in [p.main_direction + side, p.main_direction - side, -p.main_direction + side, -p.main_direction - side]:
					spots.append(p.center + diagonal.normalized() * (half_road + 2.6) * 1.414)
			_:
				spots = [p.center + side * (half_road + 2.0), p.center - side * (half_road + 2.0)]
		for spot in spots:
			if _try_prop(p, "well", spot, placed, ground, rng):
				break

	if "notice_board" in p.recipe.anchors:
		var near: Vector2 = p.center
		var tavern := p.first_of("tavern")
		if tavern != null:
			near = tavern.position
		_prop_near(p, "notice_board", near, 3.0, 9.0, placed, ground, rng)


static func _place_props(p: VillagePlan, placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> void:
	var half_road := p.recipe.road_width * 0.5
	var side := p.main_direction.orthogonal()

	# Lamps along the main road in better-off villages.
	if p.recipe.prosperity >= 0.3:
		var main := p.roads[0]
		var walked := 0.0
		var next := 4.0
		var flip := 1.0
		for i in main.size() - 1:
			var a := main[i]
			var b := main[i + 1]
			var length := a.distance_to(b)
			var tangent := (b - a) / length
			while next <= walked + length:
				var spot := a + tangent * (next - walked) + tangent.orthogonal() * flip * (half_road + 0.6)
				_try_prop(p, "lamp", spot, placed, ground, rng)
				flip = -flip
				next += 11.0
			walked += length

	# Crates and barrels outside working buildings.
	for b in p.buildings:
		if b.kind in ["tavern", "bakery", "smithy", "farm", "home_farm"]:
			for i in rng.randi_range(2, 4):
				_prop_near(p, "crate" if rng.randf() < 0.5 else "barrel", b.position, b.size.x * 0.5 + 1.0, b.size.x * 0.5 + 3.0, placed, ground, rng)

	# Faction banners at the gate.
	if p.recipe.faction != "none":
		var gate := p.center + p.main_direction * p.recipe.radius * 0.9
		for s in [-1.0, 1.0]:
			_try_prop(p, "banner", gate + side * s * (half_road + 1.2), placed, ground, rng)


static func _prop_near(p: VillagePlan, kind: String, near: Vector2, min_distance: float, max_distance: float, placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> bool:
	for attempt in 16:
		var spot := near + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(min_distance, max_distance)
		if _try_prop(p, kind, spot, placed, ground, rng):
			return true
	return false


static func _try_prop(p: VillagePlan, kind: String, spot: Vector2, placed: Array[PackedVector2Array], ground: Object, rng: RandomNumberGenerator) -> bool:
	var radius: float = PROP_RADII.get(kind, 0.5)
	if spot.distance_to(p.center) > p.recipe.radius * 1.05 or ground.is_water(spot.x, spot.y):
		return false
	var square := GenGeometry.rect_corners(spot, Vector2.ONE * radius, 0.0)
	var on_road_ok := kind == "well" and p.recipe.layout == VillageRecipe.Layout.GREEN
	if not on_road_ok:
		for road in p.roads:
			if GenGeometry.rect_distance_to_polyline(square, road) < p.recipe.road_width * 0.5 + 0.1:
				return false
	for other in placed:
		if GenGeometry.rects_overlap(square, other):
			return false
	var prop := VillagePlan.Prop.new()
	prop.kind = kind
	prop.position = spot
	prop.radius = radius
	prop.yaw = rng.randf() * TAU
	prop.ground = ground.height_at(spot.x, spot.y)
	p.props.append(prop)
	placed.append(square)
	return true


# --- story state -------------------------------------------------------------

## Applied after the layout is final, from its own streams, so a village keeps
## the same streets and houses whether it is calm, bleeding or burned.
static func _apply_story_state(p: VillagePlan, state: Dictionary) -> void:
	p.faction = state.get("faction", p.recipe.faction)
	var bleed: float = state.get("bleed", p.recipe.bleed)
	var damage: float = state.get("damage", p.recipe.damage)

	var bleed_rng := GenRng.stream(p.layout_seed, "bleed")
	for b in p.buildings:
		var roll := bleed_rng.randf()
		var height := bleed_rng.randf_range(1.5, 7.0)
		var tilt := Vector2(bleed_rng.randf_range(-0.25, 0.25), bleed_rng.randf_range(-0.25, 0.25))
		if roll < bleed * 0.85:
			b.lift = height * bleed
			b.tilt = tilt * bleed
	for prop in p.props:
		var roll := bleed_rng.randf()
		var height := bleed_rng.randf_range(0.8, 4.0)
		if roll < bleed:
			prop.lift = height * bleed

	var damage_rng := GenRng.stream(p.layout_seed, "damage")
	for b in p.buildings:
		var roof_roll := damage_rng.randf()
		var scorch_roll := damage_rng.randf()
		b.roof_damage = clampf(roof_roll * damage * 1.6 - 0.2, 0.0, 1.0)
		b.scorched = scorch_roll < damage * 0.8
