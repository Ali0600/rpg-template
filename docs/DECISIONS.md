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
- **`MOTION_MODE_FLOATING` for actors** — Godot's recommended mode for top-down, and a
  cleaner answer to the NPC-carry bug than the narrow opt-out that shipped. It changes how
  every body slides along every wall, so it needs playing rather than proving. Revisit hook:
  one line in `ActorBody._init`.
- **A real title screen.** `Router.State.TITLE` has been reachable-by-design and unused since
  M2, and M13 pointedly did not spend it on the game-over screen. Revisit hook: the day a
  title scene exists, `GameOverScreen` becomes the thing that routes to it rather than an
  overlay over a dead world.

---

## NPC movement freezes with the player, and the brain is pure

- **Chosen: `NpcBrain`, a pure class answering with an intent vector, driven from
  `world_scene._physics_process` BELOW the `player_can_move()` gate.** The intent vector is
  what makes it cheap: `ActorBody` already handles both movement modes, animation and the
  step meter, and its own header always said the player and every NPC "differ only in what
  drives them". This is the other driver, and no movement code was written twice.
- *A Node per NPC with its own `_physics_process`* - rejected: it would move on its own
  schedule, which means a second answer to "is the world running" and a speaker who can
  wander off mid-sentence unless something remembers to pause her.
- *Freeze only the SPEAKER during dialog* - rejected: the halt-to-face done when a
  conversation opens would silently stop being true for everyone else, and a town walking
  behind a dialog box while the player cannot move reads as the game having lost the input,
  not as ambience. Freezing everything is one line's placement and covers pause, battle and
  game-over for free. Revisit hook: the `_drive_npcs()` call site.
- *Behaviours as a game hook rather than map data* - rejected: patrol and wander are RPG
  vocabulary, not one game's design. A hook would mean every game writes movement code.
- **A typo'd behaviour fails the build.** Falling back to `static` would make `"wonder"` look
  like a shy NPC rather than a misspelling, and nothing on screen would ever say otherwise.
- **Every shipped NPC stays `static`,** because seven of ten QA sessions use their bodies as
  walls. Movement ships as new content placed where no session walks - a constraint found by
  reading the sessions, not by assuming.

## Two Godot MCP servers, and the addon stays out of the repo

- **Chosen: add `godot-live` (`@satelliteoflove/godot-mcp`) beside `godot`
  (`@coding-solo/godot-mcp`) in `.mcp.json`, and do NOT commit its editor addon.** The bench
  (`tools/mcp_bench`) settled the first half: they are complements, not competitors. One
  scaffolds and spawns a headless engine per call (250ms; 835ms for `create_scene`); the other
  reads and drives a running editor over a WebSocket bridge at a flat 7ms and cannot create a
  scene at all. Two entries cost nothing - with no editor running, `godot-live` reports "not
  connected".
- *Also commit and enable `addons/godot_mcp`* - **rejected on measurement.** Its `plugin.gd`
  calls `ProjectSettings.save()` to force an `MCPGameBridge` autoload, and that save **strips
  every comment from `project.godot`**: the QOA-importer explanation and the `config/game`
  refusal note both disappeared, and restoring them by hand did not survive the next build
  that loaded the plugin. Those comments are load-bearing - CLAUDE.md cites both. The forced
  autoload is then a second problem with no good side: leave the addon in the pack and it
  ships (+1MB, `exec_commands` included); exclude it and every packed boot prints three
  `Failed to instantiate an autoload` errors, which is exactly the log noise #41 removed.
- *Replace `godot` with it* - rejected: it has no `create_scene` and no `add_node`, so
  scaffolding would be lost outright.
- **Not a security problem, checked rather than assumed.** The bridge autoload gates on
  `EngineDebugger.is_active()` and speaks the debugger protocol rather than opening a port,
  so it is inert in a release export even though it ships. The addon's own source says so and
  the packed run confirms it. The objection is comment loss and log noise, not RCE.
- **Deferred - worth revisiting** if the addon gains a way to run without registering the
  autoload, or if `project.godot` stops carrying documentation worth losing. Revisit hook:
  `_ensure_game_bridge_autoload()` in `addons/godot_mcp/plugin.gd`, and the on-demand recipe
  in CLAUDE.md.
- **`npx` launch kept** for both, despite `npx` costing 494ms to connect against 64ms for a
  resolved binary. A direct path is machine-specific or an npx cache path that can be
  garbage-collected; portability beat 430ms once per session.

## The NPC carry was fixed narrowly, not by switching motion mode

- **Chosen: `platform_floor_layers = 0` on every ActorBody.** A player found NPCs being
  dragged sideways when he walked past them - but only when they approached from ABOVE. The
  cause is the moving-platform feature: `on_floor` against a moving body inherits its
  velocity, measured at 0.8px a frame (exactly walk speed) until the NPC was two tiles off
  her route. Clearing the layers opts out of exactly that and changes nothing else.
- *`MOTION_MODE_FLOATING`* — **deferred, worth trying**: it is what Godot recommends for
  top-down and it removes the floor/ceiling concept the bug is built on, rather than one
  feature that hangs off it. Rejected for now because it is not a bug fix, it is a movement
  change: floating alters how every body slides along every wall, and all eleven play
  sessions are calibrated against the current sliding. Switching it diverged
  `finish_the_quest` at the hermit and cascaded into 16 failures - none of them about NPCs.
  Whether the resulting slide feels better is a question for someone who has played it.
  Revisit hook: one line in `ActorBody._init`, plus re-deriving the affected legs.
- *Collision layers, so actors never touch* — rejected: the player would walk through NPCs,
  and seven QA sessions use NPC bodies as walls. It also deletes a real interaction rather
  than fixing it.

## Terrain is authored pixel art in a bank of its own

- **Chosen: a `TileBank` in `data/tiles/<id>.json`, authored in the rig's alphabet.** Tiles
  were the one art noun still in code — a `const TILES` of six in `TileGen`, drawn by five
  hardcoded routines (`scatter`, `speckle`, `ripple`, `brick`, `blob`). The cost was not
  abstract: no routine can draw a door, so `quest_cave.json` built an interior out of
  grass-world tiles, and a game that wanted a floor edited a file under `scripts/`. Authored
  grids make a tile as expressive as a character part, and reuse the alphabet a rig author
  already knows.
- *Move only the LIST to data, keep the procedural kinds* — rejected: it reads like the same
  fix and unlocks nothing. A new tile could still only look like one of five existing
  patterns, so the interior problem would survive the refactor intact.
- *Keep both — procedural for texture, authored for shapes* — rejected: two ways to author
  one thing, forever, and the tile appearance would stay half in `scripts/`. The procedural
  routines earned their keep once, as the SOURCE of the port: every pixel they drew was one
  of three tones or transparent, so the six shipped tiles converted losslessly and the
  committed PNGs did not move.
- *A `tiles` key inside `data/rigs/<id>.json`* — deferred, worth revisiting if the two ever
  turn out to move together in practice: it needs no new directory and no new style field.
  Rejected for now because terrain and cast should swap independently — the day an AI sprite
  source draws the characters, the ground should not have to be redrawn with them. Revisit
  hook: `SpriteStyle.tile_bank_id`, which is the only thing keeping them apart.
- **A tile's `ramp` is a default, not a requirement.** Every style previously carried an
  identical six-key `tile_ramps` dict, so adding a tile was a mandatory edit to all three.
  The bank names the default and `tile_ramps` overrides it — the same shape as the rig's
  `slot_defaults`. All three styles dropped their dict entirely, which the drift gate proved
  was a no-op.

## The shop screen is windows over the world, and asks "how many"

- **Chosen: panels over the live world, with a quantity step.** M18 shipped a full-screen dim
  with three lines of floating text; the user played it and said, correctly, that it was not
  a shop. Researched afterwards rather than before (the process failure is in
  docs/learnings.md): the JRPG UI survey, Game UI Database's buying screens, and shop-flow
  write-ups converge on list + prices + purse + description + keeper, with pick -> how many ->
  confirm as the buy flow.
- *Full-screen shop screen* — rejected: it reads as the game changing screens rather than the
  player walking up to a counter, and it hides the town the shop belongs to.
- *A shopping cart (accumulate, then check out)* — deferred, worth trying if a game wants bulk
  trading: it is the other convention the research turned up. Rejected now because it needs a
  second confirm surface and a cart to draw, for a template whose shops sell two things.
  Revisit hook: `ShopMenu.Deal` already carries a count and a total, so a cart is a list of
  Deals rather than a redesign.
- **Rotating stock, synthesis shops and deal boards** (the jrpg-design-codex's shop patterns)
  are GAME design, not template scope: they are what a game builds on `ShopDef`, and baking
  any of them in would be designing somebody's game.

## Equipment stays in the bag, and arrives at a fight as two ints

- **Chosen: `GameState.equipment` is slot -> id, and the item never leaves the inventory.**
  The Dragon Quest model. Moving an item out of the bag on equip would make the bag a
  half-truth ("what you have, except what you are using"), and every existing reader — the
  pause list, the sell counter, `requires_item` — would need to learn about a second place
  things live.
- *Equipment as its own container* — rejected for that reason; revisit hook is
  `GameState.equipment`, which would become a second Inventory.
- **Mods reach `BattleLogic` through `of()`'s parameters, already summed.** Stats are derived
  from level, so gear must be a modifier or there are two sources of truth for one number;
  and BattleLogic may not reach the Registry, so the world does the resolving.
- *A stats struct passed into the fight* — deferred, worth it the day a third modifier source
  appears (a buff, a status effect): the revisit hook is `of()`'s two int parameters, which
  would become one object. Rejected now because two ints need no ceremony.
- **Cursed gear (negative mods) is refused** by `ItemDef.problems()`. A game that wants it
  wants a different noun with its own rules — the same call `battle_heal` made about negative
  healing.

## A price belongs to the item, not to the shop

- **Chosen: `ItemDef.price`, with `ShopDef` listing ids only.** One price per item is what
  makes the sell side honest without a second table: a shop that named its own prices would
  need a buy price and a sell price per keeper, and the two would drift.
- *Prices on the shop's stock rows* — deferred, worth trying the day a game wants a haggling
  keeper or a discount: the revisit hook is `ShopDef.stock`, which would become an array of
  dictionaries instead of ids. Rejected now because one keeper needs none of it.
- **`price = 0` means not tradable, and it is the default** — the same "zero is off" shape
  `ItemDef.battle_heal` and `GameConfig.grid_step_pixels` already use. An item joins the
  economy by being priced, never by being forgotten, so quest items are safe by construction.
- *The shop opening inline from the effect list* — rejected because it does not work:
  `_on_dialog_closed` applies effects and THEN closes the dialog overlay, so the counter is
  what the close pops. Deferred instead, which is the narrow fix; applying effects after the
  close would reorder every dialog effect there is, for a bug that is only about shops.

## Gold is party state, not an item

- **Chosen: `GameState.gold` as its own field, saved as its own key (v6).** It reads like an
  item ("a thing you carry, counted"), and the Inventory would have held it for free — but an
  item is something `ItemDef` describes, `Registry` resolves and the bag can refuse; money is
  none of those. Making it an item would have put a currency in the item list, in the pause
  bag page, and in every `requires_item` check that was never written to think about it.
- *Gold as an inventory entry* — rejected: free to build, and it leaks into every surface that
  iterates the bag. The one real benefit (saves and hooks carry it automatically) is one field
  and one migration step here.
- *A `Wallet` class beside `Inventory`* — rejected as premature: a wallet with one currency is
  an integer with ceremony. Revisit hook if a second currency ever appears: `GameState.gold`
  plus its two verbs are the only places that would change.
- **A spend is refused, never clamped**, matching `Inventory.remove`'s all-or-nothing rule —
  so a purse cannot go negative by construction, and no downstream check has to tolerate one.

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

## A view that renders data declares its capacity, and the build enforces it — *M13.3*

A screenshot of the live build showed the warden's opening with a choice drawn on top of the
second line of her text. Measuring every shipped line found worse: the text area was 22px
against a 12px line, so only ONE line ever really fit, and four nodes were being silently
truncated - three of them the signposting lines added the day before to tell the player where
to go. Nine scripted play sessions pressed through those conversations on every CI run and
could not see any of it, because headless QA never renders a pixel.

**The fork.** How does a fixed 320x180 box cope with data of unbounded length?

- **Reserved bands + a build-time budget** *(chosen)*. Text gets a fixed two-line band,
  choices get their own band below it, the box grows only while a choice is up - and
  `test_dialog_fit.gd` measures every shipped line with the real font against constants owned
  by `DialogBox`, failing the build on an overflow and naming the node. Text too long for the
  box becomes another node on a `next` chain, which is this format's own pagination and paces
  the typewriter better anyway.
- *Runtime pagination* — `deferred — worth trying`: overflowing text continues on the next
  press, so any data ever written renders. Rejected for now because it duplicates what node
  chaining already does and makes an unbroken paragraph legal to write, which is a worse thing
  to have in the content than a build failure. Revisit hook: `DialogBox._show_line`, the day a
  game on this template needs prose it cannot break up.
- *A taller box* — rejected. It moves the cliff without telling anyone where the new one is,
  and the worst-case line is unbounded.
- *A smaller font* — rejected outright: 8px is already the readability floor at this
  resolution.

**The general rule.** A view that renders DATA has a capacity, and that capacity is part of
the content contract rather than an implementation detail of the view. State it in constants
the gate reads too - two copies is how the check and the thing checked drift apart - and
enforce it at build time, because the failure mode of "too big to draw" is usually silence.

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

## Sound is generated, the way art is — *M14*

The template had a whole audio seam and no audio: `AudioBus` resolving ids, a
`sound_requested` signal, a `GameContext.play()`, an `OP_SOUND` effect — and zero files, zero
callers, and a game that has been silent since M0. `data/audio/README.md` argued that was
correct: *"a placeholder beep committed to a template is a placeholder beep shipped in
somebody's game."*

That is the objection the ART side already answered, and answered better. The template does
not ship an art pack; it ships a generator driven by a style resource. Sound gets the same
answer, so nobody inherits anybody's beep.

- **A synthesiser driven by a voice resource.** *Chosen.* `data/banks/*.json` says what a cue
  is shaped like, `data/sounds/*.tres` says what it is played on, and three voices share one
  bank exactly as three sprite styles share one rig.
- **Shipping recorded sound effects.** Rejected on the grounds the art side already
  established for LPC art: licensing that follows the template into somebody's game, and one
  fixed aesthetic baked into a thing whose whole claim is that the aesthetic is swappable.
- **Keeping the seam empty and letting each game bring audio.** Rejected — that is the status
  quo, and the status quo is a subsystem no gate has ever exercised. A seam with no payload is
  not a feature, it is an untested code path with documentation.

*Deferred — music.* The user chose effects only for M14. A tune is content a designer writes,
not something a generator should compose, so the shape when it comes is a note sequence in
`data/music/*.json` performed by this same synthesiser. Revisit hook: `AudioBus.play_music`,
which already exists and has never been called.

## A cue names a shape; a voice names a sound — *M14*

Whether the two-file split was real, or ceremony copied from the art pipeline.

- **Bank plus voice.** *Chosen*, on the test of whether the two files fail differently: "the
  footstep is too long" edits the bank, "the whole game is too harsh" edits the voice. Both
  are real edits, so both files are honest. The proof it is not decorative is
  `test_two_voices_over_one_bank_do_not_sound_the_same`, plus three shipped voices — `gb16`
  square and bit-crushed, `nes16` square and brighter, `dusk16` a triangle pitched down for
  the quest's late-evening look — that re-author not one cue between them.
- **One resource holding both.** Rejected: it would make every re-voicing a full re-authoring,
  which is precisely the cost the art side pays nothing for.

## The cue vocabulary is an enum, not a lint rule — *M14*

`AudioBus` warns once on an id it does not have and carries on. That is right, and it is also
exactly how a misspelled cue ships: nobody notices a noise that was never there.

- **An enum in `Sfx`, with an id table keyed by it.** *Chosen.* Template code names a cue as
  `Sfx.Cue.HIT`, so a typo is a compile error — the strongest guarantee GDScript offers, and
  strictly better than catching it later.
- **A lint rule banning raw cue strings**, mirroring `RULE_DIRECTION`. Rejected: it cannot
  tell a cue string from any other string, so it would need domain-prefixed ids invented to
  keep it from firing on `"warp"`, `"victory"` and `"defeat"`, which are already in use as
  effect keys and spawn names. An enum needs no prefix and no exemption list.
- **Leaving it as strings and trusting the warning.** Rejected on the failure mode: the
  warning fires at the moment the sound should have played, in a log nobody is reading,
  in a build already shipped.

Content still names sounds as text, because content is data — `Sfx.of()` is what validates it,
beside every other id, at load.

## The generator calls no transcendental function — *M14*

The drift gate compares committed samples against freshly generated ones, on a Mac here and on
an Ubuntu runner in CI.

- **Square, triangle and saw from an integer phase accumulator; linear envelopes; noise from
  `SeededRng` integers.** *Chosen.* IEEE-754 pins `+ - * /` to identical results on every
  platform, so the generator is deterministic **by construction** rather than by luck.
- **`sin`, `pow`, `exp` for smoother waveforms and curves.** Rejected. Those come from the
  platform's libm and are not guaranteed bit-identical between architectures; one ULP anywhere
  makes the committed WAV differ and turns the drift gate red in CI for a reason nobody can
  reproduce locally — and a gate that flaps is a gate that gets switched off. The constraint
  costs nothing: a chip voice has no sine in it either.

## The importer is part of the pipeline, so the gate checks it — *M14*

Godot's WAV importer defaults to `compress/mode=2`, which is QOA — **lossy**. Left alone, the
drift gate would compare lossless samples while every player heard something else, and no
surface anyone looks at would say so.

- **Pin the defaults in `project.godot` `[importer_defaults]`, and have the gate compare the
  IMPORTED stream as well as the committed file.** *Chosen.* Both halves are needed: the pin
  makes new cues correct automatically, and the comparison is what would catch the pin being
  removed.
- **Setting `compress/mode` in each generated `.wav.import`.** Rejected as a list maintained
  by hand — the next cue added comes back with whatever the default is, which is the failure
  this project has hit twice with skip lists.
- **Comparing raw file bytes instead of decoded samples.** Rejected for the reason the art
  gate compares pixels rather than PNG bytes: a container header is not ours to author, and a
  gate that fails on a file which sounds identical is a gate people learn to ignore.

## A game's own file beats the generated cue — *M14*

Two roots can answer a sound id, and the order between them is the seam.

- **`data/audio` wins over the generated cue.** *Chosen.* A game replaces one sound by dropping
  one file in, and never has to delete build output to do it — which matters because the drift
  gate would put that output straight back on the next run. It is the `GameHooks` rule one
  level down: a game is additive, or it is not using this seam.
- **Generated wins, overrides as a fallback.** Rejected: it makes the generator authoritative
  over the game, which is backwards for a template whose whole claim is that a game brings its
  own look and sound.
- **One root only** (generate into `data/audio`). Rejected: `data/` is content a human authors
  and `assets/generated/` is output a gate overwrites. Merging them would mean the drift gate
  competing with a designer over the same directory.

An override is printed once at boot, and two files answering to one name is an **error** — the
loser is invisible and which one loses depends on the filesystem, which is the same reason
`Registry` refuses duplicate content ids rather than letting the last one win.

## A view asks for a sound; it never plays one — *M14*

Where the call to the speaker lives.

- **Every screen emits `sound_wanted(id)`, and `world_scene` is the one place that plays it.**
  *Chosen*, and not on purity grounds alone — it is the `_apply_effects` shape applied to
  audio, and the alternative turned out to break a gate.
- **Views calling the audio singleton directly.** Tried first, and rejected on evidence:
  `check.sh`'s per-file parse gate skips any file whose TEXT names an autoload, so a view that
  called it dropped ITSELF and every suite depending on it out of that gate. Two dialog suites
  stopped parsing the moment `DialogBox` learned to make a noise. A comment naming the
  singleton is enough to do the same thing, which is stated in `CLAUDE.md` beside the signal.
- **A pure class playing its own cues.** Not available: `BattleLogic` may not touch an
  autoload at all. It collects instead, and the view drains — which turned out to be necessary
  rather than merely tidy, because a fight's cues have to survive a DEFEAT, whose effects the
  world discards entirely. A defeat sting riding on the effect list would be silent at exactly
  the moment the player most needs telling.

## Footsteps are measured, not timed — *M14*

- **One `StepMeter` counting distance actually moved, for both movement modes.** *Chosen.* It
  slows when the player slows and stops when a wall stops them, which is what a footstep is.
  One accumulator rather than two keeps the invariant that nothing downstream can tell free
  movement from grid movement.
- **Firing on grid-step completion.** Rejected: it would need a second implementation for free
  movement, and the two would drift the first time either was touched.
- **A timer.** Rejected on the failure mode - a player walking into a wall would keep making
  footstep noises while standing perfectly still.

The honest cost of one accumulator: a diagonal grid step covers 22.6px rather than 16, so its
footfall lands part-way through the step. That is what walking sounds like anyway.

## A setting is not a save — *M14*

Where the player's volume lives.

- **Its own file, `user://settings.json`, outside every slot.** *Chosen.* A save is one run of
  one game; a setting belongs to the person at the keyboard and has to survive starting over,
  switching game and deleting every slot.
- **A field on `SaveData`.** Rejected: it would need a migration, it would be per-slot, and
  loading an old save would reset the volume — which is not a thing a load should do.
- **Not persisting at all (session-only).** Rejected on the deployed demo: every reload of the
  page would come back loud.

No version field, deliberately. There is one field; a value the enum does not contain falls
back to the default with a warning, and the next write repairs the file. A migration chain for
that would be ceremony, and `supported_versions()` would be describing a format that never
changed.

## Four named steps, cycled by confirm — *M14*

- **Off / Quiet / Normal / Loud, advanced by the confirm button.** *Chosen.* The pause menu has
  up, down and confirm; up and down move the cursor, so confirm is the only button left. Four
  steps is also what a menu row can say in one word.
- **A slider on left/right.** Rejected for now: it needs an input axis the menu does not use for
  anything else, and a continuous value has no name to draw on the row.
- **A plain on/off toggle.** Rejected: the honest complaint about game audio is rarely "silence
  it", it is "quieter than that".

The gains are not evenly spaced (0, 0.25, 0.6, 1.0) because hearing is roughly logarithmic and
even spacing sounds like three loud settings and one quiet one.

## The gate got 17x faster without losing an assertion — *M14.1*

Four milestones of M14 cost ~17 minutes of CI each, and the profile said the time was not in
the tests: 604 tests execute in 34 seconds. It was in engine boots and in the wall clock.

- **`--fixed-fps 60` on everything driven by frames.** *Chosen.* Headless Godot still paces its
  main loop against real time, so a play session that takes a player three minutes took the
  gate three minutes. Measured, both ways, before anything was built on it: play sessions
  371s → 8s with byte-identical logs, suite 37s → 8s with identical verdicts on all 595 tests,
  and **226/226 mutants still killed** — which is the real proof it did not blunt detection.
- **Rewriting the QA scripts to wait fewer frames.** Rejected outright: the frame counts ARE
  the test. A battle asserted on frame N is asserting the timing window exists.
- **Dropping the slowest two play sessions from CI.** Rejected: they are the two that play the
  whole quest and lose a fight, i.e. the only ones that cover the game end to end.

## A pull request proves what it could have broken; main proves everything — *M14.1*

The full 226-mutant sweep was 57% of every CI run, on both the PR and the merge.

- **Scoped on PR, full on main.** *Chosen by the user.* A change can only make decorative a
  mutant whose file or suite it touched, so that is what a PR runs — seconds instead of ten
  minutes. Every merge re-runs the whole sweep, where nobody waits on it, so a test that went
  decorative because of a change somewhere else is caught one step later rather than never.
- **Full sweep on every PR, sharded across parallel jobs.** Rejected for cost: identical rigor
  before merge, ~4x the runner minutes, for a window that main closes minutes later anyway.
- **Main only, nothing on PR.** Rejected: it gives up the one thing scoping is good at, which
  is catching the author's own change making the author's own test decorative.

What deliberately did NOT move: `mutants_aim.sh` runs over the whole file on every run of
both. It costs under a second and it is the check that catches new code stealing an old
mutant's aim — which has happened twice.

## The artifact is played, not enumerated — *M15*

Nothing in this project had ever looked at the `.pck` a player downloads. Two ways to fix that.

- **Boot the pack and play it** with the committed QA sessions, via `--main-pack`. *Chosen.* It
  subsumes any file list: a packed game that boots, walks, warps, talks, fights and asks for its
  sounds has demonstrably packed the maps, tiles, sheets, dialog, manifests and cues. It also
  needs no export templates and reuses a harness that already exists.
- **Enumerate the pack** — mount it with `ProjectSettings.load_resource_pack` and diff the walk
  against `ContentScan` over the source tree. Rejected as the primary gate because it proves
  presence, not playability, and presence is the weaker claim. Still worth doing one day for a
  different reason: it would finally test `ContentScan`'s docstring claim that "the same walk
  works from a .pck", which nothing exercises.
- **Grepping the raw pck for known paths.** Rejected: the packed name is `hit.wav.import`, not
  `hit.wav`, so the obvious grep proves the sidecar shipped and says nothing about the audio.

**Where it runs:** in `check.sh`, on every run, because it turned out to cost five seconds rather
than the thirty assumed while planning. That was measured before deciding. It ALSO runs in
`pages.yml` against the real deployed package, where `deploy needs: build` means a package that
does not play leaves the live page on the last good build.

## An assertion where the value is always full is decoration — *M15*

`finish_the_quest` and `fall_at_the_keep` between them make 99 assertions and five and a half
minutes of scripted play, and neither noticed `BattleLogic.damage()` returning three more than it
should.

The reason is exact: **every mid-run `assert_hp` in both scripts sits immediately after a
level-up, and a level-up is a full heal.** Damage taken is overwritten before it is ever read.
`assert_level` cannot help - xp is a per-enemy constant, so it is the same whether a fight took
two rounds or four - and `finish_the_quest` made zero `assert_xp` calls at all.

- **One `assert_hp` after a fight that does NOT level the player.** *Chosen.* That is the only
  window in either script where hp is neither full-at-start nor refilled. Both directions of the
  arithmetic are now caught (`+3` and `-1` both land on 13 against a pinned 14).
- **Recomputing the expected hp from the combat numbers.** Rejected: a test that derives its
  expectation from the thing under test cannot see that thing change. The value was read out of
  the run's own log.
- **More assertions everywhere.** Rejected as the fix. The file already *looked* like it asserted
  hp three times; the problem was never the count.

`mutate_check.sh` now drives a play session as a "suite" when the suite column points at
`tests/fixtures/qa/`, so the play gate is mutation-proven like everything else. That only became
reasonable when M14.1 made a session cost two seconds instead of ninety.

## Equipment is a screen of its own, and the flow is slot-first — *M20*

**The fork:** where does the verb "wear this" live, now that M19's answer has been played?

- **A page of its own, entered from a top-level `Equipment` row, slot-first** — *chosen.*
  A slot list showing what is in each slot, each opening the gear that fits it. Two reasons,
  and the first outranks the second: the person who asked for equipment played M19 and said
  it should be its own screen like Items; and every reference game agrees — FF I–VI, Chrono
  Trigger and the DQ SNES remakes all put Equip beside Item and none of them equip from the
  item list. "What am I wearing" becomes a glance rather than a scan of the whole bag.
- **The M19 bag toggle** — *rejected, and removed.* Confirming gear in the bag toggled
  Wear/Take-off. It was fully tested and fully green, which is exactly why it is worth
  recording: no gate can see a screen that is in the wrong place. Its good parts were kept —
  the `(E)` marker stays in the bag, and the stat preview moved to the candidate list.
- **Keeping both** (equip from either surface, the Dragon Quest III shape) — *rejected.* Two
  surfaces owning one verb drift: the bag's toggle and the picker's take-off row would have
  to agree forever about what a confirm means, and the wording already differs ("Take off"
  vs a row that removes). One verb, one owner.
- **Item-first** (pick gear, then be told where it goes) — *rejected.* It reads as an
  inventory with extra steps, and it cannot show an empty slot, which is the thing a player
  most needs to see.
- **Optimize / best-equip** — *deferred — worth trying.* An FF convenience for games with
  five slots and forty items; at two slots it is a button that does what one press already
  does. **Revisit hook:** `ItemDef.SLOTS` growing past three.

**Where a third slot plugs in:** `ItemDef.SLOTS` is the one list. Adding `&"trinket"` to it
grows the equipment page a row, teaches `problems()` the new word, and needs no screen edit.

## The stats readout is worded by the world, not composed by the menu — *M20*

**The fork:** the equip screen shows "Atk 5+3 Def 1+0". Who builds that string?

- **The world builds it and hands the menu text** — *chosen.* Naming a stat is a question
  about what a game calls things, and `PauseMenu` may not touch the Registry or a manifest.
  It is the `_gold` and `_sound` precedent exactly: a readout arrives as text.
- **The menu composes it from numbers it is handed** — *rejected.* It would need to know that
  "Atk" is what this game calls attack, and that a game with no `CombatDef` has neither.
- **The view reads the world directly** — *rejected outright.* A view that names an autoload
  drops itself, and every suite that depends on it, out of `check.sh`'s per-file parse gate.
