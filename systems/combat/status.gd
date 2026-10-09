class_name Status
extends RefCounted
## Status effect kinds a HealthComponent tracks.

enum Kind {
	STUN,  ## Can't move or act. Interrupts casts.
	SLOW,  ## magnitude = fraction of speed removed (0.3 = 30% slower).
	ROOT,  ## Can't move, can still act.
	BURN,  ## magnitude = damage per second (fire).
	CHARM,  ## Fights for the other side. Bodies decide what that means.
	REGEN,  ## magnitude = health per second.
	HASTE,  ## magnitude = fraction of speed added.
}

## Crowd control is shortened on elites and bosses (mechanics doc, Combat).
const CROWD_CONTROL := [Kind.STUN, Kind.SLOW, Kind.ROOT, Kind.CHARM]

const NAMES := {
	Kind.STUN: "Stunned",
	Kind.SLOW: "Slowed",
	Kind.ROOT: "Rooted",
	Kind.BURN: "Burning",
	Kind.CHARM: "Charmed",
	Kind.REGEN: "Regenerating",
	Kind.HASTE: "Hasted",
}


static func name_of(kind: Kind) -> String:
	return NAMES.get(kind, "Unknown")
