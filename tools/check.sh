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

step "1/7 import"
"$GODOT" --headless --path . --import >/dev/null 2>&1
result $? "project imports"

step "2/7 source rules"
"$GODOT" --headless --path . -s tools/lint_rules.gd
result $? "no unseeded RNG, raw directions or stray colours"

step "3/7 script parse"
parse_fail=0
while IFS= read -r f; do
  # Autoload singletons do not exist in a standalone script run, so a script that
  # references GameState "fails" here for a reason that is not a defect. Those are covered
  # by the smoke boot instead.
  if grep -qE "$autoload_re" "$f"; then
    continue
  fi
  out=$("$GODOT" --headless --path . --check-only -s "$f" 2>&1)
  if echo "$out" | grep -qE 'Parse Error|Compile Error'; then
    echo "  $f"; echo "$out" | grep -E 'Parse Error|Compile Error' | head -3
    parse_fail=1
  fi
  # No directory list here on purpose. A list would be a fourth copy of "what this project
  # contains" (LintCore.SOURCE_ROOTS is the other three), and the failure mode of a stale
  # one is silence: a new directory simply stops being parsed. Scanning everything and
  # excluding what is not ours cannot go stale.
done < <(find . -name '*.gd' \
  -not -path './addons/*' -not -path './.godot/*' -not -path './.git/*' \
  -not -path './build/*' -not -path './export/*' 2>/dev/null)
result $parse_fail "standalone scripts parse"

step "3b/7 whole-project compile"
# Per-file --check-only cannot resolve types that come from other scripts; this loads
# everything together so a cross-script signature mismatch fails here, loudly, instead of
# inside the test runner as a crash.
"$GODOT" --headless --path . -s tools/compile_all.gd
result $? "cross-script compile"

step "4/7 tests"
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
  gd_out=$("$GODOT" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests --ignoreHeadlessMode -c 2>&1)
  gd_status=$?
  printf '%s\n' "$gd_out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Overall Summary|Executed test suites' || true
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

step "5/7 smoke boot"
"$GODOT" --headless --path . -s tools/smoke_boot.gd
result $? "autoloads boot, input map present, pixel settings intact"

step "6/7 generated art is in sync"
# The committed PNGs under assets/generated are build output. Regenerating must not change
# them; if it does, someone edited a rig or a style and shipped the old sprites.
if [ -f tools/gen_sprites.gd ]; then
  "$GODOT" --headless --path . -s tools/gen_sprites.gd --verify
  result $? "committed sprites match the generator"
else
  echo "SKIP  gen_sprites.gd does not exist yet (M1)"
fi

step "7/7 play the game"
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
  for script in "$game_dir"*.json; do
    [ -f "$script" ] || continue
    play_ran=$((play_ran + 1))
    "$GODOT" --headless --path . -- --qa-script="res://$script" --game="$game_id"
    if [ $? -ne 0 ]; then
      echo "  FAILED: $script (--game=$game_id)"
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


# Opt-in because it re-runs a suite per mutant. It is the gate that proves the OTHER gates
# bite, so it runs before a milestone is called done, not on every save:
#   MUTANTS=1 tools/check.sh
if [ "${MUTANTS:-0}" = "1" ]; then
  step "8/8 mutation check"
  tools/mutate_check.sh --all
  result $? "every mutant killed"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then echo "check.sh: ALL GATES PASS"; else echo "check.sh: FAILURES ABOVE"; fi
exit "$fail"
