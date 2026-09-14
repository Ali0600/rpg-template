#!/usr/bin/env bash
# Composes an LPC character from a recipe, fetching the layers it needs on demand.
#
#   tools/lpc_compose.sh docs/lpc_designs/the_road.json --out=data/imports/lpc32/quest_wanderer
#   tools/lpc_compose.sh docs/lpc_designs/the_road.json --preview=build/the_road.png
#   tools/lpc_compose.sh --selftest
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
#
# The generator is read at a COMMIT, never at a branch. Every layer the committed cast was composed
# from was fetched on 2026-09-02 while master was the commit below, and all 75 of them were checked
# byte for byte against that commit on 2026-09-13; the hero's ten slash files - one for each of his
# eight layers and the dagger's two - were fetched from the same commit on 2026-09-14. A branch is
# whatever the next push makes it; a
# commit names the bytes, which is the reason CI pins every action to a SHA. There is no list of
# per-file sums on top: git's own content address already is one, and 75 digests beside it would be
# a second copy of what the commit says. To move to newer art, change the commit and re-run the
# recipes, and look at what changed.
#
# Every path it writes stays under build/lpc/. The paths come from a recipe and from the composer's
# own --list output, so a "../" in either is refused before anything is fetched.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RAW="https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/007365eac3a85121da9085a6f1aff5934307f6e4"
CACHE="build/lpc"

# RULE 1: a layer path is relative and never climbs out of the cache. One test per line rather than
# a `case` with alternatives, because mutants.tsv cannot anchor on a line holding `|`.
contained() { # $1 path under the cache
  if [ -z "$1" ]; then return 1; fi
  case "$1" in /*) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  return 0
}

fetch() {
  local rel="$1" dst="$CACHE/$1"
  if ! contained "$rel"; then
    echo "lpc_compose: refused '$rel' - a layer path must stay inside $CACHE" >&2
    return 1
  fi
  [ -f "$dst" ] && return 0
  mkdir -p "$(dirname "$dst")"
  if ! curl -fsSL "$RAW/$rel" -o "$dst"; then
    echo "lpc_compose: could not fetch $rel" >&2
    rm -f "$dst"
    return 1
  fi
  echo "  fetched $rel"
}

# Drives the real contained() and fetch(), over file:// so nothing reaches the network.
selftest() {
  local dir fail=0 pinned="$RAW" cache="$CACHE"
  dir="$(mktemp -d)"
  ok() { # $1 label  $2 expected code  $3 actual code
    if [ "$2" != "$3" ]; then
      echo "  selftest FAIL: $1 (expected exit $2, got $3)"; fail=1
    else echo "  ok: $1"; fi
  }

  # The pin is a commit. Asserted as a SHAPE rather than as this commit, which would only restate the
  # value: what has to stay true is that nobody puts a branch back.
  if [[ "$pinned" =~ /[0-9a-f]{40}$ ]]; then
    echo "  ok: the generator is read at a commit"
  else
    echo "  selftest FAIL: RAW ends in '${pinned##*/}', which is not a commit"; fail=1
  fi

  contained "sheet_definitions/body/body.json"; ok "a layer path is accepted" 0 $?
  contained "spritesheets/..hidden/walk.png"; ok "a name that only starts with dots is not a climb" 0 $?
  contained "../escaped.png"; ok "a path that climbs out is refused" 1 $?
  contained "spritesheets/../../escaped.png"; ok "a climb in the middle is refused" 1 $?
  contained "spritesheets/.."; ok "a climb at the end is refused" 1 $?
  contained "/etc/hosts"; ok "an absolute path is refused" 1 $?
  contained ""; ok "an empty path is refused" 1 $?

  # A refusal has to stop the WRITE, not just say something. The source sits where a climbing path
  # would fetch from, so without the rule the file really would land outside the cache.
  mkdir -p "$dir/up/src/sheets" "$dir/cache"
  printf 'layer\n' > "$dir/up/src/sheets/walk.png"
  printf 'outside\n' > "$dir/up/escaped.png"
  RAW="file://$dir/up/src"
  CACHE="$dir/cache/lpc"
  fetch "sheets/walk.png" >/dev/null 2>&1; ok "a contained layer is fetched" 0 $?
  if [ -f "$dir/cache/lpc/sheets/walk.png" ]; then echo "  ok: it landed in the cache"
  else echo "  selftest FAIL: a fetched layer is not in the cache"; fail=1; fi
  fetch "../escaped.png" >/dev/null 2>&1; ok "a climbing layer is refused" 1 $?
  if [ -e "$dir/cache/escaped.png" ]; then
    echo "  selftest FAIL: a refused path was written outside the cache"; fail=1
  else echo "  ok: nothing was written outside the cache"; fi
  RAW="$pinned"
  CACHE="$cache"

  rm -rf "$dir"
  [ "$fail" -eq 0 ] || return 1
  echo "  lpc_compose: selftest passed"
}

case "${1:-}" in
  --selftest)
    selftest
    exit $?
    ;;
esac

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot

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
