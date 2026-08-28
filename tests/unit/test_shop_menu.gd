extends GdUnitTestSuite
## The counter's rules, with no scene in the way.
##
## Every rule here is one a player can hit in a normal minute of shopping: buying what you
## cannot afford, selling a quest item, backing out. They are tested as a pure class because
## "the purse refused" is a rule, and a rule tested through a screen is a rule tested through
## input routing and a paint pass as well.

func _row(id: StringName, price: int, owned := 0) -> ShopMenu.ShopRow:
	return ShopMenu.ShopRow.of(id, String(id).capitalize(), price, owned)

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

func test_buying_something_you_can_afford_reports_the_deal() -> void:
	var menu := _shop(50)
	_enter(menu, ShopMenu.Row.BUY)
	var deal := menu.confirm()
	assert_int(deal.kind).is_equal(ShopMenu.Kind.BUY)
	assert_str(String(deal.item)).is_equal("tonic")
	assert_int(deal.price).is_equal(10)

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
	var deal := menu.confirm()
	assert_int(deal.kind).is_equal(ShopMenu.Kind.SELL)
	assert_int(deal.price).is_equal(5)

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
