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
static func apply(raw: Dictionary) -> Dictionary:
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


## The versions this build can carry forward. Used by the test that pins the chain, so adding
## a step without a fixture is caught rather than assumed.
static func supported_versions() -> Array[int]:
	return [1, 2]
