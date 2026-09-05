class_name GameFixtures
extends RefCounted
## Small facts about which games exist, for the suites that make one up.
##
## Two suites here scaffold a game and need a name nothing else is using. Spelling one in works
## until somebody scaffolds a game into this repo with that name - which is exactly what
## `tools/new_game.sh` invites, and exactly the failure M47 is about: a suite that assumes the
## shipped set of games and goes red over a game it has nothing to do with.


## An id no game on disk is using, starting from `base`. Deterministic, so a failure names the same
## game twice running.
static func unused_game_id(base: String) -> String:
	var taken := GameSelect.ids()
	var id := base
	var suffix := 1
	while taken.has(id):
		id = "%s_%d" % [base, suffix]
		suffix += 1
	return id
