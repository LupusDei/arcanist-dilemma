class_name FeedbackCrosshair
extends Control
## Where spells go: a dot and four ticks at the screen center. GameFeedback
## tints it (red over an enemy, gold over something magic can touch) and
## calls hit_marker() when a spell lands, which flicks the ticks outward.

var tint := Color(0.96, 0.92, 0.82):
	set(value):
		if value != tint:
			tint = value
			queue_redraw()

var _hit := 0.0
var _hit_crit := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit_marker(crit := false) -> void:
	_hit = 1.0
	_hit_crit = crit
	queue_redraw()


func _process(delta: float) -> void:
	if _hit > 0.0:
		_hit = maxf(_hit - delta * 6.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var shadow := Color(0, 0, 0, 0.6)
	var gap := 6.0 + 5.0 * _hit
	var length := 7.0
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a: Vector2 = dir * gap
		var b: Vector2 = dir * (gap + length)
		draw_line(a, b, shadow, 4.0, true)
		draw_line(a, b, tint, 2.0, true)
	draw_circle(Vector2.ZERO, 2.6, shadow)
	draw_circle(Vector2.ZERO, 1.6, tint)
	if _hit > 0.0:
		var color := Color(1.0, 0.85, 0.4, _hit) if _hit_crit else Color(1, 1, 1, _hit)
		var r := 10.0 + 6.0 * (1.0 - _hit)
		for dir in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var d: Vector2 = dir.normalized()
			draw_line(d * r, d * (r + 7.0), color, 2.5, true)
