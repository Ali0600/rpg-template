class_name SaveScreen
extends CanvasLayer
## A save point, drawn. SaveMenu decides which row; this paints and reports.
##
## A WINDOW over the live world, not a full-screen dim, for the reason the shop counter is one:
## a save point is somewhere the player walked to and is standing in, and the town behind the
## panel is what says so. The pause menu dims because it is a step outside the game; this is a
## thing happening inside it.
##
## Nothing here but the slots. The rows a pause menu would put around them - Items, Equipment,
## Status, Load - are all the wrong answer to "the priest is asking where to record your
## journey", which is why this is its own screen rather than PauseScreen opened at its save
## page. The wording of a row is still PauseMenu's, because there is one way to put a slot into
## words and this is not a second one.

## A sound this view wants played. Emitted rather than played directly: signals up, calls down,
## and the world owns the speaker. Practically too - check.sh's per-file parse gate skips any
## file whose TEXT names an autoload, so reaching the audio singleton here would quietly drop
## this file, and every suite that depends on it, out of that gate. Do not name it in prose.
signal sound_wanted(id: StringName)

## Write this slot. The world is the only thing that touches the disk, so this reports and
## waits to be told what the slots look like afterwards - the shop's `bought` shape.
signal save_requested(slot: int)

## The player is done. The world closes the overlay; this never closes itself, for the reason
## no view here frees itself - the thing that made it is the thing that knows what comes next.
signal left

const LAYER := 14
const MARGIN := 6
const PADDING := 4
const TITLE_SIZE := UiChrome.FONT_SIZE
const ROW_SIZE := UiChrome.FONT_SIZE
const HELP_SIZE := UiChrome.FONT_SIZE
const ROW_PITCH := 10
const PANEL_WIDTH := 150

var _menu: SaveMenu = null
var _style: SpriteStyle = null
var _frame: UiChrome.Frame = null
var _panel: Panel = null
var _help: Label = null
var _select: ColorRect = null
var _rows: Array[Label] = []

## The duplicate-event guard every view here has: the same event can reach a handler twice in
## one frame, and acting twice on one press moves the cursor two rows.
var _gate := InputGate.new()

## Set once leaving is on its way to the world. A SAVE deliberately does not set it: writing a
## slot leaves this screen open and the world calls refresh(), so the row shows what was just
## written - PauseScreen's rule for the same press.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: SaveMenu, style: SpriteStyle, viewport_size: Vector2i,
		title: String = "") -> void:
	_menu = menu
	_style = style
	_build(viewport_size, title)
	_paint()


## New slot contents from the world, cursor untouched. After a save that is what makes the row
## the player is looking at show what they just wrote.
func refresh(slots: Array[SlotSummary]) -> void:
	if _menu == null:
		return
	_menu.refresh(slots)
	_paint()


func menu() -> SaveMenu:
	return _menu


func _build(viewport_size: Vector2i, title: String) -> void:
	# One row per slot, and at least one: a window with no rows in it is one the player cannot
	# read and cannot escape - the empty-bag rule every list here follows.
	var count := maxi(_menu.slot_count(), 1)
	# Sized to what is about to be laid out rather than to the viewport: a window is as big as
	# the thing inside it. ONE arithmetic, computed once and reused by the help line's position
	# below - two expressions for one height is two numbers that drift, and the one that loses is
	# whichever runs second.
	var body := count * ROW_PITCH + HELP_SIZE
	var height := float(UiChrome.HEADER_HEIGHT + UiChrome.BORDER * 2 + UiChrome.PAD * 2 + body)
	_frame = UiChrome.frame(_style, Rect2(Vector2(MARGIN, MARGIN),
		Vector2(minf(PANEL_WIDTH, maxf(viewport_size.x - MARGIN * 2.0, 1.0)), height)),
		title if not title.is_empty() else "RECORD YOUR JOURNEY")
	_panel = _frame.panel
	add_child(_panel)

	var inner := _frame.inner()
	# Added BEFORE the rows so it is drawn behind them: a bar the row sits on, where this screen
	# used to write a "*" into the front of the row's own text.
	_select = UiChrome.select(_style)
	_panel.add_child(_select)
	for i in count:
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
			inner.position.y + i * ROW_PITCH)
		_panel.add_child(row)
		_rows.append(row)

	_help = UiChrome.label(_style, "dim")
	_help.text = "Enter: save    Esc: leave"
	_help.position = Vector2(inner.position.x, inner.position.y + count * ROW_PITCH)
	_panel.add_child(_help)


func _paint() -> void:
	if _menu == null or _style == null:
		return
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")
	_select.visible = false
	for i in _rows.size():
		var row := _rows[i]
		var selected := i == _menu.index()
		# The same wording as every other slot list in the game, from the one function that
		# words one. "empty" and "damaged" are different facts and a save point is exactly
		# where the difference matters.
		row.text = PauseMenu.slot_label(i, _menu.summary(i)) if i < _menu.slot_count() else ""
		row.add_theme_color_override("font_color", text if selected else dim)
		if selected:
			UiChrome.place(_select, row, _frame.inner().size.x, ROW_PITCH)


func _unhandled_input(event: InputEvent) -> void:
	if _committed or not event.is_pressed() or event.is_echo():
		return
	if not _gate.accept(event):
		return

	if event.is_action(&"move_down"):
		if _menu.move(1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"move_up"):
		if _menu.move(-1):
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint()
	elif event.is_action(&"interact"):
		_write(_menu.confirm())
	elif event.is_action(&"cancel"):
		_committed = true
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
		left.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## One answer, one signal. A refusal SAYS so with the cue a locked door uses, because "that
## did nothing" is a normal outcome and a silent one reads as a dead key.
func _write(slot: int) -> void:
	if slot < 0:
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.LOCKED))
		return
	sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
	save_requested.emit(slot)


## The row the cursor is on. What replaced reading a "*" off the front of a row's own text.
func selected_row() -> Label:
	var at := _menu.index()
	if at < 0 or at >= _rows.size():
		return null
	return _rows[at]
