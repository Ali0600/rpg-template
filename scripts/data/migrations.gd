class_name Migrations
extends RefCounted
## Carries an old save file forward, one version at a time.
##
## A migration is a HISTORICAL FACT: given the same old file it must produce the same result
## forever. That is why each step below is written out in full against plain dictionary keys,
## and calls nothing that is free to change. Reusing a live helper here would be the DRY
## instinct and the wrong one - the day that helper is retuned, old saves start migrating to
## different results than they did when they were written, silently and unreproducibly.
##
## Steps chain: a v1 file passes through every step in turn up to the current version, so
## adding v3 later means writing one more step and nothing else.

## Applies every step needed to bring `raw` up to SaveData.VERSION. Returns the migrated
## dictionary; the caller then builds a SaveData from it.
##
## `game` is an INPUT rather than something read out of the file, because a file older than
## v3 cannot say which game it belongs to - the slot's directory is the only evidence there
## is. Passing it in keeps every step a pure function of (file, game), which is what makes a
## migration reproducible; reading it from a live lookup would not be.
static func apply(raw: Dictionary, game: StringName) -> Dictionary:
	# The caller's dictionary is never touched: it is usually the parsed contents of a file
	# someone still holds, and a migration that edits it means the "original" no longer is one.
	var d := raw.duplicate(true)
	# A file with no version at all predates versioning: treat it as the first shape rather
	# than as the current one, which would skip every step and read old fields as new ones.
	var version := int(d.get("version", 1))

	# A `while` rather than an `if`: a v1 file must walk the whole chain. An `if` migrates it
	# one step and hands the rest of the system a v2 file it will not recognise - and the
	# failure appears as odd values, not as an error.
	while version < SaveData.VERSION:
		match version:
			1:
				d = _v1_to_v2(d)
			2:
				d = _v2_to_v3(d, game)
			3:
				d = _v3_to_v4(d)
			4:
				d = _v4_to_v5(d)
			_:
				# No step for this version. Stop rather than loop forever; the caller's
				# validation reports the mismatch.
				break
		version = int(d.get("version", version))
	return d


## v1 -> v2: play time was not recorded before v2.
##
## Old saves get zero rather than a guess. A fabricated value would be indistinguishable from
## a real one later, and "this save says I played for four hours" is a worse lie than "this
## save was made before we counted".
##
## Steps edit in place. `apply` owns the copy, so a step never has to remember to make one -
## and one place owning that rule is the difference between a guarantee and a convention.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	d["play_seconds"] = 0.0
	d["version"] = 2
	return d


## v2 -> v3: the game id was not recorded before v3.
##
## It comes from the slot the file was found in, which is the only thing that knows. That is
## an assumption, and it is the safe one: a save sitting in a game's directory either belongs
## to that game or was put there by hand, and the second case now announces itself the moment
## the file is re-read rather than loading a stranger's world.
static func _v2_to_v3(d: Dictionary, game: StringName) -> Dictionary:
	d["game"] = String(game)
	d["version"] = 3
	return d


## v3 -> v4: nothing was carried before v4.
##
## An empty bag rather than a guess. Every item in this game is picked up somewhere the player
## can go back to, so a save from before items existed loses nothing by starting empty - and
## inventing a key they never found would open a door the game meant to make them earn.
static func _v3_to_v4(d: Dictionary) -> Dictionary:
	d["items"] = {}
	d["version"] = 4
	return d


## v4 -> v5: nothing had been fought before v5.
##
## An empty party rather than a guess, the same call _v3_to_v4 made about the bag. A fabricated
## level-1 hero would be a lie in two directions: this step cannot see the game's CombatDef, so
## it cannot know what full health even is - and a game with no combat would get a party it has
## no use for. Empty is the honest word for "this file predates fighting", and world_scene
## turns it into a real player at the one place that can.
static func _v4_to_v5(d: Dictionary) -> Dictionary:
	d["party"] = {}
	d["version"] = 5
	return d


## The versions this build can carry forward. Used by the test that pins the chain, so adding
## a step without a fixture is caught rather than assumed.
static func supported_versions() -> Array[int]:
	return [1, 2, 3, 4, 5]
