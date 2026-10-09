class_name DungeonRecipe
extends Resource
## The character of a dungeon. The same recipe with a different seed gives a
## different dungeon of the same kind: same theme, size, difficulty and story
## rooms, different rooms, corridors, monsters and chests.

enum Style {
	CRYPT,  ## Ruined crypt: sarcophagi, bone piles, candles.
	CHAPEL,  ## Drowned chapel: pews, altars, flooded floors, stained glass.
	MINE,  ## Old mine: timber props, rails, glowing crystals.
}

## Room templates the planner and kit understand. Each changes the dressing
## and the size range a little; see DungeonPlanner.TEMPLATE_SIZES.
const TEMPLATES: PackedStringArray = ["hall", "pillared", "shrine", "ossuary", "pews", "flooded", "cavern", "dais"]

@export var display_name := "Dungeon"
@export var style: Style = Style.CRYPT
## Spawn-table biome used for this dungeon's monsters.
@export var biome: StringName = &"dungeon"
@export_range(1, 60) var level_min := 1
@export_range(1, 60) var level_max := 3

@export_group("Layout")
## Size of one grid cell in metres. Corridors are one cell wide.
@export_range(2.0, 8.0) var cell_size := 4.0
@export_range(2.0, 8.0) var wall_height := 3.4
## Rooms between the entrance and the boss on the main route.
@export_range(1, 12) var critical_min := 3
@export_range(1, 12) var critical_max := 5
## Optional rooms off the main route (treasure, dead ends). Story rooms and
## key rooms come on top of these.
@export_range(0, 12) var side_min := 1
@export_range(0, 12) var side_max := 3
## Key-and-lock pairs. Each lock sits on the main route; its key is in a side
## branch before the lock.
@export_range(0, 3) var locks := 1
@export_range(1, 8) var corridor_min := 1
@export_range(1, 8) var corridor_max := 3
## Room templates this dungeon picks from, from TEMPLATES.
@export var templates: PackedStringArray = ["hall", "pillared", "ossuary"]

@export_group("Encounters")
## Threat points per combat room per monster level. A monster costs about its
## level in threat (elites three times that), so 6 means roughly six
## level-appropriate monsters per room.
@export_range(1.0, 30.0) var threat_per_level := 6.0
## The boss room's budget as a multiple of an ordinary room's.
@export_range(1.0, 6.0) var boss_multiplier := 2.5
@export_range(0.0, 1.0) var elite_chance := 0.08

@export_group("Loot")
@export_range(0, 8) var chests_min := 2
@export_range(0, 8) var chests_max := 4

@export_group("Story")
## Side rooms a quest needs, each marked with a Marker3D of that name
## (for example "scribe_ghost"). A plan that can't place them is rejected.
@export var story_rooms: PackedStringArray = []
## Marker placed in the reward room behind the boss (for example "spellbook_page").
@export var reward_marker := ""

@export_group("Palette")
@export var wall_color := Color(0.5, 0.48, 0.46)
@export var floor_color := Color(0.36, 0.33, 0.3)
@export var trim_color := Color(0.3, 0.27, 0.25)
@export var wood_color := Color(0.42, 0.27, 0.16)
@export var accent_color := Color(1.0, 0.7, 0.35)
## Shallow water on flooded floors (chapel); alpha is the water's opacity.
@export var water_color := Color(0.2, 0.42, 0.45, 0.65)
@export var light_color := Color(1.0, 0.72, 0.45)
