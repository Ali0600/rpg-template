extends GdUnitTestSuite
## What a spell file has to say before a fight will offer it.
##
## Every refusal here is paired against the valid spell that `_spell()` builds, so a problems()
## that reported a fault on everything - which would pass all the refusals - fails the first
## test in the file.

func _spell() -> SpellDef:
	var out := SpellDef.new()
	out.id = &"test_spell"
	out.name = "Test Spell"
	out.description = "It does a thing."
	out.mp_cost = 3
	out.learn_level = 1
	out.kind = SpellDef.Kind.ATTACK
	out.power = 6
	return out

func test_a_valid_spell_has_nothing_wrong_with_it() -> void:
	assert_array(_spell().problems()).is_empty()

func test_a_spell_with_no_id_is_refused() -> void:
	var spell := _spell()
	spell.id = &""
	assert_array(spell.problems()).is_not_empty()

func test_a_spell_with_no_name_is_refused() -> void:
	# The battle list draws the name. A nameless row is one the player cannot choose between.
	var spell := _spell()
	spell.name = ""
	assert_array(spell.problems()).is_not_empty()

func test_a_free_spell_is_refused() -> void:
	# Without a cost it is a second Attack row with better numbers, and the resource is the only
	# thing that makes casting a decision rather than the answer to every turn.
	var spell := _spell()
	spell.mp_cost = 0
	assert_array(spell.problems()).is_not_empty()

func test_a_spell_learned_below_level_one_is_refused() -> void:
	var spell := _spell()
	spell.learn_level = 0
	assert_array(spell.problems()).is_not_empty()

func test_a_spell_learned_beyond_the_curve_is_allowed() -> void:
	# The control that keeps learn_level from being checked against a curve this class cannot
	# see. A spell nobody reaches is a design decision - a reward held back, a sequel's spell
	# shipped early - and refusing it here would be this file overruling the game.
	var spell := _spell()
	spell.learn_level = 99
	assert_array(spell.problems()).is_empty()

func test_an_attack_with_no_power_is_refused() -> void:
	# It would spend the MP and change nothing, which reads in play as a broken button.
	var spell := _spell()
	spell.power = 0
	assert_array(spell.problems()).is_not_empty()

func test_a_heal_with_no_power_is_refused() -> void:
	var spell := _spell()
	spell.kind = SpellDef.Kind.HEAL
	spell.power = 0
	assert_array(spell.problems()).is_not_empty()

func test_a_sleep_needs_turns_rather_than_power() -> void:
	# The one kind that ignores power, so it is the one that proves the check is per-KIND rather
	# than a single "power must be positive" line that would refuse every valid sleep.
	var spell := _spell()
	spell.kind = SpellDef.Kind.SLEEP
	spell.power = 0
	spell.status_turns = 2
	assert_array(spell.problems()).is_empty()

func test_a_sleep_that_takes_no_turns_away_is_refused() -> void:
	var spell := _spell()
	spell.kind = SpellDef.Kind.SLEEP
	spell.status_turns = 0
	assert_array(spell.problems()).is_not_empty()

func test_a_kind_no_spell_has_is_refused() -> void:
	# A hand-edited .tres carries an integer, not a dropdown. An unknown kind would fall through
	# every branch in the fight and cost the player a turn doing nothing at all.
	var spell := _spell()
	spell.kind = (SpellDef.Kind.size()) as SpellDef.Kind
	assert_array(spell.problems()).is_not_empty()

# -- elements ---------------------------------------------------------------------------------

func test_an_attack_spell_may_be_made_of_something() -> void:
	# The control for every refusal below: an element on the one kind that deals damage is the
	# whole feature, so a check written as "an element is always wrong" would pass all of them.
	var spell := _spell()
	spell.element = &"fire"
	assert_array(spell.problems()).is_empty()

func test_an_elementless_attack_spell_is_still_fine() -> void:
	# Empty is the default and means "lands at face value" - every spell shipped before elements
	# existed is this one, so refusing it would fail the whole back catalogue.
	assert_str(String(_spell().element)).is_empty()
	assert_array(_spell().problems()).is_empty()

func test_a_heal_made_of_something_is_refused() -> void:
	# It has no damage for a resistance to scale, so the field would be one nothing reads - which
	# is how a data file comes to describe an effect the fight never applies.
	var spell := _spell()
	spell.kind = SpellDef.Kind.HEAL
	spell.element = &"fire"
	assert_array(spell.problems()).is_not_empty()

func test_a_sleep_made_of_something_is_refused() -> void:
	var spell := _spell()
	spell.kind = SpellDef.Kind.SLEEP
	spell.status_turns = 2
	spell.element = &"ice"
	assert_array(spell.problems()).is_not_empty()

func test_a_boost_made_of_something_is_refused() -> void:
	# The third kind checked deliberately: the refusal lives outside the kind chain, so if it had
	# been written into one branch instead, the other two would pass while reading as covered.
	var spell := _spell()
	spell.kind = SpellDef.Kind.BOOST
	spell.power = 2
	spell.status_turns = 3
	spell.element = &"fire"
	assert_array(spell.problems()).is_not_empty()
