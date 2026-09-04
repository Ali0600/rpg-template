#!/usr/bin/env bash
# Selects the mutants a change actually needs, and prints them as a TSV on stdout.
#
#   tools/mutants_scope.sh [--base <ref>]        # default base: origin/main
#   tools/mutants_scope.sh --files a.gd b.gd     # explicit list, for tests and for hooks
#   tools/mutants_scope.sh --selftest
#
# A row is selected when the change touches the file it MUTATES (column 1) or the suite that
# is supposed to catch it (column 3). Both halves matter and for different reasons: editing a
# source file can break the rule, and editing a suite can stop it noticing.
#
# Editing tools/mutants.tsv itself selects every row the diff ADDED or CHANGED, so a new
# mutant is proven on the pull request that introduces it rather than after it merges.
#
# Touching the HARNESS selects EVERYTHING. Scoping by file assumes the machinery running the
# mutants is fixed; a change to check.sh or mutate_check.sh can invalidate every row at once,
# and by file it would select almost nothing. The commit that introduced this scoping is
# exactly that case.
#
# The harness is the files that RUN a mutant, and the list is exact rather than a directory.
# It used to be "anything under tools/", which included tools/mutants.tsv - and this project's
# contract requires every new rule to add a row there, so nearly every pull request that
# obeyed the contract selected all of them. Measured 2026-09-02: nine of the last ten pull
# request runs selected 513 to 579 of 579, and the "fast" lane was the full sweep wearing its
# name. A change to mutants.tsv needs no blanket: added_rows() below already selects exactly
# the rows it added.
#
# addons/gdUnit4/ is in the list because it is the runner every suite executes under, and
# .github/ rather than .github/workflows/ so a composite action put beside them counts too.
# tools/fetch_godot.sh is in it because it installs the ENGINE every mutant runs under - a
# version bump is exactly the change that deserves a full sweep rather than a scoped one.
#
# Accepted and stated rather than solved: project.godot and tests/helpers/* reach many suites
# and are still scoped by file. Main's full sweep is the backstop for both.
HARNESS_RE='^(tools/(check|mutate_check|mutants_scope|mutants_aim|_engine|fetch_godot)\.sh|\.github/|addons/gdUnit4/)'

# ONE predicate, used by the dispatch below AND by the selftest. It was two copies of the same
# regex, so the selftest was proving a duplicate of the rule rather than the rule.
is_harness_change() { # $1 file of changed paths
  grep -qE "$HARNESS_RE" "$1"
}
#
# What this is NOT: a replacement for the full sweep. Scoping cannot see a test that went
# decorative because of a change somewhere else entirely, so main re-runs everything on every
# merge. It also does not replace mutants_aim.sh, which is cheap enough to run over the whole
# file every time and is the thing that catches new code stealing an old mutant's aim.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TSV="${MUTANTS_TSV:-tools/mutants.tsv}"

# Rows whose mutated file or owning suite appears in the list of changed paths.
#
# The paths arrive in a FILE rather than through awk's -v, which cannot carry a newline: the
# first version of this passed a multi-line string that way, matched nothing, and was caught by
# the selftest below on its first run.
select_rows() { # $1 tsv  $2 file of changed paths, one per line
  awk -F'\t' '
    NR == FNR { if ($0 != "") want[$0] = 1; next }
    /^[[:space:]]*(#|$)/ { next }
    ($1 in want) || ($3 in want) { print }
  ' "$2" "$1"
}

# Rows the diff added or modified in the mutants file itself, so a brand new mutant is proven
# by the change that introduces it. Anchored on the sed expression, which is the column that
# actually identifies a row - a label can be reworded without changing what runs.
added_rows() {
  local base="$1" tsv="$2" exprs
  exprs="$(mktemp)"
  git diff -U0 "$base"...HEAD -- "$tsv" 2>/dev/null \
    | grep -E '^\+[^+]' | sed 's/^+//' | awk -F'\t' 'NF >= 3 { print $2 }' > "$exprs"
  if [ -s "$exprs" ]; then
    awk -F'\t' '
      NR == FNR { if ($0 != "") want[$0] = 1; next }
      /^[[:space:]]*(#|$)/ { next }
      ($2 in want) { print }
    ' "$exprs" "$tsv"
  fi
  rm -f "$exprs"
}

selftest() {
  local dir tsv fail=0
  dir="$(mktemp -d)"
  tsv="$dir/t.tsv"
  printf '# a comment\n\n' > "$tsv"
  printf 'scripts/a.gd\ts|x|y|\ttests/unit/test_a.gd\tlabel a\n' >> "$tsv"
  printf 'scripts/b.gd\ts|p|q|\ttests/unit/test_b.gd\tlabel b\n' >> "$tsv"

  check() { # $1 label  $2 expected count  $3 changed list
    local got list
    list="$dir/changed"
    printf '%s\n' "$3" > "$list"
    got=$(select_rows "$tsv" "$list" | wc -l | tr -d ' ')
    if [ "$got" != "$2" ]; then echo "  selftest FAIL: $1 (expected $2, got $got)"; fail=1
    else echo "  ok: $1"; fi
  }
  check "a changed source selects its own row"        1 "scripts/a.gd"
  check "a changed SUITE selects the row it guards"   1 "tests/unit/test_b.gd"
  check "both halves at once"                         2 "scripts/a.gd
tests/unit/test_b.gd"
  check "an unrelated file selects nothing"           0 "docs/README.md"
  check "comments and blank lines are never selected" 0 ""
  # A file whose NAME contains a row's name must not match - selection is on whole paths.
  check "a path that merely contains another"         0 "scripts/a.gd.uid"

  # A row whose mutated file lives under tools/ must still be reachable BY FILE, or narrowing
  # the harness rule would make it unselectable rather than merely unblanketed.
  printf 'tools/compile_all.gd\ts|a|b|\ttests/unit/test_compile_all.gd\tlabel c\n' >> "$tsv"
  check "a tool that is not the harness selects its own row" 1 "tools/compile_all.gd"

  # The harness rule is a grep over the changed list rather than a row match, so it is checked
  # through the REAL predicate - is_harness_change - rather than through a copy of its regex.
  harness() { printf '%s\n' "$2" > "$dir/one"; is_harness_change "$dir/one"; }
  for path in tools/check.sh tools/mutate_check.sh tools/mutants_scope.sh tools/mutants_aim.sh \
      tools/_engine.sh tools/fetch_godot.sh .github/workflows/ci.yml \
      addons/gdUnit4/bin/GdUnitCmdTool.gd; do
    if harness "" "$path"; then echo "  ok: $path is the harness"
    else echo "  selftest FAIL: $path is not recognised as the harness"; fail=1; fi
  done
  # The two that used to be swept up by "anything under tools/". mutants.tsv is the one that
  # cost the most: every pull request obeying the add-a-mutant rule ran the whole sweep.
  for path in tools/mutants.tsv tools/gen_sprites.gd scripts/world/world_scene.gd; do
    if harness "" "$path"; then
      echo "  selftest FAIL: $path misread as the harness"; fail=1
    else echo "  ok: $path is not the harness"; fi
  done

  rm -rf "$dir"
  [ "$fail" -eq 0 ] || return 1
  echo "  mutants_scope: selftest passed"
}

case "${1:-}" in
  --selftest)
    selftest
    exit $?
    ;;
  --files)
    shift
    list="$(mktemp)"
    printf '%s\n' "$@" > "$list"
    select_rows "$TSV" "$list"
    rm -f "$list"
    exit 0
    ;;
  --base|'')
    base="${2:-origin/main}"
    [ "${1:-}" = "" ] && base="origin/main"
    changed="$(mktemp)"
    git diff --name-only "$base"...HEAD 2>/dev/null > "$changed"
    if [ ! -s "$changed" ]; then
      echo "mutants_scope: no changes against $base" >&2
      rm -f "$changed"
      exit 0
    fi
    if is_harness_change "$changed"; then
      echo "mutants_scope: the harness itself changed - selecting every mutant" >&2
      grep -vE '^[[:space:]]*(#|$)' "$TSV"
    else
      { select_rows "$TSV" "$changed"; added_rows "$base" "$TSV"; } | sort -u
    fi
    rm -f "$changed"
    exit 0
    ;;
  *)
    echo "usage: tools/mutants_scope.sh [--base <ref>] | --files <path>... | --selftest" >&2
    exit 2
    ;;
esac
