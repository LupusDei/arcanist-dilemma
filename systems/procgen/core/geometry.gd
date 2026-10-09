class_name GenGeometry
## 2D helpers shared by planners: oriented rectangles on the XZ plane.


## Corners of a rectangle centred on `center`, `half` extents, rotated by `yaw`
## (the same yaw a Node3D uses around +Y).
static func rect_corners(center: Vector2, half: Vector2, yaw: float) -> PackedVector2Array:
	var x_axis := Vector2(cos(yaw), -sin(yaw))
	var z_axis := Vector2(sin(yaw), cos(yaw))
	var corners := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + x_axis * half.x * s.x + z_axis * half.y * s.y)
	return corners


## Separating-axis test for two convex quads.
static func rects_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for quad in [a, b]:
		for i in 4:
			var edge: Vector2 = quad[(i + 1) % 4] - quad[i]
			var axis := Vector2(-edge.y, edge.x)
			var a_min := INF
			var a_max := -INF
			var b_min := INF
			var b_max := -INF
			for p in a:
				var d := axis.dot(p)
				a_min = minf(a_min, d)
				a_max = maxf(a_max, d)
			for p in b:
				var d := axis.dot(p)
				b_min = minf(b_min, d)
				b_max = maxf(b_max, d)
			if a_max < b_min or b_max < a_min:
				return false
	return true


static func distance_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best


## Distance from a rectangle (given by corners) to a polyline, 0 if they touch.
static func rect_distance_to_polyline(corners: PackedVector2Array, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		if Geometry2D.is_point_in_polygon(line[i], corners):
			return 0.0
		for c in 4:
			var a := corners[c]
			var b := corners[(c + 1) % 4]
			if Geometry2D.segment_intersects_segment(a, b, line[i], line[i + 1]) != null:
				return 0.0
			best = minf(best, a.distance_to(Geometry2D.get_closest_point_to_segment(a, line[i], line[i + 1])))
			var q: Vector2 = line[i]
			best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best
