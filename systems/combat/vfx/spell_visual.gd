class_name SpellVisual
extends Resource
## How a projectile spell looks, sounds and feels: the glowing bolt, its trail
## and crackling arcs, the flash when it leaves the hand, the impact, and the
## charge-up in the hand for chargeable spells. Shared by every spell that
## points at it; SpellData.visual left empty falls back to a plain sphere.

@export_group("Colors")
## White-hot center.
@export var core_color := Color(0.92, 0.97, 1.0)
## The halo around the core.
@export var glow_color := Color(0.25, 0.75, 1.0)
## Crackling edge, arcs and sigil accents.
@export var rim_color := Color(0.7, 0.35, 1.0)
@export var trail_inner := Color(0.75, 0.95, 1.0)
@export var trail_outer := Color(0.45, 0.25, 1.0)
@export var spark_color := Color(0.6, 0.9, 1.0)

@export_group("Bolt")
## Diameter of the glow sprite in metres.
@export var size := 0.55
@export var intensity := 4.0
## How strongly the halo flickers (0 steady, 1 wild).
@export var flicker := 0.45
## Sideways wobble while flying, in metres. Purely visual.
@export var wobble := 0.06
@export var light_energy := 2.5
@export var light_range := 5.0
## Size multiplier at full charge.
@export var charge_scale := 1.9

@export_group("Trail")
## Seconds of flight the trail remembers.
@export var trail_time := 0.28
@export var trail_width := 0.24
## Embers shed per second while flying.
@export var ember_rate := 70.0
## Lightning tendrils crackling around the bolt.
@export var arc_count := 3
@export var arc_reach := 0.55

@export_group("Launch and impact")
## Show the arcane circle at the hand when it fires.
@export var launch_sigil := true
@export var impact_radius := 1.1
@export var impact_sparks := 36
@export var impact_branches := 5
## Leave a scorch mark on walls and ground.
@export var scorch := true
@export var scorch_seconds := 6.0

@export_group("Feel")
## Camera kick when the player fires it and when it lands (0 to 1).
@export var launch_shake := 0.08
@export var impact_shake := 0.18
## Sound set from SpellSfx: &"spark" is the only one so far. Empty is silent.
@export var sound_set := &"spark"
