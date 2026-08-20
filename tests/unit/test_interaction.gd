extends GdUnitTestSuite
## What pressing the button does, read as a result rather than driven through a scene.
##
## Two contracts are pinned here and both are invisible at the point they matter. Game code
## gets FIRST REFUSAL, and a refusal FALLS THROUGH - swap either and a game either never sees
## an interaction, or silently swallows every one it was only looking at. And a chest's memory
## is keyed by map, so two maps can each have a chest called "chest" without the second one
## being found already open.

const MAP := &"quest_hollow"
const OTHER_MAP := &"quest_keep"


func _ctx(flags: Dictionary = {}, seen: Dictionary = {}, items: Dictionary = {}) -> GameContext:
	return GameContext.create(MAP, Vector2i(3, 4), flags, seen, null, items)


func _target(id: StringName, record: Dictionary) -> Interactor.Target:
	return Interactor.Target.new(id, Vector2.ZERO, Vector2(10.0, 6.0), record)


func _ops(ctx: GameContext) -> Array[String]:
	var out: Array[String] = []
	for effect: Dictionary in ctx.effects():
		out.append(str(effect.get("op", "")))
	return out


func test_a_sign_says_its_line() -> void:
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "well_sign", "dialog": "sign_well"}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_DIALOG)])


func test_a_lever_sets_its_flag_without_saying_anything() -> void:
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "lever", "set_flag": "gate_open"}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_FLAG)])


func test_something_with_nothing_to_do_is_not_an_interaction() -> void:
	# The caller keeps looking rather than swallowing the press: a decorative object standing
	# between the player and an NPC must not eat the button.
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "rock"}, ctx)).is_false()
	assert_array(ctx.effects()).is_empty()


func test_a_once_object_refuses_the_second_time() -> void:
	var chest := {"id": "keychest", "dialog": "chest_key", "set_flag": "has_gate_key", "once": true}
	var first := _ctx()
	assert_bool(Interaction.decide(chest, first)).is_true()
	assert_array(_ops(first)).contains([str(GameContext.OP_SEEN)])

	var already := {Interaction.seen_key(MAP, "keychest"): true}
	var second := _ctx({}, already)
	assert_bool(Interaction.decide(chest, second)).is_false()
	assert_array(second.effects()).is_empty()


func test_two_maps_can_each_have_a_chest_called_chest() -> void:
	# Keyed on the id alone, opening one would leave the other found-empty - a bug that reads
	# as a missing item rather than as a naming collision.
	assert_str(Interaction.seen_key(MAP, "chest")).is_not_equal(Interaction.seen_key(OTHER_MAP, "chest"))
	var opened_here := {Interaction.seen_key(MAP, "chest"): true}
	var elsewhere := GameContext.create(OTHER_MAP, Vector2i.ZERO, {}, opened_here)
	assert_bool(Interaction.decide({"id": "chest", "dialog": "x", "once": true}, elsewhere)).is_true()


func test_game_code_gets_first_refusal() -> void:
	var hooks := StubHooks.new()
	hooks.takes = [&"warden"]
	hooks.says = &"warden_has_key"
	var ctx := _ctx()
	# The record says one thing; the hook overrides it entirely.
	var target := _target(&"warden", {"id": "warden", "dialog": "warden_default"})
	assert_bool(Interaction.resolve(hooks, ctx, target)).is_true()
	assert_array(hooks.handled).is_equal([&"warden"])
	assert_str(str(ctx.effects()[0].get("dialog", ""))).is_equal("warden_has_key")


func test_a_hook_that_refuses_falls_through_to_the_template() -> void:
	var hooks := StubHooks.new()
	hooks.takes = []
	var ctx := _ctx()
	var target := _target(&"kid", {"id": "kid", "dialog": "kid_talk"})
	assert_bool(Interaction.resolve(hooks, ctx, target)).is_true()
	# It was consulted, declined, and the data ran anyway.
	assert_array(hooks.offered).is_equal([&"kid"])
	assert_array(hooks.handled).is_empty()
	assert_str(str(ctx.effects()[0].get("dialog", ""))).is_equal("kid_talk")


func test_a_game_with_no_code_at_all_still_works() -> void:
	var ctx := _ctx()
	assert_bool(Interaction.resolve(null, ctx, _target(&"kid", {"id": "kid", "dialog": "kid_talk"}))).is_true()


func test_a_target_carrying_no_record_is_not_an_interaction() -> void:
	# Interactor.Target has always had a payload and nothing read it, so it could be anything.
	var ctx := _ctx()
	assert_bool(Interaction.resolve(null, ctx, _target(&"mystery", {}))).is_false()


func test_a_context_is_a_snapshot_rather_than_live_state() -> void:
	# A hook holding a context must not be able to reach back into the game's state, and
	# reads within one interaction must agree with each other.
	var flags := {&"has_gate_key": true}
	var ctx := _ctx(flags)
	flags[&"has_gate_key"] = false
	assert_bool(ctx.has_flag(&"has_gate_key")).is_true()


## The first effect carrying `op`, or an empty dictionary. Addressed by op rather than by
## index: a positional read re-aims itself at whatever now sits there the moment an effect is
## inserted ahead of it, silently and while still passing - the same failure as navigating a
## menu by counting presses.
func _effect(ctx: GameContext, op: StringName) -> Dictionary:
	for effect: Dictionary in ctx.effects():
		if StringName(str(effect.get("op", ""))) == op:
			return effect
	return {}


func test_reading_the_effects_cannot_change_them() -> void:
	var ctx := _ctx()
	ctx.set_flag(&"a")
	var taken := ctx.effects()
	taken.clear()
	assert_int(ctx.effects().size()).is_equal(1)


func test_a_flag_can_be_cleared_even_though_dialog_can_only_set_one() -> void:
	# The reason the dialog format was left alone: anything conditional beyond "set true" is
	# three lines of game code, not a new grammar in every dialog file.
	var ctx := _ctx()
	ctx.set_flag(&"has_gate_key", false)
	assert_bool(bool(_effect(ctx, GameContext.OP_FLAG).get("value", true))).is_false()


func test_a_chest_hands_over_what_is_in_it() -> void:
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "keystash", "dialog": "keystash",
		"give_item": "gate_key", "once": true}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_DIALOG), str(GameContext.OP_SOUND),
		str(GameContext.OP_GIVE_ITEM), str(GameContext.OP_SEEN)])
	var gift := _effect(ctx, GameContext.OP_GIVE_ITEM)
	assert_str(String(gift["id"])).is_equal("gate_key")
	assert_int(int(gift["count"])).is_equal(1)


func test_an_object_that_only_hands_something_over_is_not_a_dead_button() -> void:
	# Nothing to say and no flag: without give_item counting as a verb, decide() would return
	# false and the player would press a chest that does nothing.
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "cache", "give_item": "gate_key"}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_SOUND), str(GameContext.OP_GIVE_ITEM)])


func test_a_lock_refuses_without_the_item_and_says_so() -> void:
	# HANDLED, not ignored - the player pressed a real thing. And nothing else may land: a
	# lock that set its flag on the way to refusing would open the door it just refused.
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "lantern", "dialog": "lantern", "set_flag": "lit",
		"requires_item": "lamp_oil", "take_item": "lamp_oil", "locked_dialog": "lantern_dry",
		"once": true}, ctx)).is_true()
	# The refusal cue lands BEFORE the line, because the sink applies effects in order and the
	# thud belongs to the door rather than to the sentence about it.
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_SOUND), str(GameContext.OP_DIALOG)])
	assert_str(String(_effect(ctx, GameContext.OP_DIALOG)["dialog"])).is_equal("lantern_dry")


func test_with_the_item_it_works_and_the_item_goes() -> void:
	# The control for the refusal above, and the proof a consumable is consumed.
	var ctx := _ctx({}, {}, {&"lamp_oil": 1})
	assert_bool(Interaction.decide({"id": "lantern", "dialog": "lantern", "set_flag": "lit",
		"requires_item": "lamp_oil", "take_item": "lamp_oil", "locked_dialog": "lantern_dry",
		"once": true}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_DIALOG), str(GameContext.OP_FLAG),
		str(GameContext.OP_TAKE_ITEM), str(GameContext.OP_SEEN)])


func test_a_take_implies_carrying_it() -> void:
	# No requires_item at all, just a take. It must still refuse: an emitted take that fails
	# later would leave `once` recorded, so the object is spent and nothing was handed over.
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "lamp", "take_item": "lamp_oil",
		"locked_dialog": "lantern_dry", "once": true}, ctx)).is_true()
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_SOUND), str(GameContext.OP_DIALOG)])


func test_a_refusal_with_nothing_to_say_is_still_handled() -> void:
	# The map validator forbids shipping this, but decide() must not fall through to "keep
	# looking for another target" - the player is standing at a lock, not at nothing.
	var ctx := _ctx()
	assert_bool(Interaction.decide({"id": "lamp", "dialog": "lantern",
		"requires_item": "lamp_oil"}, ctx)).is_true()
	# It still THUDS. A lock with no line is a content bug the validator catches, but a lock
	# that answers a press with complete silence is indistinguishable from a dead button - and
	# the sound is the one piece of feedback that does not need a writer.
	assert_array(_ops(ctx)).is_equal([str(GameContext.OP_SOUND)])


func test_a_lock_wanting_several_counts_them() -> void:
	var record := {"id": "toll", "dialog": "gate_barred", "requires_item": "coin",
		"requires_count": 3, "locked_dialog": "gate_barred"}
	var short := _ctx({}, {}, {&"coin": 2})
	Interaction.decide(record, short)
	assert_str(String(_effect(short, GameContext.OP_DIALOG)["dialog"])).is_equal("gate_barred")
	var enough := _ctx({}, {}, {&"coin": 3})
	Interaction.decide(record, enough)
	assert_array(_ops(enough)).is_equal([str(GameContext.OP_DIALOG)])


func test_what_a_hook_is_carrying_is_a_snapshot() -> void:
	# A hook reads what the player has; it cannot reach in and change it. Giving is an effect
	# like everything else, which is what keeps one sink honest.
	var carried := {&"gate_key": 1}
	var ctx := _ctx({}, {}, carried)
	carried[&"gate_key"] = 99
	assert_int(ctx.item_count(&"gate_key")).is_equal(1)

