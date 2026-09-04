extends GdUnitTestSuite
## The rules behind the credits screen: what the notice says, and how 43 names become pages.
##
## Pure - no tree, no world, no font. What this cannot answer is whether a line FITS, which is
## `test_credits_layout.gd`'s job with the real font; the two together are the whole gate.
##
## The load-bearing test here is `test_every_shipped_artist_is_named_exactly_once`, and it is a
## SET comparison against the file rather than a per-page property. A per-item check ("every name
## on a page is an artist") is silent about a name that never made it onto one, which is the exact
## failure this screen exists to prevent: an artist the licence requires be credited, quietly
## dropped by an off-by-one in the chunking, with every other gate green.

const CREDITS := "res://assets/generated/lpc32/credits.json"


func _shipped() -> Dictionary:
	var file := JsonFile.read(CREDITS)
	assert_bool(file.ok).override_failure_message(
		"%s did not parse, so every test in this suite is measuring nothing" % CREDITS).is_true()
	return file.data


## Every line of the notice, however many pages it runs to. Asking page(0) would be asking the
## wrong question: the notice is prose and its length depends on the art a game imported, so a
## test anchored to one page silently starts measuring less than the notice the moment it grows.
func _notice_text(menu: CreditsMenu) -> String:
	var out: Array[String] = []
	for at in menu.page_count():
		if menu.page(at).title == CreditsMenu.NOTICE_TITLE:
			out.append("\n".join(menu.page(at).lines))
	return "\n".join(out)


## An input bigger than anything the demo ships, so the paging rules are proven against a case the
## content cannot reach. The shipped 43 fit in four pages; nobody would notice a rule that only
## breaks at four hundred.
func _many(count: int) -> Dictionary:
	var names: Array[String] = []
	for i in count:
		names.append("Artist %d" % i)
	return {"source": "Synthetic art", "authors": names, "licenses": ["CC-BY-SA"]}


func test_the_notice_comes_first_and_says_where_the_art_came_from() -> void:
	var menu := CreditsMenu.of(_shipped())
	assert_str(menu.page(0).title).override_failure_message(
		"the first page is not the notice, so a player meets a list of names with no idea what "
		+ "they are a list of").is_equal(CreditsMenu.NOTICE_TITLE)
	var text := _notice_text(menu)
	# The four things the licence's own example statement names: what it is, where it came from,
	# under what terms, and where the full per-file list lives.
	assert_str(text).contains("Liberated Pixel Cup")
	assert_str(text).contains("github.com")
	assert_str(text).contains("CC-BY-SA")
	assert_str(text).contains("credits.json")


func test_the_share_alike_sentence_is_said_out_loud_when_a_layer_carries_it() -> void:
	# A family sitting in a comma-separated list is not a statement of terms, and share-alike is
	# the term that decides what somebody may do with a copy of this game.
	assert_str(_notice_text(CreditsMenu.of(_shipped()))).contains("share-alike")
	var without := _shipped()
	without["licenses"] = ["CC-BY", "CC0"]
	assert_str(_notice_text(CreditsMenu.of(without))).not_contains("share-alike")


func test_the_font_is_credited_even_though_it_asks_for_nothing() -> void:
	# CC0 requires no attribution. It is named because that is right, and because it is the
	# TEMPLATE's asset - so it must appear for a style that imports nothing at all, too.
	assert_str(_notice_text(CreditsMenu.of(_shipped()))).contains("Pixel Operator")
	assert_str(_notice_text(CreditsMenu.of({}))).contains("Pixel Operator")


func test_a_style_that_draws_its_own_art_gets_one_honest_page() -> void:
	# Not an error and not a blank screen: a procedurally generated cast is a true and complete
	# answer to "who drew this", and three of the four shipped styles are exactly that.
	var menu := CreditsMenu.of({})
	assert_int(menu.page_count()).is_equal(1)
	assert_str(menu.page(0).title).is_equal(CreditsMenu.NOTICE_TITLE)
	assert_str(_notice_text(menu)).contains("sprite rig")


func test_every_shipped_artist_is_named_exactly_once() -> void:
	var credits := _shipped()
	var declared := JsonFile.to_string_array(credits.get("authors", []))
	assert_int(declared.size()).override_failure_message(
		"the shipped credits name no artists, so this proved nothing").is_greater(20)
	var menu := CreditsMenu.of(credits)
	# By the page's own title rather than "everything after the first page": the notice runs to
	# more than one page, and a gate that assumed otherwise would quietly start measuring prose.
	var drawn: Array[String] = []
	for at in menu.page_count():
		if menu.page(at).title != CreditsMenu.ARTISTS_TITLE:
			continue
		for line in menu.page(at).lines:
			drawn.append(line)
	# Compared as a whole, both ways. A name that never reached a page and a page carrying a name
	# nobody declared are two different bugs and this fails on either.
	declared.sort()
	drawn.sort()
	assert_array(drawn).override_failure_message(
		"the pages name %d artists and the file declares %d" % [drawn.size(), declared.size()]
		).is_equal(declared)


func test_a_sentence_is_never_broken_across_a_page() -> void:
	# Found by LOOKING at the first build of this screen, and by nothing else: page one ended on
	# "Some layers are share-alike, so the" and page two picked the sentence up. Every gate was
	# green - a broken paragraph is inside every bound, distinct, in order and correctly wrapped.
	#
	# Asserted by rejoining each page's lines, which is what undoes the wrap: the whole sentence
	# has to turn up inside ONE page.
	var whole := "Some layers are share-alike, so the composed art here is CC-BY-SA too."
	var menu := CreditsMenu.of(_shipped())
	var pages := 0
	for at in menu.page_count():
		if " ".join(menu.page(at).lines).contains(whole):
			pages += 1
	assert_int(pages).override_failure_message(
		"the share-alike sentence is on %d pages whole - it is split across a page boundary, "
		% pages + "so a player reads half a statement of terms").is_equal(1)


func test_no_page_can_exceed_the_capacity_the_screen_declares() -> void:
	# The third side of the capacity rule, adapted. MAX_SAVE_SLOTS closes its by refusing a config
	# that asks for more; there is no config to refuse here, because the number of artists is
	# whatever the art is - so the refusal becomes an invariant over any input at all.
	for credits: Dictionary in [_shipped(), _many(1000), _many(CreditsMenu.ROWS_PER_PAGE + 1)]:
		var menu := CreditsMenu.of(credits)
		for at in menu.page_count():
			assert_int(menu.page(at).lines.size()).override_failure_message(
				"page %d of %d holds %d rows, where the screen draws %d"
				% [at, menu.page_count(), menu.page(at).lines.size(), CreditsMenu.ROWS_PER_PAGE]
				).is_less_equal(CreditsMenu.ROWS_PER_PAGE)


func test_a_thousand_artists_still_all_get_named() -> void:
	# The pair to the test above, and it is what stops "no page overflows" being satisfiable by
	# throwing rows away - a paginator that dropped everything past page one would pass that one.
	var menu := CreditsMenu.of(_many(1000))
	var drawn := 0
	for at in menu.page_count():
		if menu.page(at).title == CreditsMenu.ARTISTS_TITLE:
			drawn += menu.page(at).lines.size()
	assert_int(drawn).is_equal(1000)


func test_turning_the_page_wraps_the_way_every_cursor_here_wraps() -> void:
	var menu := CreditsMenu.of(_shipped())
	assert_int(menu.page_count()).is_greater(2)
	assert_int(menu.index()).is_equal(0)
	assert_bool(menu.move(-1)).is_true()
	assert_int(menu.index()).is_equal(menu.page_count() - 1)
	assert_bool(menu.move(1)).is_true()
	assert_int(menu.index()).is_equal(0)


func test_a_single_page_reports_that_it_did_not_turn() -> void:
	# So the view can stay silent. A noise for a press that did nothing is the same lie as a
	# cursor on a page with no verb on it.
	assert_bool(CreditsMenu.of({}).move(1)).is_false()


func test_wrapping_breaks_a_line_without_losing_a_word() -> void:
	var lines := CreditsMenu.wrap_text("the quick brown fox jumps over the lazy dog", 12)
	for line in lines:
		assert_int(line.length()).is_less_equal(12)
	assert_str(" ".join(lines)).is_equal("the quick brown fox jumps over the lazy dog")


func test_a_url_longer_than_a_row_is_broken_rather_than_dropped() -> void:
	# A URL has no spaces to break at, and the alternative to breaking it is a line drawn off the
	# side of the window - which is the same as not printing it at all, but harder to notice.
	var url := "https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator"
	var lines := CreditsMenu.wrap_text(url, 20)
	assert_int(lines.size()).is_greater(1)
	for line in lines:
		assert_int(line.length()).is_less_equal(20)
	assert_str("".join(lines)).is_equal(url)
