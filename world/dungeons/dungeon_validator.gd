class_name DungeonValidator
## Independent checks on a finished DungeonPlan. The planner tries to obey the
## same rules; this catches anything it got wrong and is what the fuzz test and
## the retry loop rely on. Reachability is checked by walking the grid cell by
## cell through doors, not by trusting the mission graph.


static func validate(p: DungeonPlan) -> void:
	p.problems.clear()
	var recipe := p.recipe

	for r in p.rooms:
		if r.rect.size == Vector2i.ZERO:
			p.problems.append("%s room %d was never placed" % [r.kind, r.id])
	if not p.problems.is_empty():
		return

	if p.count_kind("boss") != 1 or p.count_kind("reward") != 1 or p.count_kind("entrance") != 1:
		p.problems.append("needs exactly one entrance, boss and reward room")
	for marker in recipe.story_rooms:
		if not _has_marker(p, marker, "story"):
			p.problems.append("missing story room: %s" % marker)
	if recipe.reward_marker != "" and p.rooms[p.reward_room].marker != recipe.reward_marker:
		p.problems.append("reward room has no %s" % recipe.reward_marker)

	_check_geometry(p)
	_check_reachability(p)
	_check_route(p)
	_check_encounters(p)
	_check_chests(p)
	_check_props(p)


static func _has_marker(p: DungeonPlan, marker: String, kind: String) -> bool:
	for r in p.rooms:
		if r.kind == kind and r.marker == marker:
			return true
	return false


# --- geometry ------------------------------------------------------------------

static func _check_geometry(p: DungeonPlan) -> void:
	for i in p.rooms.size():
		for j in range(i + 1, p.rooms.size()):
			if p.rooms[i].rect.grow(1).intersects(p.rooms[j].rect):
				p.problems.append("rooms %d and %d touch" % [i, j])
	for r in p.rooms:
		for x in range(r.rect.position.x, r.rect.end.x):
			for y in range(r.rect.position.y, r.rect.end.y):
				if p.cells.get(Vector2i(x, y), -999) != r.id:
					p.problems.append("room %d cell owned by something else" % r.id)
					return
	for c in p.corridors:
		for cell in c.cells:
			for r in p.rooms:
				if r.has_cell(cell):
					p.problems.append("corridor %d runs through room %d" % [c.id, r.id])
	for d in p.doors:
		if absi(d.a.x - d.b.x) + absi(d.a.y - d.b.y) != 1:
			p.problems.append("door cells not adjacent")
		elif p.cells.get(d.a) != d.room or p.cells.get(d.b) != DungeonPlan.corridor_owner(d.corridor):
			p.problems.append("door between the wrong cells")


# --- reachability --------------------------------------------------------------

## Cells reachable from the entrance holding `keys`. Two neighbouring floor
## cells connect when they belong to the same room or corridor, or a door
## joins them and its lock (if any) is open.
static func reachable_cells(p: DungeonPlan, keys: Dictionary) -> Dictionary:
	var start := p.rooms[p.entrance_room].rect.position
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var doors := {}
	for d in p.doors:
		doors[_edge_key(d.a, d.b)] = d
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		var owner = p.cells[cell]
		for step in DungeonPlanner.DIRECTIONS:
			var next: Vector2i = cell + step
			if seen.has(next) or not p.cells.has(next):
				continue
			if p.cells[next] != owner:
				var door: DungeonPlan.Door = doors.get(_edge_key(cell, next))
				if door == null or (door.lock_id >= 0 and not keys.has(door.lock_id)):
					continue
			seen[next] = true
			queue.append(next)
	return seen


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## Walk in, pick up every key you can reach, open what they unlock, repeat.
## Returns {"cells": reached cells, "keys": keys collected, "order": key pickup order}.
static func explore(p: DungeonPlan, without_key := -1) -> Dictionary:
	var keys := {}
	var order: Array[int] = []
	var reached := {}
	while true:
		reached = reachable_cells(p, keys)
		var found := false
		for r in p.rooms:
			if r.key_id >= 0 and r.key_id != without_key and not keys.has(r.key_id) and reached.has(r.rect.position):
				keys[r.key_id] = true
				order.append(r.key_id)
				found = true
		if not found:
			break
	return {"cells": reached, "keys": keys, "order": order}


static func _check_reachability(p: DungeonPlan) -> void:
	var walk := explore(p)
	var reached: Dictionary = walk["cells"]
	for r in p.rooms:
		if not reached.has(r.rect.position):
			p.problems.append("%s room %d can't be reached" % [r.kind, r.id])
	for c in p.corridors:
		for cell in c.cells:
			if not reached.has(cell):
				p.problems.append("corridor %d can't be reached" % c.id)
				break
	# Every lock must actually gate the rooms behind it, and its key must lie
	# on the near side of it.
	for r in p.rooms:
		if r.lock_id < 0:
			continue
		var key_room := -1
		for k in p.rooms:
			if k.key_id == r.lock_id:
				key_room = k.id
		if key_room < 0:
			p.problems.append("lock %d has no key" % r.lock_id)
			continue
		var without: Dictionary = explore(p, r.lock_id)["cells"]
		if without.has(r.rect.position):
			p.problems.append("lock %d can be walked around" % r.lock_id)
		if not without.has(p.rooms[key_room].rect.position):
			p.problems.append("key %d is behind its own lock" % r.lock_id)
	if p.reward_room >= 0:
		var links: Array = p.room_links().get(p.reward_room, [])
		if links.size() != 1 or links[0] != p.boss_room:
			p.problems.append("reward room isn't behind the boss")


static func _check_route(p: DungeonPlan) -> void:
	var route := p.route_to(p.boss_room)
	if route.is_empty():
		p.problems.append("no route to the boss")
		return
	var between := route.size() - 2
	if between < p.recipe.critical_min or between > p.recipe.critical_max:
		p.problems.append("route has %d rooms before the boss (want %d-%d)" % [between, p.recipe.critical_min, p.recipe.critical_max])


# --- encounters, chests, props -----------------------------------------------

static func _check_encounters(p: DungeonPlan) -> void:
	var recipe := p.recipe
	var expected := 0
	for r in p.rooms:
		if DungeonPlanner.KIND_THREAT.has(r.kind):
			expected += 1
	if p.encounters.size() != expected:
		p.problems.append("%d encounters for %d fighting rooms" % [p.encounters.size(), expected])
	var low := recipe.threat_per_level * p.level_min * 0.4
	var high := recipe.threat_per_level * p.level_max * maxf(recipe.boss_multiplier, 1.0) * 1.2
	var bosses := 0
	for e in p.encounters:
		var room := p.rooms[e.room]
		var cs := recipe.cell_size
		var room_area := Rect2(Vector2(room.rect.position) * cs, Vector2(room.rect.size) * cs)
		if not room_area.encloses(e.area):
			p.problems.append("encounter spills out of room %d" % e.room)
		if e.level < p.level_min or e.level > p.level_max:
			p.problems.append("room %d monster level %d outside %d-%d" % [e.room, e.level, p.level_min, p.level_max])
		if e.budget < low or e.budget > high:
			p.problems.append("room %d threat %.1f outside %.1f-%.1f" % [e.room, e.budget, low, high])
		if e.boss:
			bosses += 1
			if e.room != p.boss_room:
				p.problems.append("boss fight outside the boss room")
			elif e.budget < recipe.threat_per_level * p.level_max * recipe.boss_multiplier * 0.8:
				p.problems.append("boss room too easy")
	if bosses != 1:
		p.problems.append("%d boss fights" % bosses)
	if p.rooms[p.entrance_room].budget > 0.0:
		p.problems.append("monsters in the entrance")


static func _check_chests(p: DungeonPlan) -> void:
	var recipe := p.recipe
	if p.chests.size() < recipe.chests_min or p.chests.size() > maxi(recipe.chests_min, recipe.chests_max):
		p.problems.append("%d chests (want %d-%d)" % [p.chests.size(), recipe.chests_min, recipe.chests_max])
	var has_reward := false
	var cs := recipe.cell_size
	for c in p.chests:
		var room := p.rooms[c.room]
		if not Rect2(Vector2(room.rect.position) * cs, Vector2(room.rect.size) * cs).grow(-0.3).has_point(c.position):
			p.problems.append("chest outside room %d" % c.room)
		for d in p.doors:
			if c.position.distance_to(p.cell_center(d.a)) < cs * 0.9:
				p.problems.append("chest blocks a door")
		if c.tier == 2 and c.room == p.reward_room:
			has_reward = true
	if recipe.chests_min > 0 and not has_reward:
		p.problems.append("no reward chest behind the boss")


static func _check_props(p: DungeonPlan) -> void:
	var cs := p.recipe.cell_size
	var solid: Array[DungeonPlan.Prop] = []
	for prop in p.props:
		if prop.solid:
			solid.append(prop)
	for i in solid.size():
		var a := solid[i]
		var room := p.rooms[a.room]
		var inner := room.rect.grow(-1)
		var inner_area := Rect2(Vector2(inner.position) * cs, Vector2(inner.size) * cs)
		var reach := maxf(a.half.x, a.half.y)
		if not inner_area.grow(-reach * 0.5).has_point(a.position):
			p.problems.append("%s against a wall in room %d" % [a.kind, a.room])
		for j in range(i + 1, solid.size()):
			var b := solid[j]
			if a.position.distance_to(b.position) < (reach + maxf(b.half.x, b.half.y)) * 0.8 and a.kind != b.kind:
				p.problems.append("%s and %s overlap in room %d" % [a.kind, b.kind, a.room])
		for c in p.chests:
			if c.position.distance_to(a.position) < reach + 0.9:
				p.problems.append("chest blocked by %s" % a.kind)
