@tool
class_name UiPortrait
extends Control
## A flat painted bust that previews the character-creation choices until the
## 3D player model can be shown here instead.

var character: Dictionary = UiCharacterPresets.default_character():
	set(v):
		character = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(300, 380)


func _pick(list: Array, key: String) -> Dictionary:
	var i := clampi(int(character.get(key, 0)), 0, list.size() - 1)
	return list[i]


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.08, 0.12))
	# Soft vignette glow behind the head.
	for i in 6:
		draw_circle(Vector2(w * 0.5, h * 0.4), w * (0.5 - i * 0.06), Color(0.35, 0.28, 0.5, 0.05 + i * 0.015))

	var girl := int(character.get("sex", 0)) == 1
	var face: Dictionary = _pick(UiCharacterPresets.FACES, "face")
	var skin: Color = _pick(UiCharacterPresets.SKINS, "skin").color
	var hair_color: Color = _pick(UiCharacterPresets.HAIR_COLORS, "hair_color").color
	var eyes: Color = _pick(UiCharacterPresets.EYES, "eyes").color
	var build: Dictionary = _pick(UiCharacterPresets.BUILDS, "build")
	var style := clampi(int(character.get("hair", 0)), 0, UiCharacterPresets.HAIR_STYLES.size() - 1)

	var head_c := Vector2(w * 0.5, h * 0.4)
	var head_r := Vector2(w * 0.2 * face.width, w * 0.25 * face.height)
	var robe := Color(0.28, 0.24, 0.4)

	# Long hair falls behind the shoulders.
	if style in [2, 3] or (girl and style != 5):
		var back := _ellipse(head_c + Vector2(0, head_r.y * 0.55), Vector2(head_r.x * 1.25, head_r.y * (1.45 if style == 2 or girl else 1.1)))
		draw_colored_polygon(back, hair_color.darkened(0.15))

	# Shoulders and robe.
	var sw: float = w * 0.36 * build.shoulders
	var neck_y := head_c.y + head_r.y * 0.85
	var shoulders := PackedVector2Array([
		Vector2(w * 0.5 - sw * 0.35, neck_y + 10),
		Vector2(w * 0.5 + sw * 0.35, neck_y + 10),
		Vector2(w * 0.5 + sw, h * 0.86),
		Vector2(w * 0.5 + sw * 1.05, h),
		Vector2(w * 0.5 - sw * 1.05, h),
		Vector2(w * 0.5 - sw, h * 0.86),
	])
	draw_colored_polygon(shoulders, robe)
	draw_rect(Rect2(w * 0.5 - head_r.x * 0.32, head_c.y + head_r.y * 0.5, head_r.x * 0.64, head_r.y * 0.6), skin.darkened(0.12))
	# Collar with gold trim.
	var collar := PackedVector2Array([
		Vector2(w * 0.5 - head_r.x * 0.6, neck_y + 6),
		Vector2(w * 0.5, neck_y + 48),
		Vector2(w * 0.5 + head_r.x * 0.6, neck_y + 6),
	])
	draw_polyline(collar, UiTheme.GOLD, 4.0, true)

	# Head, with a narrower jaw for heart faces and a broader one for square.
	var head := _ellipse(head_c, head_r)
	if face.jaw != 0.0:
		for i in head.size():
			var p := head[i]
			if p.y > head_c.y:
				var t := (p.y - head_c.y) / head_r.y
				p.x = head_c.x + (p.x - head_c.x) * (1.0 - face.jaw * t)
				head[i] = p
	draw_colored_polygon(head, skin)
	# Ears.
	draw_circle(head_c + Vector2(-head_r.x * 0.98, head_r.y * 0.08), head_r.x * 0.16, skin.darkened(0.06))
	draw_circle(head_c + Vector2(head_r.x * 0.98, head_r.y * 0.08), head_r.x * 0.16, skin.darkened(0.06))

	# Eyes, brows, nose, mouth.
	var eye_y := head_c.y + head_r.y * 0.02
	var eye_dx := head_r.x * 0.4
	for side in [-1.0, 1.0]:
		var ec := Vector2(head_c.x + side * eye_dx, eye_y)
		draw_colored_polygon(_ellipse(ec, Vector2(head_r.x * 0.2, head_r.y * 0.1)), Color(0.97, 0.95, 0.92))
		draw_circle(ec, head_r.y * 0.075, eyes)
		draw_circle(ec, head_r.y * 0.035, Color(0.05, 0.04, 0.05))
		draw_circle(ec + Vector2(-2, -2), head_r.y * 0.02, Color(1, 1, 1, 0.9))
		var brow := hair_color.darkened(0.1)
		draw_line(ec + Vector2(-head_r.x * 0.2, -head_r.y * 0.2), ec + Vector2(head_r.x * 0.2, -head_r.y * (0.24 if girl else 0.2)), brow, 4.0 if not girl else 3.0, true)
		if girl:
			draw_line(ec + Vector2(side * head_r.x * 0.18, -head_r.y * 0.04), ec + Vector2(side * head_r.x * 0.26, -head_r.y * 0.09), Color(0.05, 0.04, 0.05), 2.0, true)
	draw_line(head_c + Vector2(0, head_r.y * 0.12), head_c + Vector2(-head_r.x * 0.06, head_r.y * 0.36), skin.darkened(0.25), 2.5, true)
	draw_arc(head_c + Vector2(0, head_r.y * 0.38), head_r.x * 0.24, 0.35, PI - 0.35, 16, Color(0.55, 0.25, 0.25) if girl else skin.darkened(0.35), 3.0, true)
	if girl:
		draw_circle(head_c + Vector2(-head_r.x * 0.55, head_r.y * 0.3), head_r.x * 0.13, Color(0.95, 0.45, 0.45, 0.22))
		draw_circle(head_c + Vector2(head_r.x * 0.55, head_r.y * 0.3), head_r.x * 0.13, Color(0.95, 0.45, 0.45, 0.22))

	# Hair on top.
	if style != 5:
		var cap := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			var t := PI + PI * float(i) / steps
			cap.append(head_c + Vector2(cos(t) * head_r.x * 1.08, sin(t) * head_r.y * 1.08 - head_r.y * 0.05))
		var fringe_depth := head_r.y * (0.42 if style == 1 else 0.3)
		cap.append(head_c + Vector2(head_r.x * 1.0, -head_r.y * 0.05))
		cap.append(head_c + Vector2(head_r.x * 0.5, -head_r.y * 0.5 + fringe_depth))
		if style == 1:
			cap.append(head_c + Vector2(head_r.x * 0.2, -head_r.y * 0.45))
			cap.append(head_c + Vector2(-head_r.x * 0.05, -head_r.y * 0.5 + fringe_depth))
			cap.append(head_c + Vector2(-head_r.x * 0.35, -head_r.y * 0.42))
		cap.append(head_c + Vector2(-head_r.x * 0.65, -head_r.y * 0.5 + fringe_depth))
		cap.append(head_c + Vector2(-head_r.x * 1.0, -head_r.y * 0.05))
		draw_colored_polygon(cap, hair_color)
		if style == 4:
			draw_circle(head_c + Vector2(0, -head_r.y * 1.2), head_r.x * 0.32, hair_color)
		if style == 3:
			for i in 5:
				draw_circle(head_c + Vector2(head_r.x * 0.95, head_r.y * (0.3 + i * 0.32)), head_r.x * (0.2 - i * 0.015), hair_color.darkened(0.05 * (i % 2)))
		# A highlight sells the shape.
		draw_arc(head_c + Vector2(-head_r.x * 0.15, -head_r.y * 0.25), head_r.x * 0.7, PI * 1.15, PI * 1.5, 12, hair_color.lightened(0.25), 3.0, true)
	else:
		draw_arc(head_c, head_r.x * 1.0, PI * 1.08, PI * 1.92, 24, hair_color.lerp(skin, 0.6), 5.0, true)

	# Frame.
	draw_rect(Rect2(Vector2.ZERO, size).grow(-1), UiTheme.GOLD, false, 2.0)


static func _ellipse(c: Vector2, r: Vector2, steps := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var t := TAU * float(i) / steps
		pts.append(c + Vector2(cos(t) * r.x, sin(t) * r.y))
	return pts
