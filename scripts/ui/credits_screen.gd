class_name CreditsScreen
extends CanvasLayer
## Who drew the art, drawn. CreditsMenu decides what is on each page; this paints and reports.
##
## A FULL-SCREEN window over the title, not a window over the world: this is reached from the
## title, where there is no world yet, and it is a document rather than a thing happening in a
## place. The shop counter and the save point are windows over the town because a player walked
## into them; nobody walks into a credits screen.
##
## It has no cursor, and that is deliberate rather than unfinished - the pause menu's status page
## made the same call. A cursor points at a row a press will do something with, and there is no
## verb here: the only presses are "turn the page" and "go back". Drawing a highlight bar under a
## line of somebody's name would be pointing at a door that is not there.
##
## It exists because the demo's art is CC-BY-SA and the licence requires the credits to be
## reachable from inside the game. See docs/GENRE_CONVENTIONS.md 12a.

## A sound this view wants played. Emitted rather than played directly: signals up, calls down,
## and the world owns the speaker. Practically too - check.sh's per-file parse gate skips any
## file whose TEXT names an autoload, so reaching the audio singleton here would quietly drop
## this file, and every suite that depends on it, out of that gate. Do not name it in prose.
signal sound_wanted(id: StringName)

## The player is done. The world closes the overlay; this never closes itself, for the reason no
## view here frees itself - the thing that made it is the thing that knows what comes next.
signal left

## Above the title (30), which is what it is drawn over.
const LAYER := 35
const MARGIN := 8
const ROW_PITCH := 10
const HELP_SIZE := UiChrome.FONT_SIZE

var _menu: CreditsMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _frame: UiChrome.Frame = null
var _help: Label = null
var _rows: Array[Label] = []

## The duplicate-event guard every view here has: the same event can reach a handler twice in one
## frame, and acting twice on one press turns two pages.
var _gate := InputGate.new()

## Set once leaving is on its way to the world, so a second press in the same frame cannot ask
## twice.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: CreditsMenu, style: SpriteStyle, viewport_size: Vector2i) -> void:
	_menu = menu
	_style = style
	_build(viewport_size)
	_paint()


## The menu behind this screen, for tests that drive the rules rather than the keys.
func menu() -> CreditsMenu:
	return _menu


## How wide a row may draw, in the units the layout gate measures in. Public because the fit gate
## asks the SCREEN rather than recomputing the arithmetic beside it - two expressions for one
## width is two numbers that drift, and the one that loses is whichever runs second.
func row_width() -> float:
	return _frame.inner().size.x if _frame != null else 0.0


func _build(viewport_size: Vector2i) -> void:
	# A full-screen ground, because the title is still in the tree underneath and a document with
	# a menu showing through it reads as a broken screen rather than as a page.
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	# Sized to what is about to be laid out rather than to the viewport, the save point's rule:
	# ONE arithmetic, computed once and reused by the help line's position below.
	var body := CreditsMenu.ROWS_PER_PAGE * ROW_PITCH + HELP_SIZE
	var height := float(UiChrome.HEADER_HEIGHT + UiChrome.BORDER * 2 + UiChrome.PAD * 2 + body)
	_frame = UiChrome.frame(_style, Rect2(Vector2(MARGIN, MARGIN),
		Vector2(maxf(viewport_size.x - MARGIN * 2.0, 1.0), height)), CreditsMenu.NOTICE_TITLE)
	add_child(_frame.panel)

	var inner := _frame.inner()
	# Enough rows for the fullest page, built once, so turning a page repaints rather than
	# rebuilding and there is no frame on which the screen is half-built.
	for i in CreditsMenu.ROWS_PER_PAGE:
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
			inner.position.y + i * ROW_PITCH)
		# Bounded and trimmed rather than allowed to draw out of the window - a Label with no
		# width does not clip, wrap or complain, which shipped twice before M42. A name is never
		# ACTUALLY trimmed, though: test_credits_layout measures every line this screen can draw
		# and fails the build if one would not fit, because half an artist credits nobody.
		row.size = Vector2(inner.size.x - float(UiChrome.ROW_INSET) * 2.0, ROW_PITCH)
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_frame.panel.add_child(row)
		_rows.append(row)

	_help = UiChrome.label(_style, "dim")
	_help.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
		inner.position.y + CreditsMenu.ROWS_PER_PAGE * ROW_PITCH)
	_frame.panel.add_child(_help)


func _paint() -> void:
	if _menu == null or _style == null:
		return
	_backdrop.color = _style.ui_color("panel")
	var page := _menu.current()
	if page == null:
		return
	_frame.title.text = page.title.to_upper()
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < page.lines.size()
		row.text = page.lines[i] if row.visible else ""
	# The page counter lives here rather than in the header band, so the band keeps saying WHAT
	# this page is while the help line says where you are in it.
	var many := _menu.page_count() > 1
	_help.text = "W/S: page %d of %d    Esc: back" % [_menu.index() + 1, _menu.page_count()] \
		if many else "Esc: back"


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or _committed or event.is_echo():
		return
	if not _gate.accept(event):
		return
	if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"interact"):
		_turn(1)
	elif event.is_action_pressed(&"move_up"):
		_turn(-1)
	elif event.is_action_pressed(&"cancel"):
		_committed = true
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
		left.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## One page on. Silent when there is nowhere to turn to, because a noise for a press that did
## nothing is the same lie as a cursor on a page with no verb.
func _turn(delta: int) -> void:
	if _menu.move(delta):
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
	_paint()
