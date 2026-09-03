class_name ControlsHint
extends CanvasLayer
## Tells a first-time player which keys do what, then gets out of the way.
##
## Mostly for the web demo, where there is no manual, no menu the player came through, and no
## reason to guess. It fades once the player has actually moved rather than on a timer: a
## timer is either too short for someone reading it or too long for someone who already knows,
## and "they moved" is the exact moment the hint stopped being needed.

const FADE_SECONDS := 0.6
const LINGER_SECONDS := 1.2

var _label := Label.new()
var _elapsed := 0.0
var _dismissed := false


func setup(style: SpriteStyle, viewport_size: Vector2i, text: String) -> void:
	layer = 5
	_label.text = text
	_label.position = Vector2(6, viewport_size.y - 14)
	_label.add_theme_font_size_override("font_size", UiChrome.FONT_SIZE)
	_label.add_theme_color_override("font_color", style.ui_color("dim"))
	add_child(_label)


## Call when the player does the thing the hint was teaching.
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	_elapsed = 0.0


func is_visible_hint() -> bool:
	return _label.modulate.a > 0.0


func _process(delta: float) -> void:
	if not _dismissed:
		return
	_elapsed += delta
	if _elapsed < LINGER_SECONDS:
		return
	var t := (_elapsed - LINGER_SECONDS) / FADE_SECONDS
	_label.modulate.a = clampf(1.0 - t, 0.0, 1.0)
	if _label.modulate.a <= 0.0:
		set_process(false)
