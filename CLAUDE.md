# RPG template — engineering rules

**This file is the contract.** If a rule here conflicts with your instinct, the rule wins.

This repo is a *template*, not a game. Everything in it exists so that building a new RPG
means editing `data/` and writing gameplay — never rewriting movement, sprites, saves or
the boot sequence. A change that makes the template more specific to one game is a
regression, however good that game looks.

## 1. Hard rules

- **Typed GDScript everywhere.** `untyped_declaration` and `unsafe_method_access` warnings
  are on. No C#.
- **Art is data, with no exception left.** Colours, palettes, cell sizes, frame counts and
  outline rules live in a `SpriteStyle` resource under `data/styles/`. A colour literal in
  `scripts/world/` or `scripts/ui/` is a build failure (`tools/lint_rules.gd`). **Terrain is
  authored the same way characters are** - a `TileBank` under `data/tiles/` in the rig's own
  `.`/`1`/`2`/`3`/`o` alphabet, one bank dressing every style. It was a `const TILES` in
  `TileGen` drawn by five hardcoded routines until M16, and the cost was legible: no routine
  could draw a door, so the quest's cave was built out of grass-world tiles.
- **Sound is data too, and generated the same way.** A cue's SHAPE is a row in
  `data/banks/<id>.json`; its VOICE is a `SoundStyle` under `data/sounds/`. Three voices share
  one bank the way three sprite styles share one rig. Template code never names a cue as a
  string — `Sfx.Cue` is an enum, so a typo is a compile error rather than a warning nobody
  reads at the moment the sound should have played.
- **Numbers live in data, not code.** A literal in a script that a designer would want to
  change is a bug. Speeds, reaches and timings come from `data/game_config.tres`.
- **Randomness is seeded.** `SeededRng` only. `randi()`, `randf()`, `Array.pick_random()`
  and `Array.shuffle()` draw from a global generator nobody seeded, which silently breaks
  every "same seed, same sprite" guarantee. The linter fails the build on them.
- **Directions come from `Dir`.** Canonical order is `down, left, right, up`, everywhere,
  forever: sheet rows, animation names, facing values. A raw `"left"` in a script is a
  build failure.
- **No logic in `.tscn`.** Scenes hold views.

## 2. Architecture

```
scripts/spritegen/  pure RefCounted, deterministic, NO node access — the sprite generator
scripts/soundgen/   the same, for sound: synth, sound_bank, sound_source + two impls
scripts/util/       dir, sfx, json_file, seeded_rng, hashing, lint_core, content_scan,
                    image_file + sound_file (build-time readers, never shipped)
scripts/data/       Resource types (SpriteStyle, SoundStyle, CharacterSpec, GameConfig, SaveData, EnemyDef, CombatDef…)
scripts/world/      Locomotion + GridWalker + NpcBrain (all pure) + the nodes that apply them
scripts/ui/         DialogRunner + DialogBox, PauseMenu + PauseScreen,
                    BattleLogic + BattleScreen, GameOverMenu + GameOverScreen (pure + view)
scripts/autoload/   EventBus Registry GameState SaveManager Router AudioBus Settings Qa
scenes/             views only
data/               all content: games, styles, rigs, tiles (terrain art), characters,
                    maps, dialog, items, enemies, combat, banks (cue shapes), sounds (voices)
games/<id>/         a game's OWN code: a GameHooks subclass, and nothing generic
assets/generated/   build OUTPUT of tools/gen_sprites.gd — never hand-edited
```

Signals up, calls down, through `EventBus`. Autoloads hold state, scenes hold views; a view
never assigns `GameState.x` — it emits and the owner responds. One writer per piece of
state.

**Which game runs is data, not code.** `data/games/<id>.tres` (`GameManifest`) holds the first
map, the spawn, the player's character, the config and the controls hint. `GameSelect` picks
one: `--game=<id>` beats the `application/config/game` project setting, which beats "there is
only one game". Nothing in `scripts/world/` may name a map, a spawn or a character again.

**When nothing chooses, refuse — never guess.** `GameSelect.choose()` returns `""` when there
is more than one game and nothing picked between them, and the boot stops there with an error
naming them. One game ships, so the single-game fallthrough is the live path and the refusal is
unreachable — it is kept armed because the day a second game is added is exactly the day a
guessed game starts presenting as the game you meant to run behaving strangely. The shipped
`config/game` is empty for that reason: with one game it needs no answer, and with two it must
be given one.

**Gameplay goes in `games/<id>/`, never in `scripts/`.** A game's code is a `GameHooks`
subclass named by its manifest. It is handed a `GameContext` and **may not name an autoload** —
naming one removes a file from the per-file parse gate AND `compile_all.gd`, so it would leave
two of the four gates silently; `LintCore.RULE_AUTOLOAD` fails the build on it. Hooks read a
snapshot and append effects; `world_scene._apply` is the single place any of it reaches live
state. `on_interact` returning `false` means "not mine" and the data's own behaviour runs — a
game is additive or it is not using this seam.

**A view asks for a sound; it never plays one.** Every screen carries
`signal sound_wanted(id)` and `world_scene._on_sound_wanted` is the single place that reaches
the speaker - the `_apply_effects` shape, for audio. Two reasons, and the second is the one
that bites: `check.sh`'s per-file parse gate skips any file whose TEXT contains an autoload
name, so a view calling the audio singleton silently drops itself AND every suite that depends
on it out of that gate. **Naming it in a comment is enough to do this** - which is how the
signal came to exist. Pure classes (`BattleLogic`) go one step further and COLLECT cues for the
view to drain, because a fight's cues must survive a defeat, whose effects are discarded.

**A tile names a ramp, never a colour, and `solid` is art data.** `TileBank.problems()`
refuses a ragged row, a typo'd pixel, a duplicated id, a tile that is not the bank's declared
size, and a transparent pixel in anything not marked `decor` - a hole in the ground shows the
window's background through the world, and it is invisible while authoring because the tile
looks right on its own. A tile's `ramp` is a DEFAULT: `SpriteStyle.tile_ramps` overrides one
where a style wants it different, which is what stops adding a tile from being a mandatory
edit to every style. `TileGen.problems(bank, style)` holds the checks needing both, the way
`CharacterSpec.problems(rig, style)` does.

**A dialog line has a SIZE, and the build enforces it.** `DialogBox` shows two lines of text
with the choices in a band of their own below them, and the box grows only while a choice is
up. Those numbers are constants on `DialogBox`; `test_dialog_fit.gd` measures every shipped
line with the real font against those same constants and fails the build on anything that
would not fit, naming the file and node. It exists because the opposite is silent: a
`RichTextLabel` with scrolling off does not wrap, scroll or complain past its height - it
CLIPS, so a fact written into the data never reaches the player and every headless gate still
passes. A line that needs more room is another node on a `next` chain.

**A dialog choice line cannot be escaped.** `cancel` closes a dialog only while a line is
being shown; on a line with choices the box routes input to the choice list instead, because
the point of a choice is that one gets picked. So a conversation that loops back THROUGH a
choice node has no way out of it - both branches of a choice must eventually end the talk.

**No actor is a moving platform, and the default says otherwise.** `platform_floor_layers`
defaults to every layer, which is a platformer contract: a body touching another from above
reports `on_floor`, and a body on a MOVING floor inherits its velocity. Top-down, every actor
is a "floor" to anything touching it from above - so an NPC walking down into the player rode
along wherever he strafed, at exactly his walk speed, while one walking UP into him was
untouched (from below he is a ceiling, and ceilings carry nobody). `ActorBody._init` clears it.
An unset engine property is not a neutral one; it is whatever genre the engine assumed.

Deliberately NOT `MOTION_MODE_FLOATING`, which Godot recommends for top-down and which would
also fix this: floating changes how every body slides along every wall, and the eleven play
sessions are calibrated against the current sliding - switching it diverged
`finish_the_quest` at the hermit into 16 cascading failures. That is a movement-feel decision
for a person who has played the game, not a side effect of a bug fix. See `docs/DECISIONS.md`.

**Two movement modes, and `place()` is the only teleport.** `GameConfig.grid_step_pixels` at
zero is free pixel movement; set to the map's tile size it is one press = one tile. Both go
through `velocity` + `move_and_slide` and produce the same `Locomotion.Step`, so nothing
downstream can tell which is running. `ActorBody.place(at, facing)` is the ONE way an actor is
teleported — it cancels a step in flight *before* assigning the position, because abandoning
one afterwards resolves it against the cell the actor left, in the map it left.

**Items are a template noun, and every effect has ONE sink.** `ItemDef` under `data/items/`
(picked up by `Registry` from its `class_name`), `Inventory` pure beside it, and a snapshot
`Dictionary` at every seam - a hook, a save, a map file. `requires_item` sits beside
`requires_flag` on objects, warps and dialog choices, and wherever a refusal can happen a
`locked_dialog` is required. **A take implies a requires**: `Interaction.decide` and the runner
both refuse before appending anything, so an effect list is all-or-nothing and `once` never
records a chest that gave nothing. Gifts go on dialog CHOICES, never nodes (a node has no
condition and no memory, so a loop hands over a second key); the once-idiom is `set_flag X` +
`hidden_if_flag X` on the same choice. `world_scene._apply_effects()` is the only place any of
it reaches live state - `_on_dialog_closed` goes through it too.

**A fight is template logic over game data, and it never writes anything.** `BattleLogic` is
pure and has NO CLOCK: `tick()` is handed one physics frame at a time by `BattleScreen`, which
is what lets a QA script press on an exact frame and get the same fight on every machine. Only
the FIRST press of a cue is captured, or mashing lands a press in every window and "timing"
means "press a lot". Results are COLLECTED and applied through `world_scene._apply_effects`, so
"a beaten enemy stays beaten" is the same map-scoped `seen` key a chest uses - persisted and
migrated for free. Enemies are a map record (`enemies[]`), fully projected by `enemy_at()` the
way `warp_at()` is, and the encounter fires on ARRIVING at a tile adjacent to one: a body stops
the player 6-10px out, so waiting for contact would make the trigger frame depend on walk
speed. Diagonals deliberately do not count - a fight that must happen is made unavoidable by
GEOMETRY (a one-tile gap), never by a radius. A game with no `CombatDef` on its manifest cannot
fight, and that is a legal shape forever.

**A shop is a COUNTER, not a list.** The screen is the anatomy every classic shop converges
on, and M18 shipped without most of it: an item list with prices RIGHT-ALIGNED in their own
column and the owned count beside them, a purse panel that becomes the running total while a
deal is being sized, a description bar in the item's own words (`ItemDef.description`, which
existed since items did and no screen showed), and the keeper's window along the bottom in
the DialogBox's shape. Windows over the LIVE WORLD, never a full-screen dim - a shop is a
place you walked into. The buy flow is pick -> **how many** -> confirm: the count step is what
lets a player buy three of something, and the total travels on the Deal so the number they
agreed to is the number the purse moves by. The keeper's words are `ShopDef` fields with
template defaults, so a game re-voices a merchant without touching a script, and a refusal is
SAID as well as thudded.

**A shop is a `ShopDef` and a dialog CHOICE, and `price = 0` means not for sale.**
`data/shops/<id>.json`-shaped `.tres` lists item ids; the price lives on the `ItemDef`, so two
keepers cannot disagree about what a tonic is worth. Zero is the DEFAULT, which is what keeps
quest items off both counters - a key that can be sold is a door that can be locked for the
rest of the run, and the failure lands hours later. `ShopMenu.tradable()` is that rule, once,
so the buy page and the sell page cannot drift. A keeper is opened by `"open_shop": "<id>"` on
a dialog choice, and the arm in `_apply_effects` DEFERS the open: `_on_dialog_closed` applies
effects and then pops the dialog overlay, so a counter opened inline would be the thing that
pop closed. The menu is the only affordability check; `spend_gold` behind it is the invariant,
and it says so loudly rather than overdrawing anyone.

**The bag's confirm is the equip verb, and only for gear.** `PauseMenu.confirm()` on the
ITEMS page answered NONE for three milestones with a comment saying a use verb was a game's
business; equipment is the answer that goes there, and a SLOTLESS row still answers nothing -
a potion heals in every RPG ever written, where "use the rope on the well" is a puzzle. The
row carries an `(E)` marker and the line under the list shows what the press would DO before
it does it ("Take off: Atk +3 (now Atk +3 Def +0)"), worded by the world because naming a
stat is a Registry question. Equipping is a TOGGLE - one list, one confirm; a second key for
"unequip" is a control nobody would find. **What is worn is not on the sell counter**, and
that refusal lives in the world rather than in ShopMenu: the counter has no business knowing
what equipment is, and a spare copy stays sellable while one is worn.

**Gear is a MODIFIER, never a stat, and it never leaves the bag.** Player attack and defense
are DERIVED (`CombatDef.attack_at(level)`), so equipment cannot be stored as a stat without
two sources of truth for one number; it arrives at `BattleLogic.of()` as two already-summed
ints, because that class may not reach the Registry. The world resolves them (`_equip_mod`),
which is the `_battle_items`/`_item_rows` precedent. `GameState.equipment` is slot -> item id
and the item STAYS in the inventory - equipping marks it, so the bag remains the one list of
what the player has, and a swap has nothing to put back. `take_item` clears the marker when
the last copy leaves by ANY path, because a slot map pointing at a phantom re-arms the moment
another copy is picked up; `SaveData.problems()` checks the same invariant against the file
itself, since a hand-edited save can describe a player who cannot exist.

**Money has ONE writer and a spend is refused, never clamped.** `GameState.gold` sits beside
hp/xp, but zero is a REAL value there (broke) rather than the "unset" hp uses, so it is a
plain field with a plain default. `give_gold`/`spend_gold` are the whole vocabulary and both
report whether they happened; a spend beyond the purse returns false and moves nothing,
because clamping turns "could not afford it" into "bought it and has nothing". Gold therefore
cannot go negative by construction rather than by a check somewhere downstream. An enemy's
`gold` rides the same collected effect list a fight already uses, so a DEFEAT - whose effects
the world discards wholesale - still pays nothing, and "a fight never writes" is untouched.
The purse is drawn on the pause screen as a READOUT, not a row: the cursor cannot land on it,
so every test that names a row by its enum stays aimed at the same row.

**An NPC's behaviour is data, and a moving one is driven by the player's own code.**
`behavior` on a map's npc record is `static` (the default), `wander` (bounded drift around
where it was placed) or `patrol` (an authored `path` of tiles, `loop` or ping-pong).
`NpcBrain` is pure and has NO CLOCK - it answers with an INTENT VECTOR, the same axis pair a
keyboard produces, so a walking NPC goes through the same `Locomotion`/`GridWalker`/`ActorBody`
the player does. Dwelling counts FRAMES; a wall-clock dwell would make a play session depend
on how busy the machine is. Draws come from a `SeededRng` keyed on game+map+npc id, never a
clock - the world had no per-frame randomness before this and still has none that a rerun
cannot reproduce.

`_drive_npcs()` sits BELOW the `Router.player_can_move()` early return, and that placement is
the whole design: a dialog, the pause menu, a fight or game-over stops the town as well as the
player, so a speaker cannot wander off mid-sentence. It is a placement rather than a line, so
no mutant can express it - `test_world_npcs.gd` proves it by moving the call above the gate.
NPC footfalls are read and DISCARDED, or a town of walkers plays footsteps the player cannot
place. **A `static` NPC is never given a brain at all**, which matters beyond cost: several QA
sessions use shipped NPC bodies as walls (the warden at village [5,3] stops every northward
leg), so a shipped NPC that started wandering would break sessions that look unrelated. A
typo'd behaviour FAILS THE BUILD rather than standing still, and a patrol waypoint in a wall
or on a warp is refused - an NPC parked on the only exit is a door that cannot be used.

**Losing ends the run, and TITLE still means nothing.** `Router.State.GAME_OVER` +
`GameOverScreen` (Continue / Start again) - an overlay, because this game boots straight into
the world and has no title scene. `TITLE` stays "nothing to drive yet"; giving it a second
meaning would break `state_name()`, which QA asserts on directly.

**A setting is not a save.** `Settings` owns `user://settings.json` - global, outside every
slot, surviving a new game and a deleted save. It carries no version: one field, an
unrecognised value falls back to the default, and the next write repairs the file. Redirected
under `--qa-script` exactly as saves are, and `test_settings.gd` ASSERTS the redirect is in
effect before touching anything - a suite that cycles the volume would otherwise write the
player's real preference, and the mutation harness runs that suite with the code deliberately
broken.

**Do not give an autoload a name that ends another identifier.** `compile_all.gd` decides what
to skip by looking for `Name.`, and `Settings.` occurs inside `ProjectSettings.` - nine files
silently left the compile gate, reported only as a count going up. The matcher now requires a
whole identifier; the hazard is the naming, so check a new singleton's name against the engine's
own globals.

**Saves are per game, and `restore()` is the one way back in.** Slots live at
`user://saves/<game>/slot_N.json` and each save NAMES its game; the two are cross-checked on
every read and a file that disagrees is parked, never loaded. `peek()` is the slot list's
silent read - drawing a menu must not park files or announce loads - which makes an unreadable
slot look *empty*, which is why `save()` parks whatever it is about to overwrite. Escape opens
`PauseMenu`/`PauseScreen` from `WORLD` only. `restore()` is the
single path from a save into a world (`from_save` then `enter_map`), and `enter_map`'s third
argument is a restored position that nothing else passes. A `--qa-script=` run saves under
`user://qa_saves`, wiped at boot, so a play script neither reads nor overwrites real progress.

**`move_and_slide()` picks its own delta** — the physics one inside a physics frame, the idle
one otherwise (pinned in `test_engine_assumptions.gd`). So never compute how far a call will
move something: end an operation by observing that it finished. This is also why the
integration suites can drive `apply()` by hand from a coroutine at all.

**The sprite contract is PNG + `<name>.sheet.json`.** Nothing engine-specific is committed
as art: `SpriteFramesFactory` turns that pair into a `SpriteFrames` at runtime. This is the
seam that lets a procedural rig, a downloaded pack or an AI generator feed the same game.

## 3. Testing

**Every gate ships with a proof that it fails on the input it exists to catch.** A
validator that has only ever passed is decoration.

- Pure logic (`spritegen/`, `Locomotion`, `DialogRunner`, `MapData`) is `RefCounted` and
  tested with no scene tree. Node behaviour uses gdUnit4's `scene_runner`.
- Mutants are mandatory: a rule with no row in `tools/mutants.tsv` is a rule nobody has
  proven is tested. `NOT APPLIED` means fix the pattern, never delete the row. A pattern must
  match exactly ONE line, and `tools/mutants_aim.sh` checks every row on every `check.sh` run —
  because writing NEW code is what breaks an old mutant's aim: repeat a line one anchors on and
  sed silently retargets it at your function. Fix by making the two lines differ (rename a
  local), never by loosening the pattern.
- Gates run **unpiped** — `cmd | tail` exits with `tail`'s status, so a failing gate
  reports success.
- Autoloads outlive a suite: call `GameState.reset()` in `before_test`.
- Assert on simulated frames, never wall-clock time. In a suite with no `scene_runner` that
  means `await get_tree().physics_frame`, not `await_millis()`: under load a millisecond
  spans no physics frame at all, and "the player did not move" becomes a fact about how busy
  the machine is. It fails as a mutation BASELINE FAILURE, which reads like a broken test.
- A simulated `InputEventAction` needs its matching RELEASE, the way `Qa.press` inserts one.
  An action left held is still held at the next press, and the engine sees no change.
- **Never navigate a menu by counting presses.** `move(PauseMenu.Row.SAVE)` and not `move(1)`:
  inserting a row re-aims every counting test at whatever now sits there, silently and while
  still passing. M12 turned a "refuse to load" test into one that SAVED a slot that way.
- **A QA leg is held until a WALL or a BODY stops it**, never for a computed number of tiles.
  An arriving hold carries the player onward into the next map, so a leg that follows a warp
  must re-anchor against geometry rather than assume where the last one left off. The one
  legitimate count is "enough frames to reach the row a door is on" - past it is fine, because
  a warp fires on arrival.

### GDScript rules that are not optional here

- `--check-only -s <file>` is a parse, not a compile: it cannot resolve types from other
  scripts, and it cannot run at all for a script naming an autoload. `tools/compile_all.gd`
  and `tools/smoke_boot.gd` cover those two holes.
- gdUnit4 exits **100** on a failed assertion, and **0** when a discovery-time parse error
  crashes it — so `check.sh` greps for `handle_crash` and compares suites-ran against
  suites-on-disk.
- Never alias a project class in a `const` inside a test suite; it crashes the scanner.
  Aliasing an **enum** (`const D := Dir.D`) is fine. Typed helpers live in `tests/helpers/`.
- `Image.flip_x()` returns nothing and mutates in place. `var left = right.flip_x()` binds
  null and mirrors the original.
- Use `Image.create_empty`, `set_pixel`, and compare colours as `to_rgba32()` ints.
  `blit_rect` overwrites alpha; `blend_rect` blends floats and produces off-palette values.
- JSON has no integers. Cast every number you read, and `Array.assign()` into typed arrays.
- Adding an autoload changes what the parse gate skips: `check.sh` and `compile_all.gd` both
  derive that list from `project.godot`, so add the singleton there and cover it in
  `smoke_boot.gd` — never by editing a list in a tool.
- A new `class_name` script is invisible to gdUnit4 until `--import` has run — the failure is
  `Could not find type "X" in the current scope` at discovery, which reads as a typo. Run
  `Godot --headless --path . --import` after adding one. `check.sh` does this as step 1.
- Running gdUnit4 by hand needs `--ignoreHeadlessMode -c`, or it refuses with `Abnormal exit
  with 103` and no test output at all.
- `mutants.tsv` patterns are EXTENDED regexes, so `+` is a quantifier: `_index + delta` matches
  nothing and fails as `PATTERN-NOT-FOUND`. Escape it.
- **`LintCore.SOURCE_ROOTS` is the one list of directories this project owns.** The linter
  and `compile_all.gd` read it; `check.sh`'s parse gate keeps no list at all and excludes
  what is not ours. A new top-level source directory goes there and nowhere else, and
  `test_lint_core.gd` fails until it does.
- **Content is discovered through `ContentScan`, never a hand-rolled `DirAccess` walk.**
  Four of those existed and disagreed about recursion, so content one directory down was
  registered by the game, never generated, and the art-drift gate passed having compared
  nothing. Results are sorted because the generator's output order must not depend on the
  filesystem.
- **The deployed web build cannot be driven by browser automation.** Godot maps web input
  from `KeyboardEvent.code`; the automation available here sends trusted events with an empty
  `code`, and hand-built events with a correct `code` arrive untrusted and are ignored. A
  screenshot proves it renders and the console proves it booted — playability needs a human.

## 4. Commands

```bash
tools/check.sh                 # import, lint, parse, compile, tests, boot, art drift, play
MUTANTS=1 tools/check.sh       # + prove every gate bites (milestone close)
tools/mutate_check.sh --list   # what each mutant claims to cover
tools/mutants_scope.sh         # the mutants THIS branch's diff could have broken
tools/pack_check.sh            # export the .pck and PLAY it - the artifact, not the source tree
```

**Every gate except one runs against `res://` in the project directory. `pack_check.sh` runs
against the `.pck` a player downloads**, because that is where a whole class of defect lives: an
asset that is not packed, an exclude filter that grew, an importer that did not run. M14 shipped
one of those - the audio seam's drop-in half had been broken in exports since the day it was
written, and no gate could have seen it.

`--export-pack` needs no export templates and `--main-pack` boots the pack with the stock
binary, so the whole thing costs about five seconds and runs in `check.sh` as step 7b. The QA
scripts are read from an ABSOLUTE host path, because `tests/*` is excluded from the pack - the
shipping preset is never modified to make itself testable.

**A missing or truncated pack HANGS rather than failing.** Measured, both of them, with no output
at all. Every packed run is `timeout`-wrapped, and any path handed to `--main-pack` is made
absolute BEFORE the run changes directory - a relative one stops resolving and presents as that
same hang.

**An expected crash must not print like an unexpected one.** The pack exporter aborts during
shutdown after writing a complete package; bash reports that as `Aborted (core dumped)` from the
shell that WAITED on it, so redirecting the command's own streams does not stop it. Both export
sites run through a wrapper shell whose stderr is discarded and which exits normally. Note bash
3.2 (macOS) never prints it and bash 5 (CI) does — not reproducing it locally proves nothing.

**A swallowed exit code needs a stated reason.** `pages.yml` ignores the exporter's status for a
real, measured one (it aborts during shutdown after writing a complete package) and says so. It
used to ignore `--import`'s status for no reason at all, which was a fail-open in the step that
builds what ships.

**Anything driven by frames gets `$GODOT_FRAMES` (`--fixed-fps 60`), from `_engine.sh`.**
Headless does not mean fast: the engine still paces its main loop against the wall clock, so a
play session that takes a player three minutes took the gate three minutes. The flag pins every
delta at 1/60 AND stops waiting for real time between frames. It changes nothing a gate can
see - these harnesses count physics frames, never seconds - which is why the ten play sessions
give byte-identical logs with it and without, the suite returns identical verdicts on all 595
tests, and all 226 mutants are still killed. The whole gate went 7m35s to 27s. Do NOT add it to
the generators; they quit in their first frame.

**The mutation sweep is split by WHERE it runs, never weakened.** A pull request proves the
mutants its own diff could have broken (`mutants_scope.sh`: rows that mutate a file it touched,
name a suite it touched, or were added by it); every merge to `main` re-runs all of them, where
nobody is waiting. `mutants_aim.sh` still runs over the WHOLE file on every run of both -
that is the check that catches new code stealing an old mutant's aim, and it costs under a
second. Both CI paths pass `--assume-green`, which is only safe because `check.sh` has just
proven all 54 suites green in the same job.

**Open the PR and walk away.** `gh pr merge --auto --squash` merges it when CI goes green;
polling a 17-minute run is how a session gets spent. This needs a required status check on
`main` - without one, `--auto` merges immediately, which is the trap.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sounds.gd
```

Drive the real game from a script, or photograph it. QA scripts live under
`tests/fixtures/qa/<game>/` and `check.sh` runs every one with `--game=<that directory>`, so
a new script needs no edit to the gate:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --qa-script=res://tests/fixtures/qa/quest/talk_to_npc.json --game=quest
```

Other headless tools: `setup_input_map.gd` (rewrites the input map — re-run after changing
bindings), `lint_rules.gd`, `compile_all.gd`, `smoke_boot.gd`, `screenshot.gd` (needs a real
rendering driver, so not headless and not in CI). `tools/_engine.sh` resolves the engine;
`GODOT_BIN` overrides it. The Godot MCP is an accelerator for interactive work, **never** a
dependency of the build.

**Two MCP servers, two jobs.** `godot` (`@coding-solo/godot-mcp`) scaffolds - create a scene,
add a node, load a sprite - by spawning a headless engine per call (250ms, 835ms for
`create_scene`). `godot-live` (`@satelliteoflove/godot-mcp`) reads and drives a RUNNING editor
over a WebSocket bridge at a flat 7ms: live scene tree, tilemap edits, input injection,
deterministic `freeze`/`step`. Measured in `tools/mcp_bench` - re-run it rather than trusting
these numbers. Neither does the other's job: `godot-live` cannot create a scene or add a node
at all.

**`godot-live` needs an addon this repo deliberately does NOT commit.** Enabling
`addons/godot_mcp` costs two things that were measured, not guessed. Its `plugin.gd` calls
`ProjectSettings.save()` to force an `MCPGameBridge` autoload, and **that save strips every
comment out of `project.godot`** - the QOA-importer note and the `config/game` refusal note
both vanished, and restoring them by hand did not survive the next build that loaded the
plugin. The forced autoload then either ships (+1MB in the pack, `exec_commands` included) or,
if excluded, makes every packed boot print three `Failed to instantiate an autoload` errors.
`--import` alone is safe; anything that loads the plugin is not. So install it on demand, use
it, and revert:

```bash
npx -y @satelliteoflove/godot-mcp --install-addon .   # then enable it in project.godot
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path .   # bridge on :6550
git checkout -- project.godot && rm -rf addons/godot_mcp                    # when done
```

The bridge runs headless - no editor window, despite what the addon's README says. With no
editor up, `godot-live` simply reports "not connected" and costs nothing.

Anything that needs the running game — the world, the player, the router — must be driven by
a `Qa` script rather than by `-s tools/x.gd`: in `-s` mode the autoload singletons are not
registered as identifiers, so a scene whose script names one will not even load.

## 5. Generated art and sound

`assets/generated/**` is output. Edit the rig (`data/rigs/*.json`) or the style
(`data/styles/*.tres`), re-run `gen_sprites.gd`, and commit both together — `check.sh`
regenerates and fails if the committed PNGs disagree with what the generator now produces.
Sound works identically: edit `data/banks/*.json` or `data/sounds/*.tres`, re-run
`gen_sounds.gd`, commit the WAVs.

**Commit the `.import` sidecar with every generated file.** An imported asset ships as its
sidecar plus the engine's cached copy; the original file is not packed, so a `.wav` or `.png`
without one works locally and is simply absent from the web build.

**The generator may not call `sin`, `pow` or `exp`.** IEEE-754 pins `+ - * /` to the same
result on every machine and libm pins nothing, so a transcendental anywhere in the render path
can make the committed bytes differ between this Mac and the Ubuntu runner — turning the drift
gate red for a reason nobody can reproduce. Waveforms are built from arithmetic and integer
noise, deliberately.

**The drift gate checks what `load()` returns, not just the file.** Godot's WAV importer
defaults to lossy QOA; `project.godot`'s `[importer_defaults]` pins it off, and
`gen_sounds.gd --verify` compares the imported stream too, because a file that matches while
the imported asset does not is a game whose every player hears something unchecked.
