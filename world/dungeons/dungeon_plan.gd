class_name DungeonPlan
extends RefCounted
## A dungeon as pure data: rooms and corridors on a grid, the doors between
## them, locks and keys, encounters and chests. Planning produces this,
## DungeonValidator checks it and DungeonBuilder turns it into nodes, so
## dungeons can be generated and checked headlessly by the thousand.
##
## Grid cells are Vector2i. Cell (x, y) covers local X [x, x+1) * cell_size and
## local Z [y, y+1) * cell_size; the floor is at local Y 0.


class Room:
	var id := 0
	## entrance, combat, key, treasure, story, boss, reward
	var kind := "combat"
	var template := "hall"
	var rect := Rect2i()
	## Mission-graph parent (-1 for the entrance).
	var parent := -1
	## On the main route from the entrance to the reward room.
	var critical := false
	## The door from the parent into this room is locked by this lock (-1 none).
	var lock_id := -1
	## A key for this lock lies in this room (-1 none).
	var key_id := -1
	## Story marker name for story rooms and the reward room.
	var marker := ""
	## Threat points to spend on monsters here (0 = no monsters).
	var budget := 0.0

	func center_cell() -> Vector2:
		return Vector2(rect.position) + Vector2(rect.size) * 0.5

	func has_cell(cell: Vector2i) -> bool:
		return rect.has_point(cell)


class Corridor:
	var id := 0
	var from_room := 0
	var to_room := 0
	## Straight run of cells from the parent room's wall to the child's.
	var cells: Array[Vector2i] = []


class Door:
	## Two edge-adjacent cells: a room cell and a corridor cell.
	var a := Vector2i.ZERO
	var b := Vector2i.ZERO
	var room := 0
	var corridor := 0
	var lock_id := -1

	func connects(p: Vector2i, q: Vector2i) -> bool:
		return (a == p and b == q) or (a == q and b == p)


class Encounter:
	var room := 0
	var boss := false
	var budget := 0.0
	## Monster level for this room; deeper rooms sit higher in the recipe's range.
	var level := 1
	var seed_value := 0
	## Interior rectangle in local metres (x, z), kept clear of walls and doors.
	var area := Rect2()


class Chest:
	var room := 0
	var position := Vector2.ZERO
	var yaw := 0.0
	## 0 ordinary, 1 side-room treasure, 2 boss reward.
	var tier := 0
	var seed_value := 0


class Prop:
	var kind := "pillar"
	var room := -1
	var position := Vector2.ZERO
	var yaw := 0.0
	var scale := 1.0
	## Blocks movement. Solid props stay off the ring of cells along the walls,
	## so every door in a room can always reach every other.
	var solid := false
	## Footprint half extents in metres (local X, Z before yaw).
	var half := Vector2(0.4, 0.4)


var recipe: DungeonRecipe
var seed_value := 0
## Seed of the attempt that produced this layout (differs from seed_value after a retry).
var layout_seed := 0
var attempts := 1
var level_min := 1
var level_max := 1
var rooms: Array[Room] = []
var corridors: Array[Corridor] = []
var doors: Array[Door] = []
var encounters: Array[Encounter] = []
var chests: Array[Chest] = []
var props: Array[Prop] = []
## Which room (>= 0) or corridor (encoded as -1 - id) owns each floor cell.
var cells := {}
var entrance_room := 0
var boss_room := -1
var reward_room := -1
var problems := PackedStringArray()


func is_valid() -> bool:
	return problems.is_empty()


func cell_size() -> float:
	return recipe.cell_size


static func corridor_owner(corridor_id: int) -> int:
	return -1 - corridor_id


func room_of(kind: String) -> Room:
	for r in rooms:
		if r.kind == kind:
			return r
	return null


func count_kind(kind: String) -> int:
	var n := 0
	for r in rooms:
		if r.kind == kind:
			n += 1
	return n


func door_between(p: Vector2i, q: Vector2i) -> Door:
	for d in doors:
		if d.connects(p, q):
			return d
	return null


## Local position (x, z) of a cell's centre.
func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * recipe.cell_size


func room_center(room: Room) -> Vector2:
	return room.center_cell() * recipe.cell_size


## Where the player appears: the middle of the entrance room, facing the way in.
func entrance_position() -> Vector3:
	var c := room_center(rooms[entrance_room])
	return Vector3(c.x, 0.0, c.y)


func exit_position() -> Vector3:
	var c := room_center(rooms[reward_room])
	return Vector3(c.x, 0.0, c.y)


func bounds() -> Rect2i:
	var box := Rect2i()
	var first := true
	for cell in cells:
		if first:
			box = Rect2i(cell, Vector2i.ONE)
			first = false
		else:
			box = box.expand(cell).expand(cell + Vector2i.ONE)
	return box


func total_budget() -> float:
	var total := 0.0
	for e in encounters:
		total += e.budget
	return total


## Room ids on the shortest door path from the entrance to `target`, ignoring locks.
func route_to(target: int) -> PackedInt32Array:
	var links := room_links()
	var previous := {entrance_room: -1}
	var queue: Array[int] = [entrance_room]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		if r == target:
			break
		for n in links.get(r, []):
			if not previous.has(n):
				previous[n] = r
				queue.append(n)
	var route := PackedInt32Array()
	if not previous.has(target):
		return route
	var at := target
	while at != -1:
		route.insert(0, at)
		at = previous[at]
	return route


## Room adjacency through corridors: {room id: [room ids]}.
func room_links() -> Dictionary:
	var links := {}
	for c in corridors:
		links.get_or_add(c.from_room, []).append(c.to_room)
		links.get_or_add(c.to_room, []).append(c.from_room)
	return links


## Stable summary of the layout, used to check that a seed always gives the same dungeon.
func fingerprint() -> int:
	var parts := PackedStringArray()
	for r in rooms:
		parts.append("%s/%s@%d,%d,%d,%d|%d|%d|%.1f" % [r.kind, r.template, r.rect.position.x, r.rect.position.y, r.rect.size.x, r.rect.size.y, r.lock_id, r.key_id, r.budget])
	for c in corridors:
		parts.append("c%d-%d:%s" % [c.from_room, c.to_room, str(c.cells)])
	for e in encounters:
		parts.append("e%d:%d:%.1f" % [e.room, e.seed_value, e.budget])
	for ch in chests:
		parts.append("t%d@%.2f,%.2f:%d" % [ch.room, ch.position.x, ch.position.y, ch.seed_value])
	for p in props:
		parts.append("%s@%.2f,%.2f" % [p.kind, p.position.x, p.position.y])
	return hash(";".join(parts))


func summary() -> String:
	var counts := {}
	for r in rooms:
		counts[r.kind] = counts.get(r.kind, 0) + 1
	var kinds := PackedStringArray()
	for kind in counts:
		kinds.append("%d %s" % [counts[kind], kind])
	return "%d rooms (%s), %d lock%s, %d encounters (%.0f threat), %d chests, route %d rooms" % [
		rooms.size(), ", ".join(kinds), recipe.locks, "" if recipe.locks == 1 else "s", encounters.size(), total_budget(), chests.size(),
		route_to(reward_room).size() if reward_room >= 0 else 0]
