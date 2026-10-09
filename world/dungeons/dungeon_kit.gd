class_name DungeonKit
extends RefCounted
## Turns a DungeonPlan's grid into chunky, slightly irregular low-poly
## geometry: flagstone floors, walls of stacked stone blocks, posts at every
## corner and door, lintels over doorways, and the props of each room. Theme
## and palette come from the recipe. All pieces go into one DungeonMeshBatch,
## and collision boxes are collected in `shapes` as [Shape3D, Transform3D].

const WALL_THICKNESS := 0.7
const FLOOR_THICKNESS := 0.5

var shapes: Array = []
## Light sources found while building: [position: Vector3, color: Color, range: float, energy: float].
var lights: Array = []
var batch := DungeonMeshBatch.new()

var _plan: DungeonPlan
var _recipe: DungeonRecipe
var _rng: RandomNumberGenerator
var _cs := 4.0
var _h := 3.4


func _init(plan: DungeonPlan) -> void:
	_plan = plan
	_recipe = plan.recipe
	_cs = _recipe.cell_size
	_h = _recipe.wall_height
	_rng = GenRng.stream(plan.layout_seed, "kit")
	batch.add_material("stone", DungeonMeshBatch.opaque())
	batch.add_material("wood", DungeonMeshBatch.opaque(0.85))
	batch.add_material("metal", DungeonMeshBatch.opaque(0.4))
	batch.add_material("accent", DungeonMeshBatch.glow(_recipe.accent_color, 2.5))
	batch.add_material("flame", DungeonMeshBatch.glow(Color(1.0, 0.62, 0.25), 4.0))
	batch.add_material("candle", DungeonMeshBatch.glow(Color(1.0, 0.85, 0.55), 3.0))
	var water := StandardMaterial3D.new()
	water.albedo_color = _recipe.water_color
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic_specular = 0.8
	batch.add_material("water", water)


func build(parent: Node3D) -> void:
	_floors()
	_walls()
	for prop in _plan.props:
		_prop(prop)
	batch.commit(parent)


# --- floors --------------------------------------------------------------------

func _floors() -> void:
	var base := _recipe.floor_color
	for cell in _plan.cells:
		var at := _plan.cell_center(cell)
		# Two by two flagstones per cell, each a little different.
		for i in 4:
			var offset := Vector2((i % 2) - 0.5, (i / 2) - 0.5) * _cs * 0.5
			var size := _cs * 0.5 - 0.08
			var lift := _rng.randf_range(-0.02, 0.04)
			var tint := _jitter(base, 0.07)
			batch.box("stone", Vector3(size, 0.2, size), _at(at + offset, -0.1 + lift, _rng.randf_range(-0.03, 0.03)), tint, false)
		# The dark grout under the stones.
		batch.box("stone", Vector3(_cs, 0.2, _cs), _at(at, -0.15), base.darkened(0.5), false)
	# Collision: one slab per room and per corridor.
	for r in _plan.rooms:
		var rect := Rect2(Vector2(r.rect.position) * _cs, Vector2(r.rect.size) * _cs)
		_shape(Vector3(rect.size.x, FLOOR_THICKNESS, rect.size.y), Vector3(rect.get_center().x, -FLOOR_THICKNESS * 0.5, rect.get_center().y))
	for c in _plan.corridors:
		for cell in c.cells:
			var at := _plan.cell_center(cell)
			_shape(Vector3(_cs, FLOOR_THICKNESS, _cs), Vector3(at.x, -FLOOR_THICKNESS * 0.5, at.y))


# --- walls ---------------------------------------------------------------------

## Every cell edge between a floor cell and something it doesn't connect to
## (rock, or another room or corridor with no door) gets a wall.
func _walls() -> void:
	var edges := {}
	for cell in _plan.cells:
		var owner = _plan.cells[cell]
		for step in DungeonPlanner.DIRECTIONS:
			var next: Vector2i = cell + step
			if _plan.cells.get(next, null) == owner:
				continue
			if _plan.cells.has(next) and _plan.door_between(cell, next) != null:
				continue
			# Edge from corner a to corner b of this cell, along the shared side.
			var a: Vector2i
			var b: Vector2i
			match step:
				Vector2i(1, 0):
					a = cell + Vector2i(1, 0)
					b = cell + Vector2i(1, 1)
				Vector2i(-1, 0):
					a = cell
					b = cell + Vector2i(0, 1)
				Vector2i(0, 1):
					a = cell + Vector2i(0, 1)
					b = cell + Vector2i(1, 1)
				_:
					a = cell
					b = cell + Vector2i(1, 0)
			edges["%d,%d,%d,%d" % [a.x, a.y, b.x, b.y]] = [a, b]
	var corner_count := {}
	var corner_dirs := {}
	for key in edges:
		var e: Array = edges[key]
		_wall_segment(e[0], e[1])
		for v in e:
			corner_count[v] = corner_count.get(v, 0) + 1
			corner_dirs[v] = corner_dirs.get(v, 0) | (1 if e[0].x != e[1].x else 2)
	# Posts where walls turn, end at a doorway, or meet.
	for v in corner_count:
		if corner_count[v] != 2 or corner_dirs[v] == 3:
			_post(Vector2(v) * _cs)
	for d in _plan.doors:
		_lintel(d)


func _wall_segment(a: Vector2i, b: Vector2i) -> void:
	var from := Vector2(a) * _cs
	var to := Vector2(b) * _cs
	var mid := (from + to) * 0.5
	var along_x := a.y == b.y
	var yaw := 0.0 if along_x else PI * 0.5
	var base := _recipe.wall_color
	var rough := 0.18 if _recipe.style == DungeonRecipe.Style.MINE else 0.06
	var courses := 3
	var course_h := _h / courses
	for row in courses:
		# Running bond: alternate rows start half a block over.
		var blocks := 2 if row % 2 == 0 else 3
		var x := -_cs * 0.5
		var widths: Array[float] = []
		var total := 0.0
		for i in blocks:
			var w := _rng.randf_range(0.7, 1.3) * (0.5 if row % 2 == 1 and (i == 0 or i == blocks - 1) else 1.0)
			widths.append(w)
			total += w
		for i in blocks:
			var w := widths[i] / total * _cs
			var depth := WALL_THICKNESS + _rng.randf_range(-rough, rough)
			var size := Vector3(w - 0.05, course_h - 0.04, depth)
			var local := Vector3(x + w * 0.5, course_h * (row + 0.5), _rng.randf_range(-rough, rough) * 0.5)
			var xform := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0, mid.y)) * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.02, 0.02)), local)
			batch.box("stone", size, xform, _jitter(base, 0.08), false)
			x += w
	# A dark core so gaps between blocks never show through, and a cap on top.
	batch.box("stone", Vector3(_cs, _h - 0.1, WALL_THICKNESS - 0.15), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _h * 0.5 - 0.05, mid.y)), base.darkened(0.55), false)
	batch.box("stone", Vector3(_cs, 0.2, WALL_THICKNESS + 0.12), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _h + 0.08, mid.y)), _jitter(_recipe.trim_color.lightened(0.15), 0.04), false)
	_shape(Vector3(_cs if along_x else WALL_THICKNESS, _h + 1.0, WALL_THICKNESS if along_x else _cs), Vector3(mid.x, (_h + 1.0) * 0.5, mid.y))
	# Chapel walls get the odd glowing window.
	if _recipe.style == DungeonRecipe.Style.CHAPEL and _rng.randf() < 0.18:
		batch.box("accent", Vector3(0.7, 1.5, WALL_THICKNESS + 0.04), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _h * 0.55, mid.y)))
		batch.prism("accent", 0.5, 0.0, 0.5, 4, Transform3D(Basis(Vector3.UP, yaw + PI * 0.25).scaled(Vector3(1, 1, 0.3)), Vector3(mid.x, _h * 0.55 + 1.0, mid.y)))


func _post(at: Vector2) -> void:
	var size := WALL_THICKNESS + 0.35
	var top := _h + 0.35
	var tint := _jitter(_recipe.trim_color, 0.05)
	if _recipe.style == DungeonRecipe.Style.MINE:
		batch.box("wood", Vector3(size * 0.8, top, size * 0.8), _at(at, top * 0.5, _rng.randf_range(-0.1, 0.1)), _jitter(_recipe.wood_color, 0.06))
		return
	batch.box("stone", Vector3(size, top, size), _at(at, top * 0.5), tint)
	batch.box("stone", Vector3(size + 0.2, 0.3, size + 0.2), _at(at, top + 0.15), tint.lightened(0.1))
	batch.box("stone", Vector3(size + 0.15, 0.35, size + 0.15), _at(at, 0.17), tint.darkened(0.1))


func _lintel(d: DungeonPlan.Door) -> void:
	var a := _plan.cell_center(d.a)
	var b := _plan.cell_center(d.b)
	var mid := (a + b) * 0.5
	var along_x := d.a.y == d.b.y
	var yaw := PI * 0.5 if along_x else 0.0
	var color := _recipe.wood_color if _recipe.style == DungeonRecipe.Style.MINE else _recipe.trim_color
	var material := "wood" if _recipe.style == DungeonRecipe.Style.MINE else "stone"
	batch.box(material, Vector3(_cs + 0.6, 0.55, WALL_THICKNESS + 0.3), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _h + 0.05, mid.y)), color)
	if d.lock_id >= 0:
		# A keystone in the key's colour marks a locked door from afar.
		batch.box("accent", Vector3(0.5, 0.5, WALL_THICKNESS + 0.4), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _h + 0.1, mid.y)))


# --- props ---------------------------------------------------------------------

func _prop(p: DungeonPlan.Prop) -> void:
	var at := p.position
	var s := p.scale
	match p.kind:
		"pillar":
			var tint := _jitter(_recipe.wall_color, 0.05)
			batch.box("stone", Vector3(1.3, 0.4, 1.3), _at(at, 0.2), tint.darkened(0.1))
			batch.prism("stone", 0.5, 0.45, _h * s, 8, _at(at, _h * s * 0.5, p.yaw), tint)
			batch.box("stone", Vector3(1.2, 0.35, 1.2), _at(at, _h * s), tint.lightened(0.08))
			_solid(p, Vector3(1.1, _h, 1.1))
		"sarcophagus":
			var tint := _jitter(_recipe.wall_color.lightened(0.1), 0.05)
			batch.box("stone", Vector3(1.1, 0.8, 2.2), _at(at, 0.4, p.yaw), tint)
			batch.box("stone", Vector3(1.25, 0.25, 2.35), _at(at, 0.92, p.yaw + _rng.randf_range(-0.12, 0.12)), tint.lightened(0.08))
			batch.box("stone", Vector3(0.5, 0.18, 0.5), _at(at + Vector2(0, -0.6).rotated(-p.yaw), 1.12, p.yaw), tint.lightened(0.15))
			_solid(p, Vector3(1.2, 1.1, 2.3))
		"bones":
			var bone := Color(0.9, 0.86, 0.74)
			for i in 4:
				batch.box("stone", Vector3(0.08, 0.08, 0.5) * s, _at(at + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)), 0.05, _rng.randf() * TAU), bone)
			batch.prism("stone", 0.13 * s, 0.11 * s, 0.22 * s, 6, _at(at, 0.1, p.yaw), bone)
		"pew":
			var wood := _jitter(_recipe.wood_color, 0.05)
			batch.box("wood", Vector3(s, 0.12, 0.5), _at(at, 0.5, p.yaw), wood)
			batch.box("wood", Vector3(s, 0.7, 0.1), _at(at + Vector2(0, -0.25), 0.85, p.yaw + _rng.randf_range(-0.05, 0.05)), wood.darkened(0.1))
			for side in [-0.5, 0.5]:
				batch.box("wood", Vector3(0.1, 0.5, 0.45), _at(at + Vector2(side * (s - 0.1), 0), 0.25, p.yaw), wood.darkened(0.2))
			_solid(p, Vector3(s, 1.1, 0.6))
		"altar":
			batch.box("stone", Vector3(2.0, 1.0, 1.0), _at(at, 0.5, p.yaw), _jitter(_recipe.wall_color.lightened(0.15), 0.03))
			batch.box("wood", Vector3(2.1, 0.08, 0.5), _at(at, 1.04, p.yaw), Color(0.55, 0.15, 0.15))
			_candles(at + Vector2(0.7, 0), 1.08, 3)
			_candles(at + Vector2(-0.7, 0), 1.08, 3)
			_solid(p, Vector3(2.0, 1.1, 1.0))
		"statue":
			# A robed figure in a pointed hat, as in the Greycloak statues.
			var grey := Color(0.62, 0.62, 0.64)
			batch.box("stone", Vector3(1.4, 0.8, 1.4), _at(at, 0.4, p.yaw), _recipe.trim_color)
			batch.prism("stone", 0.6, 0.3, 1.9, 7, _at(at, 1.75, p.yaw), grey)
			batch.prism("stone", 0.26, 0.24, 0.4, 7, _at(at, 2.9, p.yaw), grey.lightened(0.1))
			batch.prism("stone", 0.55, 0.55, 0.06, 10, _at(at, 3.1, p.yaw), grey.darkened(0.1))
			batch.prism("stone", 0.32, 0.0, 0.9, 7, _at(at, 3.55, p.yaw), grey.darkened(0.1))
			batch.prism("wood", 0.05, 0.05, 2.8, 5, _at(at + Vector2(0.55, 0.1).rotated(-p.yaw), 2.0), _recipe.wood_color)
			_solid(p, Vector3(1.4, 3.0, 1.4))
		"candles":
			_candles(at, 0.0, 5)
			_light(at, 0.6, _recipe.light_color, 7.0, 0.8)
		"dais":
			var tint := _recipe.trim_color
			batch.prism("stone", s * 1.15, s * 1.15, 0.25, 8, _at(at, 0.12, PI / 8), tint)
			batch.prism("stone", s * 0.85, s * 0.85, 0.25, 8, _at(at, 0.37, PI / 8), tint.lightened(0.08))
			batch.prism("accent", s * 0.3, s * 0.3, 0.04, 8, _at(at, 0.51, PI / 8))
			_shape(Vector3(s * 1.7, 0.5, s * 1.7), Vector3(at.x, 0.25, at.y))
		"brazier":
			var metal := Color(0.25, 0.22, 0.2)
			batch.prism("metal", 0.12, 0.12, 1.0, 6, _at(at, 0.5), metal)
			batch.prism("metal", 0.3, 0.55, 0.35, 8, _at(at, 1.15), metal)
			batch.prism("flame", 0.4, 0.0, 0.6, 6, _at(at, 1.55, _rng.randf() * TAU))
			_light(at, 2.0, _recipe.light_color, _room_light_range(p), 1.8)
			_solid(p, Vector3(0.8, 1.3, 0.8))
		"lantern":
			# Hangs from a chain over the middle of the room.
			var metal := Color(0.22, 0.2, 0.18)
			batch.box("metal", Vector3(0.04, _h * 0.5, 0.04), _at(at, _h * 0.75 + 0.6), metal)
			batch.box("metal", Vector3(0.45, 0.55, 0.45), _at(at, _h * 0.5 + 0.35, 0.3), metal)
			batch.box("candle", Vector3(0.32, 0.42, 0.32), _at(at, _h * 0.5 + 0.35, 0.3))
			_light(at, _h * 0.5, _recipe.light_color, _room_light_range(p), 1.6)
		"water":
			var room := _plan.rooms[p.room]
			var rect := Rect2(Vector2(room.rect.position) * _cs, Vector2(room.rect.size) * _cs)
			batch.box("water", Vector3(rect.size.x, 0.05, rect.size.y), _at(rect.get_center(), 0.22))
			for i in 6:
				var reed := Vector2(_rng.randf_range(rect.position.x + 0.5, rect.end.x - 0.5), _rng.randf_range(rect.position.y + 0.5, rect.end.y - 0.5))
				batch.prism("wood", 0.03, 0.0, _rng.randf_range(0.5, 1.0), 4, _at(reed, 0.4, 0.0), Color(0.3, 0.45, 0.2))
		"rubble":
			for i in 4:
				var size := Vector3(_rng.randf_range(0.25, 0.6), _rng.randf_range(0.2, 0.4), _rng.randf_range(0.25, 0.6)) * s
				var xform := Transform3D(Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))),
					Vector3(at.x + _rng.randf_range(-0.5, 0.5) * s, size.y * 0.4, at.y + _rng.randf_range(-0.5, 0.5) * s))
				batch.box("stone", size, xform, _jitter(_recipe.wall_color, 0.1))
		"crystal":
			for i in 3:
				var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4)))
				var height := _rng.randf_range(0.8, 1.6) * s
				batch.prism("accent", 0.2 * s, 0.0, height, 5, Transform3D(tilt, Vector3(at.x + _rng.randf_range(-0.3, 0.3), height * 0.4, at.y + _rng.randf_range(-0.3, 0.3))))
			batch.box("stone", Vector3(0.9, 0.3, 0.9) * s, _at(at, 0.1, p.yaw), _recipe.wall_color.darkened(0.2))
			_light(at, 1.2, _recipe.accent_color, 6.0, 0.9)
			_solid(p, Vector3(0.9, 1.5, 0.9))
		"timber":
			# Two props and a beam across the corridor.
			var wood := _jitter(_recipe.wood_color, 0.06)
			var side := Vector2(0, 1).rotated(-p.yaw) * (_cs * 0.5 - 0.35)
			for sgn in [-1.0, 1.0]:
				batch.box("wood", Vector3(0.3, _h, 0.3), _at(at + side * sgn, _h * 0.5, p.yaw), wood)
			batch.box("wood", Vector3(0.3, 0.3, _cs - 0.2), _at(at, _h - 0.15, p.yaw), wood.darkened(0.1))


func _candles(at: Vector2, y: float, count: int) -> void:
	for i in count:
		var spot := at + Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.25, 0.25))
		var height := _rng.randf_range(0.15, 0.45)
		batch.prism("stone", 0.05, 0.05, height, 6, _at(spot, y + height * 0.5), Color(0.95, 0.9, 0.78))
		batch.prism("candle", 0.04, 0.0, 0.1, 4, _at(spot, y + height + 0.05))


func _room_light_range(p: DungeonPlan.Prop) -> float:
	if p.room < 0:
		return 8.0
	var size := _plan.rooms[p.room].rect.size
	return clampf(maxf(size.x, size.y) * _cs * 0.75, 8.0, 18.0)


func _light(at: Vector2, y: float, color: Color, light_range: float, energy: float) -> void:
	lights.append([Vector3(at.x, y, at.y), color, light_range, energy])


func _solid(p: DungeonPlan.Prop, size: Vector3) -> void:
	shapes.append([_box_shape(size), Transform3D(Basis(Vector3.UP, p.yaw), Vector3(p.position.x, size.y * 0.5, p.position.y))])


func _shape(size: Vector3, at: Vector3) -> void:
	shapes.append([_box_shape(size), Transform3D(Basis.IDENTITY, at)])


static func _box_shape(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box


static func _at(at: Vector2, y: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y))


func _jitter(color: Color, amount: float) -> Color:
	var k := 1.0 + _rng.randf_range(-amount, amount)
	return Color(color.r * k, color.g * k, color.b * k * (1.0 + _rng.randf_range(-amount, amount) * 0.3))
