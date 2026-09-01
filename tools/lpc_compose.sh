#!/usr/bin/env bash
# Composes an LPC character from a recipe, fetching the layers it needs on demand.
#
#   tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer
#   tools/lpc_compose.sh docs/lpc_designs/the_road.json --preview=build/the_road.png
#
# An AUTHORING convenience, never a gate: it reaches the generator's GitHub repository for the
# ~15 small files a design needs and keeps them under build/lpc/ (gitignored, and .gdignore'd
# so the editor never imports them). What it writes - sheet.png, character.json - is exactly
# what the web app's Download PNG and Export JSON would have produced, and LpcImport checks it
# the same way. The recipe lands beside them so the character can be re-made from text.
#
# Three steps, because the path logic lives ONCE, in LpcCompose:
#   1. fetch the definitions the recipe names and the palettes (paths known without a plan);
#   2. ask lpc_compose.gd --list which layer files the plan needs, and fetch those;
#   3. compose.
# Every flag after the recipe is passed straight through and must be `--flag=value`.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot

RAW="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master"
CACHE="build/lpc"

if [ "$#" -lt 1 ]; then
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi
recipe="$1"
shift
if [ ! -f "$recipe" ]; then
  echo "lpc_compose: no recipe at $recipe" >&2
  exit 1
fi

mkdir -p "$CACHE"
touch "$CACHE/.gdignore"

fetch() {
  local rel="$1" dst="$CACHE/$1"
  [ -f "$dst" ] && return 0
  mkdir -p "$(dirname "$dst")"
  if ! curl -fsSL "$RAW/$rel" -o "$dst"; then
    echo "lpc_compose: could not fetch $rel" >&2
    rm -f "$dst"
    return 1
  fi
  echo "  fetched $rel"
}

# 1. definitions and palettes
for def in $(python3 -c 'import json,sys; [print(l["def"]) for l in json.load(open(sys.argv[1]))["layers"]]' "$recipe"); do
  fetch "sheet_definitions/$def.json" || exit 1
done
for m in body hair cloth eye; do
  fetch "palette_definitions/$m/meta_$m.json" || exit 1
  fetch "palette_definitions/$m/${m}_ulpc.json" || exit 1
done

# 2. the layer files the plan resolves to
listing=$("$GODOT" --headless --path . -s tools/lpc_compose.gd --recipe="$recipe" --cache="res://$CACHE" --list 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  printf '%s\n' "$listing" | grep -v "^Godot Engine" >&2
  exit "$status"
fi
for f in $(printf '%s\n' "$listing" | grep '^spritesheets/'); do
  fetch "$f" || exit 1
done

# 3. compose
"$GODOT" --headless --path . -s tools/lpc_compose.gd --recipe="$recipe" --cache="res://$CACHE" "$@"
