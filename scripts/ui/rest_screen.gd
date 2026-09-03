class_name RestScreen
extends CanvasLayer
## A night passing, drawn. Nothing decides here and nothing is asked: it fades down, holds,
## fades up, and says when it is done.
##
## It exists because the heal is not the thing a player experiences - the night is. Every
## reference inn in the genre spends a moment in the dark before the "good morning", and a
## rest that snapped from wounded to full with no beat in between reads as a menu transaction
## rather than as sleep.
##
## Kept as a REST screen rather than a general fade, on purpose: there is one caller. The day
## a second wants it - a warp, a cutscene - is the day it becomes a FadeScreen and takes its
## text as an argument.
## A sound this view wants played. Emitted rather than played directly: signals up, calls
## down, and the world owns the speaker. Practically too - check.sh's per-file parse gate
## skips any file whose TEXT names an autoload, so reaching the audio singleton here would
## silently drop this file, and every suite that depends on it, out of that gate. Do not name
## it in prose either.
signal sound_wanted(id: StringName)

## The night is over. The world closes the overlay; this never closes itself, for the reason
## no view here frees itself - the thing that made it is the thing that knows what comes next.
signal finished

const LAYER := 25
const TEXT_SIZE := UiChrome.FONT_SIZE

## Counted in FRAMES, handed in by the world from the config. Never seconds: a night measured
## on the wall clock is a night whose length depends on how busy the machine is, and every
## scripted session that walks through one would then arrive somewhere else.
var _fade_frames: int = 1
var _hold_frames: int = 1

var _shade := ColorRect.new()
var _line := Label.new()
var _elapsed: int = 0
var _done := false


func _ready() -> void:
	layer = LAYER


func setup(style: SpriteStyle, viewport_size: Vector2i, fade_frames: int, hold_frames: int,
		text: String) -> void:
	# maxi rather than a refusal: a config of zero would divide by nothing below, and a night
	# that lasts one frame is a legible degenerate case where a crash is not.
	_fade_frames = maxi(fade_frames, 1)
	_hold_frames = maxi(hold_frames, 1)
	var dark := style.ui_color("panel")
	dark.a = 0.0
	_shade.color = dark
	_shade.size = viewport_size
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_line.text = text
	_line.add_theme_font_size_override("font_size", TEXT_SIZE)
	_line.add_theme_color_override("font_color", style.ui_color("text"))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.size = Vector2(viewport_size.x, TEXT_SIZE + 4)
	_line.position = Vector2(0, float(viewport_size.y) * 0.5 - float(TEXT_SIZE))
	_line.modulate.a = 0.0
	add_child(_line)


## One physics frame of night. Driven by the world rather than by _process for the reason
## BattleLogic is: a screen that runs on its own clock is one a scripted session cannot land
## on the same frame of twice.
func step() -> void:
	if _done:
		return
	_elapsed += 1
	var down := _fade_frames
	var lit := _fade_frames + _hold_frames
	var up := lit + _fade_frames
	if _elapsed <= down:
		_shade.color.a = float(_elapsed) / float(_fade_frames)
		_line.modulate.a = _shade.color.a
	elif _elapsed <= lit:
		_shade.color.a = 1.0
		_line.modulate.a = 1.0
	elif _elapsed <= up:
		# The line goes out with the dark, not after it: waking to a caption over the world
		# would read as the world being wrong rather than as morning.
		_shade.color.a = float(up - _elapsed) / float(_fade_frames)
		_line.modulate.a = _shade.color.a
	else:
		_shade.color.a = 0.0
		_line.modulate.a = 0.0
		_done = true
		# Asked for on WAKING rather than on lying down, because it is the sound of being
		# well again, and the player is not well until the night is over.
		sound_wanted.emit(Sfx.id_of(Sfx.Cue.HEAL))
		finished.emit()


func is_done() -> bool:
	return _done
