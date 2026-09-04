class_name CreditsMenu
extends RefCounted
## Who drew the art, turned into pages. CreditsScreen paints these; nothing here has a node,
## a file or a singleton in it.
##
## The input is the Dictionary `tools/gen_sprites.gd` writes to
## `assets/generated/<style>/credits.json` - the composed list, every file with its artists,
## licences and URLs, merged and sorted. The world reads it and hands it here; this class turns
## it into a notice and then a list of names.
##
## Why names rather than one row per work: the payload is 43 artists over 42 works, and a work's
## row would have to carry up to ELEVEN authors. The rows that would be trimmed are exactly the
## ones with the most people to attribute, and a truncated artist is a failed attribution rather
## than a cosmetic loss. See docs/GENRE_CONVENTIONS.md 12a, which quotes the obligation from the
## generator's own README: every author must be credited, and the credits must be reachable from
## inside the game.

## One page: what the header band says, and the rows under it.
class Page:
	extends RefCounted
	var title: String = ""
	var lines: PackedStringArray = PackedStringArray()

	static func of(title_text: String, rows: PackedStringArray) -> Page:
		var out := Page.new()
		out.title = title_text
		out.lines = rows
		return out


## How many rows a page holds. The view DECLARES this, the layout audit MEASURES at it, and
## `page()` can never return more - which is this project's capacity rule adapted to generated
## data. `MAX_SAVE_SLOTS` closes its third side by refusing a config that asks for more; there is
## no config to refuse here, because the number of artists is whatever the art is. So the refusal
## becomes an invariant instead: no page ever exceeds this, whatever it is handed.
##
## Twelve rather than the fourteen that measurably fit, so a padding or font change cannot quietly
## push the last row out of the window.
const ROWS_PER_PAGE := 12

## Where the notice's prose is broken. A character count rather than a measurement, because this
## class has no font and must not acquire one - and the OUTCOME is what is gated:
## `test_credits_layout` measures every line this produces with the real font and fails if one
## would not fit the window. A count that is too greedy is caught there rather than drawn off the
## edge, which is the same bargain `test_dialog_fit` makes for a dialog line.
##
## 43 rather than a rounder number because the gate said so: at 46 the two source URLs came out
## at 296 and 301 pixels in a 292 pixel row, which is what a count guessed from an average
## character width buys you. Set from a measurement, and kept honest by the measurement.
const CHARS_PER_ROW := 43

## The template's own font, named because it is right rather than because it is owed - CC0 asks
## for nothing. It lives here and not in a game's data because it is the TEMPLATE's asset: every
## style draws in it, including the ones that generate their own art and ship no credits at all.
const FONT_CREDIT := "Font: Pixel Operator 8, Jayvee Enaguas (CC0)."

## What the notice says when a style draws its own art. Not an error and not an empty page: a
## procedurally generated cast is a true and complete answer to "who drew this".
const NOTHING_IMPORTED := "This game's art is drawn by the template's own sprite rig."

## The top-level keys naming where the art came from, in the order the notice states them.
const SOURCE_KEYS: Array[String] = ["generator", "tileset"]

const NOTICE_TITLE := "ART AND ATTRIBUTION"
const ARTISTS_TITLE := "ARTISTS"

var _pages: Array[Page] = []
var _index := 0


## `credits` is the parsed credits.json, or an empty Dictionary for a style that has none.
static func of(credits: Dictionary) -> CreditsMenu:
	var menu := CreditsMenu.new()
	# BOTH halves go through the same chunker. The notice was a single page until the capacity
	# test measured it at seventeen rows: the source sentence, two URLs and the licence terms do
	# not fit twelve lines, and a game importing more art would push it further. Paging it as well
	# deleted the special case rather than adding a second one.
	menu._pages.append_array(_paginate(NOTICE_TITLE, _notice(credits)))
	# One block per artist, so the same paginator that keeps a sentence whole keeps a NAME whole -
	# a name is never broken across two rows, because half a name credits nobody. A name too wide
	# for the window is a build failure in the layout gate, not something to paper over here.
	var artists: Array[PackedStringArray] = []
	for name in JsonFile.to_string_array(credits.get("authors", [])):
		artists.append(PackedStringArray([name]))
	menu._pages.append_array(_paginate(ARTISTS_TITLE, artists))
	return menu


## Blocks into pages of at most ROWS_PER_PAGE, keeping their order and never splitting a block.
##
## Blocks rather than lines, and that is what the first look at this screen bought: the notice
## broke across a page boundary in the middle of the sentence "Some layers are share-alike, so
## the", which every gate here passed and no gate here could see. A paragraph and a name are the
## same shape to this function - a run of rows that means nothing in halves.
##
## A block longer than a whole page is split anyway, because the alternative is a page that
## cannot be drawn. Nothing shipped is close: the longest is the four-line source sentence.
static func _paginate(title: String, blocks: Array[PackedStringArray]) -> Array[Page]:
	var out: Array[Page] = []
	var rows := PackedStringArray()
	for block in blocks:
		# A page never opens on a blank: the separator before a paragraph belongs between two
		# things, and at the top of a page there is nothing above it to separate from.
		if rows.is_empty() and block.size() == 1 and block[0].is_empty():
			continue
		if not rows.is_empty() and rows.size() + block.size() > ROWS_PER_PAGE:
			out.append(Page.of(title, rows))
			rows = PackedStringArray()
			if block.size() == 1 and block[0].is_empty():
				continue
		for line in block:
			rows.append(line)
			if rows.size() == ROWS_PER_PAGE:
				out.append(Page.of(title, rows))
				rows = PackedStringArray()
	if not rows.is_empty():
		out.append(Page.of(title, rows))
	return out


func page_count() -> int:
	return _pages.size()


func index() -> int:
	return _index


func page(at: int) -> Page:
	if at < 0 or at >= _pages.size():
		return null
	return _pages[at]


func current() -> Page:
	return page(_index)


## Turn the page. Wraps, the way every cursor in this game wraps, and reports whether it moved so
## the view knows whether to make a noise.
func move(delta: int) -> bool:
	if _pages.size() < 2:
		return false
	_index = posmod(_index + delta, _pages.size())
	return true


## Every line this menu will ever draw, in order. The fit gate walks this rather than opening the
## screen at each page, so a page nobody thought to look at is still measured.
func all_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for one: Page in _pages:
		for line in one.lines:
			out.append(line)
	return out


## The notice: what the art is, whose terms it is under, and where the full list lives.
##
## Built from the file's own top-level keys rather than from prose here, so a game that imports
## different art gets a notice about ITS art. The one sentence this template supplies is the
## pointer to credits.json, because LICENSE.txt says it today and LICENSE.txt is a .txt, which
## Godot does not pack - so between M40 and M43 that sentence reached nobody.
static func _notice(credits: Dictionary) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var gap := PackedStringArray([""])
	var source := str(credits.get("source", ""))
	if source.is_empty():
		out.append(wrap_text(NOTHING_IMPORTED, CHARS_PER_ROW))
		out.append(gap)
		out.append(wrap_text(FONT_CREDIT, CHARS_PER_ROW))
		return out
	out.append(wrap_text(source, CHARS_PER_ROW))
	for key: String in SOURCE_KEYS:
		var url := str(credits.get(key, ""))
		if not url.is_empty():
			out.append(wrap_text(url, CHARS_PER_ROW))
	var licenses := JsonFile.to_string_array(credits.get("licenses", []))
	if not licenses.is_empty():
		out.append(gap)
		out.append(wrap_text("Licences: " + ", ".join(licenses) + ".", CHARS_PER_ROW))
		# Said out loud rather than left to be inferred from the list above it: share-alike is
		# the term that decides what somebody may do with a copy of this game, and a family in a
		# comma-separated list is not a statement of terms.
		if licenses.has(LpcImport.SHARE_ALIKE):
			out.append(wrap_text(
				"Some layers are share-alike, so the composed art here is CC-BY-SA too.",
				CHARS_PER_ROW))
	out.append(gap)
	out.append(wrap_text(
		"Every file, its artists, licences and links are listed in credits.json beside the game.",
		CHARS_PER_ROW))
	out.append(wrap_text(FONT_CREDIT, CHARS_PER_ROW))
	return out


## Word wrap at a character count. Named wrap_text because a bare `wrap` is a global function in
## Godot (the numeric one), and a static method that shadows an engine builtin is a trap for the
## next reader rather than a saving of four characters.
##
## Word wrap at a character count, breaking a word only when it is longer than a whole row - which
## is what a URL is. A broken URL is retypeable; a URL that ran off the side of the window is not
## there at all.
static func wrap_text(text: String, width: int) -> PackedStringArray:
	var out := PackedStringArray()
	var room := maxi(width, 1)
	var line := ""
	for word: String in text.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if candidate.length() <= room:
			line = candidate
			continue
		if not line.is_empty():
			out.append(line)
			line = ""
		var rest := word
		while rest.length() > room:
			out.append(rest.substr(0, room))
			rest = rest.substr(room)
		line = rest
	if not line.is_empty():
		out.append(line)
	if out.is_empty():
		out.append("")
	return out
