class_name DungeonPlanner
## Recipe + seed -> DungeonPlan. No nodes are created here.
##
## Stages, each with its own random stream (see GenRng):
##   mission     grow a mission graph from rewrite rules: the main route
##               (entrance, combat rooms, boss, reward), then locks with their
##               key branches, story rooms and side rooms
##   layout      place each room on the grid next to its parent, joined by a
##               straight corridor, without touching any other room
##   templates   pick each room's template (hall, pillared, shrine...)
##   props       dress the rooms (pillars, sarcophagi, pews, crystals...)
##   encounters  give each room a threat budget and a monster level
##   chests      place loot chests against walls
##   story       apply story state (cleared, harder) without moving anything
## If the result fails validation, the planner retries with a derived seed.

const MAX_ATTEMPTS := 12
const PLACE_TRIES := 60
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Room size range in cells (min, max) per room kind; combat rooms use their template's.
const KIND_SIZES := {
	"entrance": Vector2i(3, 4),
	"key": Vector2i(3, 4),
	"treasure": Vector2i(3, 4),
	"story": Vector2i(4, 5),
	"boss": Vector2i(7, 9),
	"reward": Vector2i(4, 5),
}
const TEMPLATE_SIZES := {
	"hall": Vector2i(4, 6),
	"pillared": Vector2i(5, 7),
	"shrine": Vector2i(4, 5),
	"ossuary": Vector2i(4, 6),
	"pews": Vector2i(5, 7),
	"flooded": Vector2i(4, 7),
	"cavern": Vector2i(5, 7),
	"dais": Vector2i(5, 6),
}
## Budget multiplier per room kind (combat rooms are 1).
const KIND_THREAT := {"combat": 1.0, "key": 0.6, "treasure": 0.5, "boss": 1.0}


## `level_min`/`level_max` override the recipe's level range when > 0 (for a
## dungeon scaled to the player). `state` is story state applied after the
## layout: {"cleared": true} empties it of monsters, {"level_bonus": 2} makes
## it harder. Neither changes a single room or corridor.
static func plan(recipe: DungeonRecipe, seed_value: int, state := {}, level_min := 0, level_max := 0) -> DungeonPlan:
	var lo := level_min if level_min > 0 else recipe.level_min
	var hi := maxi(lo, level_max if level_max > 0 else recipe.level_max)
	var best: DungeonPlan = null
	for attempt in MAX_ATTEMPTS:
		var attempt_seed := seed_value if attempt == 0 else GenRng.derive(seed_value, "retry%d" % attempt)
		var candidate := _plan_once(recipe, attempt_seed, lo, hi)
		candidate.seed_value = seed_value
		candidate.attempts = attempt + 1
		DungeonValidator.validate(candidate)
		if best == null or candidate.problems.size() < best.problems.size():
			best = candidate
		if candidate.is_valid():
			break
	if not best.is_valid():
		push_warning("%s seed %d: no valid dungeon after %d attempts: %s" % [recipe.display_name, seed_value, MAX_ATTEMPTS, ", ".join(best.problems)])
	_apply_story_state(best, state)
	return best


static func _plan_once(recipe: DungeonRecipe, attempt_seed: int, lo: int, hi: int) -> DungeonPlan:
	var p := DungeonPlan.new()
	p.recipe = recipe
	p.layout_seed = attempt_seed
	p.level_min = lo
	p.level_max = hi
	_grow_mission(p, GenRng.stream(attempt_seed, "mission"))
	_pick_templates(p, GenRng.stream(attempt_seed, "templates"))
	if not _lay_out(p, GenRng.stream(attempt_seed, "layout")):
		return p
	_place_props(p, GenRng.stream(attempt_seed, "props"))
	_place_encounters(p, GenRng.stream(attempt_seed, "encounters"))
	_place_chests(p, GenRng.stream(attempt_seed, "chests"))
	return p


# --- mission graph -------------------------------------------------------------
# Rewrite rules, applied in order:
#   start   entrance -> boss -> reward
#   extend  insert combat rooms before the boss until the route is long enough
#   lock    lock a door on the route; hang a key branch (maybe guarded) off a
#           route room between the previous lock and this one
#   story   hang each story room off a room before the boss
#   side    hang treasure rooms and dead ends off rooms before the boss

static func _grow_mission(p: DungeonPlan, rng: RandomNumberGenerator) -> void:
	var recipe := p.recipe
	var route_length := rng.randi_range(recipe.critical_min, maxi(recipe.critical_min, recipe.critical_max))
	var route: Array[int] = []
	route.append(_add_room(p, "entrance", -1, true))
	for i in route_length:
		route.append(_add_room(p, "combat", route[-1], true))
	p.boss_room = _add_room(p, "boss", route[-1], true)
	route.append(p.boss_room)
	p.reward_room = _add_room(p, "reward", p.boss_room, true)
	p.rooms[p.reward_room].marker = recipe.reward_marker
	p.entrance_room = route[0]

	# Locks go on route rooms 1..boss (index in `route`), spread out and increasing.
	var lock_count := mini(recipe.locks, route.size() - 1)
	var candidates: Array[int] = []
	for i in range(1, route.size()):
		candidates.append(i)
	var lock_at: Array[int] = []
	for k in lock_count:
		var pick := candidates[rng.randi_range(0, candidates.size() - 1)]
		lock_at.append(pick)
		candidates.erase(pick)
	lock_at.sort()
	var previous := 0
	for k in lock_at.size():
		var locked := route[lock_at[k]]
		p.rooms[locked].lock_id = k
		var hang_from := route[rng.randi_range(previous, lock_at[k] - 1)]
		if rng.randf() < 0.5:
			hang_from = _add_room(p, "combat", hang_from, false)
		var key_room := _add_room(p, "key", hang_from, false)
		p.rooms[key_room].key_id = k
		previous = lock_at[k]

	var before_boss: Array[int] = []
	for r in p.rooms:
		if r.id != p.boss_room and r.id != p.reward_room:
			before_boss.append(r.id)
	for marker in recipe.story_rooms:
		var story := _add_room(p, "story", before_boss[rng.randi_range(0, before_boss.size() - 1)], false)
		p.rooms[story].marker = marker
	for i in rng.randi_range(recipe.side_min, maxi(recipe.side_min, recipe.side_max)):
		var kind := "treasure" if rng.randf() < 0.6 else "combat"
		before_boss.append(_add_room(p, kind, before_boss[rng.randi_range(0, before_boss.size() - 1)], false))


static func _add_room(p: DungeonPlan, kind: String, parent: int, critical: bool) -> int:
	var r := DungeonPlan.Room.new()
	r.id = p.rooms.size()
	r.kind = kind
	r.parent = parent
	r.critical = critical
	p.rooms.append(r)
	return r.id


static func _pick_templates(p: DungeonPlan, rng: RandomNumberGenerator) -> void:
	var templates := p.recipe.templates if not p.recipe.templates.is_empty() else PackedStringArray(["hall"])
	for r in p.rooms:
		match r.kind:
			"combat", "key", "treasure":
				r.template = templates[rng.randi_range(0, templates.size() - 1)]
			"boss":
				r.template = "dais"
			"story", "reward":
				r.template = "shrine"
			_:
				r.template = "hall"


static func _room_size(r: DungeonPlan.Room, rng: RandomNumberGenerator) -> Vector2i:
	var span: Vector2i = TEMPLATE_SIZES.get(r.template, Vector2i(4, 6)) if r.kind == "combat" else KIND_SIZES.get(r.kind, Vector2i(4, 5))
	return Vector2i(rng.randi_range(span.x, span.y), rng.randi_range(span.x, span.y))


# --- layout --------------------------------------------------------------------

static func _lay_out(p: DungeonPlan, rng: RandomNumberGenerator) -> bool:
	var entrance := p.rooms[p.entrance_room]
	var size := _room_size(entrance, rng)
	entrance.rect = Rect2i(-size / 2, size)
	_claim_room(p, entrance)
	# Rooms are created parent-first, so each parent is already placed.
	for r in p.rooms:
		if r.id == p.entrance_room:
			continue
		if not _place_child(p, p.rooms[r.parent], r, rng):
			p.problems.append("no room for %s room %d" % [r.kind, r.id])
			return false
	return true


static func _place_child(p: DungeonPlan, parent: DungeonPlan.Room, child: DungeonPlan.Room, rng: RandomNumberGenerator) -> bool:
	var recipe := p.recipe
	var pr := parent.rect
	for attempt in PLACE_TRIES:
		var dir := DIRECTIONS[rng.randi_range(0, 3)]
		if parent.id == p.entrance_room and dir == -_entrance_way_in(p):
			continue  # That wall holds the stairs out.
		var size := _room_size(child, rng)
		var length := rng.randi_range(recipe.corridor_min, maxi(recipe.corridor_min, recipe.corridor_max))
		var horizontal := dir.x != 0
		# The parent's door cell, away from its corners.
		var edge: Vector2i
		if horizontal:
			edge = Vector2i(pr.end.x - 1 if dir.x > 0 else pr.position.x, rng.randi_range(pr.position.y + 1, pr.end.y - 2))
		else:
			edge = Vector2i(rng.randi_range(pr.position.x + 1, pr.end.x - 2), pr.end.y - 1 if dir.y > 0 else pr.position.y)
		var child_edge := edge + dir * (length + 1)
		var along := size.x if horizontal else size.y
		var across := size.y if horizontal else size.x
		var k := rng.randi_range(1, across - 2)
		var origin: Vector2i
		if horizontal:
			origin = Vector2i(child_edge.x if dir.x > 0 else child_edge.x - along + 1, child_edge.y - k)
		else:
			origin = Vector2i(child_edge.x - k, child_edge.y if dir.y > 0 else child_edge.y - along + 1)
		var rect := Rect2i(origin, size)
		var path: Array[Vector2i] = []
		for t in range(1, length + 1):
			path.append(edge + dir * t)
		if not _rect_free(p, rect.grow(1)) or not _path_free(p, path, dir):
			continue
		child.rect = rect
		_claim_room(p, child)
		var corridor := DungeonPlan.Corridor.new()
		corridor.id = p.corridors.size()
		corridor.from_room = parent.id
		corridor.to_room = child.id
		corridor.cells = path
		p.corridors.append(corridor)
		for cell in path:
			p.cells[cell] = DungeonPlan.corridor_owner(corridor.id)
		_add_door(p, edge, path[0], parent.id, corridor.id, -1)
		_add_door(p, child_edge, path[-1], child.id, corridor.id, child.lock_id)
		return true
	return false


## Direction of the entrance room's first doorway (zero before it has one).
static func _entrance_way_in(p: DungeonPlan) -> Vector2i:
	for d in p.doors:
		if d.room == p.entrance_room:
			return d.b - d.a
	return Vector2i.ZERO


static func _rect_free(p: DungeonPlan, rect: Rect2i) -> bool:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			if p.cells.has(Vector2i(x, y)):
				return false
	return true


## Corridor cells must be empty, and so must the cells beside them, so two
## corridors never run side by side.
static func _path_free(p: DungeonPlan, path: Array[Vector2i], dir: Vector2i) -> bool:
	var side := Vector2i(dir.y, dir.x)
	for cell in path:
		if p.cells.has(cell) or p.cells.has(cell + side) or p.cells.has(cell - side):
			return false
	return true


static func _claim_room(p: DungeonPlan, r: DungeonPlan.Room) -> void:
	for x in range(r.rect.position.x, r.rect.end.x):
		for y in range(r.rect.position.y, r.rect.end.y):
			p.cells[Vector2i(x, y)] = r.id


static func _add_door(p: DungeonPlan, room_cell: Vector2i, corridor_cell: Vector2i, room: int, corridor: int, lock_id: int) -> void:
	var d := DungeonPlan.Door.new()
	d.a = room_cell
	d.b = corridor_cell
	d.room = room
	d.corridor = corridor
	d.lock_id = lock_id
	p.doors.append(d)


# --- props ---------------------------------------------------------------------
# Solid props only go on the room's interior (one cell in from every wall), so
# the ring along the walls always links every door.

static func _place_props(p: DungeonPlan, rng: RandomNumberGenerator) -> void:
	var cs := p.recipe.cell_size
	for r in p.rooms:
		var inner := Rect2(Vector2(r.rect.grow(-1).position) * cs, Vector2(r.rect.grow(-1).size) * cs)
		var center := p.room_center(r)
		# Every room gets a light source; the kit puts a light on it.
		if r.template in ["dais", "shrine"]:
			pass
		elif p.recipe.style == DungeonRecipe.Style.MINE or r.template in ["pillared", "pews", "flooded"]:
			_prop(p, "lantern", r, center, 0.0, 1.0)
		else:
			_prop(p, "brazier", r, center, 0.0, 1.0, true, Vector2(0.4, 0.4))
		match r.template:
			"pillared":
				for x in range(r.rect.position.x + 1, r.rect.end.x, 2):
					for y in range(r.rect.position.y + 1, r.rect.end.y, 2):
						var at := Vector2(x, y) * cs
						if inner.grow(-0.5).has_point(at):
							_prop(p, "pillar", r, at, 0.0, rng.randf_range(0.9, 1.1), true, Vector2(0.55, 0.55))
			"ossuary":
				for i in rng.randi_range(2, 4):
					var at = _free_spot(p, inner.grow(-1.2), 1.4, rng)
					if at != null:
						_prop(p, "sarcophagus", r, at, PI * 0.5 * rng.randi_range(0, 1), 1.0, true, Vector2(0.55, 1.1))
				for i in rng.randi_range(3, 6):
					_prop(p, "bones", r, _anywhere(r, cs, rng), rng.randf() * TAU, rng.randf_range(0.7, 1.3))
			"pews":
				var aisle := center.x
				var y := inner.position.y + 1.0
				while y < inner.end.y - 1.5:
					for s in [-1.0, 1.0]:
						var width := minf(inner.size.x * 0.5 - 1.6, 3.2)
						if width > 0.8:
							_prop(p, "pew", r, Vector2(aisle + s * (1.0 + width * 0.5), y), 0.0, width, true, Vector2(width * 0.5, 0.3))
					y += 2.2
				_prop(p, "altar", r, Vector2(center.x, inner.end.y - 0.6), 0.0, 1.0, true, Vector2(1.0, 0.5))
			"shrine":
				_prop(p, "statue" if r.kind != "reward" else "altar", r, center, PI, 1.0, true, Vector2(0.7, 0.7))
				for i in 4:
					var corner := Vector2(inner.position.x + 0.4 if i % 2 == 0 else inner.end.x - 0.4, inner.position.y + 0.4 if i < 2 else inner.end.y - 0.4)
					_prop(p, "candles", r, corner, rng.randf() * TAU, 1.0)
			"dais":
				_prop(p, "dais", r, center, 0.0, minf(inner.size.x, inner.size.y) * 0.22, false)
				for i in 4:
					var angle := TAU * i / 4.0 + PI * 0.25
					_prop(p, "brazier", r, center + Vector2.from_angle(angle) * minf(inner.size.x, inner.size.y) * 0.42, 0.0, 1.0, true, Vector2(0.4, 0.4))
			"flooded":
				_prop(p, "water", r, center, 0.0, 1.0)
				for i in rng.randi_range(1, 3):
					_prop(p, "rubble", r, _anywhere(r, cs, rng), rng.randf() * TAU, rng.randf_range(0.8, 1.4))
			"cavern":
				for i in rng.randi_range(2, 4):
					var at = _free_spot(p, inner.grow(-0.8), 0.9, rng)
					if at != null:
						_prop(p, "crystal", r, at, rng.randf() * TAU, rng.randf_range(0.8, 1.5), true, Vector2(0.45, 0.45))
				for i in rng.randi_range(1, 2):
					_prop(p, "rubble", r, _anywhere(r, cs, rng), rng.randf() * TAU, rng.randf_range(1.0, 1.6))
			_:
				for i in rng.randi_range(0, 2):
					_prop(p, "rubble", r, _anywhere(r, cs, rng), rng.randf() * TAU, rng.randf_range(0.6, 1.2))
	# Mines prop their corridors with timber frames.
	if p.recipe.style == DungeonRecipe.Style.MINE:
		for c in p.corridors:
			for cell in c.cells:
				_prop(p, "timber", null, p.cell_center(cell), 0.0 if c.cells.size() < 2 or c.cells[0].x != c.cells[1].x else PI * 0.5, 1.0)


static func _prop(p: DungeonPlan, kind: String, r: DungeonPlan.Room, at: Vector2, yaw: float, scale: float, solid := false, half := Vector2(0.3, 0.3)) -> void:
	var prop := DungeonPlan.Prop.new()
	prop.kind = kind
	prop.room = r.id if r != null else -1
	prop.position = at
	prop.yaw = yaw
	prop.scale = scale
	prop.solid = solid
	prop.half = half
	p.props.append(prop)


## A random point in `area` at least `clearance` metres (plus their size) from
## every solid prop placed so far, or null.
static func _free_spot(p: DungeonPlan, area: Rect2, clearance: float, rng: RandomNumberGenerator):
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return null
	for attempt in 12:
		var at := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var clear := true
		for other in p.props:
			if other.solid and at.distance_to(other.position) < clearance + maxf(other.half.x, other.half.y):
				clear = false
				break
		if clear:
			return at
	return null


## A point anywhere in the room away from the walls (for loose, walk-through clutter).
static func _anywhere(r: DungeonPlan.Room, cs: float, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(r.rect.position.x + 0.3, r.rect.end.x - 0.3),
		rng.randf_range(r.rect.position.y + 0.3, r.rect.end.y - 0.3)) * cs


# --- encounters ----------------------------------------------------------------

static func _place_encounters(p: DungeonPlan, rng: RandomNumberGenerator) -> void:
	var recipe := p.recipe
	var route := p.route_to(p.boss_room)
	var depth_of := {}
	for i in route.size():
		depth_of[route[i]] = float(i) / maxf(route.size() - 1, 1)
	for r in p.rooms:
		if not KIND_THREAT.has(r.kind):
			continue
		# Side rooms take the depth of the route room they hang off.
		var at := r
		while not depth_of.has(at.id) and at.parent >= 0:
			at = p.rooms[at.parent]
		var depth: float = depth_of.get(at.id, 0.5)
		var level := clampi(roundi(lerpf(p.level_min, p.level_max, depth)), p.level_min, p.level_max)
		var budget: float = recipe.threat_per_level * level * KIND_THREAT[r.kind]
		if r.kind == "boss":
			level = p.level_max
			budget = recipe.threat_per_level * level * recipe.boss_multiplier
		budget *= rng.randf_range(0.85, 1.15)
		r.budget = snappedf(budget, 0.1)
		var e := DungeonPlan.Encounter.new()
		e.room = r.id
		e.boss = r.kind == "boss"
		e.budget = r.budget
		e.level = level
		e.seed_value = rng.randi()
		var inner := r.rect.grow(-1)
		e.area = Rect2(Vector2(inner.position) * recipe.cell_size, Vector2(inner.size) * recipe.cell_size).grow(0.5)
		p.encounters.append(e)


# --- chests --------------------------------------------------------------------

static func _place_chests(p: DungeonPlan, rng: RandomNumberGenerator) -> void:
	var recipe := p.recipe
	var target := rng.randi_range(recipe.chests_min, maxi(recipe.chests_min, recipe.chests_max))
	var order: Array[DungeonPlan.Room] = []
	# The boss reward always gets one, then every treasure room, then combat rooms.
	order.append(p.rooms[p.reward_room])
	for r in p.rooms:
		if r.kind == "treasure":
			order.append(r)
	var combat: Array[DungeonPlan.Room] = []
	for r in p.rooms:
		if r.kind in ["combat", "key"]:
			combat.append(r)
	for i in combat.size():
		var j := rng.randi_range(i, combat.size() - 1)
		var swap := combat[i]
		combat[i] = combat[j]
		combat[j] = swap
	order.append_array(combat)
	for r in order:
		if p.chests.size() >= target:
			break
		var spot := _chest_spot(p, r, rng)
		if spot.is_empty():
			continue
		var chest := DungeonPlan.Chest.new()
		chest.room = r.id
		chest.position = spot["position"]
		chest.yaw = spot["yaw"]
		chest.tier = 2 if r.id == p.reward_room else (1 if r.kind == "treasure" else 0)
		chest.seed_value = rng.randi()
		p.chests.append(chest)


## Against a wall, on a ring cell that isn't a door cell or next to one, facing into the room.
static func _chest_spot(p: DungeonPlan, r: DungeonPlan.Room, rng: RandomNumberGenerator) -> Dictionary:
	var cs := p.recipe.cell_size
	var options: Array[Dictionary] = []
	for x in range(r.rect.position.x + 1, r.rect.end.x - 1):
		options.append({"cell": Vector2i(x, r.rect.position.y), "wall": Vector2(0, -1)})
		options.append({"cell": Vector2i(x, r.rect.end.y - 1), "wall": Vector2(0, 1)})
	for y in range(r.rect.position.y + 1, r.rect.end.y - 1):
		options.append({"cell": Vector2i(r.rect.position.x, y), "wall": Vector2(-1, 0)})
		options.append({"cell": Vector2i(r.rect.end.x - 1, y), "wall": Vector2(1, 0)})
	while not options.is_empty():
		var pick: Dictionary = options.pop_at(rng.randi_range(0, options.size() - 1))
		var cell: Vector2i = pick["cell"]
		if _near_door(p, cell) or _chest_taken(p, cell, cs):
			continue
		var wall: Vector2 = pick["wall"]
		var position := p.cell_center(cell) + wall * (cs * 0.5 - 0.7)
		# Chests face away from their wall: front is local +Z.
		return {"position": position, "yaw": atan2(-wall.x, -wall.y)}
	return {}


static func _near_door(p: DungeonPlan, cell: Vector2i) -> bool:
	for d in p.doors:
		if absi(d.a.x - cell.x) + absi(d.a.y - cell.y) <= 1:
			return true
	return false


static func _chest_taken(p: DungeonPlan, cell: Vector2i, cs: float) -> bool:
	for c in p.chests:
		if c.position.distance_to(p.cell_center(cell)) < cs * 1.2:
			return true
	return false


# --- story state ---------------------------------------------------------------

static func _apply_story_state(p: DungeonPlan, state: Dictionary) -> void:
	if state.get("cleared", false):
		for r in p.rooms:
			r.budget = 0.0
		p.encounters.clear()
		return
	var bonus: int = state.get("level_bonus", 0)
	if bonus != 0:
		for e in p.encounters:
			e.level = maxi(1, e.level + bonus)
			e.budget = snappedf(e.budget * float(e.level) / maxf(e.level - bonus, 1), 0.1)
