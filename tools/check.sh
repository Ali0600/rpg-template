#!/usr/bin/env bash
# The milestone gate. Everything here must pass before any milestone is called done.
#
# Deliberately CLI-only: the Godot MCP is an accelerator for interactive work, never a
# dependency of the build. A gate that needs a running editor is a gate that stops working
# the moment someone checks the repo out fresh - or the moment CI runs it.
#
# Gates run UNPIPED. Piping a gate into head/tail/grep replaces its exit status with the
# formatter's, so a failing check silently reports success.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot
echo "engine: $GODOT ($("$GODOT" --version 2>/dev/null | head -1))"

# THE ENGINE EXITS 0 WHEN -s NAMES A SCRIPT THAT IS NOT THERE. Measured 2026-09-04: it prints
# two ERROR lines to stderr and returns success. So every `-s tools/x.gd` step below is
# fail-open on a renamed or deleted tool - it reports PASS having run nothing.
#
# This gate used to make that worse rather than better: four steps carried
# `if [ -f tools/x.gd ]; ... else echo "SKIP  x.gd does not exist yet"`, and a SKIP touches
# neither result() nor fail, so the silence looked deliberate. The guards are gone, but deleting
# them is not the fix - the exit code still cannot be trusted.
#
# What closes it is tests/unit/test_ci_paths.gd, which reads THIS FILE, derives every
# tools/*.gd and tools/*.sh it names, and fails by name if one is not on disk. It runs at step
# 4/9 below, so check.sh as a whole goes red. Deliberately ONE implementation of that rule and
# not a second copy here: two paths answering one question drift, and the copy that loses is
# whichever runs second.
fail=0
step() { printf '\n=== %s ===\n' "$1"; }
result() { # $1 = exit code, $2 = label
  if [ "$1" -eq 0 ]; then echo "PASS  $2"; else echo "FAIL  $2 (exit $1)"; fail=1; fi
}

# Autoload names come from project.godot, never from a list typed here. A hand-maintained
# copy goes stale the day a singleton is added, and the file using it silently stops being
# covered by the parse gate below.
autoloads=$(awk '/^\[autoload\]/{f=1;next} /^\[/{f=0} f && /^[A-Za-z_][A-Za-z0-9_]*=/{sub(/=.*/,"");print}' project.godot)
if [ -z "$autoloads" ]; then
  echo "FAIL  no [autoload] entries found in project.godot - the skip list is broken"
  exit 1
fi
autoload_re="\\b($(printf '%s' "$autoloads" | paste -sd'|' -))\\b"
echo "autoloads: $(printf '%s' "$autoloads" | paste -sd',' -)"

step "1/9 import"
"$GODOT" --headless --path . --import >/dev/null 2>&1
result $? "project imports"

step "2/9 source rules"
"$GODOT" --headless --path . -s tools/lint_rules.gd
result $? "no unseeded RNG, raw directions or stray colours"

step "3/9 script parse"
# One engine boot per file, and the parse itself is free - the 0.35s is startup. So they run
# four at a time. Each is independent and read-only, which is why this is safe to parallelize
# where nothing else in this gate is; a failure has to be recorded in a FILE rather than a
# variable, because a variable set inside an xargs child dies with it.
parse_out="$(mktemp -d)"
parse_one() {
  local f="$1" out
  out=$("$GODOT" --headless --path . --check-only -s "$f" 2>&1)
  if echo "$out" | grep -qE 'Parse Error|Compile Error'; then
    { echo "  $f"; echo "$out" | grep -E 'Parse Error|Compile Error' | head -3; } \
      > "$parse_out/$(echo "$f" | tr '/.' '__')"
  fi
}
export -f parse_one
export GODOT parse_out

# No directory list here on purpose. A list would be a fourth copy of "what this project
# contains" (LintCore.SOURCE_ROOTS is the other three), and the failure mode of a stale
# one is silence: a new directory simply stops being parsed. Scanning everything and
# excluding what is not ours cannot go stale.
#
# Autoload singletons do not exist in a standalone script run, so a script that references
# GameState "fails" here for a reason that is not a defect. Those are covered by the smoke
# boot and by the whole-project compile instead.
find . -name '*.gd' \
  -not -path './addons/*' -not -path './.godot/*' -not -path './.git/*' \
  -not -path './build/*' -not -path './export/*' 2>/dev/null \
  | while IFS= read -r f; do grep -qE "$autoload_re" "$f" || printf '%s\n' "$f"; done \
  | xargs -P 4 -I{} bash -c 'parse_one "$@"' _ {}

parse_fail=0
# A count, not a glob test: an empty directory and a directory with one report must not look
# alike, and the reports are what say which file failed.
if [ "$(find "$parse_out" -type f | wc -l | tr -d ' ')" -gt 0 ]; then
  cat "$parse_out"/*
  parse_fail=1
fi
rm -rf "$parse_out"
result $parse_fail "standalone scripts parse"

step "3b/9 whole-project compile"
# Per-file --check-only cannot resolve types that come from other scripts; this loads
# everything together so a cross-script signature mismatch fails here, loudly, instead of
# inside the test runner as a crash.
"$GODOT" --headless --path . -s tools/compile_all.gd
result $? "cross-script compile"

step "4/9 tests"
if [ -f addons/gdUnit4/bin/GdUnitCmdTool.gd ]; then
  # gdUnit4 exits 0 both when it runs everything and when it runs NOTHING - a bad target
  # path, or a scanner crash during discovery, produces a green exit with no tests
  # executed. Count the suites on disk and require at least that many to report, so "the
  # runner died" can never read as "the tests passed".
  expected_suites=$(find tests -name 'test_*.gd' | wc -l | tr -d ' ')
  if [ "$expected_suites" -lt 1 ]; then
    echo "FAIL  no test suites found on disk - tests/ is missing or renamed"
    fail=1
  fi
  gd_out=$("$GODOT" --headless $GODOT_FRAMES --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests --ignoreHeadlessMode -c 2>&1)
  gd_status=$?
  printf '%s\n' "$gd_out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Overall Summary|Executed test suites' || true
  # WHICH test failed, not just that one did. Without this a red gate in CI names a count and
  # nothing else, and the only way to find out is to reproduce the whole run on that platform -
  # which is exactly the situation where you cannot. gdUnit4 prints the name and the reason
  # around its FAILED line, so print that band and nothing else.
  printf '%s\n' "$gd_out" | sed 's/\x1b\[[0-9;]*m//g' | grep -A6 -E '> .* FAILED' || true
  if printf '%s' "$gd_out" | grep -q 'handle_crash'; then
    echo "  gdUnit4 CRASHED during discovery or execution (exit was $gd_status)"
    gd_status=1
  fi
  ran_suites=$(printf '%s' "$gd_out" | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -oE 'Executed test suites *: *\(([0-9]+)/' | grep -oE '[0-9]+' | head -1)
  ran_suites=${ran_suites:-0}
  if [ "$ran_suites" -lt "$expected_suites" ]; then
    echo "  ran $ran_suites of $expected_suites test suites on disk"
    gd_status=1
  fi
  ( exit $gd_status )
  result $? "gdUnit4 suite"
else
  echo "FAIL  gdUnit4 is not vendored at addons/gdUnit4/bin/GdUnitCmdTool.gd"
  fail=1
fi

step "5/9 smoke boot"
"$GODOT" --headless --path . -s tools/smoke_boot.gd
result $? "autoloads boot, input map present, pixel settings intact"

step "6/9 generated art is in sync"
# The committed PNGs under assets/generated are build output. Regenerating must not change
# them; if it does, someone edited a rig or a style and shipped the old sprites.
"$GODOT" --headless --path . -s tools/gen_sprites.gd --verify
result $? "committed sprites match the generator"

step "6b/9 generated sound is in sync"
# The committed WAVs under assets/generated are build output too. This compares the SAMPLES
# rather than the file bytes - a container header is not ours to control - and then compares
# what load() returns, because the importer is free to transcode on the way to the game and
# its default for WAV is lossy. A file that matches while the imported stream does not is a
# game whose every player hears something the gate never checked.
"$GODOT" --headless --path . -s tools/gen_sounds.gd --verify
result $? "committed sounds match the generator"

step "6c/9 the flow diagram matches the model"
# docs/FLOW.md is drawn from tools/flow_model.json, so it is build output like the sprites and
# the sounds. Checked here rather than in the suite because it is a file-on-disk question, and
# checked BEFORE the play loop so a stale diagram is reported in a second rather than after
# twenty of them. The model itself is checked against the running game by
# tests/integration/test_flow_model.gd in step 4.
"$GODOT" --headless --path . -s tools/gen_flow_doc.gd --verify
result $? "the flow diagram matches the model"

step "6d/9 maps survive a trip through an editor"
# The only gate that runs the CONVERSION COMMAND rather than the translators behind it. The
# suites round-trip every shipped map in memory, Dictionary to Dictionary, which says nothing
# about a path, an extension, a directory or an argument - and map_io.gd is entirely those. So
# this writes every map out to Tiled AND LDtk as real files, reads them back, and requires the
# game's own reading of what returns to be the same map.
#
# Nothing it writes is committed: the editor file is a working file, and the map that ships is
# still the hand-readable JSON. It sweeps its scratch directory either way.
"$GODOT" --headless --path . -s tools/map_io.gd --verify
result $? "maps survive a trip through an editor"

step "7/9 play the game"
# The gate that needs the whole thing at once: the real physics server, the real input map,
# the real map data. It boots the game, walks the player east, and checks a wall stops them.
# Unit tests cannot answer any of those, and `-s tools/x.gd` cannot even load a scene whose
# script names an autoload - so this runs the game proper and drives it from a script.
#
# Scripts are grouped by the game they drive - tests/fixtures/qa/<game>/*.json - and each is
# run with --game=<dirname>. A hardcoded list here was fine while there was one game and
# stopped being fine the moment there were two: a second game's scripts would simply never
# run, and the gate would report a full pass having driven only the first.
play_fail=0
play_ran=0
for game_dir in tests/fixtures/qa/*/; do
  [ -d "$game_dir" ] || continue
  game_id="$(basename "$game_dir")"
  # A directory named after a game drives that game. One that is NOT the name of a game runs
  # with no --game= at all, which is how a script gets to meet the picker: the flag is exactly
  # what makes the picker stay out of the way. Derived from what is in data/games rather than
  # from a list here, so it cannot go stale.
  game_flag="--game=$game_id"
  if [ ! -f "data/games/$game_id.tres" ]; then
    game_flag=""
  fi
  for script in "$game_dir"*.json; do
    [ -f "$script" ] || continue
    play_ran=$((play_ran + 1))
    "$GODOT" --headless $GODOT_FRAMES --path . -- --qa-script="res://$script" $game_flag
    if [ $? -ne 0 ]; then
      echo "  FAILED: $script ${game_flag:-(no game chosen: the picker decides)}"
      play_fail=1
    fi
  done
done
# A play gate that drove nothing is a broken gate, not a passing one - the same reason
# lint_rules refuses to report a clean scan of zero files.
if [ "$play_ran" -eq 0 ]; then
  echo "  no QA scripts found under tests/fixtures/qa/<game>/ - the gate ran nothing"
  play_fail=1
fi
result $play_fail "$play_ran scripted play sessions"

step "7b/9 the exported artifact plays"
# Every step above this line runs against res:// in the project directory. This one runs against
# the .pck a player downloads, which is a different thing: an asset that is not packed, an
# exclude filter that grew, an importer that did not run - none of those are visible from the
# source tree, and M14 shipped one that had been broken in exports since it was written.
#
# It is here rather than only on the deploy because it turned out to cost FIVE SECONDS, export
# included - --export-pack needs no export templates, and --main-pack boots the pack with the
# stock binary. That was measured before deciding where to put it.
tools/pack_check.sh
result $? "the exported artifact plays"

# Cheap, so it runs EVERY time rather than only with MUTANTS=1. A mutant's aim is broken by
# writing new code, not by editing the mutant: add a function whose body happens to repeat a
# line an existing pattern anchors on, and sed edits whichever comes first - so the mutant
# starts reporting a verdict about a function nobody is testing. That has happened twice, and
# both times the full mutation run found it twenty minutes later, in CI.
step "8/9 mutants still aim at one line each"
tools/mutants_aim.sh
result $? "every mutant lands on exactly one line"

# Cheap, and it guards a SILENT failure: CI picks a pull request's mutants with this, so a
# scoper that selects nothing reads as "this change needed no mutants" rather than as a broken
# tool. Its selftest already caught one real bug - awk's -v cannot carry a newline, so the
# first version matched nothing at all.
step "8b/9 the mutant scoper still selects"
tools/mutants_scope.sh --selftest
result $? "a change still selects the mutants it could have broken"


# Opt-in because it re-runs a suite per mutant. It is the gate that proves the OTHER gates
# bite, so it runs before a milestone is called done, not on every save:
#   MUTANTS=1 tools/check.sh
if [ "${MUTANTS:-0}" = "1" ]; then
  step "9/9 mutation check"
  # --assume-green: step 4/9 above proved all 54 suites green minutes ago in this same run,
  # so re-proving each one before its mutants is 49 extra engine boots to answer a question
  # already answered.
  tools/mutate_check.sh --assume-green --all
  result $? "every mutant killed"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then echo "check.sh: ALL GATES PASS"; else echo "check.sh: FAILURES ABOVE"; fi
exit "$fail"
