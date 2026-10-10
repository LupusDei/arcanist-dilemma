# The opening's lessons

The game teaches itself inside the prologue's first scenes, one thing at a time, when the story needs it. There is no separate tutorial: Ma's chores, Tam and the wolves in the barley are the lessons.

| Beat | Lesson | Done when |
| --- | --- | --- |
| Waking up | Move (W A S D) and look; gold arrows mark the chores | You walk a few metres |
| Ma's chores | **Nudge** (2) the spoon off the kitchen table | The spoon flies off the table |
| | **Spark** (left click) the cold stove | The stove roars alight, with smoke from the pipe |
| Tam | **Talk** (E) to Tam | Tam asks for the jar |
| | **Jolt** (3) the jar on the fence post | The jar leaps in a crackle of blue light |
| Rook | Your choices move your alignment | A few seconds after the choice |
| The barley | Follow the arrow to the wolves; Spark them; Nudge when one is close; Dodge (Shift) when hurt; Jolt to stun; drink a draught (Q) when low | You do each one |
| After | Walk over loot; open the bag (I); spend attribute points (C) | You do each one |

Each lesson is a card above the spell bar with the key drawn as a keycap, and the matching spell slot pulses. When you do it the card turns green with a check and a chime, then leaves. Lessons are saved as story flags (`tutorial_<id>`), so they never repeat after loading.

The chores really need the right spell. A wrong one makes the prop wobble and Tam calls out which trick to use. The quest objectives are `event` objectives (`spoon_moved`, `stove_lit`, `jar_jolted`) sent by the props, so casting near them is not enough.

## Files

- `opening_tutorial.gd`: `OpeningTutorial`, picks the lesson for the moment and checks it off; Tam's speech bubbles; the arrow over the barley; the title card on a new game.
- `chore_target.gd`: `ChoreTarget`, the spoon, stove and jar. A `HealthComponent` on the `prop` team lets real spells hit them; only `spell_id` does the chore.
- `hint_card.gd`: `HintCard`, the lesson card. Scales with the window height.
- `scenes/world/millbrook_story.gd` places the props in the yard and adds the `OpeningTutorial`.

Feedback for your spells (reticle, damage numbers, hit-stop) comes from the combat system; XP, objective toasts, level-up and the other sounds are in `systems/feedback/`.

## Tests

```bash
godot --headless --path . --fixed-fps 60 --script res://systems/tutorial/tests/test_opening.gd
```

plays the opening in the real world with real spells: each lesson shows in order, only the right trick does each chore, the feedback answers, and the first fight ends in level 2.

```bash
xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . --resolution 1600x900 --script res://systems/tutorial/tests/opening_screenshots.gd -- out_dir
```

saves a screenshot at each beat.
