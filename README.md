# 2D RPG Template

A reusable top-down RPG starting point for **Godot 4.7**, built so that *art style* and
*gameplay design* are the only things a new game has to change.

It ships two halves:

1. **A consistent sprite generator** — a deterministic procedural paperdoll. Characters are
   composed from shared parts, one palette and one outline rule, so a whole cast is visually
   coherent by construction rather than by discipline. Same seed, same pixels, every run.
2. **The generic systems** — four-direction movement with tile collision, camera, data-driven
   maps, NPCs and dialog, game-flow states, saves with migrations, a seeded RNG, an audio
   bus, a headless QA harness, and a CI gate that runs all of it.

> **Status:** M0 (skeleton, tooling and CI) is in. The sprite generator lands in M1 — see
> [the milestone list](#milestones).

## Why it looks the way it looks

Consistency in pixel art comes from rules, not talent: one limited palette, one outline
style, one size family, one set of proportions. The generator holds those rules in a
`SpriteStyle` resource and enforces them as tests — every generated pixel must be a palette
colour, every character's feet must sit on the same row, every left-facing frame must be its
right-facing frame mirrored. Swapping `data/styles/gb16.tres` for another style re-skins the
entire cast.

The output tier is honest GB/SNES-era chibi, not hand-painted art. Higher fidelity is a
*source swap*: `SpriteSource` is an interface, and a file-based or AI-generated sheet feeds
the game through the same PNG + JSON contract.

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

## Layout

| Path | What lives there |
| --- | --- |
| `scripts/spritegen/` | The generator. Pure, deterministic, no node access. |
| `scripts/util/` | `Dir` (the direction contract), seeded RNG, JSON loading, hashing, lint rules. |
| `scripts/world/` | Movement, collision, maps, camera. |
| `scripts/autoload/` | Singletons: EventBus, Registry, GameState. |
| `data/` | All content: styles, rigs, characters, maps, dialog. |
| `assets/generated/` | Build output of `tools/gen_sprites.gd` — never hand-edited. |
| `tools/` | Headless scripts and the gate. |
| `tests/` | gdUnit4 suites plus the mutation harness's fixtures. |

Engineering rules are in [CLAUDE.md](CLAUDE.md); design forks and the "worth trying later"
backlog are in [docs/DECISIONS.md](docs/DECISIONS.md).

## Milestones

- [x] **M0** — project skeleton, headless tooling, lint rules, mutation harness, CI
- [ ] **M1** — the sprite generator, its consistency gates, and generated assets
- [ ] **M2** — the sprite view scene and Sprite Lab preview
- [ ] **M3** — movement, collision, camera, data maps, game-flow states, QA harness
- [ ] **M4** — NPCs, interaction, dialog
- [ ] **M5** — saves with migrations, audio, content registry
- [ ] **M6** — web export and a live demo

## Experience Gained

- Designed a deterministic, seed-driven asset generation pipeline that produces game-ready
  sprite sheets plus machine-readable metadata, with reproducibility enforced by
  golden-hash regression tests in CI.
- Built a multi-stage verification gate (static lint, isolated parse, whole-project
  compile, unit suites, runtime boot check, generated-artifact drift detection) that fails
  closed, and hardened it against three known false-green modes — a piped exit code, a test
  runner that exits 0 having run nothing, and a scan that silently visited no files.
- Implemented mutation testing over the project's own quality gates, so each rule ships
  with machine-verified proof that it detects the defect it was written for; a rule whose
  mutant stops applying fails the build rather than quietly reducing coverage.
- Authored a GitHub Actions CI pipeline with SHA-pinned third-party actions, least-privilege
  token scopes, and a checksum-verified toolchain download, avoiding third-party installer
  actions in the supply chain.
- Architected a swappable-asset-source seam (interface + PNG/JSON contract) that decouples
  the runtime from how art is produced, enabling procedural, hand-authored or AI-generated
  assets behind one API.
