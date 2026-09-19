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

const FADE_SECONDS := 0.6
const LINGER_SECONDS := 1.2

var _label: Label = null
var _elapsed := 0.0
var _dismissed := false


func setup(style: SpriteStyle, viewport_size: Vector2i, text: String) -> void:
	layer = 5
	# Built through the chrome like every other label in the game, so it takes the project font
	# and the style's own quiet colour with no arithmetic of its own.
	_label = UiChrome.label(style, "dim")
	_label.text = text
	_label.position = Vector2(6, viewport_size.y - 14)
	add_child(_label)


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
