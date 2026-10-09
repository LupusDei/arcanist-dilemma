# Character progression

XP and levels, the five attributes, path / specialization / crossing choices, talent rows, each path's spell-growth currency, character creation data, and save/load. Rules follow the Game Mechanics doc; every tunable number is in `res://data/progression/`.

## Files

| File | What it is |
| --- | --- |
| `progression_service.gd` | The `Progression` autoload: the player's appearance and progression for the running game, plus save/load slots |
| `character_progression.gd` | `CharacterProgression`: level, XP, attributes, choices, talents, spell growth |
| `character_appearance.gd` | `CharacterAppearance`: boy or girl, name, face, skin, hair style and color, eyes, build |
| `progression_save.gd` | `ProgressionSave`: JSON save files under `user://saves/` |
| `progression_data.gd` | `ProgressionData`: cached access to the JSON tables |
| `tests/test_progression.gd` | Headless tests |

| Data | What it tunes |
| --- | --- |
| `leveling.json` | Level caps (20, replay 30), XP table, points per level, choice levels, talent row levels, monster XP scaling |
| `attributes.json` | Attribute names, tooltips, base value, health formula |
| `paths.json` | Paths, spell growth rules, specializations, talent trees, suggested builds for auto-assign |
| `appearance_presets.json` | Character creation presets and default names |

## Using it from other systems

```gdscript
# Enemies: when a monster dies
Progression.grant_kill_xp(monster_level, base_xp)

# Quests
Progression.grant_xp(250, "quest")
Progression.complete_key_quest("den_of_shadows")   # bonus spell growth

# UI
Progression.leveled_up.connect(_on_level_up)
Progression.choice_available.connect(_on_choice)     # &"path", &"specialization", &"talent", &"crossing"
var p: CharacterProgression = Progression.progression
p.allocate_many({&"intelligence": 3, &"wisdom": 2})
p.auto_assign()
p.choose_path("mage"); p.choose_specialization("chronos"); p.choose_talent(10, "echo")
p.pending_choices()                                   # for a "!" badge

# Combat / spells
Progression.stats_changed.connect(func(): stats = Progression.progression.combat_stats())
p.max_health(); p.health_regen()
p.spellbook_slots(); p.open_circle()                  # wizard
p.insight_available(); p.spend_spell_growth(1)        # mage Insight
p.spell_points_available(); p.open_tree_rows()        # sorcerer
```

Signals on the autoload: `xp_gained`, `leveled_up`, `stats_changed`, `attribute_points_changed`, `spell_growth_changed`, `path_chosen`, `specialization_chosen`, `crossing_chosen`, `talent_chosen`, `talents_reset`, `choice_available`, `character_loaded`, `appearance_changed`, `game_saved`.

`combat_stats()` calls `CombatStats.from_attributes(path, str, vit, dex, int, wis)` from `res://systems/combat/` and returns null until that class exists. Progression itself only computes health, since that depends on level.

New games and loads change the same objects in place, so a listener connected once stays connected.

Other systems can save alongside the character: `Progression.save_game(slot, {"inventory": {...}})`, and read their part back from `Progression.loaded_extra` after `character_loaded`.

## Tests

```bash
godot --headless --path . --script res://systems/progression/tests/test_progression.gd
```
