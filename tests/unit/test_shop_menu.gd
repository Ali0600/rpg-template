extends GdUnitTestSuite
## The counter's rules, with no scene in the way.
##
## Every rule here is one a player can hit in a normal minute of shopping: buying what you
## cannot afford, selling a quest item, backing out. They are tested as a pure class because
## "the purse refused" is a rule, and a rule tested through a screen is a rule tested through
## input routing and a paint pass as well.

func _row(id: StringName, price: int, owned := 0) -> ShopMenu.ShopRow:
	return ShopMenu.ShopRow.of(id, String(id).capitalize(), price, owned,
		"About the %s." % id)

func _shop(gold := 100) -> ShopMenu:
	return ShopMenu.of([_row(&"tonic", 10), _row(&"rope", 30)], [_row(&"tonic", 5, 2)], gold)

func _enter(menu: ShopMenu, row: ShopMenu.Row) -> void:
	# Named, never counted: inserting a row must not re-aim every test at whatever now sits
	# where BUY used to be.
	while menu.index() != row:
		menu.move(1)
	menu.confirm()

func test_the_counter_opens_on_its_top_page() -> void:
	var menu := _shop()
	assert_int(menu.page()).is_equal(ShopMenu.Page.TOP)
	assert_int(menu.size()).is_equal(ShopMenu.Row.size())

func test_buying_asks_how_many_before_it_deals() -> void:
	# The step M18 shipped without, and the one every classic counter has: a row is picked,
	# then the keeper asks, and only THAT confirm is a deal.
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	assert_int(menu.confirm().kind).override_failure_message(
		"picking a row dealt immediately instead of asking how many").is_equal(ShopMenu.Kind.NONE)
	assert_bool(menu.asking()).is_true()
	assert_int(menu.count()).is_equal(1)
	var deal := menu.confirm()
	assert_int(deal.kind).is_equal(ShopMenu.Kind.BUY)
	assert_str(String(deal.item)).is_equal("tonic")
	assert_int(deal.count).is_equal(1)
	assert_int(deal.total).is_equal(10)

func test_buying_what_you_cannot_afford_is_refused_not_clamped() -> void:
	# The rule the whole screen exists to protect. A clamped purchase - the cheapest thing
	# instead of the chosen one - would be a plausible-looking wrong answer, which is worse
	# than nothing happening.
	var menu := _shop(5)
	_enter(menu, ShopMenu.Row.BUY)
	assert_bool(menu.affordable(menu.index())).is_false()
	assert_int(menu.confirm().kind).override_failure_message(
		"a shop sold something the player could not pay for").is_equal(ShopMenu.Kind.NONE)

func test_affordability_is_per_row_not_per_purse() -> void:
	# The near miss: with 10 gold the tonic is affordable and the rope is not, so a check that
	# looked only at the purse would pass the first assertion and get the second wrong.
	var menu := _shop(10)
	_enter(menu, ShopMenu.Row.BUY)
	assert_bool(menu.affordable(0)).is_true()
	assert_bool(menu.affordable(1)).is_false()

func test_selling_is_never_refused_for_money() -> void:
	# Selling always works: the player already holds the thing. Affordability is a BUY-page
	# question, and asking it on the sell page would refuse a broke player their only way out.
	var menu := _shop(0)
	_enter(menu, ShopMenu.Row.SELL)
	assert_bool(menu.affordable(menu.index())).is_true()
	menu.confirm()
	var deal := menu.confirm()
	assert_int(deal.kind).is_equal(ShopMenu.Kind.SELL)
	assert_int(deal.total).is_equal(5)

func test_a_shop_pays_half_and_never_nothing() -> void:
	assert_int(ShopMenu.sell_price(10)).is_equal(5)
	assert_int(ShopMenu.sell_price(9)).is_equal(4)
	# The floor matters: a 1g item selling for 0 is an item the shop takes for free.
	assert_int(ShopMenu.sell_price(1)).override_failure_message(
		"a shop took an item for nothing").is_equal(1)

func test_the_cursor_wraps_on_every_page() -> void:
	var menu := _shop()
	assert_int(menu.index()).is_equal(0)
	menu.move(-1)
	assert_int(menu.index()).is_equal(ShopMenu.Row.size() - 1)
	menu.move(1)
	assert_int(menu.index()).is_equal(0)

func test_backing_out_of_a_page_returns_to_the_row_that_opened_it() -> void:
	var menu := _shop()
	_enter(menu, ShopMenu.Row.SELL)
	assert_int(menu.page()).is_equal(ShopMenu.Page.SELL)
	assert_int(menu.cancel().kind).is_equal(ShopMenu.Kind.NONE)
	assert_int(menu.page()).is_equal(ShopMenu.Page.TOP)
	assert_int(menu.index()).override_failure_message(
		"backing out dropped the player at the top of a counter they were halfway down") \
		.is_equal(ShopMenu.Row.SELL)

func test_cancelling_the_top_page_leaves_the_shop() -> void:
	assert_int(_shop().cancel().kind).is_equal(ShopMenu.Kind.LEAVE)

func test_the_leave_row_leaves() -> void:
	var menu := _shop()
	_enter(menu, ShopMenu.Row.LEAVE)
	# _enter's own confirm is the answer here - LEAVE opens no page.
	assert_int(menu.page()).is_equal(ShopMenu.Page.TOP)

func test_an_empty_counter_still_has_a_row_to_stand_on() -> void:
	# A page with no rows is one the cursor cannot occupy and the player cannot leave.
	var menu := ShopMenu.of([], [], 10)
	_enter(menu, ShopMenu.Row.SELL)
	assert_int(menu.size()).is_equal(1)
	assert_str(ShopMenu.row_label(menu.row(0))).is_equal("(nothing here)")
	assert_int(menu.confirm().kind).is_equal(ShopMenu.Kind.NONE)
	assert_bool(menu.asking()).override_failure_message(
		"an empty page asked how many of nothing").is_false()

func test_a_deal_refreshes_without_moving_the_cursor() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	menu.move(1)
	var was := menu.index()
	menu.refresh([_row(&"tonic", 10), _row(&"rope", 30)], [_row(&"tonic", 5, 3)], 40)
	assert_int(menu.index()).override_failure_message(
		"buying sent the player back to the top of the list").is_equal(was)
	assert_int(menu.gold()).is_equal(40)

func test_a_shorter_list_pulls_the_cursor_back_into_range() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.SELL)
	menu.refresh([], [], 50)
	assert_int(menu.index()).is_less(menu.size())

func test_only_priced_things_are_tradable() -> void:
	# Zero price means not tradable, and it is the DEFAULT - so an item joins the economy by
	# being given a price, never by being forgotten. A key that can be sold is a door that can
	# be locked for the rest of the run, and the failure lands hours later.
	assert_bool(ShopMenu.tradable(1)).is_true()
	assert_bool(ShopMenu.tradable(0)).override_failure_message(
		"an unpriced quest item was offered for sale").is_false()
	assert_bool(ShopMenu.tradable(-1)).is_false()

# -- the quantity step -----------------------------------------------------------------

func test_how_many_is_capped_by_the_purse() -> void:
	# 25 gold against a 10g tonic is two, not three - the ceiling is the money, and a counter
	# that let the count run past it would be offering a deal it must then refuse.
	var menu := _shop(25)
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	assert_int(menu.limit()).is_equal(2)
	for i in 8:
		menu.move(1)
	assert_int(menu.count()).override_failure_message(
		"the count ran past what the purse can cover").is_equal(2)
	assert_int(menu.total()).is_equal(20)

func test_how_many_is_capped_by_the_bag_when_selling() -> void:
	# Selling is bounded by what is held, not by money.
	var menu := _shop(0)
	_enter(menu, ShopMenu.Row.SELL)
	menu.confirm()
	assert_int(menu.limit()).is_equal(2)
	for i in 8:
		menu.move(1)
	assert_int(menu.count()).is_equal(2)

func test_the_count_never_goes_below_one() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	for i in 5:
		menu.move(-1)
	assert_int(menu.count()).is_equal(1)

func test_the_running_total_is_count_times_price() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	menu.move(1)
	menu.move(1)
	assert_int(menu.count()).is_equal(3)
	assert_int(menu.total()).override_failure_message(
		"the total stopped multiplying, so the player agrees to one number and pays another") \
		.is_equal(30)
	assert_int(menu.confirm().total).is_equal(30)

func test_backing_out_of_how_many_moves_nothing() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	menu.move(1)
	assert_int(menu.cancel().kind).is_equal(ShopMenu.Kind.NONE)
	assert_bool(menu.asking()).is_false()
	assert_int(menu.page()).override_failure_message(
		"cancelling the count left the buy page as well").is_equal(ShopMenu.Page.BUY)

func test_moving_while_asking_changes_the_count_not_the_cursor() -> void:
	# One key for both, which is the classic counter's idiom - and the reason it needs a test
	# is that a cursor moving underneath a running total would price the wrong thing.
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	var was := menu.index()
	menu.confirm()
	menu.move(1)
	assert_int(menu.index()).is_equal(was)
	assert_int(menu.count()).is_equal(2)

# -- the keeper ------------------------------------------------------------------------

func test_the_keeper_greets_and_uses_the_shops_own_words() -> void:
	var menu := ShopMenu.of([_row(&"tonic", 10)], [], 100, "Wares!", "More?", "No coin, no cure.")
	assert_str(menu.line()).is_equal("Wares!")

func test_a_shop_with_no_voice_falls_back_to_the_templates() -> void:
	# A game ships a shop by listing stock and nothing else; the keeper still talks.
	assert_str(_shop().line()).is_equal(ShopMenu.DEFAULT_GREETING)

func test_the_keeper_says_no_when_the_purse_is_short() -> void:
	var menu := ShopMenu.of([_row(&"tonic", 10)], [], 5, "", "", "No coin, no cure.")
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	assert_str(menu.line()).override_failure_message(
		"a refusal made no words, which reads as a dead key").is_equal("No coin, no cure.")

func test_the_keeper_asks_how_many_with_the_running_total() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	menu.move(1)
	assert_str(menu.line()).contains("How many")
	assert_str(menu.line()).contains("20")

func test_the_keeper_thanks_after_a_deal() -> void:
	var menu := ShopMenu.of([_row(&"tonic", 10)], [], 100, "", "Anything else?", "")
	_enter(menu, ShopMenu.Row.BUY)
	menu.confirm()
	menu.confirm()
	assert_str(menu.line()).is_equal("Anything else?")

# -- the description bar ---------------------------------------------------------------

func test_the_selected_row_is_described_in_the_items_own_words() -> void:
	# ItemDef.description has existed since items did, and no shop screen showed it until now.
	var menu := _shop()
	_enter(menu, ShopMenu.Row.BUY)
	assert_str(menu.description()).is_equal("About the tonic.")
	menu.move(1)
	assert_str(menu.description()).override_failure_message(
		"the description stayed on the row the cursor left").is_equal("About the rope.")

func test_the_top_page_describes_nothing() -> void:
	assert_str(_shop().description()).is_empty()
