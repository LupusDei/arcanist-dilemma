# Procedural generation: the factory pattern

How Arcanist's Dilemma builds villages today, and how the same pattern extends to landscapes, dungeons and monsters so we can make unique content on demand, inside fixed bounds, every time.

The village factory in `systems/procgen/` is the working proof. Everything below marked **built** exists and is tested; everything marked **next** is the plan.

## The goal

The design doc calls for hand-built towns and key dungeons with a procedural wilderness, side dungeons and monster camps. Reason has since asked for villages to be procedural too. That only works if generation is:

- **Repeatable.** The same seed and inputs always give the same result, so a save file stores a seed, not a level, and bugs can be reproduced.
- **Bounded.** Every result passes hard checks (reachable, not overlapping, has the story pieces it needs). A generator that sometimes makes a broken level is worse than none.
- **Story-aware.** The story changes what gets generated (a bleed, a war, which faction holds a town) without reshuffling the layout the player already knows.
- **Fast.** Fast enough to generate while the player walks toward it.

## The pipeline (built, for villages)

Every factory runs the same five steps. Each step is a separate script so it can be tested alone.

| Step | Village version | Output |
| --- | --- | --- |
| **Recipe** | `VillageRecipe` resource: layout type, size, wealth, required story buildings, faction, bleed, damage, colours | A `.tres` file a designer edits in the Godot inspector |
| **Plan** | `VillagePlanner`: roads, then lots along them, then story buildings, then houses and farms, then props | `VillagePlan`: plain data, no nodes |
| **Validate** | `VillageValidator`: every anchor present, enough homes, no overlaps, nothing on a road or in water | A list of problems; empty means valid |
| **Retry** | If invalid, plan again from a seed derived from the original | The first valid plan (or the least broken, with a warning) |
| **Build** | `VillageBuilder` and `BuildingKit` turn the plan into meshes and collision; `VillageSite` shapes the terrain first | Nodes in the scene |

Planning produces data, not nodes, which is the key design choice. It means we can generate and check thousands of villages in a headless test without rendering anything, and the builder can be swapped (low-poly placeholders now, real art kits later) without touching layout logic.

### Seeds and streams

`GenRng.stream(seed, "roads")` gives each step its own random stream derived from the seed and the step's name. Adding a new step, or drawing more numbers in one step, never changes another step's output. That's what lets the story state work: bleed and damage use their own streams after the layout is final, so Millbrook in the prologue and Millbrook after the war in Act III have the same streets and the same houses, with different roofs.

### Story hooks

Recipes carry story fields, and `VillagePlanner.plan(..., state)` can override them at runtime from game state:

- **Anchors** are the buildings a quest needs. Millbrook requires a tavern (where the old man appears), a bakery and a well (*Spoons and Sparks*), a shrine, a notice board and the family farm. A plan that can't fit them is rejected.
- **Bleed** (0 to 1) tears buildings off the ground and floats them on chunks of earth with violet shards. Hallow's Rest uses 0.9 for *The Floating Village*.
- **Damage** (0 to 1) burns roofs to rafters, scorches walls and leaves rubble, for the Act III siege or a bad *Council of Millbrook* outcome.
- **Faction** colours banners, notice boards and Warden towers.

### The three recipes so far

| Recipe | Layout | Story use |
| --- | --- | --- |
| `millbrook.tres` | Village green with a well, radiating lanes | The arcanist's home, prologue and tutorial |
| `hallows_rest.tres` | Crossroads | *The Floating Village* (Act II), with bleed 0.9 |
| `vell_road_waystation.tres` | One winding street | Warden-held stop on the road to Vell (Act I) |

### How reliable it is

`tests/procgen_test.gd` plans 200 seeds of each recipe. Today all 600 are valid, each seed gives the identical village twice, and war damage doesn't move a single building. Millbrook takes about 70 ms to plan (the most crowded recipe; it retries on about a quarter of seeds), the others about 15 ms. Building takes about 25 ms.

### Try it

Open `scenes/procgen/village_lab.tscn` and press F6. N and B change the seed, 1 to 3 switch recipe, W toggles war damage. In the main world, Millbrook is generated around the spawn point from seed 1; change `village_seed` on the Millbrook node to get a different home village.

## Extending the pattern

### Landscapes and regions (next)

The meadow's `Terrain` already follows half the pattern (seeded noise, then stamps). To make regions on demand:

- **RegionRecipe:** biome (meadow, Fenwood marsh, Ironpeaks, Saltmarsh, Bleedlands), size, noise settings, water level, palette, tree and rock tables, and a list of **sites** to place: villages, dungeon entrances, monster camps, bleeds, story landmarks.
- **RegionPlan:** the heightfield, a road graph linking the sites, and site positions chosen by scoring (flat enough, near water for villages, remote for camps).
- **Validate:** every site reachable on foot from the entry point (walk the road graph and check slopes), nothing in water, sites spaced apart.
- **Build:** the order `VillageSite` uses now. Shape the terrain, build the sites, then scatter vegetation around the reserved areas.

Terrain already has the stamping API sites need: `soften_disc`, `flatten_rect`, `paint_path` and `reserve_area`, then `rebuild()`.

### Dungeons (next)

Same five steps, with a graph instead of streets:

- **DungeonRecipe:** theme (drowned chapel, Concord ruin, mine, bleed rift), size, level range, required story rooms (a boss, a spellbook page, a ghost to bind or free), and key-and-lock rules.
- **Plan:** first a **mission graph** (start, then a key, a locked door, a mini-boss, the reward, the exit), grown from a small set of rewrite rules so every dungeon has a shape, not just random rooms. Then lay the graph out on a grid using room templates (corridor, hall, shrine, pit) that fit together at doors.
- **Validate:** the exit is reachable; every lock's key is reachable before the lock; the critical path is within the recipe's length bounds; there are no orphan rooms; the encounter budget matches the level range.
- **Build:** a modular kit of wall, floor, door and pillar pieces per theme, the same way `BuildingKit` builds houses from parts.
- **Story state:** the same stream trick. A dungeon revisited after a choice keeps its rooms but swaps encounters or opens a sealed door.

### Monsters and encounters (next, with the enemies agent)

The enemies agent owns `actors/enemies/`. The factory side would be:

- **EncounterRecipe:** biome, level range, faction, a difficulty budget, and a spawn table with weights (wolves and boars in the meadow, drowned dead in the Fenwood, bleed-touched versions near a bleed).
- **Plan:** spend the budget on picks from the table, then place packs at camp sites or dungeon rooms. Elites get affixes (fast, shielded, bleed-touched) from their own stream.
- **Validate:** total threat within budget for the level range, no spawns in walls or water, a boss only where the plan asked for one.
- **Build:** hand the plan to whatever spawner the enemies system exposes, so this side never needs to know how a wolf is put together.

Monster variety comes from the same idea as houses: a base archetype plus seeded variation (size, colour, affixes, stats scaled by level) inside bounds the recipe sets.

## Rules for every factory

1. Plans are data. No nodes until the build step.
2. One named random stream per step, derived from the seed.
3. Validation is separate from planning, and it is the only judge of "valid".
4. Retry with a derived seed; never ship a plan that fails validation without a warning.
5. Story state is applied after the layout, from its own stream.
6. Each factory gets a lab scene to reroll by seed, and a fuzz test over hundreds of seeds in CI.

## What's still rough

- Building meshes are one node per part. Merging each building into one mesh will matter once there are several villages loaded.
- Roads are painted onto the terrain but don't bend the ground, so a steep lane looks steep.
- Villages can't yet sit on a river or along a coast, which the Saltmarsh will need.
- Generation runs on the main thread when the scene loads. Streaming regions in will need it on a worker thread, which planning-as-data makes straightforward.
