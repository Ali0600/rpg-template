class_name Sfx
extends RefCounted
## Every sound the template can ask for, named in exactly one place.
##
## The precedent is Dir, and the reason is the same one: AudioBus warns once on an id it does
## not have and then carries on, which is correct behaviour and is also precisely how a
## misspelled cue ships. Nobody notices a noise that was never there. So template code names a
## cue through this ENUM rather than through a string, and a typo becomes a compile error
## instead of a warning nobody reads.
##
## A lint rule was the other option and is weaker: it cannot tell a cue string from any other
## string, so it would have to guess. An enum cannot be misspelled at all.
##
## CONTENT still names sounds as text - a map or a dialog node asking for one - because content
## is data and data is validated on load, the way every other id in this project is. `of()` is
## what that validation asks.
##
## This list is also what the GENERATOR iterates: gen_sounds.gd renders one file per cue below
## and fails if the bank has no shape for one. So adding a cue here without giving it a sound
## breaks the build, rather than going quiet in play.

enum Cue {
	# The world
	FOOTSTEP,
	PICKUP,
	LOCKED,
	WARP,
	# Talking
	TALK,
	PAGE,
	# Menus
	MENU_MOVE,
	MENU_CONFIRM,
	# Fighting
	HIT,
	TIMED_HIT,
	BLOCK,
	HURT,
	HEAL,
	CAST,
	LEVEL_UP,
	VICTORY,
	DEFEAT,
}

## Keyed by the enum rather than laid out positionally, because a positional array beside an
## enum is two orders that must agree and nothing that makes them - this project has already
## fixed exactly that bug once, in Router.state_name (see docs/DECISIONS.md).
const IDS: Dictionary = {
	Cue.FOOTSTEP: &"footstep",
	Cue.PICKUP: &"pickup",
	Cue.LOCKED: &"locked",
	Cue.WARP: &"warp",
	Cue.TALK: &"talk",
	Cue.PAGE: &"page",
	Cue.MENU_MOVE: &"menu_move",
	Cue.MENU_CONFIRM: &"menu_confirm",
	Cue.HIT: &"hit",
	Cue.TIMED_HIT: &"timed_hit",
	Cue.BLOCK: &"block",
	Cue.HURT: &"hurt",
	Cue.HEAL: &"heal",
	Cue.CAST: &"cast",
	Cue.LEVEL_UP: &"level_up",
	Cue.VICTORY: &"victory",
	Cue.DEFEAT: &"defeat",
}


## The file name a cue is stored under. Empty for a value outside the enum, which only a cast
## can produce - and an empty id resolves to no sound rather than to a wrong one.
static func id_of(cue: Cue) -> StringName:
	return IDS.get(cue, &"")


## Every cue id, in enum order. The generator's work list.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cue: Cue in IDS:
		out.append(IDS[cue])
	return out


## The cue a piece of CONTENT named, or -1 for a name no cue has. Data asking for a sound goes
## through here so an unknown name is a content error reported at load, beside every other bad
## id, instead of a warning at the moment it should have made a noise.
static func of(id: StringName) -> int:
	for cue: Cue in IDS:
		if IDS[cue] == id:
			return cue
	return -1
