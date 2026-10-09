class_name UiTalentData
extends RefCounted
## Sample talent tree for the mock data source: the Chronos mage tree from the
## mechanics doc. Six rows, one per even level from 10 to 20, three sideways
## choices each. The real trees will come from res://systems/progression/.

const ROW_LEVELS: Array[int] = [10, 12, 14, 16, 18, 20]

const CHRONOS := [
	[
		{"name": "Echo", "text": "20% chance a spell repeats at half power"},
		{"name": "Borrowed Seconds", "text": "Blink returns you to where you stood 3 seconds ago, restoring health lost since"},
		{"name": "Wide Slow", "text": "Slow pairs hit an area instead of one target"},
	],
	[
		{"name": "Rewind", "text": "Once per 90 seconds, a killing blow rewinds you 4 seconds instead"},
		{"name": "Time Armor", "text": "Attackers are slowed 20%"},
		{"name": "Stasis", "text": "Freeze yourself, invulnerable for 3 seconds"},
	],
	[
		{"name": "Stolen Time", "text": "Killing a slowed enemy refunds 10% mana"},
		{"name": "Patience", "text": "Spells cast after standing still 1 second cost 30% less"},
		{"name": "Quickening", "text": "+50% mana regeneration while hasted"},
	],
	[
		{"name": "Freeze Frame", "text": "New spell: stops all enemies in an area for 2 seconds"},
		{"name": "Age", "text": "Slowed enemies lose 30% armor over 6 seconds"},
		{"name": "Loop", "text": "Damage over time ticks twice as fast"},
	],
	[
		{"name": "Foresight", "text": "See enemy attacks 0.5 seconds early as ground markers"},
		{"name": "Long Hour", "text": "All durations +25%"},
		{"name": "Tempo", "text": "Each different spell cast in a row gives +5% cast speed, stacking to 5"},
	],
	[
		{"name": "Paradox", "text": "Every 20 seconds, your next spell is instant and free"},
		{"name": "Chronarch", "text": "Your Slow also hastes you by the same amount"},
		{"name": "Second Self", "text": "Summon your past self, which repeats your last 4 casts"},
	],
]


## Builds the tree dictionary the talent picker reads.
static func chronos_tree() -> Dictionary:
	var rows := []
	for i in ROW_LEVELS.size():
		rows.append({"level": ROW_LEVELS[i], "options": CHRONOS[i]})
	return {"name": "Chronos", "rows": rows}
