#!/usr/bin/env bash
# Whether a change can move anything the gate tests. Prints `true` or `false`.
#
#   tools/ci_changed.sh [--base <ref>]        # default base: origin/main
#   tools/ci_changed.sh --files a.md b.gd     # explicit list, for tests
#   tools/ci_changed.sh --selftest
#
# ci.yml asks this on a pull request and skips the gate and the sweep when it answers false,
# while a job named `check` reports the required status either way. That replaced a second
# workflow whose paths were the mirror image of ci.yml's - one rule written in two YAML files,
# where neither copy could be run or tested directly. Here it is one script with a selftest,
# and tests/unit/test_ci_paths.gd calls THIS rather than parsing the workflow.
#
# The stakes are asymmetric, so it fails CLOSED: a path wrongly answered `true` runs the gate
# for nothing, and a path wrongly answered `false` lands a change with a green check that
# tested it. An empty list is `true` for the same reason - no evidence is not evidence of no
# change, and a diff that comes back empty is more likely a broken base ref than a no-op.
#
# docs/FLOW.md is the exception that shapes the rule: it is GENERATED from the flow model and
# compared by check.sh, so a hand-edit to it must run the real gate. test_ci_paths.gd derives
# that exception from the generators themselves, so the next generated doc cannot be forgotten.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# $1 = file of changed paths, one per line
answer() {
  local needs=false seen=0 path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    seen=$((seen + 1))
    case "$path" in
      docs/FLOW.md) needs=true ;;
      CLAUDE.md) ;;
      README.md) ;;
      docs/*) ;;
      *) needs=true ;;
    esac
  done < "$1"
  # Fail closed on an empty list. Written as an `if` rather than the shorter `[ ... ] ||`
  # because the mutation harness's expressions are pipe-delimited, and a rule no mutant can
  # aim at is a rule nobody has proven is tested.
  if [ "$seen" -eq 0 ]; then needs=true; fi
  echo "$needs"
}

selftest() {
  local dir list fail=0
  dir="$(mktemp -d)"
  list="$dir/changed"

  expect() { # $1 label  $2 expected  $3 paths (newline separated)
    local got
    printf '%s\n' "$3" > "$list"
    got="$(answer "$list")"
    if [ "$got" != "$2" ]; then echo "  selftest FAIL: $1 (expected $2, got $got)"; fail=1
    else echo "  ok: $1"; fi
  }

  expect "a script runs the gate"              true  "scripts/world/world_scene.gd"
  expect "a test runs the gate"                true  "tests/unit/test_saves.gd"
  expect "content runs the gate"               true  "data/maps/quest_village.json"
  expect "the harness runs the gate"           true  "tools/check.sh"
  expect "a workflow runs the gate"            true  ".github/workflows/ci.yml"
  expect "the agent contract does not"         false "CLAUDE.md"
  expect "the readme does not"                 false "README.md"
  expect "a document does not"                 false "docs/DECISIONS.md"
  expect "a nested document does not"          false "docs/lpc_designs/the_road.json"
  expect "the generated flow doc DOES"         true  "docs/FLOW.md"
  expect "docs beside code run the gate"       true  "docs/DECISIONS.md
scripts/world/world_scene.gd"
  # No evidence is not evidence of no change: an empty diff is more likely a broken base ref.
  expect "an empty change list runs the gate"  true  ""

  rm -rf "$dir"
  [ "$fail" -eq 0 ] || return 1
  echo "  ci_changed: selftest passed"
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
    answer "$list"
    rm -f "$list"
    exit 0
    ;;
  --base|'')
    base="${2:-origin/main}"
    [ "${1:-}" = "" ] && base="origin/main"
    changed="$(mktemp)"
    git diff --name-only "$base"...HEAD 2>/dev/null > "$changed"
    answer "$changed"
    rm -f "$changed"
    exit 0
    ;;
  *)
    echo "usage: tools/ci_changed.sh [--base <ref>] | --files <path>... | --selftest" >&2
    exit 2
    ;;
esac
