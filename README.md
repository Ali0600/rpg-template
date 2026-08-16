# 2D RPG Template

A reusable top-down RPG starting point for **Godot 4.7**, built so that *art style* and
*gameplay design* are the only things a new game has to change.

🎮 **[Play the demo](https://ali0600.github.io/sprite-generator/)** — walk around, talk to the
villagers.

![The demo town](docs/images/world.png)

It ships two halves:

1. **A consistent sprite generator** — a deterministic procedural paperdoll. Characters are
   composed from shared parts, one palette and one outline rule, so a whole cast is visually
   coherent *by construction* rather than by discipline. Same seed, same pixels, every run.
2. **The generic systems** — four-direction movement with tile collision, camera, data-driven
   maps, NPCs and branching dialog, game-flow states, saves with migrations, a seeded RNG, an
   audio seam, a headless QA harness, and CI that runs all of it.

## Why it looks the way it looks

Consistency in pixel art comes from rules, not talent: one limited palette, one outline style,
one size family, one set of proportions. A person applies those by discipline and drifts. The
generator applies them by construction and cannot — a rig part is an ASCII grid of tone
*indices*, and the style supplies what those indices mean, so there is no per-sprite place to
put a colour.

Those rules are then enforced as tests. Every generated pixel must be a palette colour; every
character's feet must sit on the same row; every left-facing frame must be its right-facing
frame mirrored; the same seed must produce the same bytes. Each gate ships with a mutant
proving it fails when broken.

![Two styles, one rig](docs/images/styles.png)

*`gb16` and `nes16` share a rig — **not one pixel of shape is redrawn between them**. They
differ only in palette, outline treatment and timings. Swapping the style re-skins the cast,
the terrain and the interface together.*

The output tier is honest GB/SNES-era chibi, not hand-painted art. Higher fidelity is a
*source swap*, not a rewrite: `SpriteSource` is an interface, and anything that writes the
`PNG + <name>.sheet.json` pair — a bought pack, an AI generator — feeds the game unchanged.

![Talking to an NPC](docs/images/dialog.png)

## Quick start

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Run the full gate the way CI does:

```bash
tools/check.sh
```

Prove the gates actually bite (slower; run before calling a milestone done):

```bash
MUTANTS=1 tools/check.sh
```

Regenerate the art after editing a rig or a style:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
```

## Making it your game

| To change | Edit | Touch any code? |
| --- | --- | --- |
| The whole art style | a file in `data/styles/` | no |
| Who the characters are | files in `data/characters/` | no |
| The world | `data/maps/*.json` — ASCII rows plus a legend | no |
| What people say | `data/dialog/*.json` | no |
| How it feels to move | `data/game_config.tres` | no |
| New body parts, new tiles | `data/rigs/*.json`, `TileGen.TILES` | one file |

If changing any of the first five needs a code edit, that's a bug in the template.

## Sprite Lab

A live preview of the generator — all four directions and the whole cast, laid out at the
game's own 320×180 so the art is judged at the size it will actually be seen.

![Sprite Lab](docs/images/sprite_lab.png)

## Layout

| Path | What lives there |
| --- | --- |
| `scripts/spritegen/` | The generator. Pure, deterministic, no node access. |
| `scripts/world/` | Movement, collision, maps, camera, interaction. |
| `scripts/ui/` | Dialog runner and its view, Sprite Lab. |
| `scripts/autoload/` | EventBus, Registry, GameState, SaveManager, Router, AudioBus, Qa. |
| `data/` | All content: styles, rigs, characters, maps, dialog, config. |
| `assets/generated/` | Build output of `tools/gen_sprites.gd` — never hand-edited. |
| `tools/` | Headless scripts and the gate. |
| `tests/` | gdUnit4 suites, fixtures, and the mutation harness's targets. |

- [CLAUDE.md](CLAUDE.md) — the engineering contract
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the seams, and what each one protects
- [docs/STYLE_GUIDE.md](docs/STYLE_GUIDE.md) — the art rules, and how to change the look
- [docs/DECISIONS.md](docs/DECISIONS.md) — design forks, with a backlog of what's worth trying
- [docs/learnings.md](docs/learnings.md) — the bugs that were interesting

## Milestones

- [x] **M0** — project skeleton, headless tooling, lint rules, mutation harness, CI
- [x] **M1** — the sprite generator, its consistency gates, and generated assets
- [x] **M2** — the sprite view scene and Sprite Lab preview
- [x] **M3** — movement, collision, camera, data maps, game-flow states, QA harness
- [x] **M4** — NPCs, interaction, branching dialog
- [x] **M5** — saves with migrations, audio seam, content registry
- [x] **M6** — web export and a live demo

## Experience Gained

- Designed a deterministic, seed-driven asset generation pipeline producing game-ready sprite
  sheets plus machine-readable metadata, with reproducibility enforced by golden-hash
  regression tests in CI.
- Built a multi-stage verification gate (static lint, isolated parse, whole-project compile,
  unit suites, runtime boot check, generated-artifact drift detection, and scripted
  end-to-end play) that fails closed, hardened against four known false-green modes: a piped
  exit code, a test runner that exits 0 having run nothing, a scan that visited no files, and
  a build artifact that no longer matches its source.
- Implemented mutation testing over the project's own quality gates, so each rule ships with
  machine-verified proof that it detects the defect it was written for; a rule whose mutant
  stops applying fails the build rather than quietly reducing coverage. Three tests were
  identified as decorative this way and rewritten to assert the mechanism.
- Authored CI/CD pipelines in GitHub Actions with SHA-pinned third-party actions,
  least-privilege token scopes, and checksum-verified toolchain downloads, avoiding
  third-party installer actions in the supply chain; the deployment job is gated on the test
  workflow's conclusion and pinned to the exact commit that passed rather than racing it.
- Built a scripted integration-test harness that drives the real application end to end
  (input, physics, state transitions) headlessly, used as both a local developer gate and a
  CI check.
- Architected a swappable-asset-source seam (interface plus a PNG/JSON contract) decoupling
  the runtime from how art is produced, enabling procedural, hand-authored or AI-generated
  assets behind one API.
- Implemented versioned save serialization with a forward-migration chain and fail-safe
  corruption handling that preserves the original bytes before any recovery path runs.

---

🔗 **Live:** https://ali0600.github.io/sprite-generator/ · **Repo:** https://github.com/Ali0600/sprite-generator
