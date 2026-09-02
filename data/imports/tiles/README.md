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
