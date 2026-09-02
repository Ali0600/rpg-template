#!/usr/bin/env bash
# Break one rule, prove a test notices, put it back.
#
# A test that has never failed proves nothing. This runs each mutant in tools/mutants.tsv:
# it edits one line of a source file, runs the suite that is supposed to care, and reports
# KILLED (the suite went red) or SURVIVED (the suite passed while the rule was broken -
# meaning that assertion is decoration).
#
# Every step that could quietly do nothing is checked instead of assumed:
#   * the file must actually CHANGE, and by exactly one line - a stale pattern that
#     matched nothing, or one that matched somewhere else entirely, is a hard failure and
#     never a skip
#   * the suite must be GREEN before the mutation, or "it went red" means nothing
#   * the mutated run must EXECUTE at least one suite - gdUnit4 exits non-zero when it
#     crashes during discovery too, and a mutation that breaks parsing would otherwise
#     read as a test bite that never happened
#   * the file is restored from a byte copy (never git checkout, which would discard
#     uncommitted work in the same file) and its checksum re-verified
#
# Usage:
#   tools/mutate_check.sh --all
#   tools/mutate_check.sh --list
#   tools/mutate_check.sh --assume-green --all   (only right after a full green suite run)
#   tools/mutate_check.sh <file> <sed-expression> <suite> [label]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot

TSV="${MUTANTS_TSV:-tools/mutants.tsv}"
RUNNER="addons/gdUnit4/bin/GdUnitCmdTool.gd"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# Echoes "<suites_ran> <failures> <errors> <crashed>" for a suite run.
#
# A "suite" may also be a scripted PLAY SESSION under tests/fixtures/qa/. The play gate proves
# things no unit suite can - that the real loop, the real input map and the real map data agree -
# and until it could be mutated, none of that was ever proven to bite. It was worth doing the
# moment a session cost two seconds instead of ninety.
run_suite() {
  local out ran fails errs crashed
  case "$1" in
    tests/fixtures/qa/*)
      # The game is the directory the script lives in, exactly as check.sh derives it, so this
      # needs no list of its own to go stale.
      local game
      game=$(basename "$(dirname "$1")")
      "$GODOT" --headless $GODOT_FRAMES --path . -- --qa-script="res://$1" --game="$game" \
        >/dev/null 2>&1
      if [ $? -eq 0 ]; then printf '1 0 0 0'; else printf '1 1 0 0'; fi
      return
      ;;
  esac
  out=$("$GODOT" --headless $GODOT_FRAMES --path . -s "$RUNNER" -a "$1" --ignoreHeadlessMode -c 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g')
  crashed=0
  printf '%s' "$out" | grep -q 'handle_crash' && crashed=1
  ran=$(printf '%s' "$out" | grep -oE 'Executed test suites: *\([0-9]+/' \
        | grep -oE '[0-9]+' | head -1)
  fails=$(printf '%s' "$out" | grep -oE '\| *[0-9]+ failures' | grep -oE '[0-9]+' | tail -1)
  errs=$(printf '%s' "$out" | grep -oE '\| *[0-9]+ errors' | grep -oE '[0-9]+' | tail -1)
  printf '%s %s %s %s' "${ran:-0}" "${fails:-0}" "${errs:-0}" "$crashed"
}

verified_green=" "

# Skips the baseline runs. Only safe where a FULL green suite run already proved this exact
# tree - check.sh proves every suite green at step 4/9 and only then reaches step 9/9, and in
# CI the `gate` job does it before any `sweep` shard starts. Across jobs is the same claim as
# within one: a suite run and a mutant run have never shared anything but the checkout, the
# binary and the import cache, and a shard rebuilds all three from the same inputs. In that
# window a per-suite baseline is a second answer to a question already answered, and it is
# dozens of extra engine boots to get it.
#
# The risk it accepts, stated plainly: if a suite were ALREADY red, every mutant against it
# would read as KILLED. That is exactly what the baseline exists to catch - so this flag is for
# call sites that have just proven the opposite, and never for a bare run.
ASSUME_GREEN=0

# A red baseline makes every mutant look killed, so each suite is proven green once first.
ensure_green() {
  [ "$ASSUME_GREEN" = "1" ] && return 0
  case "$verified_green" in *" $1 "*) return 0 ;; esac
  read -r ran fails errs crashed <<<"$(run_suite "$1")"
  if [ "$crashed" -ne 0 ] || [ "$ran" -lt 1 ] || [ "$fails" -ne 0 ] || [ "$errs" -ne 0 ]; then
    echo "BASELINE FAILURE: $1 is not green before mutation"
    echo "  (suites ran=$ran failures=$fails errors=$errs crashed=$crashed)"
    return 1
  fi
  verified_green="${verified_green}$1 "
  return 0
}

# $1 file  $2 sed expression  $3 suite  $4 label
mutate_one() {
  local file="$1" expr="$2" suite="$3" label="${4:-$2}"
  local backup="$WORK/$(echo "$file" | tr '/' '_')"
  local before after changed_lines

  [ -f "$file" ] || { echo "MISSING FILE  $file"; return 2; }
  [ -e "$suite" ] || { echo "MISSING SUITE $suite"; return 2; }
  ensure_green "$suite" || return 2

  before="$(sha "$file")"
  cp "$file" "$backup"
  # Restore even on an interrupt: a half-mutated source file left on disk is the one
  # outcome worse than a surviving mutant.
  trap 'cp "$backup" "$file" 2>/dev/null; rm -rf "$WORK"; exit 130' INT TERM

  sed -E "$expr" "$file" > "$WORK/mutated" || { echo "SED FAILED    $label"; return 2; }
  cp "$WORK/mutated" "$file"
  after="$(sha "$file")"

  if [ "$before" = "$after" ]; then
    cp "$backup" "$file"
    echo "NOT APPLIED   $label"
    echo "  the pattern matched nothing in $file - the mutant is stale, not the code"
    return 2
  fi

  changed_lines=$(diff "$backup" "$file" | grep -c '^>')
  if [ "$changed_lines" -ne 1 ]; then
    cp "$backup" "$file"
    echo "TOO BROAD     $label"
    echo "  changed $changed_lines lines in $file; a mutant must land on exactly one"
    return 2
  fi

  read -r ran fails errs crashed <<<"$(run_suite "$suite")"

  cp "$backup" "$file"
  trap 'rm -rf "$WORK"' INT TERM
  if [ "$(sha "$file")" != "$before" ]; then
    echo "RESTORE FAILED $file no longer matches its original checksum"
    return 3
  fi

  if [ "$crashed" -ne 0 ] || [ "$ran" -lt 1 ]; then
    echo "BROKEN        $label"
    echo "  the mutation stopped the runner (ran=$ran crashed=$crashed); no test judged it"
    return 2
  fi
  if [ $((fails + errs)) -gt 0 ]; then
    echo "KILLED        $label"
    return 0
  fi
  echo "SURVIVED      $label"
  echo "  $suite passed with $file:$expr applied - that rule is not actually tested"
  return 1
}

# Consumed before the mode dispatch so it composes with every form, including the positional
# single-mutant one.
while [ "${1:-}" = "--assume-green" ]; do
  ASSUME_GREEN=1
  shift
done

case "${1:-}" in
  --list)
    grep -vE '^\s*(#|$)' "$TSV" | awk -F'\t' '{printf "%-28s %s\n", $3, $4}'
    exit 0
    ;;
  --all)
    total=0; killed=0; bad=0
    while IFS=$'\t' read -r file expr suite label; do
      case "$file" in ''|'#'*) continue ;; esac
      total=$((total + 1))
      mutate_one "$file" "$expr" "$suite" "$label"
      case $? in
        0) killed=$((killed + 1)) ;;
        *) bad=$((bad + 1)) ;;
      esac
    done < <(grep -vE '^\s*(#|$)' "$TSV")
    printf '\n%d/%d mutants killed\n' "$killed" "$total"
    [ "$bad" -eq 0 ] || exit 1
    exit 0
    ;;
  '')
    echo "usage: tools/mutate_check.sh [--assume-green] --all | --list | <file> <sed-expr> <suite> [label]"
    exit 2
    ;;
  *)
    mutate_one "$1" "$2" "$3" "${4:-}"
    exit $?
    ;;
esac
