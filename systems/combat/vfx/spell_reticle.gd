class_name SpellReticle
extends Control
## The aiming reticle for the player's spells: an arcane crosshair whose outer
## ring fills while charging, with hit markers (white), crit markers (gold)
## and a kill burst. Hidden when the mouse is free.

var accent := Color(0.45, 0.85, 1.0)
var rim := Color(0.75, 0.45, 1.0)
## 0 to 1 while charging.
var charge := 0.0
var charging := false
## Show even when the mouse isn't captured (sandbox, recordings).
var force_visible := false

var _hit_time := -10.0
var _hit_crit := false
var _kill_time := -10.0
var _fire_time := -10.0
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_hit(crit: bool, killed: bool) -> void:
	_hit_time = _clock
	_hit_crit = crit
	if killed:
		_kill_time = _clock


func show_fire() -> void:
	_fire_time = _clock


func _process(delta: float) -> void:
	_clock += delta
	visible = force_visible or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var shadow := Color(0, 0, 0, 0.45)
	var kick := maxf(1.0 - (_clock - _fire_time) / 0.15, 0.0)
	var spread := 9.0 + 7.0 * kick - 4.0 * charge

	# Center dot.
	draw_circle(c, 2.6, shadow)
	draw_circle(c, 1.8, Color(1, 1, 1, 0.95))

	# Four rune ticks pointing in.
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5 + PI * 0.25 * charge)
		var a := c + dir * spread
		var b := c + dir * (spread + 7.0)
		draw_line(a, b, shadow, 4.0, true)
		draw_line(a, b, accent.lerp(Color.WHITE, 0.5), 2.0, true)

	# Charge ring with a bright head.
	var radius := 22.0
	draw_arc(c, radius, 0, TAU, 48, Color(1, 1, 1, 0.12 if charging else 0.06), 2.0, true)
	if charging and charge > 0.0:
		var start := -PI * 0.5
		var end := start + TAU * charge
		var col := accent.lerp(rim, charge) if charge < 1.0 else Color(1.0, 0.95, 0.7)
		draw_arc(c, radius, start, end, 48, shadow, 5.0, true)
		draw_arc(c, radius, start, end, 48, col, 3.0, true)
		draw_circle(c + Vector2.RIGHT.rotated(end) * radius, 3.5, Color.WHITE)
		if charge >= 1.0:
			var pulse := 0.5 + 0.5 * sin(_clock * 16.0)
			draw_arc(c, radius + 5.0 + pulse * 3.0, 0, TAU, 48, Color(col, 0.6 * pulse), 2.0, true)

	# Hit marker: four slashes flying outward.
	var since_hit := _clock - _hit_time
	if since_hit < 0.28:
		var t := since_hit / 0.28
		var hit_col := Color(1.0, 0.82, 0.25) if _hit_crit else Color.WHITE
		hit_col.a = 1.0 - t
		var inner := 10.0 + 10.0 * t
		var length := 9.0 if not _hit_crit else 13.0
		for i in 4:
			var dir := Vector2.RIGHT.rotated(PI * 0.25 + i * PI * 0.5)
			draw_line(c + dir * inner, c + dir * (inner + length), Color(0, 0, 0, hit_col.a * 0.6), 5.0, true)
			draw_line(c + dir * inner, c + dir * (inner + length), hit_col, 2.5, true)

	# Kill: a ring bursting outward.
	var since_kill := _clock - _kill_time
	if since_kill < 0.45:
		var t := since_kill / 0.45
		draw_arc(c, 18.0 + 40.0 * ease(t, 0.4), 0, TAU, 64, Color(rim.lerp(Color.WHITE, 0.4), 1.0 - t), 3.0, true)
