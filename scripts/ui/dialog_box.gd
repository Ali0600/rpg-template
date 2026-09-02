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
const FONT_SIZE := 8
## The fallback font's height at FONT_SIZE. Pinned as a constant so the layout arithmetic is
## readable, and asserted against the real font in the fit gate - if a project theme ever
## changes the font, that assertion fails rather than the box quietly shrinking.
const LINE_HEIGHT := 12
## How many lines of text one node may use. Two is a deliberate ceiling on the WRITING as much
## as on the box: a conversation that needs more is a conversation with another node in it,
## and chaining `next` is this format's own pagination.
const TEXT_LINES := 2
const MAX_CHOICES := 4

const SPEAKER_Y := 2
const TEXT_Y := 15
const PADDING := 4
## Choices get their OWN band, below every line of text rather than below where the text
## happened to end. Placing them relative to the rendered text is what put a choice on top of
## a second line in the shipped build: the position was computed for one-line text and the
## data grew past it.
const CHOICE_Y := TEXT_Y + TEXT_LINES * LINE_HEIGHT + 2
const CHOICE_PITCH := 12
const PAD_BOTTOM := 5

## The box with nothing to answer: speaker, two lines, done.
const BOX_HEIGHT := TEXT_Y + TEXT_LINES * LINE_HEIGHT + PAD_BOTTOM

const CHARACTERS_PER_SECOND := 45.0

## How many revealed characters between typewriter blips. Not one per character: at 45 a
## second that is a continuous tone rather than a voice. This is a FEEL number - no gate can
## check it, only a person can hear it - so it sits here as one knob to turn rather than as a
## rhythm spread through the reveal code.
const CHARACTERS_PER_BLIP := 3

var _runner: DialogRunner
var _panel := ColorRect.new()
var _speaker := Label.new()
var _text := RichTextLabel.new()
var _choice_labels: Array[Label] = []
var _choice_index := 0
var _revealed := 0.0
var _blipped := 0
var _style: SpriteStyle
var _gate := InputGate.new()
var _viewport := UiScale.DESIGN_SIZE


## How wide a line of text may be, given the screen. A function rather than a constant because
## the fit gate has to ask the same question of the same numbers, and the panel's width is a
## function of the viewport.
static func text_width(viewport_width: int) -> float:
	return float(viewport_width - MARGIN * 2 - PADDING * 2)


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
	# No fallback colour is typed here: a style that forgot to define its panel should show
	# the readable default the style module owns, not a black rectangle invented in the view.
	_viewport = viewport_size
	_panel.color = style.ui_color("panel")
	_resize(0)
	add_child(_panel)

	_speaker.position = Vector2(PADDING, SPEAKER_Y)
	_speaker.add_theme_font_size_override("font_size", FONT_SIZE)
	_speaker.add_theme_color_override("font_color", style.ui_color("dim"))
	_panel.add_child(_speaker)

	_text.position = Vector2(PADDING, TEXT_Y)
	# The full TEXT_LINES tall. It used to be 22px against a 12px line, so even two lines were
	# clipped - the box could really only ever show one.
	_text.size = Vector2(text_width(_viewport.x), TEXT_LINES * LINE_HEIGHT)
	_text.bbcode_enabled = false
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_text.add_theme_color_override("default_color", style.ui_color("text"))
	_panel.add_child(_text)

	for i in MAX_CHOICES:
		var label := Label.new()
		label.position = Vector2(PADDING + 4, CHOICE_Y + i * CHOICE_PITCH)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.visible = false
		_panel.add_child(label)
		_choice_labels.append(label)


func open(runner: DialogRunner) -> bool:
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
	_speaker.text = line.speaker
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


## Grows or shrinks the panel to fit what this line needs, keeping it pinned to the bottom of
## the screen - so the box opens upward into the world rather than down off the edge of it.
func _resize(choices: int) -> void:
	var height := height_for(choices)
	_panel.position = Vector2(MARGIN, _viewport.y - height - MARGIN)
	_panel.size = Vector2(_viewport.x - MARGIN * 2, height)


func _layout_choices(line: DialogRunner.Line) -> void:
	# Choices sit in their own band under the WHOLE text area, not under the text as drawn.
	# Their positions were set once in _build; nothing here recomputes them from the line.
	for i in mini(line.choices.size(), _choice_labels.size()):
		var label := _choice_labels[i]
		label.text = "  " + line.choices[i]
		label.visible = true
	_paint_choices()


func _paint_choices() -> void:
	for i in _choice_labels.size():
		if not _choice_labels[i].visible:
			continue
		var selected := i == _choice_index
		_choice_labels[i].add_theme_color_override(
			"font_color", _style.ui_color("text") if selected else _style.ui_color("dim"))
		var text := _choice_labels[i].text
		_choice_labels[i].text = ("> " if selected else "  ") + text.substr(2)


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
