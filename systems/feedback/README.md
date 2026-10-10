# Game feedback

`GameFeedback` makes the things the combat layer doesn't cover answer back, on screen and by ear. `GameSession` adds one to each play scene (the world and dungeons); it only listens to signals, so no other system depends on it.

The combat system owns the feedback for your spells: the reticle, hit and kill markers, damage numbers, camera kick and hit-stop (`systems/combat/vfx/`, `CombatFeedback`). This layer adds the rest:

- **Status words** over enemies ("Stunned!", "Burning").
- **Getting hurt**: a red number over the player and a thump; a green number on a big heal.
- **Kills**: "+N XP" where the monster fell.
- **Level-up**: a pillar of light, a ring and a fanfare, under the HUD's level-up banner.
- **Pickups**: the item's name in its rarity color, "+N gold".
- **Quest objectives**: a toast with a check and a chime when one is done, and the count for kills.
- **Failed casts**: "Not enough mana", "Jolt is recharging".
- **Sounds**: `FeedbackSfx` synthesizes small sounds in code (chimes, whooshes, zaps, thumps) until real audio exists, including cast sounds for spells that have no voice of their own yet (Nudge, Jolt). `FeedbackSfx.play(node, &"chime")`.

World text uses fixed-size `Label3D`s, so it reads the same at any distance. The 2D parts scale with the window height until the project sets a stretch mode.
