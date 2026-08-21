#!/usr/bin/env bash
# Plays the ARTIFACT, not the source tree.
#
#   tools/pack_check.sh                 # export a pack, then play it
#   tools/pack_check.sh <pack>          # play a pack somebody already exported
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

fail=0
ran=0
for name in the_game_makes_noise talk_to_npc warp_between_maps save_and_load; do
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
