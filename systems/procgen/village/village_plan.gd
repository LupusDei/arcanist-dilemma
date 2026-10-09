class_name VillagePlan
extends RefCounted
## A village as pure data: roads, buildings and props with positions on the XZ
## plane. Planning produces this, validation checks it and building turns it
## into nodes, so plans can be generated and checked headlessly by the thousand.


class Building:
	var kind := "house"
	var position := Vector2.ZERO
	## Same convention as Node3D.rotation.y. The front door faces local +Z.
	var yaw := 0.0
	## Width (local X), wall height per floor, depth (local Z).
	var size := Vector3(6, 2.8, 7)
	var floors := 1
	var ground := 0.0
	## Farms: a fenced field behind the house, in the building's local space.
	var field_size := Vector2.ZERO
	var field_offset := 0.0
	var field_ground := 0.0
	# Story state, filled after the layout is fixed.
	var lift := 0.0
	var tilt := Vector2.ZERO
	var roof_damage := 0.0
	var scorched := false

	func footprint(padding := 0.0) -> PackedVector2Array:
		return GenGeometry.rect_corners(position, Vector2(size.x, size.z) * 0.5 + Vector2.ONE * padding, yaw)

	func field_center() -> Vector2:
		var back := Vector2(sin(yaw), cos(yaw)) * field_offset
		return position + back

	func field_footprint(padding := 0.0) -> PackedVector2Array:
		return GenGeometry.rect_corners(field_center(), field_size * 0.5 + Vector2.ONE * padding, yaw)

	func has_field() -> bool:
		return field_size != Vector2.ZERO


class Prop:
	var kind := "crate"
	var position := Vector2.ZERO
	var yaw := 0.0
	var radius := 0.5
	var ground := 0.0
	var lift := 0.0


var recipe: VillageRecipe
var seed_value := 0
## Seed of the attempt that produced this layout (differs from seed_value after a retry).
var layout_seed := 0
var attempts := 1
var center := Vector2.ZERO
## First road is the main road, which points toward the village entrance.
var roads: Array[PackedVector2Array] = []
var main_direction := Vector2.UP
## Open space at the centre kept free of buildings (village green or square).
var green_radius := 0.0
var buildings: Array[Building] = []
var props: Array[Prop] = []
var faction := "none"
var problems := PackedStringArray()


func is_valid() -> bool:
	return problems.is_empty()


func has_kind(kind: String) -> bool:
	for b in buildings:
		if b.kind == kind:
			return true
	for p in props:
		if p.kind == kind:
			return true
	return false


func count_kinds(kinds: Array) -> int:
	var count := 0
	for b in buildings:
		if b.kind in kinds:
			count += 1
	return count


func first_of(kind: String) -> Building:
	for b in buildings:
		if b.kind == kind:
			return b
	return null


## Stable summary of the layout, used to check that a seed always gives the same village.
func fingerprint() -> int:
	var parts := PackedStringArray()
	for road in roads:
		for point in road:
			parts.append("%.2f,%.2f" % [point.x, point.y])
	for b in buildings:
		parts.append("%s@%.2f,%.2f,%.3f|%.2f,%.2f,%.2f|%.2f" % [b.kind, b.position.x, b.position.y, b.yaw, b.size.x, b.size.y, b.size.z, b.lift])
	for p in props:
		parts.append("%s@%.2f,%.2f" % [p.kind, p.position.x, p.position.y])
	return hash(";".join(parts))


func summary() -> String:
	var counts := {}
	for b in buildings:
		counts[b.kind] = counts.get(b.kind, 0) + 1
	var kinds := PackedStringArray()
	for kind in counts:
		kinds.append("%d %s" % [counts[kind], kind])
	return "%d buildings (%s), %d props, %d roads" % [buildings.size(), ", ".join(kinds), props.size(), roads.size()]
