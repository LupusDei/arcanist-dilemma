class_name DamageType
extends RefCounted
## Damage types from the mechanics doc. Every spell has exactly one.

enum Kind { PHYSICAL, FIRE, COLD, LIGHTNING, FORCE, ARCANE, MIND }

const NAMES := {
	Kind.PHYSICAL: "Physical",
	Kind.FIRE: "Fire",
	Kind.COLD: "Cold",
	Kind.LIGHTNING: "Lightning",
	Kind.FORCE: "Force",
	Kind.ARCANE: "Arcane",
	Kind.MIND: "Mind",
}

const COLORS := {
	Kind.PHYSICAL: Color(0.8, 0.8, 0.8),
	Kind.FIRE: Color(1.0, 0.45, 0.1),
	Kind.COLD: Color(0.45, 0.8, 1.0),
	Kind.LIGHTNING: Color(0.75, 0.7, 1.0),
	Kind.FORCE: Color(0.95, 0.85, 0.55),
	Kind.ARCANE: Color(0.75, 0.35, 1.0),
	Kind.MIND: Color(1.0, 0.45, 0.8),
}

## Armor reduces these; the rest are reduced by resistances.
const ARMORED := [Kind.PHYSICAL, Kind.FORCE]


static func name_of(kind: Kind) -> String:
	return NAMES.get(kind, "Unknown")


static func color_of(kind: Kind) -> Color:
	return COLORS.get(kind, Color.WHITE)
