class_name UiMockSpell
extends Resource
## Stand-in for combat's SpellData. The HUD reads these fields by name (see
## UiBind), so any of them can be missing on the real resource.

@export var id: StringName
@export var display_name := ""
@export var glyph := ""
@export var color := Color.WHITE
@export var damage_type := ""
@export var cost := 0.0
@export var cooldown := 0.0
@export var cast_time := 0.0
@export_multiline var description := ""
@export var icon: Texture2D


static func make(id_: StringName, name_: String, color_: Color, cost_: float, cooldown_: float, cast_time_: float, description_: String) -> UiMockSpell:
	var s := UiMockSpell.new()
	s.id = id_
	s.display_name = name_
	s.glyph = name_.left(1)
	s.color = color_
	s.cost = cost_
	s.cooldown = cooldown_
	s.cast_time = cast_time_
	s.description = description_
	return s
