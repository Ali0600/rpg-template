class_name TitleScreen
extends CanvasLayer
## The first thing the game draws. TitleMenu decides; this paints and reports.
##
## An OVERLAY over an empty world rather than a scene of its own, and the reason is the same
## one that keeps the game-over screen an overlay: there is nothing to boot into a second
## scene FOR. The world node is what resolves which game is running, and it does that exactly
## once per process - a title scene with its own boot would be a second answer to that
## question, which is the failure the whole game-select design exists to prevent.
##
## It sits ABOVE the game-over screen because it is what the game-over screen routes to.
## A sound this view wants played. Emitted rather than played directly, for two reasons.
##
## Signals up, calls down - the world owns the speaker, and a view asking for a noise is the
## same shape as a view asking for anything else. And practically: check.sh's per-file parse
## gate skips any file whose TEXT names an autoload, so calling the audio singleton here would
## quietly drop this file out of that gate, along with every test that depends on it. Do not
## name it in prose either.
signal sound_wanted(id: StringName)

signal load_requested(slot: int)
signal new_game_requested
signal credits_requested

## The player asked for the options page. Not committed either, and for the same reason.
signal options_requested

const LAYER := 30
const MARGIN := 8
## The one screen in this game with a big word on it. A title is mostly its own name.
const HEADING_SIZE := UiChrome.HEADING_SIZE
const ROW_SIZE := UiChrome.FONT_SIZE
const HELP_SIZE := UiChrome.FONT_SIZE
const ROW_PITCH := 11
## The rows sit in the lower half, under the name.
const ROWS_Y := 96

var _menu: TitleMenu = null
var _style: SpriteStyle = null
var _backdrop := ColorRect.new()
var _heading: Label = null
var _frame: UiChrome.Frame = null
var _select: ColorRect = null
var _rows: Array[Label] = []
var _help: Label = null

var _gate := InputGate.new()

## Set once an answer is on its way. Both answers rebuild the tree on a deferred call, so there
## is a window in which this is still on screen and must not answer again.
var _committed := false


func _ready() -> void:
	layer = LAYER


## `heading` is the game's own title, handed in the way the controls hint is: what a game is
## called is a manifest's business, and this class may not read one.
func setup(menu: TitleMenu, style: SpriteStyle, viewport_size: Vector2i, heading: String) -> void:
	_menu = menu
	_style = style
	_build(viewport_size, heading)
	_paint()


func refresh(slots: Array[SlotSummary]) -> void:
	if _menu == null:
		return
	_menu.refresh(slots)
	_committed = false
	_paint()


## The menu behind this screen, for tests that drive the rules rather than the keys.
func menu() -> TitleMenu:
	return _menu


func _build(viewport_size: Vector2i, heading: String) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	# Centred across the whole width rather than positioned by hand: a game with a longer name
	# than this one's should not have to come and edit a constant. Nothing in the references
	# argues for a window around a title's own name - what they share is that the name is the
	# largest thing on screen, which is what HEADING_SIZE is for. See GENRE_CONVENTIONS S16a.
	_heading = UiChrome.label(_style, "text", HEADING_SIZE)
	_heading.text = heading
	_heading.position = Vector2(0, ROWS_Y - 48)
	_heading.size = Vector2(viewport_size.x, HEADING_SIZE + 6)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_heading)

	# The rows in a window of their own, centred under the name. Enough for the widest page,
	# built once, so a page change repaints rather than rebuilding and there is no frame on which
	# the screen is half-built.
	var count := maxi(_menu.row_count(), _menu.slot_count())
	var height := float(UiChrome.BORDER * 2 + UiChrome.PAD * 2) + count * ROW_PITCH
	var width := float(viewport_size.x) * 0.6
	_frame = UiChrome.frame(_style, Rect2((float(viewport_size.x) - width) * 0.5,
		float(ROWS_Y) - float(UiChrome.PAD), width, height))
	add_child(_frame.panel)
	var inner := _frame.inner()
	_select = UiChrome.select(_style)
	_frame.panel.add_child(_select)
	for i in count:
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x, inner.position.y + i * ROW_PITCH)
		row.size = Vector2(inner.size.x, ROW_PITCH)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_frame.panel.add_child(row)
		_rows.append(row)

	_help = UiChrome.label(_style, "dim")
	_help.position = Vector2(MARGIN, viewport_size.y - 12)
	add_child(_help)


func _paint() -> void:
	if _style == null or _menu == null:
		return
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")

	_backdrop.color = _style.ui_color("panel")
	_heading.add_theme_color_override("font_color", text)
	_help.add_theme_color_override("font_color", dim)
	_help.text = "W/S to choose    E to pick" if _menu.page() == TitleMenu.Page.TOP \
		else "W/S to choose    E to pick    Esc to go back"

	# The window is as tall as the page it is DRAWING, not as tall as the widest one it could.
	# Built for the widest - a slot list is longer than two commands - it stood over the first
	# page with a hand's width of nothing under the last row, which reads as a list that failed
	# to finish rather than as a menu.
	_frame.panel.size.y = float(UiChrome.BORDER * 2 + UiChrome.PAD * 2) \
		+ maxi(_menu.size(), 1) * ROW_PITCH
	_select.visible = false
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < _menu.size()
		if not row.visible:
			continue
		var selected := i == _menu.index()
		row.text = _label_for(i)
		row.add_theme_color_override("font_color", text if selected else dim)
		if selected:
			UiChrome.place(_select, row, _frame.inner().size.x, ROW_PITCH)


## The row the cursor is on, or null when nothing is pressable.
func selected_row() -> Label:
	var at := _menu.index()
	if at < 0 or at >= _rows.size() or not _rows[at].visible:
		return null
	return _rows[at]


func _label_for(at: int) -> String:
	if _menu.page() == TitleMenu.Page.TOP:
		return _menu.top_label(at)
	# The same row text the pause and game-over screens draw, from the same function: a slot
	# that reads one way when you save it and another when you are choosing it is two menus
	# describing one file.
	return PauseMenu.slot_label(at, _menu.summary(at))


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or _committed or event.is_echo():
		return
	if not _gate.accept(event):
		return
	if event.is_action_pressed(&"move_down"):
		if _menu.move(1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action_pressed(&"move_up"):
		if _menu.move(-1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action_pressed(&"interact"):
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
		_act(_menu.confirm())
	elif event.is_action_pressed(&"cancel"):
		_act(_menu.cancel())
	else:
		return
	get_viewport().set_input_as_handled()


## Turns one answer into one signal. A refusal repaints and says nothing, which is why the menu
## returns NONE rather than throwing: "that did nothing" is a normal outcome here too.
func _act(pick: SlotMenu.Pick) -> void:
	match pick.kind:
		TitleMenu.Kind.LOAD:
			_committed = true
			load_requested.emit(pick.slot)
		TitleMenu.Kind.NEW_GAME:
			_committed = true
			new_game_requested.emit()
		TitleMenu.Kind.CREDITS:
			# NOT committed: the credits screen is closed back to this one, and a title that had
			# latched an answer would be deaf when the player returned to it.
			credits_requested.emit()
		TitleMenu.Kind.OPTIONS:
			# Not committed, for the credits' reason exactly - the options page comes back here.
			options_requested.emit()
		_:
			_paint()
