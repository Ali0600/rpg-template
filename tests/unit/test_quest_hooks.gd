extends GdUnitTestSuite
## The Barred Gate's only code, tested the way the template's own pure logic is.
##
## A game's hooks are a RefCounted handed a snapshot, so "the warden says a different thing
## once you are carrying the key" is a test that reads a result rather than one that walks a
## player across three maps. The scripted play session does that too, and it should - but a
## failure there tells you the quest broke, and a failure here tells you which line.
##
## This suite is also the demonstration: nothing below touches a scene, a node or an autoload,
## because game code is not allowed to and does not need to.

const MAP := &"quest_village"


func _hooks() -> GameHooks:
	var manifest := load("res://data/games/quest.tres") as GameManifest
	assert_object(manifest).is_not_null()
	return manifest.new_hooks()


func _ctx(flags: Dictionary, items: Dictionary = {}, seen: Dictionary = {}) -> GameContext:
	return GameContext.create(MAP, Vector2i(5, 4), flags, seen, null, items)


func _warden() -> Interactor.Target:
	return Interactor.Target.new(&"warden", Vector2.ZERO, Vector2(10.0, 6.0),
		{"id": "warden", "dialog": "warden_asks"})


func _said(ctx: GameContext) -> String:
	for effect: Dictionary in ctx.effects():
		if StringName(str(effect.get("op", ""))) == GameContext.OP_DIALOG:
			return str(effect.get("dialog", ""))
	return ""


func test_the_game_ships_hooks_and_they_have_no_problems() -> void:
	var hooks := _hooks()
	assert_object(hooks).is_not_null()
	assert_array(hooks.problems()).is_empty()


func test_with_nothing_yet_the_warden_uses_her_line_from_the_map() -> void:
	# Returning false is the design, not a fallback: the hook has nothing to add, so the
	# map's own `dialog` runs and adding a sentence to her opening never touches code.
	var ctx := _ctx({})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_false()
	assert_array(ctx.effects()).is_empty()


func test_carrying_the_key_she_says_something_else() -> void:
	var ctx := _ctx({}, {&"gate_key": 1})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_has_key")


func test_once_the_lantern_is_lit_that_wins_over_the_key() -> void:
	# Order matters and is invisible at the point it is written: the player still has the key
	# after lighting the lantern, so checking the key first would make the ending unreachable.
	var ctx := _ctx({&"lit_the_lantern": true}, {&"gate_key": 1})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_thanks")


func test_the_hooks_ignore_everyone_but_the_warden() -> void:
	# A hook that claimed every target would swallow the signs and the stash, and they would
	# stop working with no error anywhere.
	var ctx := _ctx({&"lit_the_lantern": true})
	var stash := Interactor.Target.new(&"keystash", Vector2.ZERO, Vector2(10.0, 6.0),
		{"id": "keystash", "dialog": "keystash"})
	assert_bool(_hooks().on_interact(ctx, stash)).is_false()
	assert_array(ctx.effects()).is_empty()


func test_every_line_the_hooks_name_exists() -> void:
	# The ids live only in the hooks, so nothing in data can notice them going missing - a
	# rename would leave the warden silent exactly when she has something to say.
	#
	# The declared list is compared WHOLE against a literal here rather than counted, because a
	# list read off the thing under test is satisfied by construction: an empty dialog_ids()
	# makes the loop below run no iterations and pass. Membership fails in both directions, so
	# a line added to the hooks and not to data is caught by the same assertion as one removed.
	assert_array(_hooks().dialog_ids()).override_failure_message(
		"the warden's conversations are not the four this game is written around"
		).contains_exactly_in_any_order(
			[&"warden_asks", &"warden_has_key", &"warden_thanks", &"warden_keeper_down"])
	for dialog_id in _hooks().dialog_ids():
		var runner := DialogRunner.load_from("res://data/dialog/%s.json" % dialog_id, {})
		assert_bool(runner.ok).override_failure_message(runner.error).is_true()
		assert_array(runner.problems()).is_empty()


func test_she_notices_the_keeper_is_down_before_the_lantern_is_lit() -> void:
	# The branch M13 added, and the only thing in the game that reads a fight's result. She
	# barred the gate against that thing, so she is the one person who should notice.
	var ctx := _ctx({}, {}, {"quest_keep/keeper": true})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_keeper_down")

func test_the_lit_lantern_still_outranks_the_beaten_keeper() -> void:
	# Most-advanced-first, and the control for the test above: by the time the keep is lit,
	# "you killed the thing" is old news and she has an ending to deliver.
	var ctx := _ctx({&"lit_the_lantern": true}, {}, {"quest_keep/keeper": true})
	assert_str(_said(ctx)).is_equal("")
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_thanks")

func test_a_beaten_keeper_outranks_merely_holding_the_key() -> void:
	var ctx := _ctx({}, {&"gate_key": 1}, {"quest_keep/keeper": true})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_keeper_down")

func test_the_key_alone_still_gets_its_own_line() -> void:
	# The control for THAT: dropping the keeper branch in above the key branch would make this
	# test the only thing that notices.
	var ctx := _ctx({}, {&"gate_key": 1})
	assert_bool(_hooks().on_interact(ctx, _warden())).is_true()
	assert_str(_said(ctx)).is_equal("warden_has_key")

func test_the_seen_key_the_hooks_name_is_the_one_the_map_actually_produces() -> void:
	# The hooks spell "quest_keep/keeper" as a literal, because game code may not call into
	# the template to build one. That makes it a second source of truth for a key the MAP
	# decides - so this is the test that keeps the two spelling it the same way.
	var map := MapData.load_from("res://data/maps/quest_keep.json")
	var ids: Array[StringName] = []
	for entry: Variant in map.enemies:
		ids.append(StringName(str((entry as Dictionary).get("id", ""))))
	assert_array(ids).override_failure_message(
		"quest_keep no longer places an enemy called 'keeper', so the warden's line about it is unreachable"
	).contains([&"keeper"])
	assert_str(Interaction.seen_key(map.id, "keeper")).is_equal("quest_keep/keeper")

# -- the opening the player cannot walk past -------------------------------------------------

func test_a_new_game_opens_with_the_warden_saying_her_piece() -> void:
	# The premise used to be optional: she is a static figure two tiles off the spawn, and a
	# play-test walked past her, never found the key, and was never told one existed.
	var ctx := _ctx({})
	_hooks().on_map_entered(ctx)
	assert_str(_said(ctx)).override_failure_message(
		"a new game began with nobody having said what the player is for").is_equal("warden_asks")

func test_she_does_not_say_it_again_once_she_has() -> void:
	# The control. A hook that opened it unconditionally would pass the test above and reopen
	# the conversation on every walk back into the village - including on every load.
	var ctx := _ctx({&"met_the_warden": true})
	_hooks().on_map_entered(ctx)
	assert_bool(ctx.has_effects()).override_failure_message(
		"the opening replayed for a player who had already heard it").is_false()

func test_the_other_maps_open_with_nothing() -> void:
	var ctx := GameContext.create(&"quest_cave", Vector2i(1, 6), {}, {}, null, {})
	_hooks().on_map_entered(ctx)
	assert_bool(ctx.has_effects()).override_failure_message(
		"the warden's opening followed the player into another map").is_false()

func test_the_line_it_opens_is_the_one_that_records_having_been_heard() -> void:
	# The two halves are in different files - the hook opens the dialog, and the dialog's own
	# first node sets the flag that stops it reopening - so this pins that they agree. If the
	# flag were renamed in the data, the opening would replay forever and every other test
	# here would still pass.
	var runner := DialogRunner.load_from("res://data/dialog/warden_asks.json")
	assert_bool(runner.ok).is_true()
	assert_array(runner.problems()).is_empty()
	runner.begin()
	assert_array(runner.flags_to_set()).override_failure_message(
		"the warden's opening does not record that it was heard, so it reopens forever"
	).contains([&"met_the_warden"])
