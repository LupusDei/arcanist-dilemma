class_name SpellReticle
extends Control
## The aiming reticle for the player's spells: an arcane crosshair whose outer
## ring fills while charging, with hit markers (white), crit markers (gold)
## and a kill burst. Hidden when the mouse is free. Sized for a 720p-tall
## screen and scaled up with taller ones.

var accent := Color(0.45, 0.85, 1.0)
var rim := Color(0.75, 0.45, 1.0)
## 0 to 1 while charging.
var charge := 0.0
var charging := false
## Show even when the mouse isn't captured (sandbox, recordings).
var force_visible := false
## Colour of what the reticle is over (red enemy, gold prop); transparent for nothing.
var target_tint := Color.TRANSPARENT

var _hit_time := -10.0
var _hit_crit := false
var _kill_time := -10.0
var _fire_time := -10.0
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors alone leave a Control 0x0 under a CanvasLayer; offsets fill the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	var k := maxf(size.y / 720.0, 1.0)
	var shadow := Color(0, 0, 0, 0.55)
	var kick := maxf(1.0 - (_clock - _fire_time) / 0.15, 0.0)
	var on_target := target_tint.a > 0.0
	var ink := Color(target_tint, 1.0) if on_target else Color(1, 1, 1, 0.95)
	var spread := (16.0 + 10.0 * kick - 6.0 * charge - (4.0 if on_target else 0.0)) * k

	# Center dot with a dark outline so it reads on grass and sky alike.
	draw_circle(c, 4.5 * k, shadow)
	draw_circle(c, (3.5 if on_target else 3.0) * k, ink)

	# Four rune ticks pointing in; they close in over a target.
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5 + PI * 0.25 * charge)
		var a := c + dir * spread
		var b := c + dir * (spread + 13.0 * k)
		draw_line(a, b, shadow, 6.0 * k, true)
		draw_line(a, b, ink if on_target else accent.lerp(Color.WHITE, 0.6), 3.0 * k, true)

	# Outer ring: faint at rest, solid in the target's colour when on one.
	var radius := 40.0 * k
	draw_arc(c, radius, 0, TAU, 64, shadow if on_target else Color(0, 0, 0, 0.25), 4.0 * k, true)
	draw_arc(c, radius, 0, TAU, 64, Color(target_tint, 0.9) if on_target else Color(1, 1, 1, 0.3 if charging else 0.22), 2.0 * k, true)

	# Charge ring with a bright head.
	if charging and charge > 0.0:
		var start := -PI * 0.5
		var end := start + TAU * charge
		var col := accent.lerp(rim, charge) if charge < 1.0 else Color(1.0, 0.95, 0.7)
		draw_arc(c, radius, start, end, 64, shadow, 7.0 * k, true)
		draw_arc(c, radius, start, end, 64, col, 4.5 * k, true)
		draw_circle(c + Vector2.RIGHT.rotated(end) * radius, 5.0 * k, Color.WHITE)
		if charge >= 1.0:
			var pulse := 0.5 + 0.5 * sin(_clock * 16.0)
			draw_arc(c, radius + (6.0 + pulse * 4.0) * k, 0, TAU, 64, Color(col, 0.6 * pulse), 2.5 * k, true)

	# Hit marker: four slashes flying outward.
	var since_hit := _clock - _hit_time
	if since_hit < 0.3:
		var t := since_hit / 0.3
		var hit_col := Color(1.0, 0.82, 0.25) if _hit_crit else Color.WHITE
		hit_col.a = 1.0 - t
		var inner := (14.0 + 14.0 * t) * k
		var length := (14.0 if not _hit_crit else 19.0) * k
		for i in 4:
			var dir := Vector2.RIGHT.rotated(PI * 0.25 + i * PI * 0.5)
			draw_line(c + dir * inner, c + dir * (inner + length), Color(0, 0, 0, hit_col.a * 0.6), 7.0 * k, true)
			draw_line(c + dir * inner, c + dir * (inner + length), hit_col, 3.5 * k, true)

	# Kill: a ring bursting outward.
	var since_kill := _clock - _kill_time
	if since_kill < 0.45:
		var t := since_kill / 0.45
		draw_arc(c, (26.0 + 56.0 * ease(t, 0.4)) * k, 0, TAU, 64, Color(rim.lerp(Color.WHITE, 0.4), 1.0 - t), 4.0 * k, true)
