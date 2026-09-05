class_name GameHooks
extends RefCounted
## The one place a game's own code is reached from.
##
## A game names its subclass in `data/games/<id>.tres`, puts it under `games/<id>/`, and
## overrides only the verbs it actually has - every method here does nothing by default, so
## a game with no code at all simply has no hooks file.
##
## This exists because the template had nowhere to put gameplay. Every new mechanic landed in
## scripts/world/world_scene.gd, the file whose whole job is to be game-agnostic, and each one
## made the template a little more specific to one game.
##
## Two rules make the seam hold, both enforced rather than documented:
##
##   * A hook is handed a GameContext, never an autoload. Naming `GameState.` in a script
##     removes it from the per-file parse gate AND the whole-project compile, silently
##     (scripts/util/lint_core.gd fires on it for anything under res://games/).
##   * A hook that returns false has NOT handled the thing, and the template's own behaviour
##     runs. That is what keeps a game additive: it takes the cases it cares about and leaves
##     signs, chests and conversations to the template.

## Called after a map is built and the player is standing in it.
func on_map_entered(_ctx: GameContext) -> void:
	pass


## First refusal on every interaction. Return true when the game handled this target and the
## template should not; false to fall through to what the data says.
func on_interact(_ctx: GameContext, _target: Interactor.Target) -> bool:
	return false


## The conversations this game opens from its own code, which no map record names.
##
## Declared rather than discovered, because a hook says `ctx.say(...)` in a branch and nothing
## can read a branch. A content gate walks the maps to find out what a game can reach, and every
## dialog reached only from here is invisible to that walk - so without this the three lines the
## warden says on later visits are conversations no game owns, and the gate that asks whether
## every conversation belongs to somebody would refuse the game that ships.
##
## The same list `problems()` already checks the existence of. One list, not two.
func dialog_ids() -> Array[StringName]:
	return []


## Everything wrong with this game's own content, joined to the same gate that validates
## maps and manifests - so a game's problems are reported the way the template's are.
func problems() -> Array[String]:
	return []
