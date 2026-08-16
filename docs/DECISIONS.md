# Decisions

Forks with real alternatives, recorded as they were made. The backlog at the top is the
one-glance menu of things still worth trying.

## Backlog — alternatives worth trying later

- **Grid-step movement** (one press = exactly one tile, tweened). Makes NPC pathing,
  triggers and tests exact. Revisit hook: `scripts/world/locomotion.gd` — it is already a
  pure function from input to velocity/facing, so a second mode is a sibling implementation
  plus a `movement_mode` field on `GameConfig`.
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
