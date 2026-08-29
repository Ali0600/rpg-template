extends GdUnitTestSuite
## Who fights beside the player: the noun, and the party rules that live on GameState.
##
## Two rules here are the whole reason a party is more than "a second set of numbers". A
## companion at zero health is an ORDINARY outcome the game must be able to write down, where a
## solo player at zero health means "never fought" - so party_unset asks about both. And a
## marker is a claim on a carried copy, so one sword cannot be on two backs, checked as a count
## rather than as a presence.

func before_test() -> void:
	GameState.reset()

func after_test() -> void:
	GameState.reset()

func _member(id: StringName, member_name: String) -> PartyMemberDef:
	var out := PartyMemberDef.new()
	out.id = id
	out.name = member_name
	out.character = &"quest_wanderer"
	return out

# --- the noun -----------------------------------------------------------------------------

func test_a_complete_member_is_accepted() -> void:
	assert_array(_member(&"scrapper", "Rook").problems()).is_empty()

func test_a_member_with_no_id_is_refused() -> void:
	var m := _member(&"", "Rook")
	assert_array(m.problems()).is_not_empty()

func test_a_member_with_no_name_is_refused() -> void:
	# The name is drawn in the fight and in the member window; without one the party is a row
	# of blanks and the failure looks like a layout bug.
	assert_array(_member(&"scrapper", "").problems()).is_not_empty()

func test_a_member_wearing_no_character_is_refused() -> void:
	# Without art there is nothing to draw, and an invisible fighter reads as a broken screen
	# rather than as missing content.
	var m := _member(&"scrapper", "Rook")
	m.character = &""
	assert_array(m.problems()).is_not_empty()

func test_a_member_who_joins_below_level_one_is_refused() -> void:
	var m := _member(&"scrapper", "Rook")
	m.join_level = 0
	assert_array(m.problems()).is_not_empty()

func test_a_member_joining_above_level_one_is_fine() -> void:
	# The control: "a veteran joins" is the genre's own shape, not a fault.
	var m := _member(&"scrapper", "Rook")
	m.join_level = 4
	assert_array(m.problems()).is_empty()

func test_a_member_listing_one_spell_twice_is_refused() -> void:
	# Twice in the list is once in the fight, so the duplicate is silent - and it is usually a
	# copy-paste that meant to name a different spell.
	var m := _member(&"scrapper", "Rook")
	m.spells = [&"mend", &"mend"]
	assert_array(m.problems()).is_not_empty()

func test_a_member_with_no_spells_is_a_perfectly_ordinary_member() -> void:
	# Dragon Quest II's hero has no magic at all, and most companions in the genre are not
	# casters - so the empty list is the default rather than an oversight.
	assert_array(_member(&"scrapper", "Rook").problems()).is_empty()

func test_a_members_own_broken_curve_is_reported_against_them() -> void:
	var m := _member(&"scrapper", "Rook")
	m.combat = CombatDef.new()
	var faults := m.problems()
	assert_array(faults).is_not_empty()
	assert_str(faults[0]).override_failure_message(
		"a fault in a member's curve was reported without saying whose it was").contains("scrapper")

func test_a_member_with_no_curve_is_fine() -> void:
	# Null means "grows like the player does", which is the common case.
	var m := _member(&"scrapper", "Rook")
	m.combat = null
	assert_array(m.problems()).is_empty()

# --- who is real, and who is not ------------------------------------------------------------

func test_nobody_is_a_companion_until_they_are_written_down() -> void:
	assert_bool(GameState.has_companion(&"scrapper")).is_false()
	assert_dict(GameState.companion(&"scrapper")).is_empty()

func test_a_companion_is_four_numbers_through_one_writer() -> void:
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	var back := GameState.companion(&"scrapper")
	assert_int(int(back["hp"])).is_equal(11)
	assert_int(int(back["xp"])).is_equal(14)
	assert_int(int(back["level"])).is_equal(2)
	assert_int(int(back["mp"])).is_equal(3)

func test_reading_a_companion_hands_back_a_copy() -> void:
	# The Inventory rule, applied to people: a caller who edits what they were handed must not
	# be editing the live state behind the one writer's back.
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	var borrowed := GameState.companion(&"scrapper")
	borrowed["hp"] = 1
	assert_int(int(GameState.companion(&"scrapper")["hp"])).override_failure_message(
		"editing a borrowed companion record changed the live one").is_equal(11)

func test_the_leader_cannot_be_set_as_a_companion() -> void:
	# The empty id is the leader's everywhere, and routing them through here would be a second
	# writer for the four fields set_party owns.
	GameState.set_party(20, 0, 1, 8)
	GameState.set_companion(&"", 1, 0, 1, 0)
	assert_bool(GameState.companions.is_empty()).override_failure_message(
		"the leader was written into the companion map under an empty id").is_true()
	assert_int(GameState.player_hp).is_equal(20)

func test_a_fresh_game_has_nobody_and_no_party() -> void:
	assert_bool(GameState.party_unset()).is_true()

func test_a_player_at_full_health_is_a_party() -> void:
	GameState.set_party(20, 0, 1, 8)
	assert_bool(GameState.party_unset()).is_false()

func test_a_leader_at_nought_beside_a_companion_is_still_a_party() -> void:
	# The state M27 makes possible: they fell, somebody else finished the fight, and the party
	# is walking to an inn. Read as "unset" this refills them from the curve on the way into
	# the next fight - a silent resurrection that deletes what the player is walking to undo.
	GameState.set_party(0, 30, 2, 4)
	GameState.set_companion(&"scrapper", 6, 30, 2, 1)
	assert_bool(GameState.party_unset()).override_failure_message(
		"a leader who fell beside a standing companion was read as having never fought").is_false()

func test_a_leader_at_nought_alone_is_an_unset_party() -> void:
	# The other half: with nobody else standing, reaching zero was a DEFEAT, whose effects are
	# discarded wholesale - so zero still means "never fought" here.
	GameState.set_party(0, 0, 1, 0)
	assert_bool(GameState.party_unset()).is_true()

# --- one copy, one back ---------------------------------------------------------------------

func test_a_companion_can_wear_their_own_gear() -> void:
	GameState.give_item(&"bronze_sword")
	assert_bool(GameState.equip(&"weapon", &"bronze_sword", &"scrapper")).is_true()
	assert_str(str(GameState.equipped(&"weapon", &"scrapper"))).is_equal("bronze_sword")
	assert_str(str(GameState.equipped(&"weapon"))).override_failure_message(
		"equipping a companion put the item on the leader as well").is_equal("")

func test_two_people_cannot_wear_one_carried_sword() -> void:
	GameState.give_item(&"bronze_sword")
	assert_bool(GameState.equip(&"weapon", &"bronze_sword")).is_true()
	assert_bool(GameState.equip(&"weapon", &"bronze_sword", &"scrapper")).override_failure_message(
		"one carried sword was worn by two people at once").is_false()

func test_two_carried_swords_go_on_two_backs() -> void:
	# The control the refusal needs: it must be about the COUNT, not about two people owning
	# the same kind of thing.
	GameState.give_item(&"bronze_sword", 2)
	assert_bool(GameState.equip(&"weapon", &"bronze_sword")).is_true()
	assert_bool(GameState.equip(&"weapon", &"bronze_sword", &"scrapper")).is_true()
	assert_int(GameState.wearers_of(&"bronze_sword")).is_equal(2)

func test_wearing_what_is_already_on_is_still_the_no_op_it_always_was() -> void:
	# The reason the check counts what the marker total WOULD be rather than what it is: with a
	# plain "is anyone wearing this", re-confirming the sword already in the slot would start
	# answering no.
	GameState.give_item(&"bronze_sword")
	assert_bool(GameState.equip(&"weapon", &"bronze_sword")).is_true()
	assert_bool(GameState.equip(&"weapon", &"bronze_sword")).override_failure_message(
		"re-equipping what was already worn was refused").is_true()

func test_a_slot_that_is_not_a_slot_is_refused() -> void:
	# Its own guard since the copies rule swallowed the "carries none" one - without it an
	# empty slot name becomes a key in the worn map, which every reader would then have to
	# tolerate.
	GameState.give_item(&"bronze_sword")
	assert_bool(GameState.equip(&"", &"bronze_sword")).is_false()
	assert_bool(GameState.equipment.has(&"")).override_failure_message(
		"a slot with no name became a slot").is_false()

func test_nobody_wears_what_the_bag_does_not_hold() -> void:
	assert_bool(GameState.equip(&"weapon", &"bronze_sword", &"scrapper")).is_false()

func test_selling_the_last_copy_strips_the_companion_wearing_it() -> void:
	GameState.give_item(&"bronze_sword")
	GameState.equip(&"weapon", &"bronze_sword", &"scrapper")
	assert_bool(GameState.take_item(&"bronze_sword")).is_true()
	assert_str(str(GameState.equipped(&"weapon", &"scrapper"))).override_failure_message(
		"a companion kept wearing a sword nobody is carrying").is_equal("")

func test_selling_one_of_two_strips_exactly_one_marker_and_the_leader_keeps_theirs() -> void:
	# The count rule, and the tie-break: companions lose the marker first so the player keeps
	# what they are wearing, which is where the loss is least surprising.
	GameState.give_item(&"bronze_sword", 2)
	GameState.equip(&"weapon", &"bronze_sword")
	GameState.equip(&"weapon", &"bronze_sword", &"scrapper")
	assert_bool(GameState.take_item(&"bronze_sword")).is_true()
	assert_int(GameState.wearers_of(&"bronze_sword")).override_failure_message(
		"selling one of two swords stripped the wrong number of markers").is_equal(1)
	assert_str(str(GameState.equipped(&"weapon"))).override_failure_message(
		"the leader lost their sword when a spare was sold").is_equal("bronze_sword")

func test_the_newest_companion_loses_a_sold_sword_before_an_older_one() -> void:
	# Which one loses it has to be a RULE, not whichever order the dictionary offered - "it
	# reproduces differently on a different day" is the bug a seeded template cannot have. With
	# one companion this is unobservable, which is why the test carries two.
	GameState.give_item(&"bronze_sword", 2)
	GameState.equip(&"weapon", &"bronze_sword", &"older")
	GameState.equip(&"weapon", &"bronze_sword", &"newest")
	assert_bool(GameState.take_item(&"bronze_sword")).is_true()
	assert_str(str(GameState.equipped(&"weapon", &"newest"))).override_failure_message(
		"the newest companion kept the sword and an older one lost it").is_equal("")
	assert_str(str(GameState.equipped(&"weapon", &"older"))).override_failure_message(
		"an older companion lost the sword before the newest one").is_equal("bronze_sword")

func test_what_a_companion_wears_counts_as_equipped() -> void:
	# The bag's marker and the shop's refusal both ask this about the PARTY, which is what
	# stops a companion's armour being sold out from under them.
	GameState.give_item(&"bronze_sword")
	GameState.equip(&"weapon", &"bronze_sword", &"scrapper")
	assert_bool(GameState.is_equipped(&"bronze_sword")).is_true()

func test_asking_what_a_stranger_wears_does_not_make_them_a_member() -> void:
	assert_str(str(GameState.equipped(&"weapon", &"nobody"))).is_equal("")
	assert_bool(GameState.companion_equipment.has(&"nobody")).override_failure_message(
		"asking what somebody wears conjured a record for them").is_false()

func test_resetting_clears_the_party() -> void:
	# An autoload outlives every suite in the run, so anything not reset here is present in the
	# next one - and a leftover companion is a fight with a stranger in it.
	GameState.set_companion(&"scrapper", 11, 14, 2, 3)
	GameState.give_item(&"bronze_sword")
	GameState.equip(&"weapon", &"bronze_sword", &"scrapper")
	GameState.reset()
	assert_dict(GameState.companions).is_empty()
	assert_dict(GameState.companion_equipment).is_empty()
