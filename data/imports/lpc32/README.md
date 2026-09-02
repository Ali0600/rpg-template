# Imported LPC characters

One folder per character, named by the character id the game uses (`hero`, `npc_elder`,
`quest_slink`…), holding exactly the two files the **Universal LPC Spritesheet Character
Generator** downloads:

```
data/imports/lpc32/<character_id>/sheet.png        # "Download PNG"  – the whole 832×3456 sheet
data/imports/lpc32/<character_id>/character.json   # "Export JSON"   – the layers and their credits
```

`tools/gen_sprites.gd` converts every folder here into `assets/generated/lpc32/<id>.png` +
`<id>.sheet.json` (the pair the game loads), merges the credits into `credits.json` and writes
`LICENSE.txt` beside them. `check.sh` step 6 regenerates in memory and fails if the committed
output differs — so after adding or changing a character:

```bash
godot --headless --path . -s tools/gen_sprites.gd
```

and commit the folder here together with what it produced.

## Making one — from a recipe (no browser)

A hero can be text. A recipe names the generator's layers and colours, and
`tools/lpc_compose.sh` fetches just the files it needs (into `build/lpc/`, gitignored) and
composes the same two files the browser would download, then checks them with the importer:

```bash
tools/lpc_compose.sh docs/lpc_designs/the_road.json --preview=build/hero.png   # look first
tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer
```

A layer with no art for the body type, no walk cycle, or a licence outside `lpc32.tres` is
refused by name. `recipe.json` lands beside the two files, so the character can be re-made.

## Making one — in the browser

1. Open the generator (the link on its README:
   <https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator>).
2. In the **licence filter**, tick the families `data/styles/lpc32.tres` accepts — currently
   CC0, CC-BY, OGA-BY and CC-BY-SA. A layer outside the list fails the build by name, so ticking
   the filter first is quicker than finding out later.
3. Design the character. Leave the **shadow** layer off: the importer measures the feet from
   the lowest opaque pixel, and a baked shadow would put the origin under the shadow rather
   than under the feet.
4. Press **Download PNG** and **Export JSON**, and put the two files in a folder named after
   the character.
5. Paste the URL from the address bar into the table below, so the character can be reopened
   and edited later — the hash after `#` is the whole recipe.

Only the **walk** rows (8–11) are read today; idle is the walk cycle's standing frame. Other
animations on the sheet are ignored, not refused, so a later clip (slash, hurt) is one more row
in `LpcImport`'s table rather than a re-export.

## Recipes

| character | made from | how |
|---|---|---|
| `quest_wanderer` | `docs/lpc_designs/the_road.json` | `tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer` |
| `quest_scrapper` | `docs/lpc_designs/quest_scrapper.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_scrapper.json --out=data/imports/lpc32/quest_scrapper` |
| `quest_warden` | `docs/lpc_designs/quest_warden.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_warden.json --out=data/imports/lpc32/quest_warden` |
| `quest_hermit` | `docs/lpc_designs/quest_hermit.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_hermit.json --out=data/imports/lpc32/quest_hermit` |
| `town_elder` | `docs/lpc_designs/town_elder.json` | `tools/lpc_compose.sh docs/lpc_designs/town_elder.json --out=data/imports/lpc32/town_elder` |
| `town_kid` | `docs/lpc_designs/town_kid.json` | `tools/lpc_compose.sh docs/lpc_designs/town_kid.json --out=data/imports/lpc32/town_kid` |
| `town_smith` | `docs/lpc_designs/town_smith.json` | `tools/lpc_compose.sh docs/lpc_designs/town_smith.json --out=data/imports/lpc32/town_smith` |
| `town_carter` | `docs/lpc_designs/town_carter.json` | `tools/lpc_compose.sh docs/lpc_designs/town_carter.json --out=data/imports/lpc32/town_carter` |
| `inn_keeper` | `docs/lpc_designs/inn_keeper.json` | `tools/lpc_compose.sh docs/lpc_designs/inn_keeper.json --out=data/imports/lpc32/inn_keeper` |
| `quest_slink` | `docs/lpc_designs/quest_slink.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_slink.json --out=data/imports/lpc32/quest_slink` |
| `quest_gloom` | `docs/lpc_designs/quest_gloom.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_gloom.json --out=data/imports/lpc32/quest_gloom` |
| `quest_keeper` | `docs/lpc_designs/quest_keeper.json` | `tools/lpc_compose.sh docs/lpc_designs/quest_keeper.json --out=data/imports/lpc32/quest_keeper` |

Three more designs sit beside it — `the_ember`, `the_scrappers_match`, `the_apprentice` — each
composable the same way. A character made in the browser instead records its `#…` link here.

Three of the twelve were re-cut after their previews and none of the three was visible to any
gate: the Gloom was a bare-chested, blood-spattered zombie body; the warden's `ash` hair is a
pinkish mauve rather than grey; and the town elder wore the same green tunic as Rook. Look at
what you compose - `--preview=` draws it through the importer, which is what the game loads.
