# Game feedback

`GameFeedback` makes every action answer back, on screen and by ear. `GameSession` adds one to each play scene (the world and dungeons); it only listens to signals, so no other system depends on it.

- **Crosshair** at the screen center, where spells go. Red over an enemy, gold over something magic can touch (the opening's chores). The ticks flick out when a spell lands, gold on a crit.
- **Damage numbers** over enemies, tinted by the spell, bigger with a "!" on a crit. Status words ("Stunned!", "Burning").
- **Getting hurt**: a red number over the player, a camera kick and a thump.
- **Kills**: a short hit-stop, a ring of light, and "+N XP" where the monster fell.
- **Level-up**: a pillar of light, a ring, and a fanfare, under the HUD's level-up banner.
- **Pickups**: the item's name in its rarity color, "+N gold".
- **Quest objectives**: a toast with a check and a chime when one is done, and the count for kills.
- **Failed casts**: "Not enough mana", "Jolt is recharging".
- **Sounds**: `FeedbackSfx` synthesizes small sounds in code (chimes, zaps, whooshes, thumps) until real audio exists. `FeedbackSfx.play(node, &"chime")`.

World text uses fixed-size `Label3D`s, so it reads the same at any distance. The 2D parts scale with the window height.
