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
			5:
				d = _v5_to_v6(d)
			6:
				d = _v6_to_v7(d)
			7:
				d = _v7_to_v8(d)
			8:
				d = _v8_to_v9(d)
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


## v5 -> v6: there was no money before v6.
##
## Broke rather than a gift. The same call every step above makes: a fabricated purse would be
## indistinguishable from earned money later, and handing an old save enough to buy what the
## game meant it to fight for is a worse lie than "this file predates the economy".
static func _v5_to_v6(d: Dictionary) -> Dictionary:
	d["gold"] = 0
	d["version"] = 6
	return d


## v6 -> v7: nothing was worn before v7.
##
## An empty slot map, the call every step above makes. Handing an old save a sword it never
## earned is the same lie as handing it gold, with an extra edge: the equipment map must
## agree with the bag, and this step cannot know what is in one.
static func _v6_to_v7(d: Dictionary) -> Dictionary:
	d["equipment"] = {}
	d["version"] = 7
	return d


## v7 -> v8: there was no magic before v8.
##
## Spent rather than full, and this is the one step where the honest default is also the
## unwelcoming one. Every step above hands an old save the EMPTY version of the new thing, and
## full MP would be the gift those steps all refuse - but there is a second reason here: what
## "full" is depends on the game's CombatDef, which a migration may not reach, and a number
## invented in this file would be wrong for every game but the one it was copied from.
##
## An old save therefore loads with nothing to cast and fills up at the first inn, which is
## where a player goes anyway after a run that predates the feature. A party is only touched
## when there IS one: a file with no party carries no magic, the same pairing to_save() makes.
static func _v7_to_v8(d: Dictionary) -> Dictionary:
	var party: Dictionary = d.get("party", {}) if d.get("party", {}) is Dictionary else {}
	if not party.is_empty():
		party["mp"] = 0
		d["party"] = party
	d["version"] = 8
	return d


## v8 -> v9: nobody had joined before v9.
##
## The simplest step in the chain, and deliberately so. Membership is derived from flags rather
## than stored, so there is no roster to carry forward; what v9 adds is each companion's own
## numbers, and a save written before parties existed has none by definition. An empty
## dictionary is the whole truth about it.
##
## Note what this step does NOT do, and cannot: it does not consult the game's roster to fill
## anybody in. A migration is a historical fact and may not reach a manifest, a Registry or a
## CombatDef - so if that save's game has since gained a companion whose flag is already set,
## the world derives them from their curve on first contact, which is the same path a fresh
## game takes. That is why this step needs to know no member id at all.
static func _v8_to_v9(d: Dictionary) -> Dictionary:
	d["companions"] = {}
	d["version"] = 9
	return d


## The versions this build can carry forward. Used by the test that pins the chain, so adding
## a step without a fixture is caught rather than assumed.
static func supported_versions() -> Array[int]:
	return [1, 2, 3, 4, 5, 6, 7, 8, 9]
