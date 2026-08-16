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
   scripts/ui/                 DialogRunner (pure) → DialogBox
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

## Autoloads

| | |
| --- | --- |
| `EventBus` | signals only; payload shapes documented at the declaration |
| `Registry` | loads every `.tres` under `data/`, indexed by type and id, duplicates reported |
| `GameState` | the live state, and the only thing that mutates it |
| `SaveManager` | JSON slots; an unreadable save is preserved before anything else |
| `Router` | game-flow states; the single owner of input ownership |
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

- **Art style** → a new file in `data/styles/`. Nothing else.
- **Characters** → files in `data/characters/`; unspecified slots fill from the seed.
- **World** → files in `data/maps/`, ASCII plus a legend.
- **Writing** → files in `data/dialog/`.
- **Feel** → `data/game_config.tres`.
- **New mechanics** → new files under `scripts/`, with the pure part separated so it can be
  tested without a scene, and a mutant per rule.

If a change to any of the first five requires editing something under `scripts/`, that is a
bug in the template rather than in the game.
