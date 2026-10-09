# Spells and combat

A data-driven spell system for the three paths, plus health, damage and status effects. Everything here follows the mechanics doc (Combat, Paths, Spells sections).

## Try it

- Sandbox: open `res://systems/combat/sandbox/combat_sandbox.tscn` and press F6. WASD moves, the mouse aims, left click casts the cantrip, 1 to 6 and right click cast the bar. F1 to F4 switch between tricks, wizard, mage and sorcerer (each with a level 11 kit), T rests, R resets the dummies.
- Tests: `godot --headless --path . --fixed-fps 60 --script res://systems/combat/tests/test_combat.gd`

## Pieces

| File | What it is |
| --- | --- |
| `health_component.gd` | `HealthComponent`: health, armor, resistances (capped at 75%), wards, statuses (stun, slow, root, burn, charm, regen, haste) with elite/boss crowd-control scaling. Respects `is_invulnerable` on its body (the player's dodge). |
| `hit.gd`, `damage_type.gd`, `status.gd` | One packet of damage; the six damage types plus physical; status kinds. |
| `combat_stats.gd` | `CombatStats.from_attributes(path, str, vit, dex, int, wis)` turns attributes into spell power, crit, cast speed, resource size and the rest, using the doc's per-point values. |
| `spell_caster.gd` | `SpellCaster`: cast times, cooldowns, resource checks, interrupts, crits; resolves spells and emits signals. |
| `spells/spell_data.gd` | `SpellData`: one spell as a Resource. Delivery (projectile, targeted, area at target, nova, cone, self) plus a list of effects. |
| `effects/` | `DamageEffect`, `StatusEffect`, `KnockbackEffect`, `HealEffect`, `WardEffect`. Add a new effect by subclassing `SpellEffect`. |
| `delivery/` | Projectiles, bursts, chains, scatter and lingering ground. Hits are found through the `combat_targets` group, so no collision layers are needed; walls block projectiles with a ray. |
| `resources/` | `ArcanaPool` (wizard), `ManaPool` (mage, with `ley_multiplier` for ley lines), `StrainPool` (sorcerer: overstrain +25% power and backlash, collapse at 150% stuns for 2s). |
| `spells/trick_set.gd` | Levels 1 to 4: Spark, Nudge, Jolt, growing 10% per level. |
| `spells/wizard_spellbook.gd` | Slots per level, books in a Library, inscribe/upgrade/prepare at a rest, circles every 3 levels at 1.35x each, variant books. |
| `spells/mage_codex.gd` | Words, raw experiments (half power, double mana, first-time misfire), Insight every second level from 6, formulate at a rest, word mastery from practice. `mage_pair_rules.gd` builds any of the 64 pairs that has no authored file. |
| `spells/sorcerer_spell_tree.gd` | Full tree visible, 1 point per level (4 at the path choice), rows open every 3 levels from 5, prerequisites, ranks 1 to 5 (+20% power, +10% strain), synergies (+5% per partner rank). |
| `spells/spell_library.gd` | Loads every spell in `res://data/spells/` by id. No autoload needed. |
| `input/player_combat_input.gd` | Casting input for the real player, aiming through the camera. |

Spells live in `res://data/spells/` (tricks, wizard, mage, sorcerer) and can be edited in the inspector.

## For the other systems

- **Enemies:** add a `HealthComponent` child named `HealthComponent` (team `&"enemy"`). Deal damage with `health.take_damage(Hit.new(amount, DamageType.Kind.PHYSICAL, self))`. React to `knocked_back(impulse)`, stop while `is_stunned()`, multiply speed by `get_move_speed_multiplier()`, treat `Status.Kind.CHARM` as fighting for the player. Casting enemies can use a `SpellCaster` with `team = &"enemy"` on their HealthComponent; heavy hits and stuns interrupt them.
- **Progression:** on any stat change call `caster.set_stats(CombatStats.from_attributes(...))` and add `stats.bonus_health` to the player's `HealthComponent.max_health`. On level-up set `caster.source.level`. At the path choice call `caster.set_source(...)` with a `WizardSpellbook`, `MageCodex` (then `grant_starting_kit()`) or `SorcererSpellTree` (then `grant_starting_points()`).
- **UI:** read `caster.get_action_bar()`, `get_cantrip()`, `get_cast_progress()`, `get_cooldown_remaining(spell)`, `get_cost(spell)`, `caster.caster_resource` (`get_display_name()`, `current`, `maximum`, `get_fill()`), `caster.source.describe_growth(spell)`. Redraw on `bar_changed`, `resource_changed`, `cooldown_started`, `cast_started`, `cast_interrupted`, `spell_cast`. Floating numbers can come from each `HealthComponent.damaged(hit, amount)`.
