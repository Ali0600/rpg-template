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

## Making one

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

| character | generator URL |
|---|---|
| `hero` | _(paste the `#…` link here)_ |
