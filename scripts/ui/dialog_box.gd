class_name DialogBox
extends CanvasLayer
## Draws a conversation and takes the player's answers. Owns no rules about what happens
## next - it asks a DialogRunner and shows what it is told.
##
## The typewriter is not decoration: at 320x180 a line appears all at once and is easy to
## read past, and a reveal both paces the scene and gives the confirm button something to
## do on a first press. Pressing confirm mid-reveal completes the line rather than skipping
## it, which is the behaviour every player expects and the one that is easy to get wrong.

signal closed(flags_to_set: Array)

const BOX_HEIGHT := 54
const MARGIN := 6
const CHARACTERS_PER_SECOND := 45.0

var _runner: DialogRunner
var _panel := ColorRect.new()
var _speaker := Label.new()
var _text := RichTextLabel.new()
var _choice_labels: Array[Label] = []
var _choice_index := 0
var _revealed := 0.0
var _style: SpriteStyle
var _gate := InputGate.new()


func _ready() -> void:
	layer = 10
	visible = false


## Builds the box from the style's interface colours, so it re-skins along with the art.
func setup(style: SpriteStyle, viewport_size: Vector2i) -> void:
	_style = style
	# No fallback colour is typed here: a style that forgot to define its panel should show
	# the readable default the style module owns, not a black rectangle invented in the view.
	_panel.color = style.ui_color("panel")
	_panel.position = Vector2(MARGIN, viewport_size.y - BOX_HEIGHT - MARGIN)
	_panel.size = Vector2(viewport_size.x - MARGIN * 2, BOX_HEIGHT)
	add_child(_panel)

	_speaker.position = Vector2(4, 2)
	_speaker.add_theme_font_size_override("font_size", 8)
	_speaker.add_theme_color_override("font_color", style.ui_color("dim"))
	_panel.add_child(_speaker)

	_text.position = Vector2(4, 13)
	_text.size = Vector2(_panel.size.x - 8, 22)
	_text.bbcode_enabled = false
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 8)
	_text.add_theme_color_override("default_color", style.ui_color("text"))
	_panel.add_child(_text)

	for i in 4:
		var label := Label.new()
		label.position = Vector2(8, 12 + i * 10)
		label.add_theme_font_size_override("font_size", 8)
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
	_text.visible_characters = 0
	_choice_index = 0
	for i in _choice_labels.size():
		var label := _choice_labels[i]
		label.visible = false
	if line.has_choices():
		_layout_choices(line)


func _layout_choices(line: DialogRunner.Line) -> void:
	# Choices sit under the text, so the line stays readable while the answer is picked.
	for i in mini(line.choices.size(), _choice_labels.size()):
		var label := _choice_labels[i]
		label.text = "  " + line.choices[i]
		label.position = Vector2(8, 26 + i * 9)
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
		if not _fully_revealed():
			# First press completes the line rather than skipping it. Skipping on the first
			# press means a player who taps through loses text they never saw.
			_revealed = float(_text.get_total_character_count())
			_text.visible_characters = _text.get_total_character_count()
		elif not _runner.advance():
			_close()
		else:
			_show_line()
		get_viewport().set_input_as_handled()


func _choice_input(event: InputEvent, line: DialogRunner.Line) -> void:
	var count := line.choices.size()
	if event.is_action(&"move_down"):
		_choice_index = (_choice_index + 1) % count
		_paint_choices()
	elif event.is_action(&"move_up"):
		_choice_index = (_choice_index + count - 1) % count
		_paint_choices()
	elif event.is_action(&"interact"):
		if not _runner.choose(_choice_index):
			_close()
		else:
			_show_line()
	else:
		return
	get_viewport().set_input_as_handled()


func _close() -> void:
	visible = false
	var flags := _runner.flags_to_set()
	_runner = null
	closed.emit(flags)
