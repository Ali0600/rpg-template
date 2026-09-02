#!/usr/bin/env bash
# Fetches the art a tile bank cuts from, into the directory the bank reads it from.
#
#     tools/fetch_tiles.sh data/tiles/lpc32.json
#
# An AUTHORING CONVENIENCE, never a gate. The drift gate compares committed inputs to committed
# outputs and never reaches the network; this exists so the inputs can be got in the first place,
# and so the next person can see where each file came from rather than being told to go looking.
#
# A file already present is left alone, so a re-run costs nothing and cannot overwrite art that
# was fetched by hand. An entry with no `url` is exactly that case - a pack that arrives as a zip
# has no single file to curl, so its sheet is extracted once and put in place by a person; this
# reports it rather than failing, because "you have to do this one yourself" is information.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

bank="${1:-}"
if [ -z "$bank" ] || [ ! -f "$bank" ]; then
  echo "fetch_tiles: usage: tools/fetch_tiles.sh <data/tiles/bank.json>" >&2
  exit 1
fi

read -r id kind < <(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("id", ""), d.get("pixels_from", "rows"))
' "$bank")

if [ "$kind" != "files" ]; then
  echo "fetch_tiles: '$bank' draws its own pixels; there is nothing to fetch" >&2
  exit 1
fi

dest="data/imports/tiles/$id"
mkdir -p "$dest"
fetched=0
present=0
byhand=0

while IFS='	' read -r name url; do
  if [ -f "$dest/$name" ]; then
    present=$((present + 1))
    continue
  fi
  if [ -z "$url" ]; then
    echo "  BY HAND  $name - no url; see the bank's urls and put the file at $dest/$name"
    byhand=$((byhand + 1))
    continue
  fi
  if curl -fsSL "$url" -o "$dest/$name"; then
    echo "  fetched  $name"
    fetched=$((fetched + 1))
  else
    echo "fetch_tiles: could not fetch $url" >&2
    rm -f "$dest/$name"
    exit 1
  fi
done < <(python3 -c '
import json, sys
for f in json.load(open(sys.argv[1])).get("files", []):
    print("%s\t%s" % (f.get("file", ""), f.get("url", "")))
' "$bank")

echo "fetch_tiles: $fetched fetched, $present already there, $byhand to place by hand ($dest)"
[ "$byhand" -eq 0 ]
