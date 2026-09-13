#!/usr/bin/env bash
# Fetches the art a tile bank cuts from, into the directory the bank reads it from, and checks it.
#
#     tools/fetch_tiles.sh data/tiles/lpc32.json
#     tools/fetch_tiles.sh data/tiles/lpc32.json --into=build/tiles_check   # what the URLs serve now
#     tools/fetch_tiles.sh --selftest
#
# An AUTHORING CONVENIENCE, never a gate. The drift gate compares committed inputs to committed
# outputs and never reaches the network; this exists so the inputs can be got in the first place,
# and so the next person can see where each file came from rather than being told to go looking.
#
# A file already present is left alone, so a re-run cannot overwrite art that was fetched by hand.
# An entry with no `url` is exactly that case - a pack that arrives as a zip has no single file to
# curl, so its sheet is extracted once and put in place by a person; this reports it rather than
# failing silently, because "you have to do this one yourself" is information.
#
# EVERY FILE IS CHECKED AGAINST THE `sha256` ITS BANK NAMES - fetch_godot.sh's rule, one noun along.
# The sum sits in the repository beside the URL, because a sum served by the host that serves the
# file cannot notice that host serving a different one. None of the three outcomes is quiet:
#   - a download that does not match is never put in place;
#   - a file already there that does not match is REPORTED and left alone, because it may be art
#     somebody placed on purpose, and then it is the bank that is out of date;
#   - a url with no sum is fetched to scratch and not put in place either: the run prints the sum it
#     got, so adding a file is a decision made by somebody who has looked at it.
# So a plain re-run doubles as a check that the committed sheets are the ones the bank was cut from,
# and it reaches no network when they are all there.
#
# Names are file names, never paths. A bank naming "../x.png" would write wherever that points, so a
# file name or a bank id with a slash in it is refused before anything touches the disk.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ROOT="data/imports/tiles"

# Prefer coreutils, fall back to shasum - fetch_godot.sh's reason: macOS has no sha256sum.
SHA256_TOOL="shasum -a 256"
command -v sha256sum >/dev/null 2>&1 && SHA256_TOOL="sha256sum"
sha256_of() { # $1 file
  $SHA256_TOOL "$1" 2>/dev/null | awk '{print $1}'
}

# RULE 1: a name is a file name, never a path. One test per line rather than a `case` with
# alternatives, because mutants.tsv cannot anchor on a line holding `|`.
plain_name() { # $1 name
  if [ -z "$1" ]; then return 1; fi
  if [ "$1" = "." ]; then return 1; fi
  if [ "$1" = ".." ]; then return 1; fi
  case "$1" in */*) return 1 ;; esac
  return 0
}

# RULE 2: the bytes are the ones the bank names. An empty expected sum matches nothing.
matches() { # $1 file  $2 expected sha256
  local got
  got="$(sha256_of "$1")"
  if [ -z "$got" ]; then
    echo "fetch_tiles: no sha256 tool on this host (looked for sha256sum, shasum)" >&2
    return 1
  fi
  [ "$got" = "$2" ]
}

# The whole run, for any bank into any root. The selftest drives this same function against a
# scratch directory and file:// URLs.
fetch_bank() { # $1 bank json  $2 the directory holding one directory per bank
  local bank="$1" root="$2" header id kind dest scratch
  local name sum url fetched=0 present=0 byhand=0 refused=0
  if ! header="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print("%s\x1f%s" % (d.get("id", ""), d.get("pixels_from", "rows")))
' "$bank" 2>/dev/null)"; then
    echo "fetch_tiles: '$bank' is not a bank this can read" >&2
    return 1
  fi
  IFS=$'\x1f' read -r id kind <<< "$header"
  if [ "$kind" != "files" ]; then
    echo "fetch_tiles: '$bank' draws its own pixels; there is nothing to fetch" >&2
    return 1
  fi
  if ! plain_name "$id"; then
    echo "fetch_tiles: bank id '$id' is not a directory name" >&2
    return 1
  fi
  dest="$root/$id"
  mkdir -p "$dest"
  scratch="$(mktemp -d)"

  while IFS=$'\x1f' read -r name sum url; do
    if ! plain_name "$name"; then
      echo "  REFUSED  '$name' - a bank names files, not paths"
      refused=$((refused + 1))
      continue
    fi
    if [ -f "$dest/$name" ]; then
      if ! matches "$dest/$name" "$sum"; then
        echo "  CHANGED  $name - on disk it is $(sha256_of "$dest/$name"), and the bank names '$sum'"
        refused=$((refused + 1))
        continue
      fi
      present=$((present + 1))
      continue
    fi
    if [ -z "$url" ]; then
      echo "  BY HAND  $name - no url; see the bank's urls and put the file at $dest/$name"
      byhand=$((byhand + 1))
      continue
    fi
    if ! curl -fsSL "$url" -o "$scratch/$name"; then
      echo "fetch_tiles: could not fetch $url" >&2
      rm -rf "$scratch"
      return 1
    fi
    if ! matches "$scratch/$name" "$sum"; then
      echo "  REFUSED  $name - the url served $(sha256_of "$scratch/$name"), and the bank names '$sum'."
      echo "           Nothing was put in place. A new file's sum goes into the bank from somebody who has looked at it."
      refused=$((refused + 1))
      continue
    fi
    mv "$scratch/$name" "$dest/$name"
    echo "  fetched  $name"
    fetched=$((fetched + 1))
  done < <(python3 -c '
import json, sys
for f in json.load(open(sys.argv[1])).get("files", []):
    print("%s\x1f%s\x1f%s" % (f.get("file", ""), f.get("sha256", ""), f.get("url", "")))
' "$bank")

  rm -rf "$scratch"
  echo "fetch_tiles: $fetched fetched, $present already there and matching, $byhand to place by hand, $refused refused ($dest)"
  if [ "$refused" -ne 0 ]; then return 1; fi
  [ "$byhand" -eq 0 ]
}

# Every case drives the real fetch_bank over file:// URLs, so nothing reaches the network, and every
# case gets a fresh bank and a fresh root.
selftest() {
  local dir fail=0 good out
  dir="$(mktemp -d)"
  ok() { # $1 label  $2 expected code  $3 actual code
    if [ "$2" != "$3" ]; then
      echo "  selftest FAIL: $1 (expected exit $2, got $3)"; fail=1
    else echo "  ok: $1"; fi
  }
  says() { # $1 label  $2 haystack  $3 needle
    case "$2" in
      *"$3"*) echo "  ok: $1" ;;
      *) echo "  selftest FAIL: $1 (said: $2)"; fail=1 ;;
    esac
  }
  absent() { # $1 label  $2 path
    if [ -e "$2" ]; then echo "  selftest FAIL: $1 ($2 exists)"; fail=1
    else echo "  ok: $1"; fi
  }
  bank() { # $1 the bank's files array, as JSON
    rm -rf "$dir/root"
    printf '{"id": "cut", "pixels_from": "files", "files": %s}\n' "$1" > "$dir/bank.json"
  }
  run() {
    out="$(fetch_bank "$dir/bank.json" "$dir/root" 2>&1)"
  }

  printf 'fetch_tiles selftest\n' > "$dir/art.png"
  printf 'different bytes\n' > "$dir/other.png"

  # THE INSTRUMENT, by a known answer - fetch_godot.sh's reason. If the expected sum came from
  # sha256_of, one that returned a constant would accept the good case and refuse the bad one, and
  # every case below would pass over a function that computes nothing.
  good=ef1eba58e5bf1d0a4e069343d4aee3169385774fd23522b709de7e4f8d01a497
  if [ "$(sha256_of "$dir/art.png")" = "$good" ]; then
    echo "  ok: sha256_of computes SHA-256 (known answer)"
  else
    echo "  selftest FAIL: sha256_of gave '$(sha256_of "$dir/art.png")', not the known answer"; fail=1
  fi

  bank "[{\"file\": \"art.png\", \"sha256\": \"$good\", \"url\": \"file://$dir/art.png\"}]"
  run; ok "a download that matches its sum is accepted" 0 $?
  if [ "$(sha256_of "$dir/root/cut/art.png")" = "$good" ]; then echo "  ok: and it is in place"
  else echo "  selftest FAIL: the accepted download is not in place"; fail=1; fi
  run; ok "a re-run over matching art passes" 0 $?
  says "a re-run counts it as already there" "$out" "1 already there"

  bank "[{\"file\": \"art.png\", \"sha256\": \"$good\", \"url\": \"file://$dir/other.png\"}]"
  run; ok "a url serving other bytes is refused" 1 $?
  absent "a refused download is never put in place" "$dir/root/cut/art.png"

  bank "[{\"file\": \"art.png\", \"url\": \"file://$dir/art.png\"}]"
  run; ok "a url with no sum is not trusted" 1 $?
  says "it says what the url served, so a person can check it" "$out" "$good"
  absent "a file with no sum is never put in place" "$dir/root/cut/art.png"

  bank "[{\"file\": \"art.png\", \"sha256\": \"$good\"}]"
  mkdir -p "$dir/root/cut"
  cp "$dir/other.png" "$dir/root/cut/art.png"
  run; ok "art on disk that is not what the bank names is reported" 1 $?
  says "the report says it changed" "$out" "CHANGED"
  if [ "$(sha256_of "$dir/root/cut/art.png")" = "$(sha256_of "$dir/other.png")" ]; then
    echo "  ok: and the art is left alone"
  else echo "  selftest FAIL: art on disk was overwritten"; fail=1; fi

  bank "[{\"file\": \"../escaped.png\", \"sha256\": \"$good\", \"url\": \"file://$dir/art.png\"}]"
  run; ok "a file name that is a path is refused" 1 $?
  absent "nothing was written outside the bank's directory" "$dir/root/escaped.png"

  bank "[{\"file\": \"plants.png\", \"sha256\": \"$good\"}]"
  run; ok "a file with no url and nothing on disk is left to a person" 1 $?
  says "it says so" "$out" "BY HAND"

  rm -rf "$dir/root"
  printf '{"id": "../evil", "pixels_from": "files", "files": []}\n' > "$dir/bank.json"
  run; ok "a bank id that is a path is refused" 1 $?
  absent "and no directory was made for it" "$dir/evil"

  rm -rf "$dir"
  [ "$fail" -eq 0 ] || return 1
  echo "  fetch_tiles: selftest passed"
}

bank=""
into=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --selftest)
      selftest
      exit $?
      ;;
    --into=*) into="${1#--into=}" ;;
    # The 2026-08-04 lesson, made loud: the space form would leave the value in a positional slot.
    --into) echo "fetch_tiles: write --into=DIR, not --into DIR - the space form sets nothing" >&2; exit 1 ;;
    --*) echo "fetch_tiles: unknown flag '$1'" >&2; exit 1 ;;
    *) bank="$1" ;;
  esac
  shift
done

if [ -z "$bank" ] || [ ! -f "$bank" ]; then
  echo "fetch_tiles: usage: tools/fetch_tiles.sh <data/tiles/bank.json> [--into=DIR]" >&2
  exit 1
fi
fetch_bank "$bank" "${into:-$ROOT}"
