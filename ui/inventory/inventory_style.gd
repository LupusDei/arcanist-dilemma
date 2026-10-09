class_name InventoryStyle
extends RefCounted
## Colors and drawing for the inventory screen. Uses the shared UiTheme
## (res://ui/theme/ui_theme.gd) when it is in the project, with the same
## dark-panel, gold-trim palette as a fallback so this screen also runs alone.

const GOLD := Color(0.78, 0.62, 0.34)
const GOLD_BRIGHT := Color(1.0, 0.85, 0.5)
const GOLD_DIM := Color(0.45, 0.36, 0.22)
const PARCHMENT := Color(0.93, 0.87, 0.74)
const MUTED := Color(0.6, 0.56, 0.5)
const PANEL := Color(0.07, 0.06, 0.09, 0.94)
const SLOT := Color(0.04, 0.035, 0.05, 0.95)
const GOOD := Color(0.5, 0.88, 0.42)
const BAD := Color(0.92, 0.36, 0.3)
const CELL := 44

static var _theme: Theme
static var _ui_theme_script: Script
static var _checked := false


static func get_theme() -> Theme:
	var shared := _shared_theme_script()
	if shared:
		return shared.get_theme()
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = 16
		_theme.set_color("font_color", "Label", PARCHMENT)
		_theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
		_theme.set_constant("outline_size", "Label", 3)
		_theme.set_type_variation("HeaderLabel", "Label")
		_theme.set_font_size("font_size", "HeaderLabel", 26)
		_theme.set_color("font_color", "HeaderLabel", GOLD_BRIGHT)
		_theme.set_type_variation("SubtleLabel", "Label")
		_theme.set_font_size("font_size", "SubtleLabel", 14)
		_theme.set_color("font_color", "SubtleLabel", MUTED)
		_theme.set_stylebox("panel", "PanelContainer", panel_style())
		var btn := panel_style(Color(0.14, 0.12, 0.16, 0.97), GOLD_DIM, 1, 4)
		btn.shadow_size = 0
		btn.set_content_margin_all(6)
		_theme.set_stylebox("normal", "Button", btn)
		_theme.set_color("font_color", "Button", PARCHMENT)
	return _theme


static func panel_style(bg := PANEL, border := GOLD, border_width := 2, radius := 6) -> StyleBoxFlat:
	var shared := _shared_theme_script()
	if shared:
		return shared.panel_style(bg, border, border_width, radius)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	return s


## Draws an item filling [param rect] on [param canvas]: its icon, or a colored
## placeholder with a short label, a rarity border and a stack count.
static func draw_item(canvas: CanvasItem, rect: Rect2, item: ItemInstance, dim := false) -> void:
	var base := item.get_base()
	var color := base.color if base else Color.GRAY
	var rarity_color := item.get_color()
	var inner := rect.grow(-3)
	var fill := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, 0.95)
	canvas.draw_rect(inner, fill)
	if base and base.icon:
		canvas.draw_texture_rect(base.icon, inner, false)
	else:
		# A lighter band so placeholders read as objects, not flat boxes.
		var band := Rect2(inner.position + Vector2(inner.size.x * 0.25, inner.size.y * 0.12), Vector2(inner.size.x * 0.5, inner.size.y * 0.76))
		canvas.draw_rect(band, Color(color.r, color.g, color.b, 0.9))
		var font := ThemeDB.fallback_font
		var text := short_label(item)
		var size := 13 if text.length() > 2 else 16
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(inner.get_center().x - tw / 2.0, inner.get_center().y + size * 0.35)
		canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
		canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, PARCHMENT)
	var border_w := 1.0 if item.rarity == ItemDefs.Rarity.COMMON else 2.0
	canvas.draw_rect(inner, rarity_color if item.rarity != ItemDefs.Rarity.COMMON else GOLD_DIM, false, border_w)
	if item.get_max_stack() > 1 and item.quantity > 1:
		var font := ThemeDB.fallback_font
		var q := str(item.quantity)
		var qpos := inner.end - Vector2(font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 3, 4)
		canvas.draw_string_outline(font, qpos, q, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		canvas.draw_string(font, qpos, q, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PARCHMENT)
	if dim:
		canvas.draw_rect(inner, Color(0.6, 0.05, 0.05, 0.35))


## Two or three letters for a placeholder icon: "St" for a staff, "Rg" for a ring.
static func short_label(item: ItemInstance) -> String:
	var base := item.get_base()
	if base == null:
		return "?"
	match base.kind:
		ItemDefs.Kind.POTION:
			return "HP" if base.heal_amount > 0.0 else "LY"
		ItemDefs.Kind.SPELLBOOK:
			return ItemInstance._roman(item.circle)
		ItemDefs.Kind.MATERIAL:
			return base.display_name.substr(0, 2)
		ItemDefs.Kind.GOLD:
			return "G"
	const LABELS := {&"staff": "St", &"wand": "Wd", &"hat": "Hat", &"robe": "Rb", &"gloves": "Gl",
			&"belt": "Bt", &"boots": "Bo", &"amulet": "Am", &"ring": "Rg", &"grimoire": "Gr",
			&"lens": "Ln", &"focus": "Fc"}
	return LABELS.get(base.category, base.display_name.substr(0, 2))


static func _shared_theme_script() -> Script:
	if not _checked:
		_checked = true
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == &"UiTheme":
				_ui_theme_script = load(entry["path"])
	return _ui_theme_script
