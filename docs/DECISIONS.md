# Decisions

Forks with real alternatives, recorded as they were made. The backlog at the top is the
one-glance menu of things still worth trying.

## Backlog — alternatives worth trying later

- **An AI sprite source** (PixelLab or similar) for higher-fidelity art. Revisit hook:
  `scripts/spritegen/sprite_source.gd` — implement the interface, emit PNG + sheet.json,
  and the game does not change. Direction aliases for compass-named rows already exist in
  `scripts/util/dir.gd`.
- **A second cell size** (32×32 characters, 32px tiles). Revisit hook: `SpriteStyle`
  already carries `cell_size` and `tile_size`; the work is a rig authored at that size.
- **Tiled / LDtk map import.** Revisit hook: `scripts/world/map_data.gd` is the only thing
  that parses a map file; a second parser producing the same struct is the whole job.
- **Asymmetric side parts** (a satchel on one hip only). Blocked by
  `mirror_left_from_right`; revisit hook is the `left = flip_x(right)` branch in
  `sprite_compositor.gd`.
- **Slots that say WHY they cannot be loaded** ("unreadable" rather than "empty"). Revisit
  hook: `SaveManager._read` already computes the distinction and `peek()` discards it.
- **Using an item from the bag** (a general "Use" verb on the pause menu's item list). Still
  deferred after M13: `ItemDef.battle_heal` is the template's first and only use verb, and it
  is deliberately narrow — a potion heals in every RPG ever written, where "use the rope on
  the well" is a puzzle, and a template that grew a verb for the second one would be
  designing somebody's game. Revisit hook unchanged: `PauseMenu.confirm()` on the ITEMS page
  already returns `NONE` where the answer would go.
- **Flee odds, and damage variance.** M13 made both deterministic — a boss refuses every
  escape and everyone else allows it; a hit is worth exactly what the numbers say. A designer
  can reason about that and a QA script can rely on it. Revisit hooks: the flee branch in
  `BattleLogic.press()`, and `BattleLogic.damage()`.
- **A real title screen.** `Router.State.TITLE` has been reachable-by-design and unused since
  M2, and M13 pointedly did not spend it on the game-over screen. Revisit hook: the day a
  title scene exists, `GameOverScreen` becomes the thing that routes to it rather than an
  overlay over a dead world.

---

## Engine and language

- **Chosen: Godot 4.7 with typed GDScript.** The user's other 2D RPG (saltcharter) is
  Godot, so its headless gate, mutation harness and gdUnit4 setup transfer directly instead
  of being reinvented — and a template is worth most in the engine its owner actually
  reaches for.
- *Phaser 3 (TypeScript)* — rejected: batteries-included tilemaps and physics would have
  reached a first screen sooner, but Phaser's own patterns would then be the template, and
  headless testing of movement is much harder.
- *Vanilla TypeScript + Canvas* — rejected: everything would be ours and testable, but it
  means writing a renderer, a tilemap and a physics layer before writing a game.

## The sprite generator is procedural, with a source seam

- **Chosen: a code-native paperdoll rig, deterministic from a seed, behind a
  `SpriteSource` interface.** Consistency is the actual requirement, and a procedural rig
  gives it *by construction*: every character is composed from the same parts, the same
  palette ramps and the same outline rule, so they cannot drift apart. It is free, offline,
  reproducible, and every consistency rule can be a test.
- *AI-first (PixelLab / Retro Diffusion)* — deferred, worth trying: higher fidelity, and
  its `character_id` does keep one character consistent across its own animations. Rejected
  as the default because it needs an API key and credits, cannot be regenerated
  deterministically in CI, and a template that cannot build its own art offline is not a
  template. Revisit hook: `scripts/spritegen/sprite_source.gd`.
- *Layered LPC art (Universal LPC Spritesheet)* — rejected: excellent art, but it is
  GPL/CC-BY-SA licensed and locks the template to one visual style, which is the opposite
  of the goal.
- **Expected quality tier, stated up front:** clean GB/SNES-era chibi with a strict
  palette. Not hand-painted. Higher fidelity is a source swap, not a rewrite.

## Cell size is 16×24, not 16×32

- **Chosen: a 16×24 character cell on 16px tiles.** Planned as 16×32, changed while laying
  out the rig: a 24-row cell gives a head that is a clean third of the height (the chibi
  proportion that stays readable at 16px wide) with no dead space, and 24 = 1.5 tiles keeps
  characters and terrain in one size family. A 32-row cell left eight empty rows above every
  head that only a tall hat would ever use.
- *16×32* — deferred: worth revisiting if the template ever wants hats, helmets or long
  weapons that break the head line. Revisit hook: `cell_size` on the style plus the `at`
  offsets in the rig; nothing in code assumes 24.

## Slots that must share a colour, share it

- **Chosen: `slot_ramp_from` in the rig — sleeves follow the body, hands follow the head.**
  Randomised characters otherwise get pale hands on a dark face, which reads as a rendering
  bug rather than as a data one. An explicit ramp on the character still wins, so gloves are
  expressible.
- *One ramp per slot, always* — rejected: simpler, and produces a visibly broken cast the
  moment skin tone is randomised.

## Generated colours are computed in whole bytes

- **Chosen: `Color8` arithmetic for the tinted outline, not `Color.darkened()`.** An 8-bit
  image truncates a float channel while `Color.to_rgba32()` rounds it, so a float-derived
  colour reports one value and comes back out of the PNG one unit darker. The palette gate
  caught it on the tinted style's first run.
- *Loosening the palette gate to a tolerance* — rejected outright: a palette whose members
  depend on which side of the pipeline you ask is not a palette, and a gate with a tolerance
  cannot catch the next colour that leaks in.

## Rigs and stamps are JSON, not .tres

- **Chosen: `data/rigs/*.json` holding ASCII pixel grids.** Pixel art authored as text
  (`.` transparent, `1/2/3` = ramp tones) is readable and diffable in a way a binary or a
  `.tres` multi-line string is not, and it is the idiom that worked in the user's earlier
  jrpg-1 sprite module.
- *Resources (.tres) for parts* — rejected: multi-line string arrays in a `.tres` are
  hostile to edit by hand and produce unreadable diffs.
- *A dedicated editor* — deferred: the Sprite Lab scene shows the result; an editing UI is
  a project of its own.

## Free pixel movement, not grid-step

- **Chosen: free movement with four-direction facing**, axis-separated collision so walls
  slide. It feels better to move around in, and it is the model both of the user's earlier
  2D projects used.
- *Grid-step* — deferred, worth trying (see backlog): deterministic positions make triggers
  and tests exact, at the cost of a stiffer feel.

## Maps are data files, not scenes

- **Chosen: `data/maps/*.json` — ASCII rows plus a legend, built at runtime.** A map you
  can read in a diff and generate from a script is worth more in a template than one that
  needs the editor open, and it keeps "add a game" inside `data/`.
- *Editor-authored .tscn maps* — not rejected: `MapBuilder` accepts a PackedScene too, so a
  project that outgrows ASCII can keep the same spawn/warp plumbing.

## Committed art is PNG + JSON only

- **Chosen: the generator writes PNGs and a sheet JSON; `SpriteFrames` and `TileSet` are
  built at runtime.** A committed `.tres` referencing a texture that has not been imported
  yet breaks on a fresh clone, and it would weld the contract to Godot — the same PNG+JSON
  pair can feed any engine.
- *Committing SpriteFrames/TileSet resources* — rejected: faster to load, but it puts
  engine internals in the art pipeline and makes a fresh checkout order-dependent.

## CI installs Godot itself, with a pinned checksum

- **Chosen: download the official build and verify a SHA-512 pinned in the workflow.** A
  checksum served by the same host as the file cannot detect that host serving a different
  file, so the sum lives in the repo where a change to it is reviewable.
- *A third-party setup-godot action* — rejected: one more supply-chain dependency to
  SHA-pin and audit for a step that is four lines of `curl` and `sha512sum`.

## The web build is single-threaded

- **Chosen: `variant/thread_support=false`, pinned in the committed export preset.** A
  threaded web build needs `SharedArrayBuffer`, which needs the COOP/COEP cross-origin
  isolation headers — and GitHub Pages cannot send custom headers, so a threaded build would
  export successfully, deploy successfully, and then refuse to start in the browser. Godot
  4.3+ makes single-threaded the default and supported path for exactly this reason.
- *Threaded, hosted somewhere that can send headers* — deferred: better audio latency and
  real threads, at the cost of the demo no longer being one file in a repo. Revisit hook:
  `export_presets.cfg`, one line, plus a host that is not Pages.

## Deploy waits for CI rather than racing it

- **Chosen: the Pages workflow triggers on `workflow_run` of the check workflow, gated on
  `conclusion == 'success'`, and checks out that run's `head_sha`.** A plain `push` trigger
  runs the deploy *beside* the tests, not after them — which looks identical every day until
  the one where a red build ships. Pinning the SHA matters too: `workflow_run` checks out the
  default branch's HEAD by default, which is not necessarily the commit that was tested.
- *A `needs:` in one workflow* — rejected: it would couple the demo's slow template download
  to every PR's feedback time.

## The QA harness drives the real game

- **Chosen: an autoload that reads a JSON script and drives the running game.** Not a choice
  so much as a discovery: `-s tools/x.gd` cannot even *load* a scene whose script names an
  autoload, because singletons are not registered as identifiers in that mode. Anything that
  needs the real game must be driven from inside it.
- Two things it must do that were not obvious. Count **physics** frames, not idle ones —
  headless they run at wildly different rates, so "hold right for 30 frames" would mean a
  different distance on every machine. And press through `Input.parse_input_event`, not
  `Input.action_press` — the latter sets input *state* (what polling reads) and never
  delivers an *event* (what handlers read), so a harness built on it can move the player
  around perfectly and never press a button.

## Testing: gdUnit4, vendored, with a mutation harness

- **Chosen: gdUnit4 6.2.0 committed into `addons/`, run from the CLI, plus
  `tools/mutants.tsv`.** Vendoring makes a fresh clone runnable with no plugin install, and
  the mutation harness is what keeps the other gates honest.
- *Trusting a green suite* — rejected on the evidence: gdUnit4 exits 0 when a discovery
  crash means it ran nothing, so `check.sh` counts executed suites against suites on disk.

## Which game runs is a manifest resource, chosen by a precedence that refuses to guess

The fork: `world_scene.gd` held `demo_town`, `start` and `hero` as consts, so a second game
could not exist without editing the generic world. Where should those live, and what picks
between two games?

- **Chosen: a `GameManifest` resource per game in `data/games/`, selected by
  `--game=` > the `application/config/game` project setting > "there is exactly one".**
  A resource rather than loose settings because a game is a *set* of decisions that travel
  together, and because `config: GameConfig` can then be a real reference the exporter
  follows rather than a path string that fails at first step.
- *Extra fields on `GameConfig`* — rejected: `game_config.tres` is the numbers a designer
  tunes, and "which map do we start in" is not a number. Two games sharing one feel would
  also have had to duplicate every tuning value.
- *A `--game` argument only* — rejected: the exported web build has no command line, so the
  browser demo could never be anything but the default.
- *A project setting only* — rejected: the QA harness cannot edit `project.godot` on its way
  past, so a second game would only ever be reachable by walking to it through a warp.
- *Picking the first game when nothing chooses* — **rejected on the failure mode, which is
  the whole point of the entry.** Booting the wrong game does not present as a selection
  bug; it presents as the game you meant to run behaving strangely, and you go and debug
  that. Refusing costs one line of config and is unmistakable.
- *A title screen that lists the games* — `deferred — worth trying`. It is the friendly
  version of the same choice and needs `Router.State.TITLE` to actually be entered, which
  nothing does yet. Revisit hook: `scripts/data/game_select.gd::ids()` already returns
  exactly the menu such a screen would show.

## Game code lives in `games/`, is reached through `GameHooks`, and never names an autoload

The fork: the template had nowhere to put gameplay. Every new mechanic landed in
`world_scene.gd` — the file whose entire job is to be game-agnostic — and `ARCHITECTURE.md`
said so out loud ("new mechanics → new files under `scripts/`").

- **Chosen: a `GameHooks` subclass under `games/<id>/`, named by the game's manifest, handed
  a `GameContext` rather than the autoloads.** One name in data resolves to one object with
  one lifecycle, it is a `RefCounted` testable with no scene tree, and `on_interact`'s
  return-`bool` shape is what a battle or a shop would need later without re-cutting the seam.
- *A per-kind handler registry that game code registers into* — rejected: something has to
  run before anything can register, and the only "runs at boot" slots are autoloads or
  `world_scene._ready`, so it needs the hooks seam as its bootstrap and you end up with two
  mechanisms. `deferred — worth trying` as an internal shape once a game outgrows a `match`;
  hooks can hold one privately. Revisit hook: `GameHooks.on_interact`.
- *A script path per map or per object in the map JSON* — `deferred — worth trying` as an
  escape hatch, rejected as the primary seam: the interesting state is cross-cutting ("she
  reacts because you opened the chest"), so it routes through flags anyway and the flag
  vocabulary ends up spread across a dozen files with nowhere to validate it. It is also the
  hardest to gate — there is no single function whose absence a mutant can prove.
  Revisit hook: `Interaction.resolve`, which already takes hooks as a parameter.

The **no-autoload** rule is the load-bearing half, and it is mechanical rather than stylistic.
`--check-only` and `tools/compile_all.gd` both skip any script naming a singleton, so game
code reaching for `GameState` would leave two of the four gates without saying anything.
`GameContext` is therefore a snapshot plus an effect list — the `DialogRunner` pattern, which
collects flags and lets the caller apply them — and `LintCore.RULE_AUTOLOAD` fails the build
rather than a doc paragraph asking nicely.

Three things stayed deliberately untouched, each with the reason it would have been the wrong
work now:

- *`Router`* — it owns input, not scenes, and does that correctly. `TITLE` and `PAUSED` are
  unreachable because no title screen or pause menu exists: a missing feature, not a broken
  router. (Its `state_name()` is a positional array literal that would mis-name every state
  if a member were ever inserted — `deferred — worth fixing`, revisit hook `router.gd:27`.
  **Both fixed in M10**: the pause menu reaches `PAUSED`, and the name is derived from the
  enum.)
- *Dialog effects* — conditional nodes, `clear_flag`, item/warp/sound nodes. An NPC reacting
  to what you carry is three lines of game code (`ctx.say(a if ctx.has_flag(k) else b)`), and
  `set_flag(key, false)` gives clearing for free. Inventing a mini-language instead would
  have proven nothing about whether the hooks seam works, which is the point of the milestone.
  `deferred — worth trying`; revisit hook `dialog_runner.gd::_go_to`.
- *`SaveData`* — a quest is expressible in `flags` and `seen`, both already typed, persisted
  and migrated. Adding a per-game dictionary is purely additive later and does not re-cut
  this seam. `deferred`; trigger: the first game that needs a count rather than a boolean.
  **That trigger fired in M12** — see "Items are the template's business after all".
  (A `game` FIELD landed in M10 for a different reason — see below — but the per-game
  dictionary is still deferred on the same terms.)

## The second game lives in this repo rather than in one that consumes the template — *superseded in M11*

The fork: the template's claim needed testing by building something else on it. Where should
that something else live?

- **Chosen: `data/games/quest.tres` plus `games/quest/`, beside the demo, in this repo.** CI
  runs both games' play sessions on every push, the gates cover the second game's content the
  same way they cover the first, and the acceptance criterion is checkable — the commit that
  adds the game must not touch `scripts/`, `tools/` or `scenes/`, which `git diff --stat`
  answers. It also makes the repo a worked example rather than a description of one.
- *A separate repo that pulls the template in* — `deferred — worth trying`, and it tests
  something this cannot: **starting from the template**, which is the actual use case. Cloning,
  renaming, deleting the demo, and finding out what breaks is a different question from
  "can a second game coexist". Not done now because template fixes would have to be ported
  back by hand, and CI could not see the result. Revisit hook: `data/games/` — a game is
  already a self-contained set of files, so lifting one out is a copy rather than a surgery.
- *A branch, or a throwaway spike* — rejected: a spike answers the question once and then
  rots, and nothing keeps the answer true. The point of the exercise is a claim that stays
  checked, which needs the second game in CI.

What it found, which is the argument for having done it at all: three template defects that
six milestones of unit tests, mutants and gates had not — a QA op that raced the steps after
it, an art gate that walked a different set of directories than the game did, and three
disagreeing lists of "which directories does this project own".

## Nothing choosing a game asks a human, rather than refusing — *superseded in M11*

M7 decided that two games with nothing choosing between them is a **refusal**, because a
guessed game presents as the game you meant to run behaving strangely. That was right, and it
was right for a reason with an expiry date: there was nobody to ask. This is that entry
landing, and it does not overturn the decision so much as finish it.

> **Superseded.** One game ships as of M11, so there is nothing to choose between and the
> picker was deleted with the second game. The precedence it consumed is unchanged, and the
> refusal below is what a second game would meet again. Kept for the reasoning, not as
> current behaviour.

- **Chosen: the picker is what happens when `GameSelect.should_ask()` is true** — more than
  one game, and neither `--game=` nor the project setting nor "there is only one" having
  answered. `choose()` is untouched, so the precedence stays one pure function in one file,
  and the picker is a new *consumer* of its "nothing chose" answer rather than a competing
  rule. Everything that already chose still skips the menu, which is why all seven scripted
  play sessions run unchanged.
- *A picker that always appears at boot, with `--game=` skipping it* — rejected: it makes the
  project setting mean "preselected row" instead of "the game that boots", and a template
  cloned down to one game would show a menu with one entry in it.
- *Reaching the picker only through Tab, leaving boot alone* — rejected: the deployed page has
  no command line and no Tab-before-you-start, so the one surface where choosing matters most
  would be the one surface that could not.
- *A separate title scene, swapped to with `change_scene_to_file`* — `rejected — for now`. It
  would fix the four build-once guards for free by rebuilding the world from scratch, but it
  is the repo's first ever scene change, `Router` deliberately owns input rather than scenes,
  autoloads survive a swap so `GameState.reset()` is still needed, and the deferred-frame
  timing is a new source of races for a QA harness that steps in physics frames. The overlay
  costs one `CanvasLayer` and a teardown that is testable in one file.

**The setting ships empty**, which turned two gates red and both fixes were improvements:
`smoke_boot` now validates *every* shipped manifest rather than only the one that boots — with
a picker, every game is reachable from the first screen — and `test_game_select` asserts the
project either boots a game or offers one, which is the real property.

Closing the M7 note that pointed at `GameSelect.ids()` as the revisit hook: a menu needs
titles, start maps and characters, so it is built on `manifests()` and `unresolved()` instead.

## A second game varies only what its design demands

The Barred Gate shipped with a `GameConfig` of its own, whose only difference from the
template's was `allow_diagonal = false` — "the pure four-direction feel of the earliest
top-down RPGs". The reasoning was fine. The decision was not mine to make quietly.

The user found it in the first minute of playing and asked the right question: *what else is
missing?* That is the real cost. A second game exists to **isolate** what building a game
actually changes, and every gratuitous difference destroys that: once one thing differs for no
reason the design asked for, the player cannot tell a deliberate choice from a defect, and the
control instance has stopped being a control.

- **Chosen: The Barred Gate shares `data/game_config.tres`, and `dusk16` matches `gb16`'s
  animation timing exactly.** The only axis the second game moves is colour — palette and
  outline. Anything that feels different from now on is a bug, by construction.
- *Keep the four-direction feel as a shipped design choice* — rejected. It is a good idea for
  some game; it is a bad idea for the one whose job is to hold everything else constant.
  A game that wants it sets one field, and `GameConfig.allow_diagonal` is still there for it.
- *Keep `dusk16`'s slower gait* — rejected for the same reason, though it was the more
  defensible of the two: `STYLE_GUIDE` does list timing as a style axis and `nes16` varies it.
  But the game wearing `dusk16` is the control, so its style is a control too.

The rule this leaves: **a game brings its own config when its design needs one, not to have
one.** `GameManifest.config` is still per-game — the capability is the point of the seam — and
`docs/ARCHITECTURE.md` now says when to use it.

`tests/fixtures/qa/quest/walk_diagonally.json` is the gate. Every one of the seven play
sessions that existed held a single direction at a time, so none of them could see this — the
new one holds two and requires both axes to move.

## Grid stepping is a distance in the config, and it has no clock

One press = exactly one tile, tweened, instead of free pixel movement. The first item in this
file's backlog, now built.

- **Chosen: a pure `GridWalker` beside `Locomotion`, one per actor, selected by
  `GameConfig.grid_step_pixels > 0`.** The direction still comes from `Locomotion.step()`, so
  `allow_diagonal` and the ties-go-horizontal rule have one implementation between the two
  modes rather than two that drift.
- *A second implementation of `Locomotion.step()`* — which the backlog entry and
  `locomotion.gd`'s own comment both promised — **rejected once it was looked at.** `Locomotion`
  is static and an actor holds only its facing, so there is nowhere to keep how far through a
  step it is. The per-actor state was the entire cost, and the comment has been corrected.
- *A `movement_mode` enum* — rejected: no enum exists in any `scripts/data/` resource,
  `camera_smoothing > 0.0` sets the "zero means off" precedent, and an enum would leave the
  step *distance* homeless. An actor holds a `GameConfig` and never the map's `SpriteStyle`, so
  the distance has to live with the selector or be plumbed through `setup()`.
  `GameManifest.problems()` checks the step against the start map's tile size, which is the one
  place both facts are in scope.
- *Landing the step by predicting distance-per-frame* — rejected on measurement.
  `move_and_slide()` picks its own delta (physics inside a physics frame, idle otherwise), so a
  prediction overshoots in exactly the hand-driven loop the integration tests use. A step ends
  when its target stops being *ahead*. `test_engine_assumptions.gd` pins that engine fact.
  The cost is that a step's duration quantises to whole frames — up to one frame per cell,
  invisible and consistent, where a mispredicted landing would be neither.
- *A pause between steps* — `rejected — not built`. Continuous walking under a held key is the
  expected feel, and a pause of three frames or more makes any "N still ticks means blocked"
  helper report blocked in open ground.
- *Input buffering* (a direction tapped mid-step being remembered) — `deferred — worth trying`.
  Today a tap during a step is lost and a direction still held when one ends is picked up on
  that same call, so there is never an idle frame between steps. Revisit hook: `GridWalker.plan`,
  which already sees the input every frame and could latch it.

**No shipped game uses it.** `data/game_config.tres` keeps free movement, both manifests keep
sharing it, and not one of the 8 QA fixtures changed — about 10 of their steps encode
"N frames = M tiles" arithmetic that grid mode would void. The honest gap: the scripted play
gate never exercises the mode. It is covered by 21 unit cases and 8 integration cases driving a
real body into real walls, plus 15 mutants.

A blocked diagonal **slides** along its free axis rather than stopping dead, matching
`move_and_slide` and the existing diagonal-slide gate. It is free here: the grid is
axis-aligned, so the slid-to position is itself a cell centre.

## Saves are per game, and a file must agree with the directory it sits in

The fork: two games ship in one build, sharing this save format and these field names. Whose
progress is `slot_0.json`?

- **Chosen: `user://saves/<game>/slot_N.json`, and the save NAMES its game.** "Slot 1" then
  means one thing — the first slot of the game you are playing — and the pause menu lists only
  slots it could actually load. The name inside the file is checked against the directory on
  every read, so a file copied, moved or hand-edited into the wrong game is refused and parked
  rather than loaded. That check is the point: a demo save loading into the quest does not
  present as a mismatched file, it presents as the quest being broken, and you go and debug
  the quest.
- *Shared slots that switch game on load* — `deferred — worth trying`: one list, and loading
  a slot boots the game it belongs to. Rejected for now because a load becomes a full teardown
  and boot rather than a map entry, and the slot list has to render every game's palette and
  character to be readable. Revisit hook: `world_scene._commit_load`, which would call
  `start_game(manifest)` before `restore(data)`.
- *One flat namespace with the game stored inside* — rejected: the slot numbers still collide,
  so "slot 1" means whatever was saved there last, and the menu has to filter a list whose
  numbering then has holes in it.

### The v2→v3 step takes the game as an argument

A file older than v3 cannot say which game it is; the directory it was found in is the only
evidence there is. So `Migrations.apply(raw, game)` takes it as **data**, which keeps every
step a pure function of `(file, game)` — the frozen-forever property a migration needs.

- *An adopting loader* (fill the field in from the caller after migrating) — rejected: it
  makes "this file said nothing" and "this file said the right thing" the same case, so the
  cross-check that catches a misfiled save can never fire on an old one.
- *Refusing everything below v3* — rejected: the chain exists precisely so old saves survive,
  and refusing them makes `supported_versions()` a lie.

### A scripted session saves under `user://qa_saves`, wiped at boot

`SaveManager.dir_for()` reads the command line: any `--qa-script=` and saves go to a separate
directory, emptied on start. A play script that wrote to the real one would overwrite a
player's progress on a machine that has both, and one that READ from it would pass or fail
depending on who ran it. The QA fixture leans on this directly — it opens Load on an empty
slot and requires the refusal, which is only deterministic because the directory is known
empty.

- *A fresh temp directory per run* — rejected: it leaks one directory per run, and nothing
  ever proves the run started clean; wiping a fixed known path is checkable.

### Reading the slot list has no side effects

`peek()` is a separate, silent read: no `save_changed`, no parking, no `push_error`. Merely
LOOKING at the pause menu must not produce `.corrupt` files. The consequence is that an
unreadable slot is drawn as *empty*, which is why `save()` parks whatever it is about to
overwrite — otherwise the menu, which refuses to load an "empty" slot, could never park a
damaged one but could silently save over it.

- *Distinguishing empty / unreadable / another game's in the list* — `deferred — worth trying`:
  a row reading "Slot 2: unreadable" is more honest than one reading "empty". It needs a
  tri-state return where there is currently a nullable one. Revisit hook: `SaveManager._read`
  already computes exactly that distinction and throws it away at the boundary.

## The pause menu is Resume / Save / Load, and Escape is what opens it — *Items added in M12*

The fork: a pause menu is where a game puts everything that is not playing. What goes on it?

> **Amended in M12.** A fourth row, **Items**, sits directly after Resume: it is the row a player
> opens most often, and Save/Load keep their order relative to each other. The cost was one that
> only a mutant found - `test_pause_and_saves`' navigation helper counted two presses to reach
> Load and silently became a SAVE, quietly writing a slot in the middle of a test about refusing
> to load one. Any test that navigates a menu by counting is a test that re-aims itself when a
> row is inserted; those now name the row (`move(PauseMenu.Row.SAVE)`) rather than counting to it.

- **Chosen: three rows, and Escape opens it from the world.** Save and Load are the reason it
  exists; everything else on a typical pause menu is either already a keypress here or is a
  feature this template does not have yet. Escape (`cancel`) was the one bound action the world
  did not handle.
- *A "Switch game" row* — `deferred`: with one game there is nothing to switch to, and the
  row would come back with the second game rather than before it.
- *Settings (volume, window, bindings)* — `deferred — worth trying`: none of the three have
  anywhere to be stored yet. `AudioBus` is the seam a volume row would use.
- *Quit* — rejected: the web build cannot honour it, and a menu row that does nothing on one
  of two shipped platforms is worse than no row.

The pure/view split is `DialogRunner`/`DialogBox`'s exactly: `PauseMenu` is a cursor over pages
and slots with no nodes in it, `PauseScreen` paints it from a `SpriteStyle`. Opening a slot
page returns `NONE` — changing what is on screen is not something the world has to act on —
which is what keeps "arriving at the save list" from writing slot 0.

### Loading an empty slot is refused, not clamped

`PauseMenu.confirm()` on an empty LOAD row returns `NONE`. The precedent is
`DialogRunner.choose()`: clamping to the nearest filled slot turns a UI mistake into a
plausible-looking wrong answer, and here the wrong answer is loading a game the player did not
ask for. Saving is not symmetric — an empty slot is exactly where a save goes.

That refusal is also the first of two fail-closed layers for a misfiled save, and it fires
first: a save that does not read back reads as **empty**, so the menu never offers it. The
loader's own check is the second, and the only way to reach it through the menu is for a slot
to go bad between the frame that drew it and the frame that loaded it. That is the case the
integration suite stages, because it is the only one that exercises the screen's latch.

### The screen latches when it answers, and a refusal has to un-latch it

`PauseScreen` stops accepting input the moment it has emitted `resumed` or `load_requested`,
because a load rebuilds the world one frame later and a second press in that window would
answer a question already settled. The cost is that a load which comes back *refused* must
clear the latch — otherwise the menu sits there looking perfectly normal with every key dead,
and the only way out is killing the game. A mutant covers exactly that line, and it survived
the first time it was run: the test drove the refusal through the signal, which skips the
latch entirely. Driving it through real keypresses is what made the rule real.

## One game ships, and the picker went with the second one

The fork: the repo was called `sprite-generator` and shipped two games — a demo town and a
quest — with a picker to choose between them. The name described one feature of a project that
had become something else, and the second game had done its job.

- **Chosen: merge both worlds into one game, delete the picker, rename to `rpg-template`.**
  The demo's town and cave became the road into *The Barred Gate*, re-styled to `dusk16` with
  three new character specs; `data/games/demo.tres`, `GamePicker`, `GameMenu` and
  `GameSelect.should_ask/unresolved/switchable` are gone. What a visitor now meets is a game,
  not a menu asking which demo they would like.
- *Keep both games* — rejected: the second game was **proof**, not content, and it had already
  produced its findings (three template defects, plus the feel-parity correction). Kept, it is
  two worlds to maintain, two art sets to regenerate, and a first screen that asks a question
  nobody visiting a template wants to answer.
- *Keep the picker for a future second game* — `deferred — worth trying`: it is a real feature
  and it worked. It is deleted rather than left dormant because an unreachable screen rots
  quietly. **Revisit hook:** `GameSelect.choose()` still returns `""` for "more than one game
  and nothing chose", and `world_scene._ready()` is where a picker would consume that answer
  again — the seam it plugged into is intact, only the consumer is gone.

**What was given up, stated plainly.** The template's claim used to be checkable: *a second
game was added without touching `scripts/`, `tools/` or `scenes/`*, provable with
`git diff --stat`. That proof is now history rather than something CI re-runs. The seams it
tested are all still exercised — `GameHooks` by the warden, `GameManifest` by the boot,
`start_game`/`_teardown_game` by `restore()` and by `test_game_switch` — but nothing standing
in the repo re-proves the claim end to end. The honest replacement is the deferred item that
was always the stronger test: **a separate repo that consumes this one.**

### The road between the two worlds

The town and the village are joined by one door each, both anchored on a wall rather than on a
tile count: the village's is the south-east corner of its own east wall, the town's is the one
gap in its north wall. Every QA script that crosses them holds a direction into a wall and lets
the geometry stop it, so the scripts say "walk until something stops you" rather than "walk
4.5 tiles" — which is the difference between a fixture that survives a map edit and one that
does not.

The demo's NPCs needed `dusk16` art, and a character exists for exactly one style
(`CharacterSpec.style_id`). So `town_elder`, `town_kid` and `town_smith` are new specs with the
same seeds as their `gb16` originals — same parts, new palette, which is the style-swap the
generator exists to make free. `gb16` and `nes16` and their eight specs stay: they are what
`test_gates_consistency` compares styles across, and what Sprite Lab shows.

## Items are the template's business after all

The fork: the quest's key was a boolean flag, and `interaction.gd` said in as many words that
"items with names and counts… belong in a game's own hooks". Making the quest about *carrying*
things meant either building an inventory inside `games/quest/` or reversing that.

- **Chosen: items are a template noun.** `ItemDef` + a pure `Inventory`, `give_item`/`take_item`
  as effects, and `requires_item` beside `requires_flag` on objects, warps and dialog choices.
  The reversal is honest rather than reluctant: a key, a coin, a potion and a quest token are one
  mechanism wearing four names, and `docs/DECISIONS.md` had already written down the trigger for
  this — "the first game that needs a count rather than a boolean". Every game re-inventing the
  same dictionary-of-counts is exactly what the template exists to stop.
- *Keep it in the game's hooks* — rejected: it works, and the second game to want items writes it
  again, differently, with its own save-migration bug. The line the template still does not cross
  is prices, hit points and turn order — the moment a map file needs a type system, the template
  has started designing somebody's game.
- *A `kind` on an object plus game code* — rejected: it moves the vocabulary into a string the
  template cannot validate, so a typo becomes a silent no-op instead of a content error.

### No stack limit, and no "use" yet

A cap would let a pickup FAIL, and a chest marked `once` has already recorded being opened by the
time the give is applied — so a full bag eats the key and the door stays shut with nothing on
screen saying why. Unbounded counts cannot produce that; a game needing a cap enforces it in its
own hooks, where it can also say so. "Use" is `deferred — worth trying`: it needs a verb per item
and an effect vocabulary for what using does, which is a design decision no shipped item needs
yet. Revisit hook: `PauseMenu.confirm()` on the ITEMS page returns `NONE` where that answer goes.

### A take implies a requires

`Interaction.decide` and `DialogRunner._visible_choices` both refuse *before* appending any
effect when a `take_item` cannot be covered. Without that rule the take is emitted, fails at the
sink, and the `mark_seen` beside it still lands — a chest that is spent and gave nothing, which
looks like a lost item rather than a bug. It also makes an effect list all-or-nothing, so a
failure at the sink means a hook is wrong rather than a player being unlucky.

### Gifts live on choices, never on nodes

A dialog node has no condition and no memory of having been entered, so a conversation that loops
back through a gift node hands over a second key every pass. A choice can carry `set_flag X` and
`hidden_if_flag X` naming the same flag, which is "taken once, offered never again" — and
`_visible_choices` counts flags earned *earlier in this conversation*, because nothing has been
written to the game state until the box closes.

- *Node-level `give_item`* — rejected: it reads as the obvious place to put it and is a
  duplication bug waiting for the first looping conversation.
- *A `once` on a dialog node* — `deferred`: it is a second memory to persist and migrate, for a
  case the flag pair already covers.

### The dialog's second sink is gone

`_on_dialog_closed` used to write flags to `GameState` directly, which was fine while a
conversation could only earn flags. It now emits the same effect dictionaries a hook does and
goes through `_apply_effects` — one vocabulary, one place to look for "what does this actually
do", and one place that has to learn a new op.



## Hit points and turn order are the template's business after all — *M13*

`scripts/world/interaction.gd` has carried this sentence since M12: *"Prices, hit points and
turn order are still over the line - the moment a map file needs a type system, the template
has started designing somebody's game."* M12 wrote it while moving **items** across that same
line, on the grounds that "a count rather than a boolean" is the one noun every game
re-invents. M13 makes the identical argument one level up and moves hit points and turn order
too.

**The fork.** Where does a battle system live?

- **In the template, with all content as data** — `BattleLogic` beside `DialogRunner`,
  `EnemyDef`/`CombatDef` beside `ItemDef`, encounters as a map record. *Chosen.* Every RPG
  built on this thing would otherwise rewrite "a number that ticks down, a number that ticks
  up, and whose turn it is" — each with its own save-migration bug, its own idea of what a
  seeded damage roll is, and its own untested defeat path.
- **In `games/<id>/`, as that game's own code.** Rejected for the reason the second game
  would prove: it would re-invent HP from scratch, and the first thing it would get wrong is
  the save. This is the items argument verbatim.
- **A `kind: "enemy"` on an NPC record plus hook code.** Rejected: the template cannot
  validate a vocabulary it does not own. A misspelt enemy id would be an NPC that simply does
  nothing, where `enemy_refs()` makes it a build failure.

**Where the line is now.** Over it: *economy* (prices, shops, currency) and *battle
scripting* — what a particular boss does on turn three is a game's own business, and
`GameHooks` is where it goes. Under it: the numbers, the turn order, and the screen.

**What that bought, concretely.** "A beaten enemy stays beaten" is the same map-scoped `seen`
key an opened chest already used, so it persisted and migrated for free. A battle's results
go through `world_scene._apply_effects` like every other effect, so there is still exactly one
place where anything reaches live state.

**Retuned after play, M13.1.** The first timing values shipped without anyone playing the
game, and the user's verdict on the live build was one sentence: *"way too fast for human
reaction."* They were right, and the reason is structural rather than a matter of taste — the
`!` lights exactly WHEN the window opens (`cue_on()` is the same comparison the press is
judged by, deliberately, so the screen and the rule cannot drift), so the window is not a
margin around a beat the player already saw coming: it *is* the entire reaction budget. Eight
frames is 133ms against a human's ~250ms. The window went to 24 frames and the cues to 72/84
to keep the window a small fraction of the wind-up. Nothing about balance moved, because the
window is not in the damage arithmetic. The lesson generalises past this game: **when a cue
and its window open together, size the window for REACTING, not for precision** — and a feel
number that no test can judge needs a human before it ships, not after.

## No fact a player needs may be single-sourced in optional dialog — *M13.2*

A play-test of the live build ended with the tester holding a flask of lamp oil, told about a
key they never found, and asking how the quest was supposed to be played. Nothing was broken.
Every gate was green. The data was built that way.

**What the audit found.** Classifying each of the eleven facts a player needs by how reachable
its statements are — FORCED (unavoidable on the critical path), LIKELY (a refusal fired by an
obvious attempt), OPTIONAL (needs pressing something skippable) — turned an argument about
taste into a list of defects:

- Two facts were stated **nowhere**: that the key is under the hollow's one bush, and that the
  ending is walking back to the warden.
- "The key is in the hollow, west" was OPTIONAL and **single-sourced** in the warden's dialog,
  and she is a static figure two tiles off the spawn with nothing to make you press her.
- Every statement of what the oil is FOR sat **downstream of the key** — one line requires
  carrying it, the other requires being inside the keep — while the oil itself was obtainable
  in the first minute, ungated. Getting oil first is a legal, natural, unpunished order that
  produces an item the game will not explain until you have solved the other half.
- The line carrying four facts at once (lantern dry / oil exists / hermit has it / cave east
  of town) was **destroyed by progress**: the hook's priority puts `was_seen(keeper)` above
  `has_item(key)` forever, so beating the Keeper first deleted it from that save permanently.
- Both refusals were dead ends. `gate_barred` never said "key"; `lantern_dry` never said "oil".

**The rule now.** No fact a player needs may be single-sourced in optional dialog. Every
refusal names what it wants and points somewhere. An item obtainable before its purpose is
statable carries its purpose at pickup. And a conditional line that can be permanently
outranked must have its facts repeated by the line that outranks it.

**The fork: how does the premise reach the player?** Chosen — **the opening conversation is
forced** (`GameHooks.on_map_entered`, guarded by a flag the dialog's own first node sets). A
quest whose premise is optional is one most players never learn they are on, and the genre has
opened this way since the eighties. What falls out for free from state that already exists: a
load does not replay it (`restore()` is state first, then `enter_map`), and Start Again after
a defeat does — which is right, because that is a new run of the story.

*Rejected — gating the hermit's oil on quest knowledge* (`requires_flag`, so the choice is
hidden until you know the lantern is dry). It enforces the intended order and would have made
the tester's confusion impossible, but at the cost of sending them back across two maps for a
flask they had already been shown. Making the world explain itself beats making the world
withhold. Revisit hook: the choice list in `data/dialog/hermit.json`.

*Rejected — reordering the hook so `has_item(key)` outranks `was_seen(keeper)`.* It would have
saved the lost line, but the priority order is correct as a matter of story — the warden should
react to the Keeper being gone before she reacts to a key. Fixed by redundancy instead: the
outranking line now carries the outranked one's facts.

## Game over is an overlay, and TITLE still means nothing — *M13*

Losing had to go somewhere. The user asked for "game over → title".

- **A `GAME_OVER` overlay offering Continue and Start again.** *Chosen.* It reuses the slot
  machinery the pause menu already had, and boot stays world-first — which eight play scripts
  and every integration suite assume.
- **Reusing `Router.State.TITLE`.** Rejected. TITLE has meant "nothing to drive yet" since
  M2, and it is the state the router boots in; making it also mean "the run ended" would give
  one honest state two meanings, and `state_name()` feeds QA assertions directly.
- **Building a real title scene.** Deferred, not rejected — see the backlog. It is a
  milestone of its own (a new scene, a boot path that does not go straight into a map, and a
  New Game flow that is more than `start_game` re-entry), and doing it badly to host a
  game-over screen would be the tail wagging the dog.

The honest caveat, recorded because it will be asked: this is not a title screen, and the
game still cannot be quit to anything. It is the minimum that makes losing mean something —
your save matters, and a fresh run is genuinely fresh.
