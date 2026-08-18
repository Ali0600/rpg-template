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
  if a member were ever inserted — `deferred — worth fixing`, revisit hook `router.gd:27`.)
- *Dialog effects* — conditional nodes, `clear_flag`, item/warp/sound nodes. An NPC reacting
  to what you carry is three lines of game code (`ctx.say(a if ctx.has_flag(k) else b)`), and
  `set_flag(key, false)` gives clearing for free. Inventing a mini-language instead would
  have proven nothing about whether the hooks seam works, which is the point of the milestone.
  `deferred — worth trying`; revisit hook `dialog_runner.gd::_go_to`.
- *`SaveData`* — a quest is expressible in `flags` and `seen`, both already typed, persisted
  and migrated. Adding a per-game dictionary is purely additive later and does not re-cut
  this seam. `deferred`; trigger: the first game that needs a count rather than a boolean.

## The second game lives in this repo rather than in one that consumes the template

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

## Nothing choosing a game asks a human, rather than refusing

M7 decided that two games with nothing choosing between them is a **refusal**, because a
guessed game presents as the game you meant to run behaving strangely. That was right, and it
was right for a reason with an expiry date: there was nobody to ask. This is that entry
landing, and it does not overturn the decision so much as finish it.

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
