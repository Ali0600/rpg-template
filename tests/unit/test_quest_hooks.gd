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


func _ctx(flags: Dictionary, items: Dictionary = {}) -> GameContext:
	return GameContext.create(MAP, Vector2i(5, 4), flags, {}, null, items)


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
	# The two dialog ids live only in the hooks, so nothing in data can notice them going
	# missing - a rename would leave the warden silent exactly when she has something to say.
	for dialog_id in ["warden_has_key", "warden_thanks"]:
		var runner := DialogRunner.load_from("res://data/dialog/%s.json" % dialog_id, {})
		assert_bool(runner.ok).override_failure_message(runner.error).is_true()
		assert_array(runner.problems()).is_empty()
