#!/usr/bin/env bash
# A new game: a manifest, a first room, somebody standing in it, and a session that boots it.
#
#   tools/new_game.sh --id=my_game
#   tools/new_game.sh --id=my_game --style=gb16 --movement=grid --hooks
#   tools/new_game.sh --id=my_game --out=user://somewhere   # anywhere but the project
#
# Flags: --id (required) --title --style --character --npc --sound
#        --movement=free|grid --save=anywhere|at_point --combat=none|turns --hooks --out
#
# A wrapper over `tools/new_game.gd`, and it exists for one reason: so nobody has to type the
# engine's path. `_engine.sh` resolves it from the usual places and honours GODOT_BIN, the same
# resolution check.sh and map_io.sh use - so this keeps working when the app moves.
#
# WRITE EVERY FLAG AS --flag=value. The space form is REFUSED out loud, because a value written
# after a space leaves the option at its default and the run does something nobody asked for.
#
# It never edits project.godot. With more than one game in data/games and nothing choosing between
# them the boot refuses rather than guessing, so the last thing it prints is what to add by hand.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=tools/_engine.sh
. "$(dirname "$0")/_engine.sh"
require_godot

if [ "$#" -eq 0 ]; then
  # The engine would answer this with "a game needs an id", one boot later. Said here instead.
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

"$GODOT" --headless --path . -s tools/new_game.gd "$@"
