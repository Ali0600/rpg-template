class_name OptionsScreen
extends CanvasLayer
## The options page, drawn. OptionsMenu decides what the rows say; this paints and reports.
##
## It has TWO bases, which no other screen here does: it is opened from the title and from the
## pause menu, and it is drawn differently over each. Over the title it is a document and gets an
## opaque ground, the credits' rule. Over the world it is a dimmed window over the place the
## player is standing in - because the thing being chosen here is what the WINDOWS look like, and
## a palette judged against a black screen is a palette judged somewhere it will never be seen.
##
## It has a cursor, unlike the credits and the status page, because this page has verbs: every row
## does something when pressed. The value cycles on confirm; there is no left/right axis, and
## OptionsMenu says why.
##
## Like every view here it names no singleton, in code or in prose - the per-file parse gate drops
## any file whose TEXT does, along with every suite that depends on it. So it asks for a noise by
## signal and asks for a change by signal, and the world does both.

## A sound this view wants played.
signal sound_wanted(id: StringName)

## The player asked for the next volume step. The world owns the value; a view that wrote it would
## be a second writer for something that outlives every scene.
signal sound_requested

## The player asked for the next window palette. Same rule, and one step further: which palettes
## exist is a content question this class may not ask.
signal window_requested

## The player is done. The world closes the overlay and decides what is underneath; this never
## closes itself, for the reason no view here frees itself.
signal left

## Above the title (30) and the credits (35), which are the two things it is drawn over.
const LAYER := 36
const MARGIN := 8
const PADDING := 4
const ROW_PITCH := 10
const HELP_SIZE := UiChrome.FONT_SIZE
const PANEL_WIDTH := 168

## Air between the last row and the help line. Without it the help sits at exactly one ROW_PITCH
## below the last row, which is the spacing between two rows - so it reads as a third row that
## the cursor mysteriously refuses to land on. Found by looking at it.
const HELP_GAP := 5

## How much of the world shows through when this is opened over one. The pause screen's number,
## because it is the same idea: you are still standing where you were.
const BACKDROP_ALPHA := 0.85

var _menu: OptionsMenu = null
var _style: SpriteStyle = null
var _over_world := false
var _backdrop := ColorRect.new()
var _frame: UiChrome.Frame = null
var _select: ColorRect = null
var _help: Label = null
var _rows: Array[Label] = []

## The duplicate-event guard every view here has: one press can reach a handler twice in a frame.
var _gate := InputGate.new()

## Set once leaving is on its way, so a second press cannot ask twice.
var _committed := false


func _ready() -> void:
	layer = LAYER


func setup(menu: OptionsMenu, style: SpriteStyle, viewport_size: Vector2i,
		over_world: bool = false) -> void:
	_menu = menu
	_style = style
	_over_world = over_world
	_build(viewport_size)
	_paint()


## New words on the rows, cursor untouched - after the world has changed a value and worded it.
func refresh(sound: String, window: String) -> void:
	if _menu == null:
		return
	_menu.refresh(sound, window)
	_paint()


## New colours, after the player chose a palette. Rebuilt rather than repainted because a window's
## fill and rule live in a StyleBox made once, and this is the one screen that has to change its
## own colours while it is being looked at - which is most of the point of it.
func restyle(style: SpriteStyle) -> void:
	if _style == null or _menu == null:
		return
	_style = style
	var size := Vector2i(int(_backdrop.size.x), int(_backdrop.size.y))
	# The backdrop goes with everything else rather than being kept and recoloured: taken out of
	# the tree and not freed it would be an orphan, and the suites here assert a baseline of zero.
	for child in get_children():
		remove_child(child)
		child.free()
	_rows.clear()
	_backdrop = ColorRect.new()
	_build(size)
	_paint()


func menu() -> OptionsMenu:
	return _menu


## The row the cursor is on, for the layout audit - the SaveScreen accessor, so a gate can ask
## which row is chosen rather than recomputing the arithmetic beside it.
func selected_row() -> Label:
	if _menu == null or _menu.index() < 0 or _menu.index() >= _rows.size():
		return null
	return _rows[_menu.index()]


func _build(viewport_size: Vector2i) -> void:
	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size
	add_child(_backdrop)

	var body := _menu.size() * ROW_PITCH + HELP_GAP + HELP_SIZE
	var height := float(UiChrome.HEADER_HEIGHT + UiChrome.BORDER * 2 + UiChrome.PAD * 2 + body)
	var width := minf(PANEL_WIDTH, maxf(viewport_size.x - MARGIN * 2.0, 1.0))
	# CENTRED, where the save point and the counter sit in a corner. Those are windows over a
	# place the player walked into, and where they sit says which part of the world they belong
	# to; this belongs to no part of it. Two rows in a corner of a 320x180 screen read as a
	# screen that had not finished drawing - which is what the first photograph of it looked like.
	var at := Vector2(floorf((viewport_size.x - width) * 0.5),
		floorf((viewport_size.y - height) * 0.5))
	_frame = UiChrome.frame(_style, Rect2(at, Vector2(width, height)), "OPTIONS")
	add_child(_frame.panel)

	var inner := _frame.inner()
	# Added BEFORE the rows so the bar draws behind the words rather than over them.
	_select = UiChrome.select(_style)
	_frame.panel.add_child(_select)
	for i in _menu.size():
		var row := UiChrome.label(_style, "text")
		row.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
			inner.position.y + i * ROW_PITCH)
		# Bounded and trimmed rather than allowed to draw out of the window - a Label with no
		# width does not clip, wrap or complain. Nothing shipped is ACTUALLY trimmed, though:
		# test_options_layout measures every row this screen can draw against the real font.
		row.size = Vector2(inner.size.x - float(UiChrome.ROW_INSET) * 2.0, ROW_PITCH)
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_frame.panel.add_child(row)
		_rows.append(row)

	_help = UiChrome.label(_style, "dim")
	# Only the two keys this page adds. Up and down are the same cursor every other menu in the
	# game teaches, and naming them here cost 60px the window does not have - which the layout
	# audit refused on its first run.
	_help.text = "E: change    Esc: back"
	_help.position = Vector2(inner.position.x + float(UiChrome.ROW_INSET),
		inner.position.y + _menu.size() * ROW_PITCH + HELP_GAP)
	_frame.panel.add_child(_help)


func _paint() -> void:
	if _menu == null or _style == null:
		return
	var panel := _style.ui_color("panel")
	if _over_world:
		# Translucent over a place, opaque over a document. The world behind this is what a
		# window colour is chosen AGAINST.
		panel.a = BACKDROP_ALPHA
	_backdrop.color = panel
	var text := _style.ui_color("text")
	var dim := _style.ui_color("dim")
	_select.visible = false
	for i in _rows.size():
		var row := _rows[i]
		var selected := i == _menu.index()
		row.text = _menu.label(i)
		row.add_theme_color_override("font_color", text if selected else dim)
		if selected:
			UiChrome.place(_select, row, _frame.inner().size.x, ROW_PITCH)


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or _committed or not event.is_pressed() or event.is_echo():
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
		_act(_menu.confirm())
	elif event.is_action(&"cancel"):
		_act(_menu.cancel())
	else:
		return
	get_viewport().set_input_as_handled()


## Turns one answer into one signal.
##
## Neither change COMMITS: the page stays up, the world changes the value and hands back the new
## words, and the row says what it now is. That is the save row's rule, and here it is most of the
## point - a player picking a window colour is comparing, which means pressing more than once.
func _act(pick: OptionsMenu.Pick) -> void:
	match pick.kind:
		OptionsMenu.Kind.SOUND:
			# No noise from here, deliberately, where the window row makes one: the world plays
			# the blip AFTER the step has been applied, so it is heard at the volume just chosen.
			# That is the only feedback there is that Off means off.
			sound_requested.emit()
		OptionsMenu.Kind.WINDOW:
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			window_requested.emit()
		OptionsMenu.Kind.LEAVE:
			_committed = true
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
			left.emit()
		_:
			_paint()
