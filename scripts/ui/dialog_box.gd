class_name DialogBox
extends CanvasLayer
## Draws a conversation and takes the player's answers. Owns no rules about what happens
## next - it asks a DialogRunner and shows what it is told.
##
## The typewriter is not decoration: at 320x180 a line appears all at once and is easy to
## read past, and a reveal both paces the scene and gives the confirm button something to
## do on a first press. Pressing confirm mid-reveal completes the line rather than skipping
## it, which is the behaviour every player expects and the one that is easy to get wrong.

## A sound this view wants played. Emitted rather than played directly, for two reasons.
##
## Signals up, calls down - the world owns the speaker, and a view asking for a noise is the
## same shape as a view asking for anything else. And practically: check.sh's per-file parse
## gate skips any file whose TEXT names an autoload, so calling the audio singleton here would
## quietly drop this file out of that gate, along with every test that depends on it. That is
## not hypothetical - it is how this signal came to exist. Do not name it in prose either.
signal sound_wanted(id: StringName)

signal closed(effects: Array)

## The box's CAPACITY, named here because it is half of a contract: the other half is
## tests/unit/test_dialog_fit.gd, which measures every shipped line against these numbers and
## fails the build on anything that will not fit. They are constants rather than magic numbers
## in _build for exactly that reason - a gate that kept its own copy would drift, and the day
## it drifted the overflow would be silent again.
##
## Silent is the word that matters. A line too long for this box is not wrapped, scrolled or
## reported: RichTextLabel with scroll_active off simply CLIPS it, so a fact written into the
## data never reaches the player and nothing anywhere says so.
const MARGIN := 6
const FONT_SIZE := UiChrome.FONT_SIZE
## The project font's height at FONT_SIZE, and the unit a line is COUNTED in. Pinned as a
## constant so the layout arithmetic is readable, and asserted against the real font in the fit
## gate - if the font ever changes, that assertion fails rather than the box quietly shrinking.
##
## EIGHT since M42, where it was twelve: Pixel Operator 8 is drawn for this size, so a line is
## exactly as tall as the glyphs in it. That is also why the line count went UP - see TEXT_LINES.
const LINE_HEIGHT := 8
## The air between two drawn lines. A pixel font has no built-in leading: at LINE_HEIGHT alone a
## descender sits on the next line's capitals. Counting and DRAWING are therefore different
## numbers, and each is used for exactly one thing - LINE_HEIGHT to ask "how many lines is this
## text", LINE_PITCH to place anything.
const LINE_SPACING := 2
const LINE_PITCH := LINE_HEIGHT + LINE_SPACING
## How many lines of text one node may use. A deliberate ceiling on the WRITING as much as on
## the box: a conversation that needs more is a conversation with another node in it, and
## chaining `next` is this format's own pagination.
##
## THREE since M42, and the box did not grow to buy it: three 8px lines with leading is 30px
## where two 12px lines were 24. It is also the genre's own middle - Pokemon shows two,
## EarthBound three, Dragon Warrior eight - and the pixel font is WIDER per character than the
## engine's default was at the same size, so two would have cut fifteen shipped lines in half.
const TEXT_LINES := 3
const MAX_CHOICES := 4

## The speaker's name lives in the window's HEADER BAND now, not on a line of its own inside it.
## Persona puts it in a tab above the box's corner, which is where a conversation with two people
## becomes readable at a glance - and which has nowhere to sit six pixels from the edge of a
## 320px screen, so the band is this template's stated adaptation. See GENRE_CONVENTIONS S6.
const TEXT_Y := UiChrome.HEADER_HEIGHT + UiChrome.BORDER + UiChrome.PAD
const PADDING := UiChrome.BORDER + UiChrome.PAD
## Choices get their OWN band, below every line of text rather than below where the text
## happened to end. Placing them relative to the rendered text is what put a choice on top of
## a second line in the shipped build: the position was computed for one-line text and the
## data grew past it.
const CHOICE_Y := TEXT_Y + TEXT_LINES * LINE_PITCH + 2
const CHOICE_PITCH := LINE_PITCH
## How far a choice sits inside the text column. The fit gate spends it out of the width it
## measures a choice against, so the two read ONE number rather than each keeping a 4.
const CHOICE_INSET := 2
const PAD_BOTTOM := 5

## The box with nothing to answer: speaker, its lines, done.
const BOX_HEIGHT := TEXT_Y + TEXT_LINES * LINE_PITCH + PAD_BOTTOM

## Room between the speaker's face and the words they are saying.
const FACE_GAP := 3.0

const CHARACTERS_PER_SECOND := 45.0

## How many revealed characters between typewriter blips. Not one per character: at 45 a
## second that is a continuous tone rather than a voice. This is a FEEL number - no gate can
## check it, only a person can hear it - so it sits here as one knob to turn rather than as a
## rhythm spread through the reveal code.
const CHARACTERS_PER_BLIP := 3

var _runner: DialogRunner
## The window. Kept under the name `_panel` because it is what a screen's geometry is measured
## from and three suites read it by that name; it is a framed Panel now rather than a bare rect.
var _panel: Panel = null
var _frame: UiChrome.Frame = null
var _speaker: Label = null
## The speaker's face, when the node names one. Hidden otherwise, so a sign or a chest lays the
## box out exactly as a person does - a portrait that reserved its column either way would put
## every unattributed line in a narrower box for no reason.
var _face: TextureRect = null
var _source: SpriteSource = null
var _select: ColorRect = null
var _text := RichTextLabel.new()
var _choice_labels: Array[Label] = []
var _choice_index := 0
var _revealed := 0.0
var _blipped := 0
var _style: SpriteStyle
var _gate := InputGate.new()
var _viewport := UiScale.DESIGN_SIZE


## How wide a line of text may be, given the screen and the face beside it. A function rather
## than a constant because the fit gate has to ask the same question of the same numbers - one
## place, so the box and the gate cannot come to disagree about how much room a line has.
##
## `face` is what the portrait column costs, and it is an ARGUMENT rather than a lookup because
## the gate has to be able to ask for the widest any style declares. Every shipped style happens
## to draw a 12-design-pixel face - lpc32's 24 at world scale 2, the rig styles' 12 at 1 - but
## that is a property of today's data and not a promise.
static func text_width(viewport_width: int, face := 0.0) -> float:
	var column := 0.0 if face <= 0.0 else face + FACE_GAP
	return float(viewport_width - MARGIN * 2) - PADDING * 2.0 - column


## The widest face any shipped style would put in this box. What the fit gate measures against,
## because a line that fits beside a small portrait and not beside a large one is a line that
## clips for whoever plays the style nobody measured.
static func widest_face() -> float:
	var out := 0.0
	for path in ContentScan.files("res://data/styles", ["tres"]):
		var style := load(path) as SpriteStyle
		if style != null:
			out = maxf(out, UiChrome.portrait_span(style))
	return out


## How tall the box stands while answering `count` choices. The box GROWS for a decision and
## shrinks back after: a reader needs the room exactly while they are choosing, and a box that
## was always tall enough for four choices would cover half the world for every line of chat.
static func height_for(count: int) -> int:
	if count <= 0:
		return BOX_HEIGHT
	return CHOICE_Y + count * CHOICE_PITCH + PAD_BOTTOM


func _ready() -> void:
	layer = 10
	visible = false


## Builds the box from the style's interface colours, so it re-skins along with the art.
func setup(style: SpriteStyle, viewport_size: Vector2i) -> void:
	_style = style
	_viewport = viewport_size
	# A window rather than a rectangle, with the speaker's name in its band. The name is set per
	# line, so the band is built with a space in it: a header exists or it does not, and a box
	# whose band appeared only once somebody was named would change height mid-conversation.
	_frame = UiChrome.frame(style, Rect2(Vector2.ZERO, Vector2.ONE), " ")
	_panel = _frame.panel
	_speaker = _frame.title
	_speaker.add_theme_color_override("font_color", style.ui_color("text"))
	_resize(0)
	add_child(_panel)

	_face = TextureRect.new()
	_face.visible = false
	_panel.add_child(_face)

	_text.position = Vector2(PADDING, TEXT_Y)
	# The full TEXT_LINES tall. It used to be 22px against a 12px line, so even two lines were
	# clipped - the box could really only ever show one.
	_text.size = Vector2(text_width(_viewport.x), TEXT_LINES * LINE_PITCH)
	_text.bbcode_enabled = false
	_text.scroll_active = false
	# Set rather than left to the theme: the drawn advance has to be LINE_PITCH for the box's
	# arithmetic to describe what a reader sees, and a default nobody chose is a number that
	# can move under it.
	_text.add_theme_constant_override("line_separation", LINE_SPACING)
	_text.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_text.add_theme_color_override("default_color", style.ui_color("text"))
	_panel.add_child(_text)

	# The cursor, added BEFORE the choices so it is drawn behind them: a bar the answer sits on
	# rather than a ">" glued to the front of the answer's own text. The old marker was part of
	# the STRING, which is why the repaint had to strip two characters back off to redraw it.
	_select = UiChrome.select(style)
	_panel.add_child(_select)
	for i in MAX_CHOICES:
		var label := UiChrome.label(style, "text")
		label.position = Vector2(PADDING + CHOICE_INSET, CHOICE_Y + i * CHOICE_PITCH)
		label.visible = false
		_panel.add_child(label)
		_choice_labels.append(label)


## Opens a conversation. The SOURCE arrives here rather than at setup, and that is not a detail:
## the box is built once for the life of a game (`world_scene` guards on its child count) while
## the source is rebuilt per map from that map's style, so a face captured at setup would be cut
## from the first map's art for the rest of the run.
func open(runner: DialogRunner, source: SpriteSource = null) -> bool:
	_source = source
	_runner = runner
	if not _runner.begin():
		push_error("DialogBox: dialog '%s' has nowhere to start" % runner.id)
		return false
	visible = true
	_show_line()
	return true


func is_open() -> bool:
	return visible


func _show_line() -> void:
	var line := _runner.line()
	if line == null:
		_close()
		return
	_speaker.text = line.speaker.to_upper()
	_show_face(line.portrait)
	_text.text = line.text
	_revealed = 0.0
	_blipped = 0
	_text.visible_characters = 0
	_choice_index = 0
	for i in _choice_labels.size():
		var label := _choice_labels[i]
		label.visible = false
	_resize(line.choices.size() if line.has_choices() else 0)
	if line.has_choices():
		_layout_choices(line)


## Puts this speaker's face in the box, or takes the last one out. The text column moves with it:
## a line nobody is credited with gets the whole width, which is what a sign and a chest want.
func _show_face(character: StringName) -> void:
	if _face.get_parent() != null and is_instance_valid(_face):
		_face.queue_free()
	_face = TextureRect.new()
	_face.visible = false
	_panel.add_child(_face)
	var span := 0.0
	if _source != null and not String(character).is_empty():
		var built := UiChrome.portrait(_style, _source, character)
		_face.queue_free()
		_face = built
		_face.position = Vector2(PADDING, TEXT_Y)
		_panel.add_child(_face)
		if _face.visible:
			span = UiChrome.portrait_span(_style)
	# Only the COLUMN moves per line: where the text starts and how wide it is. Its HEIGHT is set
	# once in setup and never again - two writers for one value is one of them quietly repairing
	# the other, which is exactly what hid a broken height here until a mutant survived.
	_text.position = Vector2(PADDING + (0.0 if span <= 0.0 else span + FACE_GAP), TEXT_Y)
	_text.size.x = text_width(_viewport.x, span)


## Grows or shrinks the panel to fit what this line needs, keeping it pinned to the bottom of
## the screen - so the box opens upward into the world rather than down off the edge of it.
func _resize(choices: int) -> void:
	var height := height_for(choices)
	_panel.position = Vector2(MARGIN, _viewport.y - height - MARGIN)
	_panel.size = Vector2(_viewport.x - MARGIN * 2, height)
	if _frame != null and _frame.header != null:
		_frame.header.size.x = _panel.size.x - float(UiChrome.BORDER) * 2.0


func _layout_choices(line: DialogRunner.Line) -> void:
	# Choices sit in their own band under the WHOLE text area, not under the text as drawn.
	# Their positions were set once in _build; nothing here recomputes them from the line.
	for i in mini(line.choices.size(), _choice_labels.size()):
		var label := _choice_labels[i]
		label.text = line.choices[i]
		label.visible = true
	_paint_choices()


func _paint_choices() -> void:
	# The cursor is placed once, over whichever answer is chosen - where it used to be two
	# characters written into every row's own text and stripped back off to redraw it.
	_select.visible = false
	for i in _choice_labels.size():
		if not _choice_labels[i].visible:
			continue
		var selected := i == _choice_index
		if selected:
			UiChrome.place(_select, _choice_labels[i],
				_panel.size.x - PADDING * 2.0, CHOICE_PITCH)
		_choice_labels[i].add_theme_color_override(
			"font_color", _style.ui_color("text") if selected else _style.ui_color("dim"))



func _process(delta: float) -> void:
	if not visible or _runner == null:
		return
	var total := _text.get_total_character_count()
	if _revealed < float(total):
		_revealed = minf(_revealed + delta * CHARACTERS_PER_SECOND, float(total))
		_text.visible_characters = int(_revealed)
		# A while rather than an if: one slow frame can reveal several characters at once, and
		# a single blip per frame would make the voice speed up and slow down with the machine.
		while _text.visible_characters - _blipped >= CHARACTERS_PER_BLIP:
			_blipped += CHARACTERS_PER_BLIP
			sound_wanted.emit(Sfx.id_of(Sfx.Cue.TALK))


func _fully_revealed() -> bool:
	return _text.visible_characters >= _text.get_total_character_count()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	# One event, one action. A conversation advanced twice by one press skips a line, which
	# reads as missing dialogue rather than as a double-fire.
	if not _gate.accept(event):
		return

	var line := _runner.line()
	if line != null and line.has_choices() and _fully_revealed():
		_choice_input(event, line)
		return

	if event.is_action(&"interact") or event.is_action(&"cancel"):
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.PAGE))
		if not _fully_revealed():
			# First press completes the line rather than skipping it. Skipping on the first
			# press means a player who taps through loses text they never saw.
			_revealed = float(_text.get_total_character_count())
			_text.visible_characters = _text.get_total_character_count()
			# Caught up with the reveal, so the rest of the line does not blip its way out
			# all at once on the next frame.
			_blipped = _text.visible_characters
		elif not _runner.advance():
			_close()
		else:
			_show_line()
		get_viewport().set_input_as_handled()


func _choice_input(event: InputEvent, line: DialogRunner.Line) -> void:
	var count := line.choices.size()
	if event.is_action(&"move_down"):
		_choice_index = (_choice_index + 1) % count
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint_choices()
	elif event.is_action(&"move_up"):
		_choice_index = (_choice_index + count - 1) % count
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_MOVE))
		_paint_choices()
	elif event.is_action(&"interact"):
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.MENU_CONFIRM))
		if not _runner.choose(_choice_index):
			_close()
		else:
			_show_line()
	else:
		return
	get_viewport().set_input_as_handled()


func _close() -> void:
	visible = false
	var earned := _runner.effects()
	_runner = null
	closed.emit(earned)
