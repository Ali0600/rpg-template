# RPG template — engineering rules

**This file is the contract.** If a rule here conflicts with your instinct, the rule wins.

This repo is a *template*, not a game. Everything in it exists so that building a new RPG
means editing `data/` and writing gameplay — never rewriting movement, sprites, saves or
the boot sequence. A change that makes the template more specific to one game is a
regression, however good that game looks.

## 1. Hard rules

- **Typed GDScript everywhere.** `untyped_declaration` and `unsafe_method_access` warnings
  are on. No C#.
- **Art is data.** Colours, palettes, cell sizes, frame counts and outline rules live in a
  `SpriteStyle` resource under `data/styles/`. A colour literal in `scripts/world/` or
  `scripts/ui/` is a build failure (`tools/lint_rules.gd`).
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
scripts/spritegen/  pure RefCounted, deterministic, NO node access — the generator
scripts/util/       dir, json_file, seeded_rng, hashing, lint_core, content_scan
scripts/data/       Resource types (SpriteStyle, CharacterSpec, GameConfig, SaveData…)
scripts/world/      Locomotion (pure) + the nodes that apply it
scripts/ui/         DialogRunner (pure) + its view
scripts/autoload/   EventBus Registry GameState SaveManager Router AudioBus Qa
scenes/             views only
data/               all content: games, styles, rigs, characters, maps, dialog
games/<id>/         a game's OWN code: a GameHooks subclass, and nothing generic
assets/generated/   build OUTPUT of tools/gen_sprites.gd — never hand-edited
```

Signals up, calls down, through `EventBus`. Autoloads hold state, scenes hold views; a view
never assigns `GameState.x` — it emits and the owner responds. One writer per piece of
state.

**Which game runs is data, not code.** `data/games/<id>.tres` (`GameManifest`) holds the first
map, the spawn, the player's character, the config and the controls hint. `GameSelect` picks
one: `--game=<id>` beats the `application/config/game` project setting, which beats "there is
only one game", and two games with nothing choosing is a **refusal** — a guessed game presents
as the game you meant to run behaving strangely. Nothing in `scripts/world/` may name a map,
a spawn or a character again.

**Gameplay goes in `games/<id>/`, never in `scripts/`.** A game's code is a `GameHooks`
subclass named by its manifest. It is handed a `GameContext` and **may not name an autoload** —
naming one removes a file from the per-file parse gate AND `compile_all.gd`, so it would leave
two of the four gates silently; `LintCore.RULE_AUTOLOAD` fails the build on it. Hooks read a
snapshot and append effects; `world_scene._apply` is the single place any of it reaches live
state. `on_interact` returning `false` means "not mine" and the data's own behaviour runs — a
game is additive or it is not using this seam.

**The sprite contract is PNG + `<name>.sheet.json`.** Nothing engine-specific is committed
as art: `SpriteFramesFactory` turns that pair into a `SpriteFrames` at runtime. This is the
seam that lets a procedural rig, a downloaded pack or an AI generator feed the same game.

## 3. Testing

**Every gate ships with a proof that it fails on the input it exists to catch.** A
validator that has only ever passed is decoration.

- Pure logic (`spritegen/`, `Locomotion`, `DialogRunner`, `MapData`) is `RefCounted` and
  tested with no scene tree. Node behaviour uses gdUnit4's `scene_runner`.
- Mutants are mandatory: a rule with no row in `tools/mutants.tsv` is a rule nobody has
  proven is tested. `NOT APPLIED` means fix the pattern, never delete the row.
- Gates run **unpiped** — `cmd | tail` exits with `tail`'s status, so a failing gate
  reports success.
- Autoloads outlive a suite: call `GameState.reset()` in `before_test`.
- Assert on simulated frames, never wall-clock time.

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
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
```

Drive the real game from a script, or photograph it:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --qa-script=res://tests/fixtures/qa/talk_to_npc.json
```

Other headless tools: `setup_input_map.gd` (rewrites the input map — re-run after changing
bindings), `lint_rules.gd`, `compile_all.gd`, `smoke_boot.gd`, `screenshot.gd` (needs a real
rendering driver, so not headless and not in CI). `tools/_engine.sh` resolves the engine;
`GODOT_BIN` overrides it. The Godot MCP is an accelerator for interactive work, **never** a
dependency of the build.

Anything that needs the running game — the world, the player, the router — must be driven by
a `Qa` script rather than by `-s tools/x.gd`: in `-s` mode the autoload singletons are not
registered as identifiers, so a scene whose script names one will not even load.

## 5. Generated art

`assets/generated/**` is output. Edit the rig (`data/rigs/*.json`) or the style
(`data/styles/*.tres`), re-run `gen_sprites.gd`, and commit both together — `check.sh`
regenerates and fails if the committed PNGs disagree with what the generator now produces.
