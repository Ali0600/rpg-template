# Imported terrain

One directory per tile bank, named by the bank's id, holding the art it cuts from:

```
data/imports/tiles/<bank id>/<file>.png
data/tiles/<bank id>.json          # the bank: which cell of which file each tile is
```

A bank with `"pixels_from": "files"` names, per tile, a `from` file and a `cell` — column then
row, in cells of the bank's own `tile` size — and lists every file under `files` with its
`authors`, `licenses` and `urls`. That list is the licence gate's whole input: a tile cut from a
file the bank does not credit is refused, and a file offered under no licence the style accepts is
refused by name. It is also what puts the artists into `assets/generated/<style>/credits.json`
beside the ones who drew the cast.

`tools/gen_sprites.gd` cuts the tiles into `assets/generated/<style>/tiles.png` and writes
`tiles.json` beside it. `check.sh` step 6 regenerates in memory and fails if the committed atlas
differs, so after changing a bank or its art:

```bash
godot --headless --path . -s tools/gen_sprites.gd
godot --headless --path . --import
```

The second line is not optional if you are about to LOOK at the result: the game loads the
imported texture, so a fresh `tiles.png` behind a stale import shows you the old ground.

## Getting the art

```bash
tools/fetch_tiles.sh data/tiles/lpc32.json
```

It downloads every file whose entry carries a `url`, skips what is already there, and reports —
rather than fails — a file that has none. `plants.png` is that case: it ships as a zip from its
OpenGameArt page, so its one sheet is extracted and put in place by hand.

## Authoring an edge

A tile may say what its boundary with other ground looks like, and then the generator composes
every shape that boundary can take:

    { "id": "water", "from": "water.png", "cell": [1, 5], "solid": true,
      "ring": { "n": {"cell": [1, 2]}, "e": {"cell": [2, 3]}, ... },
      "over": [["grass", "grass_alt"], ["path"]] }

`ring` is twelve pieces - `n e s w` for the four edges, `ne nw se sw` for the outer corners, and
`ne_in nw_in se_in sw_in` for the inner notches. A piece is a cell like a tile is, and its `from`
defaults to the tile's own sheet. An optional thirteenth, `c`, says what fills a quarter with no
edge in it; leave it out and the tile's own plain art is used, which is what makes an interior
cell identical to the flat tile.

LPC's ground sheets are laid out for exactly this. Measured from `grass.png`, `dirt.png` and
`water.png`, which are each 3 cells by 6 at 32px:

| row | cells |
|---|---|
| 0 | a one-wide north cap, then `se_in`, then `sw_in` |
| 1 | a one-wide south cap, then `ne_in`, then `nw_in` |
| 2 | `nw` `n` `ne` |
| 3 | `w`, the plain centre, `e` |
| 4 | `sw` `s` `se` |
| 5 | three plain fill variants |

The two one-wide caps go unused: a shape is composed from four QUARTERS of the pieces above, so
a strip one tile wide gets its north and south edges from the `n` and `s` pieces at once.

`over` is a list of GROUPS. A group is the ground this edge is drawn against - grass and its
tufted variant are one material to a shoreline - and the FIRST id in it is the tile whose plain
art the edge is composed over. A cell touching two groups takes the one more of its sides face,
then the one more of its corners, then the group the file names first.

Everything is refused by name: a ring without an `over` and an `over` without a ring, a missing
or misspelt piece, a ring on a decor tile, an `over` naming the tile itself or something the bank
has no tile for, and an atlas the rings have made too wide for a texture.

## Choosing cells

Look at the sheet, then look at the RESULT. LPC's ground sheets are laid out for an editor's
terrain tool — a 3x3 ring of edges and corners around a centre — so the cell you want for a
template that has no transitions is a plain fill, and the plain fill in the middle of the ring is
often a single flat colour, which the shipped-art gate refuses. The row of variants below it is
usually what you want.

Two of this bank's twelve were re-cut after the first screenshot: the inn had a cold green stone
floor, and its tables sat high in their cells like stools. Neither was visible to any gate.

## What is in `lpc32`

Nine sheets, all CC-BY-SA. Lanea Zimmerman's (Sharm's) base tileset for the ground, buildings,
interiors and furniture; Daniel Armstrong's (HughSpectrum's) castle floors; and bluecarrot16's
plants pack for the bush, because the base set has none and the demo's own dialogue names one.
Full credits, per file, are in `data/tiles/lpc32.json` and in the generated `credits.json`.
