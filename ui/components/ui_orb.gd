@tool
class_name UiOrb
extends Control
## A Diablo-style glass orb that fills from the bottom. Used for health and
## for the path resource. With [member overfill] (sorcerer strain past
## capacity) the rim pulses red.

@export var fill_color := Color(0.8, 0.1, 0.12):
	set(v):
		fill_color = v
		queue_redraw()
## 0 to 1. The drawn level eases toward it.
@export_range(0.0, 1.0) var ratio := 1.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		set_process(true)
@export var overfill := false:
	set(v):
		overfill = v
		set_process(true)

var shown_ratio := 1.0
var _pulse := 0.0


func _ready() -> void:
	shown_ratio = ratio


func _process(delta: float) -> void:
	shown_ratio = move_toward(shown_ratio, ratio, maxf(delta * 1.5, absf(ratio - shown_ratio) * delta * 6.0))
	if overfill:
		_pulse = fmod(_pulse + delta * 4.0, TAU)
	queue_redraw()
	if is_equal_approx(shown_ratio, ratio) and not overfill:
		set_process(false)


func snap() -> void:
	shown_ratio = ratio
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var rim := UiTheme.GOLD.darkened(0.15)
	if overfill:
		rim = rim.lerp(Color(1, 0.15, 0.1), 0.5 + 0.5 * sin(_pulse))
	draw_circle(c, r + 4.0, Color(0, 0, 0, 0.6))
	draw_circle(c, r + 3.0, rim)
	draw_circle(c, r, Color(0.035, 0.03, 0.045))
	if shown_ratio > 0.005:
		var poly := segment(c, r, shown_ratio)
		draw_colored_polygon(poly, fill_color)
		# A lighter band along the surface reads as liquid.
		var line := segment(c, r, shown_ratio)
		if shown_ratio < 0.995 and line.size() > 1:
			draw_line(line[0], line[line.size() - 1], fill_color.lightened(0.35), 2.0)
	# Glass highlight and shade.
	draw_circle(c + Vector2(-r * 0.32, -r * 0.38), r * 0.26, Color(1, 1, 1, 0.13))
	draw_circle(c + Vector2(-r * 0.4, -r * 0.46), r * 0.09, Color(1, 1, 1, 0.22))
	draw_arc(c, r, 0.0, TAU, 72, Color(0, 0, 0, 0.7), 2.0, true)


## Polygon of the part of a circle (centre [param c], radius [param r]) below
## a water line at [param fill] (0 empty, 1 full). Y points down.
static func segment(c: Vector2, r: float, fill: float) -> PackedVector2Array:
	var h := r - 2.0 * r * clampf(fill, 0.0, 1.0)
	var a := asin(clampf(h / r, -1.0, 1.0))
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var t := lerpf(a, PI - a, float(i) / steps)
		pts.append(c + Vector2(cos(t), sin(t)) * r)
	return pts
