#!/usr/bin/env bash
# Maps out to a visual editor, and back.
#
#   tools/map_io.sh --out=tiled --dir=build/maps    # write every map as .tmj
#   tools/map_io.sh --out=ldtk  --dir=build/maps    # write every map as .ldtk
#   tools/map_io.sh --in=build/maps/quest_village.ldtk
#   tools/map_io.sh --verify                        # what check.sh step 6d runs
#
# A wrapper over `tools/map_io.gd`, and it exists for one reason: so nobody has to type the
# engine's path. `_engine.sh` resolves it from the usual places and honours GODOT_BIN, which is
# the same resolution check.sh and pack_check.sh use - so this keeps working when the app moves,
# and works on a machine that has never had `godot` on its PATH.
#
# Every flag is passed straight through, and map_io.gd REFUSES the `--flag value` form out loud.
# Write `--out=ldtk`, never `--out ldtk`: the space form leaves the value in a positional slot
# and the option at its default, which is a run reporting on a configuration nobody chose.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot

if [ "$#" -eq 0 ]; then
  # The engine would answer this with "nothing to do", one boot later. Said here instead,
  # because a usage message is worth more than a launch.
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

"$GODOT" --headless --path . -s tools/map_io.gd "$@"
