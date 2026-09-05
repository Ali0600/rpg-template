class_name OptionsMenu
extends RefCounted
## What the player is pointing at on the options page, and what a press there means.
##
## Pure, like every menu in this project: no tree, no nodes, and it may not ask any singleton
## what the volume is or which palettes exist. It is HANDED the words - "Normal", "Parchment" -
## the way PauseMenu is handed its slot summaries, and the world is what knows where words come
## from. That is not only tidiness: the per-file parse gate drops any file whose text names a
## singleton, along with every suite that depends on it, so a menu that asked would quietly
## leave the build's coverage.
##
## Two rows, and confirm CYCLES the value on the one the cursor is on. Up and down move the
## cursor and confirm is the only button left - the same argument that made the volume four
## named steps in M14, and the reason there is no left/right axis: no menu view in this project
## reads move_left or move_right, so an axis here would be a second input contract for one row.
##
## See docs/GENRE_CONVENTIONS.md 16b for where the genre puts a page like this and what it lets
## a player change.

## The rows, in the order they are drawn. Appended to, never reordered: a scripted play session
## lands on a row by counting presses and has no enum to name.
enum Row { SOUND, WINDOW }

## What a press answered. LEAVE is cancel's answer rather than a silent close, so the screen has
## one thing to read rather than two.
enum Kind { NONE, SOUND, WINDOW, LEAVE }


## One answer, carried as a value - the PauseMenu.Pick shape, so a caller reads a field rather
## than decoding a signed integer.
class Pick:
	extends RefCounted
	var kind: Kind = Kind.NONE

	static func of(kind_value: Kind) -> Pick:
		var out := Pick.new()
		out.kind = kind_value
		return out


## What the Sound row says. Text, because reading it means asking the singleton that owns it.
var _sound := ""
## What the Window row says: the chosen palette's own name, or the word for none of them.
var _window := ""
var _index := 0


static func of(sound: String, window: String) -> OptionsMenu:
	var menu := OptionsMenu.new()
	menu._sound = sound
	menu._window = window
	return menu


## New words, cursor untouched. Confirm changes a value and leaves the page up, so the row has to
## be able to say what it now is without sending the player back to the top - the save row's rule.
func refresh(sound: String, window: String) -> void:
	_sound = sound
	_window = window


func index() -> int:
	return _index


func size() -> int:
	return Row.size()


## Wrapping, like every cursor in this project. Answers whether it actually moved, so the view can
## stay silent on a press that did nothing.
func move(delta: int) -> bool:
	if delta == 0 or size() <= 1:
		return false
	_index = posmod(_index + delta, size())
	return true


func confirm() -> Pick:
	match _index:
		Row.SOUND:
			return Pick.of(Kind.SOUND)
		Row.WINDOW:
			return Pick.of(Kind.WINDOW)
	return Pick.of(Kind.NONE)


func cancel() -> Pick:
	return Pick.of(Kind.LEAVE)


## The row's text. Both rows name the setting AND its current value, because a row reading only
## "Sound" is a row a player has to press to find out anything about.
func label(at: int) -> String:
	match at:
		Row.SOUND:
			return "Sound: %s" % _sound if not _sound.is_empty() else "Sound"
		Row.WINDOW:
			return "Window: %s" % _window if not _window.is_empty() else "Window"
	return ""
