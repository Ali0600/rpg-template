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
# carried gdUnit4's 554 files - its TCP server, its runners, its own test suites. Playing the pack
# could not notice, because nothing loads them: every session still played.
DEV_TREES='res://(tests|tools|docs|reports|addons/gdUnit4|data/imports)/'

# Every development-only path the pack names, one per line. A pack's file table holds each path as
# plain text (measured on 4.7.1: `res://data/games/quest.tres` is in it verbatim), so reading it
# needs no engine. The tail is the characters a path is made of rather than "anything printable",
# which let the binary after a name ride along and counted one file as three.
dev_paths_in() { # $1 pack
  LC_ALL=C grep -a -o -E "${DEV_TREES}[[:alnum:]_.@+/-]*" "$1" 2>/dev/null | sort -u
}

# The verdict on what a pack CONTAINS. Separate from playing it, and before it: an artifact can
# play perfectly and still carry things nobody meant to ship.
contents_ok() { # $1 pack
  local leaked count
  # A pack this cannot read proves nothing about what is in it. An encrypted or reformatted file
  # table names no development path because it names no path at all, and that would read as clean.
  if ! grep -a -q 'res://data/games/' "$1"; then
    echo "FAIL  $1 names no res://data/games/ path, so its file table was not read and its contents are unknown"
    return 1
  fi
  leaked="$(dev_paths_in "$1")"
  if [ -n "$leaked" ]; then
    count="$(printf '%s\n' "$leaked" | wc -l | tr -d ' ')"
    echo "FAIL  the pack carries $count file(s) that only build or test the game, e.g.:"
    printf '%s\n' "$leaked" | head -5 | sed 's/^/        /'
    return 1
  fi
  return 0
}

# Drives the REAL contents_ok over packs small enough to write by hand - fetch_godot.sh's precedent.
# The accepting case is what makes every refusal evidence of anything.
selftest() {
  local dir fail=0 out leak
  dir="$(mktemp -d)"
  ok() { # $1 label  $2 expected code  $3 actual code
    if [ "$2" != "$3" ]; then
      echo "  selftest FAIL: $1 (expected exit $2, got $3)"; fail=1
    else echo "  ok: $1"; fi
  }
  table() { # $1 file  $2... the paths its file table names, NUL-separated the way a pack's are
    local file="$1" p
    shift
    printf 'GDPC' > "$file"
    for p in "$@"; do printf '\0%s' "$p" >> "$file"; done
  }

  table "$dir/clean.pck" res://data/games/quest.tres res://scripts/world/world_scene.gd \
    res://addons/a_plugin_the_game_runs/plugin.gd res://data/tiles/lpc32.json
  contents_ok "$dir/clean.pck" >/dev/null
  ok "a pack of the game's own files is accepted, a plugin it runs included" 0 $?

  for leak in res://addons/gdUnit4/src/network/GdUnitServer.gd res://tests/unit/test_saves.gd \
      res://tools/check.sh res://docs/FLOW.md res://reports/report_1/index.html \
      res://data/imports/lpc32/quest_wanderer/sheet.png; do
    table "$dir/leak.pck" res://data/games/quest.tres res://scripts/world/world_scene.gd "$leak"
    out="$(contents_ok "$dir/leak.pck")"
    ok "a pack carrying $leak is refused" 1 $?
    case "$out" in
      *"$leak"*) echo "  ok: the refusal names it" ;;
      *) echo "  selftest FAIL: the refusal did not name $leak"; fail=1 ;;
    esac
  done

  table "$dir/unreadable.pck" "no paths in here at all"
  contents_ok "$dir/unreadable.pck" >/dev/null
  ok "a pack whose file table names nothing is refused rather than passed" 1 $?

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
for name in the_game_makes_noise talk_to_npc warp_between_maps save_and_load read_the_credits \
    change_the_options; do
  script="$ROOT/tests/fixtures/qa/quest/$name.json"
  [ -f "$script" ] || { echo "FAIL  no such play script: $script"; fail=1; continue; }
  ran=$((ran + 1))
  out="$WORK/$name.log"
  ( cd "$WORK" && "$TIMEOUT" "$LIMIT" "$GODOT" --headless $GODOT_FRAMES \
      --main-pack "$PACK" -- --qa-script="$script" --game=quest ) > "$out" 2>&1
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
