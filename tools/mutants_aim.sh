#!/usr/bin/env bash
# Checks that every mutant in mutants.tsv still lands on EXACTLY ONE line.
#
# mutate_check.sh already refuses an ambiguous mutant (TOO BROAD) - but it finds out by
# running the whole suite for every row, which is twenty-odd minutes. This answers the same
# question in about a second, and it answers it for a reason worth having separately:
#
# A MUTANT'S AIM IS BROKEN BY WRITING NEW CODE, NOT BY EDITING THE MUTANT.
#
# Both times this bit, the row was years-old and untouched: a new function was added whose
# body happened to contain a line character-identical to the one an existing pattern anchored
# on, and sed edited whichever came first. The mutant then reported a verdict about a
# function nobody was testing. Nothing in the diff of that change looks wrong.
#
# So run this after any change that ADDS code near something already covered - it is cheap
# enough to run every time - and fix it by making the two lines differ (rename the local,
# anchor on an adjacent unique line), never by loosening the pattern.
#
# Exits 1 if any row matches zero lines (stale) or more than one (ambiguous).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TSV="${MUTANTS_TSV:-tools/mutants.tsv}"
[ -f "$TSV" ] || { echo "mutants_aim: no $TSV" >&2; exit 1; }

fail=0
rows=0
while IFS=$'\t' read -r file expr suite label; do
	[ -n "${file:-}" ] || continue
	rows=$((rows + 1))
	if [ ! -f "$file" ]; then
		echo "MISSING FILE  $file  :: $label"
		fail=1
		continue
	fi
	# Count the lines sed actually rewrites, the same way mutate_check.sh judges it.
	changed=$(sed -E "$expr" "$file" 2>/dev/null | diff "$file" - | grep -c '^>')
	if [ "$changed" = "0" ]; then
		echo "STALE         $file  :: $label"
		echo "              the pattern matches nothing - the mutant is out of date, not the code"
		fail=1
	elif [ "$changed" != "1" ]; then
		echo "AMBIGUOUS     $file  (matches $changed lines)  :: $label"
		echo "              sed edits the FIRST one, so this mutant reports a verdict about"
		echo "              whichever function happens to come first in the file"
		fail=1
	fi
done < <(grep -vE '^\s*(#|$)' "$TSV")

if [ "$rows" -eq 0 ]; then
	echo "mutants_aim: no rows read from $TSV - the scan is broken, not the file" >&2
	exit 1
fi
if [ "$fail" -eq 0 ]; then
	echo "mutants_aim: $rows mutants, each landing on exactly one line"
fi
exit $fail
