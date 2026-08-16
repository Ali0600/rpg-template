# The art system

How the generator makes a cast look like one game, and how to change what that game looks
like. Nothing here is advice — every rule below is enforced by a test in
`tests/unit/test_gates_consistency.gd`, and every one of those has a mutant in
`tools/mutants.tsv` proving it fails when broken.

## The idea

Consistency in pixel art does not come from talent, it comes from *rules held everywhere at
once*: one palette, one outline treatment, one light direction, one size family, one set of
proportions. A person applies those rules by discipline and drifts. A generator applies them
by construction and cannot.

So a character here is never drawn. It is **composed**: shapes come from a rig, colours come
from a style, and the two meet in a compositor that has no colours of its own.

```
data/rigs/gb16.json      shapes  — ASCII pixel grids, no colour
data/styles/gb16.tres    colours — palette, outline mode, timings
data/characters/*.tres   choices — which part and which ramp per slot, plus a seed
                ↓
     SpriteCompositor → SheetBuilder → PNG + <name>.sheet.json
                ↓
     SpriteFramesFactory → SpriteFrames → AnimatedSprite2D
```

## The rules, and why each one is a test

| Rule | Why it matters | Gate |
| --- | --- | --- |
| Every opaque pixel is a palette colour | One colour from outside the style, and "change the style to change the art" stops being true | `test_every_pixel_comes_from_the_style_palette` |
| Tiles use the character palette | Terrain in different colours from the cast is how mixed-asset games betray themselves | `test_tiles_use_the_same_palette_as_the_characters` |
| The whole cast shares one ground row | A one-row difference reads as standing at different depths — obvious in motion, invisible in a still | `test_the_whole_cast_stands_on_one_ground_line` |
| No walk frame lifts both feet | The bob is what makes four frames read as walking; a bobbed foot leaves the floor | `test_a_walk_frame_never_lifts_both_feet` |
| Left is right, mirrored | One authored side, two directions — and drift puts the detail on the wrong side silently | `test_facing_left_is_facing_right_mirrored` |
| The outline wraps the silhouette | Outlines are generated, so the rule is structural: no body pixel touches empty space bare | `test_the_outline_wraps_the_silhouette` |
| Same seed, same pixels | Everything else rests on it: the drift gate, golden hashes, reproducing a bug report | `tests/unit/test_determinism.gd` |

Two more rules are enforced by `tools/lint_rules.gd` rather than by a gate, because they are
about the *source*: no colour literal outside `scripts/spritegen/` and `scripts/data/`, and
no unseeded randomness anywhere.

## Anatomy of the shipped rig

Cell is **16×24**; tiles are **16×16**. Feet sit on row 22 and the generated outline lands on
row 23, so the ground row is the last row of the cell and every character shares it.

```
row  2- 6   hair
row  4-10   head        (face at row 7)
row 11-16   body        (sleeves 12-16, hands 16)
row 16-20   legs
row 21-22   feet
row    23   outline only — the ground line
```

Head is ⅓ of the height: the chibi proportion that stays readable at 16 px wide. The body is
6 px across and the head is 8, which is what keeps the head reading as the focal point.

### Pixel characters

| Char | Means |
| --- | --- |
| `.` | transparent |
| `1` | the slot's ramp **shadow** tone |
| `2` | its **base** tone |
| `3` | its **light** tone |
| `o` | forced outline pixel (rarely needed — the outline pass handles the silhouette) |

A part carries no colour. That is the whole trick: the same `head_round` is a pale farmhand
or a dark-skinned guard depending only on which ramp the character assigns to `head`.

### Slots

`legs · shoes · body · arms · hands · head · face · hair`, drawn in that order, back to
front. `slot_ramp_from` makes a slot follow another's colour — sleeves follow the body,
hands follow the head — so a randomised character never gets pale hands on a dark face.

`"bob": false` marks the parts that must not ride the walk bounce. Legs and feet carry the
stride; if they bobbed, the character would leave the ground and the grounding gate would
(correctly) fail.

## How to change the look

### Re-skin everything: write a new style

Copy `data/styles/gb16.tres`, change the ramps and the outline mode, keep `rig_id`. That is
what `nes16.tres` is: **not one pixel of shape is redrawn**, and the cast and the world both
change. Compare `assets/generated/gb16/_contact.png` with `assets/generated/nes16/_contact.png`.

Ramps are `[shadow, base, light]` hex strings. Three tones per material is the cel-shading
budget; a fourth is where a limited palette starts to look muddy. Outline modes:

- `0` NONE — no outline pass; the shapes carry the silhouette
- `1` SOLID — one outline colour everywhere; the classic readable choice
- `2` TINTED — each material edged in its own shadow tone; softer, warmer

> Compute generated colours in **whole bytes** (`Color8`), never with `Color.darkened()`.
> An 8-bit image *truncates* a float channel while `Color.to_rgba32()` *rounds* it, so a
> float-derived colour reports one value and comes back out of the PNG one unit darker —
> and the palette gate is right to reject it. Pinned by
> `test_color8_survives_a_round_trip_through_an_image_but_floats_may_not`.

### Add a part

Add an entry under `parts` in the rig with a `slot`, and a `views` block for `front`, `side`
and `back` (omit a view the part is not drawn in — the face has no back). Each view needs
`at` (top-left in the cell) and `frames`. Use `frame_map` to reuse drawings across the four
walk frames: the two passing poses are the same picture, so it is authored once.

Then add the part id to `part_choices` in any style that should be able to roll it.

Author **inset by a pixel** on every side — the outline pass needs somewhere to go.

### Add a character

A `.tres` in `data/characters/` with an `id`, a `style_id` and a `seed`. Every slot you do
not name is filled from the seed, deterministically, so a crowd of villagers is one short
file each. Name a slot's `parts` or `ramps` entry to pin it.

### Add a tile

Add a definition to `TileGen.TILES` and a ramp for it in every style's `tile_ramps`. `solid`
becomes a collision shape — which tiles block movement is an *art data* decision, so the
movement code never learns the word "cliff".

## Regenerating

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/gen_sprites.gd
```

`assets/generated/**` is build output. Edit a rig or a style, re-run, and commit both
together: `tools/check.sh` regenerates in memory and fails if what is committed differs.
Read `_contact.png` afterwards — the gates catch the quiet failures, but only your eyes
catch "this looks wrong".

## Using a different art source entirely

`SpriteSource` is the seam. Anything that can write a PNG plus a `.sheet.json` works
unchanged — a hand-drawn sheet, a bought pack, or an AI generator such as PixelLab, which
produces exactly this shape of four-direction sheet.

```json
{ "version": 1, "cell": [16,24], "columns": 4, "rows": 4,
  "directions": ["south","west","east","north"],
  "animations": { "idle": {"frames":[0],"fps":4,"loop":true},
                  "walk": {"frames":[0,1,2,3],"fps":8,"loop":true} },
  "anchor": [8,23] }
```

Row labels may be compass names in any order — `Dir` maps them onto the canonical
`down, left, right, up`, so an outside pack is described in its own vocabulary and nothing is
hand-edited on the way in. See
`tests/fixtures/spritegen/external_meta_compass.json`, which is exactly that case.

What such a source gives up is the guarantee this document is about: the palette, grounding
and mirror gates only hold for art the generator made. Run an outside sheet through them and
expect to hear about it.
