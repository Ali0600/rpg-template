# Architecture

What each layer is for, and — more usefully — what each seam is *protecting*. A template is
mostly a set of decisions about where things are allowed to touch.

## The shape

```
                 data/                        (everything a game brings)
   styles/  rigs/  characters/  maps/  dialog/  game_config.tres
                    │
                    ▼
   scripts/spritegen/          pure · deterministic · no nodes
   Rig → SpriteCompositor → SheetBuilder → PNG + <name>.sheet.json
                    │
                    ▼  ← the contract. Anything that writes this pair is a valid art source.
   SpriteFramesFactory → SpriteFrames → SpriteView (origin = the feet)
                    │
                    ▼
   scripts/world/              Locomotion (pure) → ActorBody → MapBuilder
   scripts/data/               SpriteStyle · GameConfig · SaveData · ItemDef · Inventory (pure)
   scripts/ui/                 DialogRunner → DialogBox · PauseMenu → PauseScreen
   scripts/autoload/           EventBus · Registry · GameState · SaveManager · Router · AudioBus · Qa
```

## The seams, and what each one buys

**Shapes have no colour.** A rig part is an ASCII grid of tone *indices*; the style supplies
what those indices mean. Neither half can express a character on its own, which is why a cast
cannot drift apart: there is no per-sprite place to put a colour.

**The art source is an interface.** The game consumes `PNG + <name>.sheet.json`, never a
generator. `ProceduralSpriteSource` composes in memory (Sprite Lab, tests);
`FileSpriteSource` reads what was committed (the game). A third — a downloaded pack, an AI
generator — needs no change here, and `Dir` already accepts compass row labels because that
is how outside packs describe themselves.

**Nothing engine-specific is committed as art.** `SpriteFrames` and `TileSet` are built at
runtime. A committed `.tres` pointing at a texture would make a fresh clone depend on import
order, and would weld the pipeline to Godot.

**Pure things are pure.** `Locomotion`, `DialogRunner`, `MapData`, `Interactor` and the whole
of `spritegen/` are `RefCounted` with no node access. That is what lets the feel of the
movement, the branching of a conversation and every consistency rule be tested by *reading a
result* instead of by driving a scene.

**One owner per question.** `Router` alone answers "can the player move right now?" — two
systems each holding a `can_move` boolean is how a player ends up frozen after a dialog that
visibly closed, with each system certain it released control.

**Positions are feet.** A `SpriteView`'s origin, an `ActorBody`'s collider, a y-sort key and a
tile coordinate all refer to the same point: where the character stands. A taller sprite drops
in without re-tuning any of them.

**Art data decides collision.** Which tiles block movement comes from the tiles' own metadata,
so adding a cliff is an art change and the movement code never learns the word "cliff".

**An object is an interaction point, not a sprite.** A map's `objects` are ids at tiles with
something to say or a flag to set. What the player *sees* is the decor tile already there, and
whether it blocks them comes from that tile — so a sign or a chest is four lines of data and
`MapBuilder` gains no rendering code. They join NPCs in one candidate list, so the "closest
thing I am facing" rule stays a single rule rather than two competing ones.

A warp can carry `requires_flag` and `locked_dialog`: that is a locked door, expressed in
data. A warp without them is open, which is what every warp written before locking existed
means — and a warp that is locked with nothing to say is a *validation error*, because a door
that ignores you reads as a broken warp rather than as a shut gate.

## Autoloads

| | |
| --- | --- |
| `EventBus` | signals only; payload shapes documented at the declaration |
| `Registry` | loads every `.tres` under `data/`, indexed by type and id, duplicates reported |
| — | *(`GameSelect` is not an autoload: it must answer in `-s` tool runs, where singletons do not exist)* |
| `GameState` | the live state, and the only thing that mutates it |
| `SaveManager` | JSON slots under `user://saves/<game>/`; a save that is unreadable, or that names a different game than its directory, is preserved before anything else |
| `Router` | game-flow states; the single owner of input ownership. `PAUSED` is the pause menu |
| `AudioBus` | play by name; an unknown id warns once |
| `Qa` | inert unless `--qa-script=` is passed |

Signals up, calls down. A view never assigns `GameState.x`; it emits, and the owner responds.

## Testing layers

| Layer | Instrument | Answers |
| --- | --- | --- |
| Pure logic | gdUnit4, no tree | do the rules decide correctly? |
| Consistency gates | over every shipped style × character × direction × frame | does the art obey its own rules? |
| Scene | gdUnit4 `scene_runner` | does a node actually play, position and collide? |
| The whole game | `Qa` scripts in `check.sh` | does it boot, move, and hand control over? |
| The gates themselves | `tools/mutants.tsv` | does any of the above actually bite? |

The last row is the one that keeps the others honest. A rule with no mutant is a rule nobody
has proven is tested — and three times during this build a mutant proved a test decorative.

## Where a new game changes things

- **Which game runs** → a manifest in `data/games/`: start map, spawn, player character,
  config, controls hint. `--game=<id>` beats `config/game` in `project.godot`, which beats
  "there is only one game" — and when nothing chooses, the boot **refuses** rather than
  guessing, naming the games it found. One game ships, so nothing has to choose today;
  the refusal is what keeps the second one honest when it arrives.
- **Art style** → a new file in `data/styles/`. Nothing else.
- **Terrain** → a tile bank in `data/tiles/`: pixel art in the rig's own alphabet, plus
  `solid` (does it block?) and `decor` (does it stand on another tile?). One bank dresses
  every style, because a tile names a ramp rather than a colour.
- **Characters** → files in `data/characters/`; unspecified slots fill from the seed.
- **World** → files in `data/maps/`, ASCII plus a legend.
- **How NPCs behave** → `behavior` on an npc record: `static`, `wander` (with a
  `range`) or `patrol` (with a `path` of tiles). No code: the brain is template logic over
  map data, and it drives the same body the player uses.
- **Writing** → files in `data/dialog/`.
- **What can be carried** → files in `data/items/`. A map hands one over with `give_item`,
  a lock wants one with `requires_item`, a lantern drinks one with `take_item`, and a dialog
  choice can do any of the three.
- **Feel** → `data/game_config.tres`, including which of the two movement modes runs:
  `grid_step` false is free pixel movement, true is one press = one tile. It is a flag rather
  than a distance because the config is bound to a tile size, so a step that is not a tile
  cannot be written down. A game *may* bring its own config, and should only do so
  when its design demands it: a game that varies a knob for no reason turns every difference
  a player feels into a suspected defect.
- **New mechanics** → a `GameHooks` subclass under `games/<id>/`, named by the manifest.
  Never under `scripts/`: that tree is the template, and every mechanic added to it makes
  the template more specific to one game.

If a change to any of the first six requires editing something under `scripts/`, that is a
bug in the template rather than in the game.

### The rule that makes `games/` work

Game code is handed a `GameContext` and **may not name an autoload** — no `GameState.`, no
`Router.`, no `EventBus.`. This is mechanical, not stylistic: Godot's `--check-only` and
`tools/compile_all.gd` both *skip* any script naming a singleton (one does not exist in a
standalone run), so a hook that reached for `GameState` would silently leave two of the four
gates and could only fail in front of a player. `LintCore` fails the build on it.

A hook reads the snapshot and *appends effects* — `set_flag`, `mark_seen`, `say`, `warp_to`,
`play` — which `world_scene` applies in one place. Same shape as `DialogRunner`, which
collects flags and never writes them. It also means a hook cannot acquire a power the data
lacks, and a sign cannot acquire one the hook lacks: both produce the same list.

Returning `false` from `on_interact` means *"not mine"*, and the template's own behaviour
runs. That is what keeps a game additive.
