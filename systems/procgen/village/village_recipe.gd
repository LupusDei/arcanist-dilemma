class_name VillageRecipe
extends Resource
## The character of a village. The same recipe with a different seed gives a
## different village of the same kind; the story-state fields (faction, bleed,
## damage) can also be overridden at generation time so one village changes
## with the story without changing its layout.

enum Layout {
	GREEN,  ## Houses around a central green with a well, roads radiating out.
	CROSSROADS,  ## Two roads crossing at a square.
	STREET,  ## One winding main street, like a road or river village.
}

## Building kinds the planner and builder understand.
const BUILDING_KINDS: PackedStringArray = ["house", "farm", "tavern", "bakery", "smithy", "shrine", "warden_post", "home_farm"]
## Props that can also be anchors.
const PROP_ANCHORS: PackedStringArray = ["well", "notice_board"]

@export var display_name := "Village"
@export var layout: Layout = Layout.GREEN
@export_range(12.0, 80.0) var radius := 28.0
## Target number of ordinary houses and farms, on top of the anchors.
@export_range(2, 60) var house_count := 14
@export var road_width := 3.2
## Bigger homes, more two-storey buildings, lamps along the main road.
@export_range(0.0, 1.0) var prosperity := 0.5
## Share of outer lots that become farms with fenced fields.
@export_range(0.0, 1.0) var farm_share := 0.3

@export_group("Story")
## Buildings and props that must exist, from BUILDING_KINDS and PROP_ANCHORS.
## A plan that can't place them all is rejected and retried with a new sub-seed.
@export var anchors: PackedStringArray = ["well", "tavern", "notice_board"]
@export_enum("none", "wardens", "unbound") var faction := "none"
## 0 is untouched. 1 is a full bleed: loose magic tears buildings off the ground.
@export_range(0.0, 1.0) var bleed := 0.0
## 0 is intact. 1 is war-torn: roofs gone, walls broken, scorch marks.
@export_range(0.0, 1.0) var damage := 0.0

@export_group("Palette")
@export var wall_color := Color(0.56, 0.36, 0.22)
@export var trim_color := Color(0.36, 0.23, 0.14)
@export var roof_color := Color(0.86, 0.43, 0.18)
@export var stone_color := Color(0.62, 0.62, 0.6)
