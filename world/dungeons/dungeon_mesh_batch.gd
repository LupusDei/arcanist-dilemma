class_name DungeonMeshBatch
extends RefCounted
## Collects many small low-poly pieces into one mesh per material, so a whole
## dungeon draws in a handful of calls. Pieces are flat-shaded and carry a
## vertex colour, which is how blocks of the same material get their slight
## cartoon colour variation.

class Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()


## key -> Surface
var _surfaces := {}
var _materials := {}


## Registers a material under `key`. Opaque materials should use vertex colour
## as albedo (see opaque()).
func add_material(key: String, material: Material) -> void:
	_materials[key] = material


static func opaque(roughness := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	return m


static func glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## `bottom` false skips the underside, for pieces that sit on the floor.
func box(key: String, size: Vector3, xform: Transform3D, color := Color.WHITE, bottom := true) -> void:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var st := _surface(key)
	for face in [[4, 5, 6, 7, Vector3.BACK], [1, 0, 3, 2, Vector3.FORWARD], [5, 1, 2, 6, Vector3.RIGHT],
			[0, 4, 7, 3, Vector3.LEFT], [7, 6, 2, 3, Vector3.UP], [0, 1, 5, 4, Vector3.DOWN]]:
		if not bottom and face[4] == Vector3.DOWN:
			continue
		_quad(st, xform * c[face[0]], xform * c[face[1]], xform * c[face[2]], xform * c[face[3]], xform.basis * face[4], color)


## A prism with `sides` faces: a cylinder, a cone (top 0), a bowl (top > bottom)
## or a gem. Origin at the middle of its height.
func prism(key: String, bottom: float, top: float, height: float, sides: int, xform: Transform3D, color := Color.WHITE, caps := true) -> void:
	var st := _surface(key)
	var y0 := -height * 0.5
	var y1 := height * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := xform * (d0 * bottom + Vector3(0, y0, 0))
		var p1 := xform * (d1 * bottom + Vector3(0, y0, 0))
		var p2 := xform * (d1 * top + Vector3(0, y1, 0))
		var p3 := xform * (d0 * top + Vector3(0, y1, 0))
		var mid := (d0 + d1).normalized()
		var normal := (xform.basis * (mid * height + Vector3(0, bottom - top, 0))).normalized()
		if top <= 0.001:
			_tri(st, p0, p1, p2, normal, color)
		else:
			_quad(st, p0, p1, p2, p3, normal, color)
		if caps:
			var up := (xform.basis * Vector3.UP).normalized()
			if top > 0.001:
				_tri(st, xform * Vector3(0, y1, 0), p3, p2, up, color)
			_tri(st, xform * Vector3(0, y0, 0), p1, p0, -up, color)


## Builds one MeshInstance3D per material with everything added so far.
func commit(parent: Node3D) -> void:
	for key in _surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var surface: Surface = _surfaces[key]
		arrays[Mesh.ARRAY_VERTEX] = surface.vertices
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_COLOR] = surface.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.name = key.capitalize().replace(" ", "")
		instance.mesh = mesh
		instance.material_override = _materials.get(key)
		if key == "water":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
	_surfaces.clear()


func _surface(key: String) -> Surface:
	if not _surfaces.has(key):
		_surfaces[key] = Surface.new()
	return _surfaces[key]


func _quad(st: Surface, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_tri(st, a, b, c, normal, color)
	_tri(st, a, c, d, normal, color)


## Godot draws clockwise triangles as front faces; flip the winding if needed
## so the face points along `normal`.
func _tri(st: Surface, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var n := normal.normalized()
	if (b - a).cross(c - a).dot(n) > 0.0:
		st.vertices.append_array([a, c, b])
	else:
		st.vertices.append_array([a, b, c])
	st.normals.append_array([n, n, n])
	st.colors.append_array([color, color, color])
