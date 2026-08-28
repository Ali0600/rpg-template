extends GdUnitTestSuite
## Conversations, walked as data rather than clicked through.
##
## Keeping the rules out of the view is what makes this possible: branching, choices, flags
## and endings are all decided here, so they can be checked by walking a script and reading
## the result instead of by pressing a button and watching a box.

const DIALOG_DIR := "res://data/dialog/"

func _sample(known_flags: Dictionary = {}) -> DialogRunner:
	return DialogRunner.from_dict({
		"id": "sample",
		"start": "greet",
		"nodes": {
			"greet": {"speaker": "A", "text": "hello", "next": "ask"},
			"ask": {"speaker": "A", "text": "well?", "choices": [
				{"text": "yes", "next": "yes", "set_flag": "agreed"},
				{"text": "no", "next": "no"},
				{"text": "secret", "next": "yes", "requires_flag": "knows_secret"},
			]},
			"yes": {"speaker": "A", "text": "good"},
			"no": {"speaker": "A", "text": "shame"},
		},
	}, known_flags)

func test_every_shipped_dialog_is_valid() -> void:
	var dir := DirAccess.open(DIALOG_DIR)
	assert_object(dir).is_not_null()
	var count := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == "json":
			count += 1
			var runner := DialogRunner.load_from(DIALOG_DIR + name)
			assert_array(runner.problems()).override_failure_message(
				"%s: %s" % [name, runner.problems()]).is_empty()
		name = dir.get_next()
	dir.list_dir_end()
	# A loop over an empty directory validates nothing and reports success.
	assert_int(count).is_greater(0)

func test_a_conversation_walks_line_by_line() -> void:
	var runner := _sample()
	assert_bool(runner.begin()).is_true()
	assert_str(runner.line().text).is_equal("hello")
	assert_bool(runner.advance()).is_true()
	assert_str(runner.line().text).is_equal("well?")

func test_the_end_of_a_conversation_is_reported_not_guessed() -> void:
	# The caller hands control back on this signal, so it has to be explicit - checking
	# whether the next line happens to be empty would end a conversation on a blank line.
	var runner := _sample()
	runner.begin()
	runner.advance()
	runner.choose(1)
	assert_str(runner.line().text).is_equal("shame")
	assert_bool(runner.advance()).is_false()
	assert_bool(runner.is_finished()).is_true()
	assert_object(runner.line()).is_null()

func test_a_line_with_choices_does_not_advance_on_its_own() -> void:
	# Advancing past a choice would pick for the player - exactly what a held confirm button
	# would do otherwise.
	var runner := _sample()
	runner.begin()
	runner.advance()
	var before := runner.current_id()
	assert_bool(runner.advance()).is_true()
	assert_str(runner.current_id()).is_equal(before)

func test_choosing_follows_the_branch() -> void:
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_bool(runner.choose(0)).is_true()
	assert_str(runner.line().text).is_equal("good")

func test_an_out_of_range_choice_is_refused_not_clamped() -> void:
	# Clamping turns a UI bug into a plausible wrong answer that nobody notices.
	var runner := _sample()
	runner.begin()
	runner.advance()
	var before := runner.current_id()
	assert_bool(runner.choose(9)).is_false()
	assert_bool(runner.choose(-1)).is_false()
	assert_str(runner.current_id()).is_equal(before)
	assert_bool(runner.is_finished()).is_false()

func test_a_choice_the_player_cannot_take_is_hidden_not_offered() -> void:
	# The menu never shows something it would then reject.
	assert_int(_line_choices(_sample()).size()).is_equal(2)
	assert_int(_line_choices(_sample({"knows_secret": true})).size()).is_equal(3)

func _line_choices(runner: DialogRunner) -> Array[String]:
	runner.begin()
	runner.advance()
	return runner.line().choices

func test_a_hidden_choice_shifts_the_indices_it_hides_behind() -> void:
	# The index the player picks refers to what they can SEE. If choose() counted hidden
	# entries too, the second visible option would run the third branch - and it would look
	# like a writing mistake rather than an off-by-one.
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_bool(runner.choose(1)).is_true()
	assert_str(runner.line().text).is_equal("shame")

func test_flags_are_collected_and_never_written() -> void:
	# A pure runner cannot reach the game state, and that is the right shape: the caller
	# applies them once the line has actually been shown, so an abandoned conversation
	# leaves no promises behind.
	var runner := _sample()
	runner.begin()
	runner.advance()
	assert_array(runner.flags_to_set()).is_empty()
	runner.choose(0)
	assert_array(runner.flags_to_set()).contains([&"agreed"])

func test_a_conversation_abandoned_before_the_flag_earns_nothing() -> void:
	var runner := _sample()
	runner.begin()
	runner.advance()
	runner.choose(1)
	assert_array(runner.flags_to_set()).is_empty()

func test_a_dialog_that_starts_nowhere_is_refused() -> void:
	var runner := DialogRunner.from_dict({"id": "broken", "start": "missing", "nodes": {
		"greet": {"text": "hello"},
	}})
	assert_bool(runner.begin()).is_false()
	assert_str(str(runner.problems())).contains("which does not exist")

func test_a_next_pointing_nowhere_is_reported() -> void:
	# Left unchecked, the conversation just ends early and reads as if it was written that way.
	var runner := DialogRunner.from_dict({"id": "broken", "start": "a", "nodes": {
		"a": {"text": "hello", "next": "b"},
	}})
	# Asserted on the entry rather than on str(array): an array's string form escapes the
	# quotes inside it, so a `contains` against the readable message silently never matches.
	assert_int(runner.problems().size()).is_equal(1)
	assert_str(runner.problems()[0]).contains("continues to")
	assert_str(runner.problems()[0]).contains("does not exist")

func test_an_unreachable_node_is_reported() -> void:
	# It was written, it is in the file, and no player will ever see it.
	var runner := DialogRunner.from_dict({"id": "orphan", "start": "a", "nodes": {
		"a": {"text": "hello"},
		"lost": {"text": "nobody gets here"},
	}})
	assert_str(str(runner.problems())).contains("unreachable")

func test_a_missing_dialog_file_is_an_error() -> void:
	var runner := DialogRunner.load_from("res://data/dialog/nope.json")
	assert_bool(runner.ok).is_false()
	assert_str(str(runner.problems())).contains("did not load")


## A conversation that loops: the gift node returns to the greeting, which is exactly the
## shape that hands over a second key on the second pass if nothing stops it.
func _hermit() -> Dictionary:
	return {
		"id": "hermit",
		"start": "greet",
		"nodes": {
			"greet": {
				"speaker": "Hermit", "text": "Oil?",
				"choices": [
					{ "text": "Please.", "next": "gave", "give_item": "lamp_oil",
						"set_flag": "took_oil", "hidden_if_flag": "took_oil" },
					{ "text": "Just passing.", "next": "greet" },
				],
			},
			"gave": { "speaker": "Hermit", "text": "Mind the wick.", "next": "greet" },
		},
	}


func test_a_gift_on_a_choice_is_collected_as_an_effect_not_written() -> void:
	var runner := DialogRunner.from_dict(_hermit())
	runner.begin()
	runner.choose(0)
	var ops: Array[String] = []
	for effect in runner.effects():
		ops.append(str(effect.get("op", "")))
	assert_array(ops).is_equal([str(GameContext.OP_FLAG), str(GameContext.OP_GIVE_ITEM)])
	assert_str(String(runner.effects()[1]["id"])).is_equal("lamp_oil")
	# flags_to_set is derived from the same list, so the two cannot disagree.
	assert_array(runner.flags_to_set()).is_equal([&"took_oil"])


func test_a_gift_hidden_behind_the_flag_it_sets_cannot_be_taken_twice() -> void:
	# Nothing has been written to the game state yet - the flag exists only inside this
	# conversation - so without counting flags earned here, the loop hands over a second one.
	var runner := DialogRunner.from_dict(_hermit())
	runner.begin()
	assert_int(runner.line().choices.size()).is_equal(2)
	runner.choose(0)
	runner.advance()
	assert_int(runner.line().choices.size()).override_failure_message(
		"the gift was offered again on the second pass through the same node").is_equal(1)


func test_a_choice_needing_an_item_the_player_lacks_is_hidden() -> void:
	var data := {"id": "gate", "start": "ask", "nodes": {"ask": {"speaker": "Gate", "text": "?",
		"choices": [{"text": "Unlock it.", "next": "ask", "requires_item": "gate_key"},
			{"text": "Leave.", "next": "ask"}]}}}
	var without := DialogRunner.from_dict(data)
	without.begin()
	assert_int(without.line().choices.size()).is_equal(1)
	var with_key := DialogRunner.from_dict(data, {}, {&"gate_key": 1})
	with_key.begin()
	assert_int(with_key.line().choices.size()).override_failure_message(
		"the choice stayed hidden from a player holding the key").is_equal(2)


func test_a_choice_that_takes_an_item_waits_until_the_player_has_it() -> void:
	# A take implies a requires here too: offering to hand over something you are not
	# carrying is a choice that can only go wrong once taken.
	var data := {"id": "toll", "start": "ask", "nodes": {"ask": {"speaker": "Toll", "text": "?",
		"choices": [{"text": "Pay.", "next": "ask", "take_item": "coin", "take_count": 2}]}}}
	var broke := DialogRunner.from_dict(data, {}, {&"coin": 1})
	broke.begin()
	assert_int(broke.line().choices.size()).is_equal(0)
	var flush := DialogRunner.from_dict(data, {}, {&"coin": 2})
	flush.begin()
	assert_int(flush.line().choices.size()).is_equal(1)


func test_a_conversation_lists_every_item_it_names() -> void:
	var refs := DialogRunner.from_dict(_hermit()).item_refs()
	assert_array(refs).is_equal([&"lamp_oil"])



# --- paying for something, and being told no ------------------------------------------------
#
# Money is the one requirement that is SHOWN and refused rather than hidden. A requires_item
# hides the choice, because offering to hand over what you are not carrying can only go wrong
# when taken - but a price is quoted out loud, so a player who says yes to one they cannot
# meet has to hear why not. That is `poor_next`, and it is mandatory.


func _keeper(gold: int) -> DialogRunner:
	return DialogRunner.from_dict({
		"id": "keeper",
		"start": "ask",
		"nodes": {
			"ask": {"speaker": "K", "text": "Six gold for the night.", "choices": [
				{"text": "Yes, please.", "next": "slept", "spend_gold": 6, "rest": true,
					"poor_next": "poor", "set_flag": "slept_once"},
				{"text": "Not tonight.", "next": "bye"},
			]},
			"slept": {"speaker": "K", "text": "Morning."},
			"poor": {"speaker": "K", "text": "Come back with the coin."},
			"bye": {"speaker": "K", "text": "Suit yourself."},
		},
	}, {}, {}, gold)


func test_paying_for_a_night_spends_and_rests() -> void:
	var runner := _keeper(10)
	assert_bool(runner.begin()).is_true()
	assert_bool(runner.choose(0)).is_true()
	assert_str(runner.line().text).is_equal("Morning.")
	var ops: Array[String] = []
	for effect in runner.effects():
		ops.append(str(effect.get("op", "")))
	assert_array(ops).contains(["spend_gold", "rest"])
	for effect in runner.effects():
		if str(effect.get("op", "")) == "spend_gold":
			assert_int(int(effect.get("amount", 0))).is_equal(6)


func test_a_purse_that_cannot_cover_it_is_told_so_and_charged_nothing() -> void:
	# The whole point of the refusal being a NODE: the player hears the answer. And nothing is
	# collected - not the spend, not the rest, and not the flag riding the same choice, which
	# is the all-or-nothing rule a take already follows.
	var runner := _keeper(5)
	runner.begin()
	assert_bool(runner.choose(0)).is_true()
	assert_str(runner.line().text).override_failure_message(
		"a player who cannot pay was not told why").is_equal("Come back with the coin.")
	assert_array(runner.effects()).override_failure_message(
		"a refused deal left something behind: %s" % [runner.effects()]).is_empty()


func test_the_choice_is_still_offered_when_the_purse_is_short() -> void:
	# Shown, not hidden - the opposite of requires_item, and deliberately. A keeper who stops
	# offering a room is a keeper the player cannot find out the price from.
	var runner := _keeper(0)
	runner.begin()
	assert_int(runner.line().choices.size()).is_equal(2)


func test_a_second_night_is_checked_against_what_the_first_already_committed() -> void:
	# Nothing has reached the game state yet, so a conversation spending twice would otherwise
	# be checked twice against the same untouched purse - the reason _flag_known counts flags
	# earned earlier in the same conversation.
	var runner := DialogRunner.from_dict({
		"id": "twice",
		"start": "a",
		"nodes": {
			"a": {"text": "again?", "choices": [
				{"text": "pay", "next": "b", "spend_gold": 6, "poor_next": "poor"}]},
			"b": {"text": "and again?", "choices": [
				{"text": "pay", "next": "c", "spend_gold": 6, "poor_next": "poor"}]},
			"c": {"text": "done"},
			"poor": {"text": "no coin"},
		},
	}, {}, {}, 10)
	runner.begin()
	assert_bool(runner.choose(0)).is_true()
	assert_bool(runner.choose(0)).is_true()
	assert_str(runner.line().text).override_failure_message(
		"ten gold paid for two six-gold nights").is_equal("no coin")
	assert_int(runner.effects().size()).override_failure_message(
		"the second night was collected as well as refused").is_equal(1)


func test_a_price_with_nothing_to_say_when_refused_is_a_content_error() -> void:
	var runner := DialogRunner.from_dict({
		"id": "mute", "start": "a", "nodes": {
			"a": {"text": "pay up", "choices": [{"text": "ok", "next": "b", "spend_gold": 6}]},
			"b": {"text": "done"},
		}})
	assert_array(runner.problems()).override_failure_message(
		"a keeper that charges and says nothing when refused passed the gate").is_not_empty()


func test_a_refusal_pointing_nowhere_is_a_content_error() -> void:
	var runner := DialogRunner.from_dict({
		"id": "dangling", "start": "a", "nodes": {
			"a": {"text": "pay up", "choices": [
				{"text": "ok", "next": "b", "spend_gold": 6, "poor_next": "nowhere"}]},
			"b": {"text": "done"},
		}})
	assert_array(runner.problems()).is_not_empty()


func test_a_price_of_nothing_is_a_content_error() -> void:
	var runner := DialogRunner.from_dict({
		"id": "free", "start": "a", "nodes": {
			"a": {"text": "pay up", "choices": [
				{"text": "ok", "next": "b", "spend_gold": 0, "poor_next": "b"}]},
			"b": {"text": "done"},
		}})
	assert_array(runner.problems()).is_not_empty()


func test_a_refusal_node_is_reachable() -> void:
	# It is reached only by being unable to pay, which is still reached. Miss this and every
	# correctly-written refusal fails the build as unreachable - a gate refusing correct data.
	assert_array(_keeper(10).problems()).override_failure_message(
		"a well-formed keeper failed the content gate").is_empty()
