class_name UiTheme
extends RefCounted
## The shared look for every screen: dark panels, gold trim and parchment text,
## in the spirit of Diablo 2 and World of Warcraft. Built in code so every
## colour lives in one place.

const GOLD := Color(0.78, 0.62, 0.34)
const GOLD_BRIGHT := Color(1.0, 0.85, 0.5)
const GOLD_DIM := Color(0.45, 0.36, 0.22)
const PARCHMENT := Color(0.93, 0.87, 0.74)
const MUTED := Color(0.6, 0.56, 0.5)
const PANEL := Color(0.07, 0.06, 0.09, 0.94)
const PANEL_LIGHT := Color(0.14, 0.12, 0.16, 0.97)
const SLOT := Color(0.04, 0.035, 0.05, 0.95)
const HEALTH := Color(0.8, 0.1, 0.12)
const XP := Color(0.86, 0.66, 0.2)
const GOOD := Color(0.5, 0.88, 0.42)
const BAD := Color(0.92, 0.36, 0.3)

const RESOURCE_COLORS := {
	&"mana": Color(0.16, 0.38, 0.92),
	&"arcana": Color(0.6, 0.32, 0.95),
	&"strain": Color(0.96, 0.46, 0.12),
}
const RESOURCE_NAMES := {&"mana": "Mana", &"arcana": "Arcana", &"strain": "Strain"}

static var _theme: Theme
static var _serif: SystemFont


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Serif font for titles and headers; falls back to the default font where
## none of these are installed.
static func serif_font() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Palatino", "Georgia", "Book Antiqua", "Times New Roman", "serif"])
		_serif.font_weight = 600
	return _serif


static func resource_color(kind: StringName) -> Color:
	return RESOURCE_COLORS.get(kind, RESOURCE_COLORS[&"mana"])


static func resource_name(kind: StringName) -> String:
	return RESOURCE_NAMES.get(kind, String(kind).capitalize())


static func panel_style(bg := PANEL, border := GOLD, border_width := 2, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	return s


static func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := panel_style(bg, border, 1, 4)
	s.shadow_size = 0
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 3)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", serif_font())
	t.set_font_size("font_size", "TitleLabel", 54)
	t.set_color("font_color", "TitleLabel", GOLD_BRIGHT)
	t.set_constant("outline_size", "TitleLabel", 8)

	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", serif_font())
	t.set_font_size("font_size", "HeaderLabel", 26)
	t.set_color("font_color", "HeaderLabel", GOLD_BRIGHT)

	t.set_type_variation("SubtleLabel", "Label")
	t.set_font_size("font_size", "SubtleLabel", 14)
	t.set_color("font_color", "SubtleLabel", MUTED)

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	var normal := _button_style(PANEL_LIGHT, GOLD_DIM)
	var hover := _button_style(Color(0.22, 0.17, 0.2, 0.98), GOLD_BRIGHT)
	var pressed := _button_style(Color(0.3, 0.22, 0.14, 0.98), GOLD_BRIGHT)
	var disabled := _button_style(Color(0.1, 0.09, 0.11, 0.7), Color(0.3, 0.28, 0.27))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD_BRIGHT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_focus_color", "Button", PARCHMENT)
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.4, 0.37))

	t.set_type_variation("BigButton", "Button")
	t.set_font("font", "BigButton", serif_font())
	t.set_font_size("font_size", "BigButton", 22)

	var field := panel_style(Color(0.03, 0.025, 0.04, 0.95), GOLD_DIM, 1, 4)
	field.shadow_size = 0
	field.set_content_margin_all(8)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = GOLD_BRIGHT
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", PARCHMENT)
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	t.set_font_size("font_size", "LineEdit", 20)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.025, 0.04, 0.9)
	bar_bg.border_color = GOLD_DIM
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = XP
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", PARCHMENT)

	var tooltip := panel_style(Color(0.05, 0.04, 0.07, 0.97), GOLD, 1, 4)
	tooltip.shadow_size = 4
	tooltip.set_content_margin_all(10)
	t.set_stylebox("panel", "TooltipPanel", tooltip)
	t.set_color("font_color", "TooltipLabel", PARCHMENT)

	var sep := StyleBoxLine.new()
	sep.color = GOLD_DIM
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	return t
