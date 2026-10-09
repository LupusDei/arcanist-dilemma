class_name QuestUiStyle
extends RefCounted
## The dialogue box and quest tracker use the shared UiTheme so they match the
## HUD. This adds only what those screens need on top: lean hint colours.

const GOLD := UiTheme.GOLD
const GOLD_BRIGHT := UiTheme.GOLD_BRIGHT
const PARCHMENT := UiTheme.PARCHMENT
const MUTED := UiTheme.MUTED
const PANEL := UiTheme.PANEL
const GOOD := UiTheme.GOOD
const BAD := UiTheme.BAD

## Hint colours for choices: order is blue, freedom is orange, good is green, evil is red.
const LEAN_COLORS := {
	"Lawful": Color(0.55, 0.72, 1.0),
	"Chaotic": Color(1.0, 0.62, 0.3),
	"Good": Color(0.55, 0.9, 0.5),
	"Evil": Color(0.95, 0.4, 0.4),
}


static func get_theme() -> Theme:
	return UiTheme.get_theme()


static func serif_font() -> Font:
	return UiTheme.serif_font()


static func panel_style(bg := PANEL, border := GOLD, border_width := 2, radius := 6) -> StyleBoxFlat:
	return UiTheme.panel_style(bg, border, border_width, radius)


## The colour for a lean hint such as "Chaotic, Good": the first word's colour.
static func lean_color(hint: String) -> Color:
	for word in LEAN_COLORS:
		if hint.begins_with(word):
			return LEAN_COLORS[word]
	return MUTED
