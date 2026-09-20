#!/usr/bin/env bash
# Plays the ARTIFACT, not the source tree.
#
#   tools/pack_check.sh                 # export a pack, then play it
#   tools/pack_check.sh <pack>          # play a pack somebody already exported
#   tools/pack_check.sh --selftest      # prove the contents check refuses AND accepts
#
# Every other gate in this project runs against res:// in the project directory. Nothing has
# ever looked at the .pck a player downloads, and the packaging step is where a whole class of
# defect lives: an asset that is not packed, an exclude filter that grew, an importer that did
# not run. Those are invisible from the source tree by construction - M14 shipped one that had
# been broken in exports since the day it was written.
#
# --main-pack boots the pack as res:// using the stock engine binary, so this needs no export
# templates at all. The QA scripts are read from an ABSOLUTE host path because tests/* is
# excluded from the pack - which is the point: the shipping preset is not modified to be
# testable.
#
# The sessions are the same committed ones check.sh runs. They are chosen so that between them
# they touch every kind of packed content: maps and tiles, sprite sheets, dialog, the game
# manifest, save slots and the generated audio.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# What a player's download must never carry: the trees that exist to build and test the game.
# Written out HERE rather than read from export_presets.cfg's exclude filter, because a check that
# read the filter would agree with it by construction - including on the day it stops naming one of
# them. The preset is where the rule is applied; this is where it is checked, against the artifact.
# It is not `addons/`: a game may add a plugin it really runs, and only the test framework is known
# to belong to the build rather than to the game.
#
# Measured before it was written (2026-09-13): the filter had never named addons/, and the web pack
# carried gdUnit4 - 260 files, its TCP server and its runners among them. Playing the pack could not
# notice, because nothing loads them: every session still played.
DEV_TREES='(tests|tools|docs|reports|addons/gdUnit4|data/imports)/'

# The pack cut into NUL-separated fields, one per line. 4.7.1 writes every path in its file table
# WITHOUT `res://`, straight after a 32-bit little-endian length whose high bytes are zero (measured:
# `1c 00 00 00`, then `data/games/quest.tres.remap`), so each entry begins a field. A `res://` string
# is a REFERENCE - the uid cache and the class cache name every script that has a uid - and a path in
# the middle of a field is prose, like a JSON readme naming a tool. The first version of this check
# matched `res://` anywhere, so it read references: it caught gdUnit4 only because those scripts
# carry uids, and a development file nothing refers to would have passed. The one thing it can still
# misread is a length-prefixed string inside a packed binary that begins with one of these trees -
# none does today, and it would refuse rather than pass.
pack_fields() { # $1 pack
  LC_ALL=C tr '\000' '\n' < "$1"
}

# The verdict on what a pack CONTAINS. Separate from playing it, and before it: an artifact can
# play perfectly and still carry things nobody meant to ship.
contents_ok() { # $1 pack
  local fields leaked count
  # Cut once. A `tr | grep -q` pipe can lose tr to SIGPIPE when grep stops early, and under pipefail
  # that status would flip the verdict of the `if !` around it.
  fields="$(pack_fields "$1")"
  # A table this cannot find proves nothing about what is in the pack. An encrypted or reformatted
  # directory has no entry starting a field, and would otherwise read as clean.
  if ! LC_ALL=C grep -a -q -E '^data/games/' <<< "$fields"; then
    echo "FAIL  $1 has no data/games/ entry in its file table, so the table was not read and its contents are unknown"
    return 1
  fi
  # Entries whose path length is a multiple of four have no padding, so a byte of what follows can
  # stick to the printed name; the verdict does not depend on it.
  leaked="$(LC_ALL=C grep -a -o -E "^${DEV_TREES}[[:alnum:]_.@+/-]*" <<< "$fields")"
  if [ -n "$leaked" ]; then
    leaked="$(sort -u <<< "$leaked")"
    count="$(grep -c . <<< "$leaked")"
    echo "FAIL  the pack's file table has $count entries that only build or test the game, e.g.:"
    head -5 <<< "$leaked" | sed 's/^/        /'
    return 1
  fi
  return 0
}

## The flag a session is played with: --game=<its directory> when that directory names a game, and
## nothing at all otherwise - check.sh's rule, so a session under tests/fixtures/qa/menu/ meets the
## title's Switch game row the way the deployed page does. One test per line, for mutants.tsv.
game_flag_for() { # $1 the session's directory name  $2 the project root
  if [ -f "$2/data/games/$1.tres" ]; then
    printf -- '--game=%s' "$1"
  fi
}

# Drives the REAL contents_ok over packs small enough to write by hand - fetch_godot.sh's precedent.
# The accepting cases are what make every refusal evidence of anything.
selftest() {
  local dir fail=0 out leak
  local clean=(data/games/quest.tres.remap scripts/world/world_scene.gdc \
    addons/a_plugin_the_game_runs/plugin.gdc data/tiles/lpc32.json)
  dir="$(mktemp -d)"
  ok() { # $1 label  $2 expected code  $3 actual code
    if [ "$2" != "$3" ]; then
      echo "  selftest FAIL: $1 (expected exit $2, got $3)"; fail=1
    else echo "  ok: $1"; fi
  }
  # A file table the way 4.7.1 writes one: each path WITHOUT `res://`, after a 32-bit little-endian
  # length whose high bytes are zero, then NUL padding. The length's value is immaterial to the
  # reading; the NUL in front of every path is the whole point.
  table() { # $1 file  $2... the paths the table names
    local file="$1" p
    shift
    printf 'GDPC' > "$file"
    for p in "$@"; do printf '\034\000\000\000%s\000' "$p" >> "$file"; done
  }

  table "$dir/clean.pck" "${clean[@]}"
  contents_ok "$dir/clean.pck" >/dev/null
  ok "a pack of the game's own files is accepted, a plugin it runs included" 0 $?

  # Prose inside a packed file. data/tiles/lpc32.json's readme names tools/fetch_tiles.sh, and a
  # search of the whole pack read that as a packed tool.
  table "$dir/prose.pck" "${clean[@]}"
  printf '\000\000{"_readme": ["run tools/fetch_tiles.sh", "\\"docs/GENRE_CONVENTIONS.md"]}' \
    >> "$dir/prose.pck"
  contents_ok "$dir/prose.pck" >/dev/null
  ok "a development path named in a packed file's text is not a packed file" 0 $?

  # The JSON fixture is the case the first version could not see: nothing else in a pack refers to
  # it, so its table entry is the only place its path appears.
  for leak in addons/gdUnit4/src/network/GdUnitServer.gdc tests/unit/test_saves.gdc \
      tests/fixtures/qa/quest/talk_to_npc.json tools/check.sh docs/FLOW.md \
      reports/report_1/index.html data/imports/lpc32/quest_wanderer/sheet.png; do
    table "$dir/leak.pck" "${clean[@]}" "$leak"
    out="$(contents_ok "$dir/leak.pck")"
    ok "a pack carrying $leak is refused" 1 $?
    case "$out" in
      *"$leak"*) echo "  ok: the refusal names it" ;;
      *) echo "  selftest FAIL: the refusal did not name $leak"; fail=1 ;;
    esac
  done

  # A reference is not an entry. The uid cache names res://data/games/quest.tres in a length-prefixed
  # field of its own, so a pack whose only games path is that reference has a table this never found.
  printf 'GDPC\034\000\000\000res://data/games/quest.tres\000' > "$dir/reference.pck"
  printf '\034\000\000\000scripts/world/world_scene.gdc\000' >> "$dir/reference.pck"
  contents_ok "$dir/reference.pck" >/dev/null
  ok "a pack whose only games path is a reference is refused as unread" 1 $?

  table "$dir/unreadable.pck" "no paths in here at all"
  contents_ok "$dir/unreadable.pck" >/dev/null
  ok "a pack whose file table names nothing is refused rather than passed" 1 $?

  # The game a session plays, over a project written here: quest is a game and menu is not.
  mkdir -p "$dir/project/data/games"
  : > "$dir/project/data/games/quest.tres"
  if [ "$(game_flag_for quest "$dir/project")" = "--game=quest" ]; then
    echo "  ok: a session in a game's directory plays that game"
  else
    echo "  selftest FAIL: a session in quest/ was not given --game=quest"; fail=1
  fi
  if [ -z "$(game_flag_for menu "$dir/project")" ]; then
    echo "  ok: a session in a directory naming no game is given no --game=, so it meets the picker"
  else
    echo "  selftest FAIL: a session in menu/ was handed a game"; fail=1
  fi

  rm -rf "$dir"
  [ "$fail" -eq 0 ] || return 1
  echo "  pack_check: selftest passed"
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

PACK="${1:-}"
PRESET="Web"
ROOT="$(pwd)"

# Created up front because the export below drops its exit status in here. Also the directory
# the play sessions run FROM: it has no project.godot in it, so the engine cannot quietly fall
# back to the source tree and test the very thing this gate exists to look past. Proven - the
# same run from /tmp plays identically, and that is the only reason to believe the pack is what
# actually ran.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A pack that is missing or truncated does not fail - it HANGS. Measured: a nonexistent pack and
# a half-copied one both sat there until killed, with no output at all. So every packed run is
# bounded, and an unusable artifact reports as a timeout instead of eating the job's budget.
LIMIT=120
TIMEOUT="$(command -v timeout || command -v gtimeout)"
if [ -z "$TIMEOUT" ]; then
  echo "FAIL  no timeout(1) available - a broken pack would hang this gate rather than fail it"
  exit 1
fi

# Writes the pack, quietly.
#
# The exit code is not evidence in either direction: the headless exporter writes the complete
# package and THEN aborts during shutdown (exit 134) - the same reasoning pages.yml states for
# the full web export. The ARTIFACT is the evidence, which is what the guards below check.
#
# It runs through a wrapper shell so that shell, rather than this one, is the one that notices
# the signal. Bash prints "Aborted (core dumped)" for a foreground command killed by a signal,
# and redirecting the command's own streams does not stop it - the message comes from the shell
# that waited, not from the program. In a gate's log it reads as a crash nobody handled, which
# is exactly the kind of line that teaches people to skim. The wrapper's stderr is discarded and
# it exits normally, so there is nothing left to report; the real status is kept in a file and
# used only where it is genuinely informative, in the failure messages.
export_status="?"
export_pack() {
  bash -c '"$1" --headless --path . --export-pack "$2" "$3" >/dev/null 2>&1; echo $? > "$4"' \
    _ "$GODOT" "$1" "$2" "$WORK/export_status" 2>/dev/null
  export_status="$(cat "$WORK/export_status" 2>/dev/null || echo '?')"
}

if [ -z "$PACK" ]; then
  PACK="$ROOT/build/pack_check/index.pck"
  mkdir -p "$(dirname "$PACK")"
  rm -f "$PACK"
  echo "exporting $PRESET pack..."
  export_pack "$PRESET" "$PACK"
fi

if [ ! -s "$PACK" ]; then
  if [ "$export_status" = "?" ]; then
    echo "FAIL  no pack at $PACK - nothing was exported, and that path holds no pack"
  else
    echo "FAIL  the export produced no pack at $PACK (exporter exited $export_status)"
  fi
  exit 1
fi
# Made absolute BEFORE anything changes directory. The sessions run from a scratch directory
# (so the engine cannot fall back to the source tree), and a relative pack path stops resolving
# the moment that happens - which presents as the pack HANGING, not as a path error. This
# script hit exactly that on its first run with a caller-supplied path.
case "$PACK" in
  /*) ;;
  *) PACK="$ROOT/$PACK" ;;
esac
# A tripwire, not a gate: it only catches a truncated write. What the pack CONTAINS is proven
# by playing it, below.
bytes=$(wc -c < "$PACK" | tr -d ' ')
if [ "$bytes" -lt 100000 ]; then
  echo "FAIL  $PACK is only $bytes bytes - the package is truncated (exporter exited $export_status)"
  exit 1
fi
echo "pack: $PACK ($bytes bytes)"

# What it CONTAINS, before anything plays it. Playing proves the game is in there; it cannot see
# what else is.
if ! contents_ok "$PACK"; then
  echo "pack_check: the exported artifact carries files a player should never download"
  exit 1
fi
echo "contents: nothing that only builds or tests the game"

fail=0
ran=0
# change_the_options is here for read_the_credits' reason: its Window row cycles the palettes in
# data/palettes/, which are .tres resources that have to be packed, and "they did not get packed"
# is invisible to every gate running against res://.
# read_the_credits is here for a reason the others are not: it opens a screen that READS a
# generated file out of the pack. Every other gate in this project runs against res://, where
# assets/generated is simply a directory - so "credits.json did not get packed" is a defect only
# this can see, and it is the shape M14 shipped in the audio seam.
# two_in_the_hollow_by_the_sword is here because it is the only session that chooses the sword on the
# Options page and fights with it, so the Fights row and the arena's screen are proven in the artifact
# a player downloads rather than only in res://.
for session in quest/the_game_makes_noise quest/talk_to_npc quest/warp_between_maps \
    quest/save_and_load quest/read_the_credits quest/change_the_options \
    quest/two_in_the_hollow_by_the_sword quest/play_from_the_pad; do
  name="${session#*/}"
  script="$ROOT/tests/fixtures/qa/$session.json"
  [ -f "$script" ] || { echo "FAIL  no such play script: $script"; fail=1; continue; }
  ran=$((ran + 1))
  out="$WORK/$name.log"
  ( cd "$WORK" && "$TIMEOUT" "$LIMIT" "$GODOT" --headless $GODOT_FRAMES \
      --main-pack "$PACK" -- --qa-script="$script" $(game_flag_for "${session%%/*}" "$ROOT") ) > "$out" 2>&1
  code=$?
  if [ "$code" -eq 124 ]; then
    echo "  HUNG    $name (killed after ${LIMIT}s - the pack is unusable)"
    fail=1
  elif [ "$code" -ne 0 ]; then
    echo "  FAILED  $name"
    grep -E '^qa: FAIL' "$out" | sed 's/^/          /' | head -5
    fail=1
  else
    echo "  played  $name"
  fi
done

if [ "$ran" -eq 0 ]; then
  echo "FAIL  no play scripts ran - this gate proved nothing"
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "pack_check: the exported artifact does not play"
  exit 1
fi
echo "pack_check: the exported artifact plays ($ran sessions)"
