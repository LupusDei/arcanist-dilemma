@tool
class_name UiSpellSlot
extends Control
## One action bar slot: spell icon (or a placeholder glyph until there is art),
## key hint, a clockwise cooldown sweep and a flash when the spell goes off.

@export var key_hint := "1":
	set(v):
		key_hint = v
		queue_redraw()

var spell: Variant = null:
	set(v):
		spell = v
		tooltip_text = _tooltip()
		queue_redraw()
var cooldown_total := 0.0
var cooldown_remaining := 0.0
var _flash := 0.0
var _failed := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(58, 58)
	mouse_filter = Control.MOUSE_FILTER_PASS


func start_cooldown(duration: float) -> void:
	cooldown_total = duration
	cooldown_remaining = duration
	set_process(true)


func flash() -> void:
	_flash = 1.0
	set_process(true)


func fail() -> void:
	_failed = 1.0
	set_process(true)


func _process(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	_failed = maxf(0.0, _failed - delta * 3.0)
	queue_redraw()
	if cooldown_remaining <= 0.0 and _flash <= 0.0 and _failed <= 0.0:
		set_process(false)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var inner := rect.grow(-3)
	draw_rect(rect, Color(0, 0, 0, 0.75))
	draw_rect(rect.grow(-1), UiTheme.GOLD_DIM, false, 2.0)
	draw_rect(inner, UiTheme.SLOT)
	var font := get_theme_default_font()
	if spell != null:
		var icon: Variant = UiBind.read(spell, ["icon"])
		if icon is Texture2D:
			draw_texture_rect(icon, inner, false)
		else:
			_draw_placeholder_icon(inner, font)
	if cooldown_remaining > 0.0 and cooldown_total > 0.0:
		_draw_sweep(inner, cooldown_remaining / cooldown_total)
		var secs := "%d" % ceilf(cooldown_remaining) if cooldown_remaining >= 1.0 else "%.1f" % cooldown_remaining
		_draw_centered(font, secs, inner.get_center() + Vector2(0, 7), 20, Color.WHITE)
	if _flash > 0.0:
		draw_rect(inner, Color(1, 0.95, 0.7, 0.45 * _flash))
	if _failed > 0.0:
		draw_rect(inner, Color(1, 0.1, 0.1, 0.4 * _failed))
	draw_string_outline(font, Vector2(5, size.y - 5), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
	draw_string(font, Vector2(5, size.y - 5), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.PARCHMENT)


func _draw_placeholder_icon(inner: Rect2, font: Font) -> void:
	var color := UiBind.spell_color(spell)
	var c := inner.get_center()
	var r := inner.size.x * 0.5
	draw_rect(inner, color.darkened(0.75))
	draw_circle(c, r * 0.82, color.darkened(0.45))
	draw_circle(c, r * 0.6, color.darkened(0.1))
	draw_circle(c + Vector2(-r * 0.18, -r * 0.2), r * 0.25, color.lightened(0.4))
	if cooldown_remaining <= 0.0:
		var glyph := str(UiBind.read(spell, ["glyph"], UiBind.spell_name(spell).left(1)))
		_draw_centered(font, glyph, c + Vector2(0, 8), 22, Color(1, 1, 1, 0.95))


func _draw_sweep(inner: Rect2, fraction: float) -> void:
	var c := inner.get_center()
	var r := inner.size.length()
	var pts := PackedVector2Array([c])
	var steps := 32
	for i in steps + 1:
		var t := -PI / 2.0 + TAU * (1.0 - fraction) + TAU * fraction * float(i) / steps
		pts.append(c + Vector2(cos(t), sin(t)) * r)
	# Clip the fan to the slot by drawing it into the slot's rect only.
	var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]))
	for poly in clipped:
		draw_colored_polygon(poly, Color(0, 0, 0, 0.68))


func _draw_centered(font: Font, text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(baseline_center.x - w * 0.5, baseline_center.y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _tooltip() -> String:
	if spell == null:
		return "Empty slot (%s)" % key_hint
	var lines: PackedStringArray = [UiBind.spell_name(spell)]
	var cost: Variant = UiBind.read(spell, ["cost", "resource_cost", "mana_cost"])
	var cast: Variant = UiBind.read(spell, ["cast_time"])
	var cd: Variant = UiBind.read(spell, ["cooldown"])
	var facts: PackedStringArray = []
	if cost != null:
		facts.append("Cost %d" % cost if float(cost) > 0.0 else "Free")
	if cast != null:
		facts.append("Instant" if float(cast) <= 0.0 else "%.1fs cast" % cast)
	if cd != null and float(cd) > 0.0:
		facts.append("%.1fs cooldown" % cd)
	if not facts.is_empty():
		lines.append(" · ".join(facts))
	var desc: Variant = UiBind.read(spell, ["description"])
	if desc != null and str(desc) != "":
		lines.append(str(desc))
	return "\n".join(lines)
