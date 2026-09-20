class_name ControlsHint
extends CanvasLayer
## Tells a first-time player which keys do what, then gets out of the way.
##
## Mostly for the web demo, where there is no manual, no menu the player came through, and no
## reason to guess. It fades once the player has actually moved rather than on a timer: a
## timer is either too short for someone reading it or too long for someone who already knows,
## and "they moved" is the exact moment the hint stopped being needed.
##
## It is also drawn only while the keys it names do something - the world hands it show_while() -
## because a hint teaching WASD under a conversation, a menu or a fight is teaching a lie.
##
## And it names the keys of the device in the player's hands: the text it is handed is a template
## in Prompts' tokens, the game's own verbs around the template's words, and the world hands it
## reprompt() at mount and whenever the device changes. Reworded in place, never rebuilt, for the
## reason restyle() gives below.

const FADE_SECONDS := 0.6
const LINGER_SECONDS := 1.2
## The label's inset from the window's left edge, and the room kept on the right.
const MARGIN := 6

var _label: Label = null
var _template := ""
var _device := Prompts.Device.KEYBOARD
var _elapsed := 0.0
var _dismissed := false


## The width a hint may draw in: the window less a margin either side. Declared here, measured
## against by test_controls_fit for every game's hint in both devices' words, and what the label
## is clipped to - the three halves of a capacity. The shipped hint drew 356 design pixels on a
## 320 window with "pause" off the right edge, from the first commit until M52, because a Label
## with no width does not clip, wrap or complain.
static func text_width(viewport_width: int) -> float:
	return float(viewport_width - 2 * MARGIN)


func setup(style: SpriteStyle, viewport_size: Vector2i, text: String) -> void:
	layer = 5
	# Built through the chrome like every other label in the game, so it takes the project font
	# and the style's own quiet colour with no arithmetic of its own.
	_template = text
	_label = UiChrome.label(style, "dim")
	_label.position = Vector2(MARGIN, viewport_size.y - 14)
	add_child(_label)
	_label.size = Vector2(text_width(viewport_size.x), _label.size.y)
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_refill()


## New colours on the label already there, for when the player recolours the windows mid-run.
##
## Restyled rather than rebuilt, which is the opposite of what the dialog box does and is the
## whole point: this view carries STATE - whether it has been dismissed and how far through its
## fade it is - and a fresh one would put "use the arrow keys" back on the screen of somebody who
## has been playing for an hour. One colour is little enough to re-apply by hand; anything with
## more than that is rebuilt instead, so the two paths cannot drift.
func restyle(style: SpriteStyle) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", style.ui_color("dim"))


## The device in the player's hands, for the words the line uses. In place: the fade and the
## dismissal are untouched, so a player an hour in is not shown "use the arrow keys" again.
func reprompt(device: Prompts.Device) -> void:
	_device = device
	_refill()


## The one line that sets the text, so a reworded hint and a fresh one cannot differ.
func _refill() -> void:
	if _label == null:
		return
	_label.text = Prompts.fill(_template, _device)


## What the line says right now, for a session or a suite to read.
func text() -> String:
	return _label.text if _label != null else ""


## Call when the player does the thing the hint was teaching.
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	_elapsed = 0.0


## Drawn, or not, according to whether the keys it names do anything.
##
## TOLD rather than asking, because this file may not name an autoload: check.sh's per-file parse
## gate skips any file whose TEXT holds one, and a view that asked the router would take itself AND
## every suite depending on this class out of that gate.
##
## The LAYER's own visibility, which is what stops the label being drawn at all. The fade owns the
## label's alpha and the two never meet - they answer different questions, "do these keys work" and
## "has this player already learned it" - so a faded-out hint in the world is still SHOWN here. That
## is what lets the rule be stated in both directions rather than only one.
func show_while(keys_work: bool) -> void:
	visible = keys_work


## Whether the label is in a drawn tree - NOT whether it is still opaque.
##
## is_visible_in_tree() answers for the whole chain above it, CanvasLayers included, which
## test_engine_assumptions pins because a CanvasLayer is not a CanvasItem and its taking part at all
## is the special case. So this reads what the engine will actually paint, rather than handing back
## the property show_while just set.
func shown() -> bool:
	return _label != null and _label.is_visible_in_tree()


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
