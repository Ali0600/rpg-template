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
# Touching the HARNESS - anything under tools/ or the workflows - selects EVERYTHING. Scoping
# by file assumes the machinery running the mutants is fixed; a change to check.sh or
# mutate_check.sh can invalidate every row at once, and by file it would select almost nothing.
# The commit that introduced this scoping is exactly that case.
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

  # The harness rule is a grep over the changed list rather than a row match, so it is checked
  # against the real predicate rather than through select_rows.
  harness() { printf '%s\n' "$2" | grep -qE '^(tools/|\.github/workflows/)'; }
  if harness "" "tools/check.sh"; then echo "  ok: a harness change is recognised"
  else echo "  selftest FAIL: tools/ not recognised as the harness"; fail=1; fi
  if harness "" ".github/workflows/ci.yml"; then echo "  ok: a workflow change is recognised"
  else echo "  selftest FAIL: workflows not recognised as the harness"; fail=1; fi
  if harness "" "scripts/world/world_scene.gd"; then
    echo "  selftest FAIL: ordinary source misread as the harness"; fail=1
  else echo "  ok: ordinary source is not the harness"; fi

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
    if grep -qE '^(tools/|\.github/workflows/)' "$changed"; then
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
