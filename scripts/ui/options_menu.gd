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
## Confirm CYCLES the value on the row the cursor is on. Up and down move the cursor and confirm
## is the only button left - the same argument that made the volume four named steps in M14, and
## the reason there is no left/right axis: no menu view in this project reads move_left or
## move_right, so an axis here would be a second input contract for one row.
##
## Since M51 the page also carries rows about how the game PLAYS (PlayChoices). They are handed
## as a dictionary of axis -> word, and a play row is drawn only when its axis is in it: the world
## leaves out an axis the game offers fewer than two values on, because a row that cycles among one
## value is a key that does nothing - the pause menu hides its Save row for exactly that reason.
##
## See docs/GENRE_CONVENTIONS.md 16b and 16c for where the genre puts a page like this and what it
## lets a player change.

## The rows, in the order they are drawn. Appended to, never reordered: a scripted play session
## lands on a row by counting presses and has no enum to name.
enum Row { SOUND, WINDOW, FIGHTS }

## What a press answered. LEAVE is cancel's answer rather than a silent close, so the screen has
## one thing to read rather than two. Appended to as well.
enum Kind { NONE, SOUND, WINDOW, LEAVE, FIGHTS }

## The play axis each play row is about - the one place a row is tied to an axis.
const PLAY_ROWS: Dictionary = {Row.FIGHTS: PlayChoices.FIGHTS}


## One answer, carried as a value - the PauseMenu.Pick shape, so a caller reads a field rather
## than decoding a signed integer.
class Pick:
	extends RefCounted
	var kind: Kind = Kind.NONE
	## The play axis a play row is about, and empty for every other row.
	var axis: StringName = &""

	static func of(kind_value: Kind, axis_value: StringName = &"") -> Pick:
		var out := Pick.new()
		out.kind = kind_value
		out.axis = axis_value
		return out


## What the Sound row says. Text, because reading it means asking the singleton that owns it.
var _sound := ""
## What the Window row says: the chosen palette's own name, or the word for none of them.
var _window := ""
## Play axis -> what its row says. An axis that is not here has no row.
var _play: Dictionary = {}
var _index := 0


static func of(sound: String, window: String, play: Dictionary = {}) -> OptionsMenu:
	var menu := OptionsMenu.new()
	menu._sound = sound
	menu._window = window
	menu._play = play.duplicate()
	return menu


## New words, cursor untouched. Confirm changes a value and leaves the page up, so the row has to
## be able to say what it now is without sending the player back to the top - the save row's rule.
func refresh(sound: String, window: String, play: Dictionary = {}) -> void:
	_sound = sound
	_window = window
	_play = play.duplicate()


func index() -> int:
	return _index


## The rows this page draws, in order: the two every game has, then each play row it was handed a
## word for.
func rows() -> Array[int]:
	var out: Array[int] = [Row.SOUND, Row.WINDOW]
	for row: int in PLAY_ROWS:
		if _play.has(PLAY_ROWS[row]):
			out.append(row)
	return out


## The Row drawn at `at`, or -1 where the page has none. The one place a cursor becomes a Row, so the
## drawing and the pressing cannot disagree about which row is the third one.
func row_at(at: int) -> int:
	var shown := rows()
	if at < 0 or at >= shown.size():
		return -1
	return shown[at]


func size() -> int:
	return rows().size()


## Wrapping, like every cursor in this project. Answers whether it actually moved, so the view can
## stay silent on a press that did nothing.
func move(delta: int) -> bool:
	if delta == 0 or size() <= 1:
		return false
	_index = posmod(_index + delta, size())
	return true


func confirm() -> Pick:
	match row_at(_index):
		Row.SOUND:
			return Pick.of(Kind.SOUND)
		Row.WINDOW:
			return Pick.of(Kind.WINDOW)
		Row.FIGHTS:
			return Pick.of(Kind.FIGHTS, PlayChoices.FIGHTS)
	return Pick.of(Kind.NONE)


func cancel() -> Pick:
	return Pick.of(Kind.LEAVE)


## The row's text. Every row names the setting AND its current value, because a row reading only
## "Sound" is a row a player has to press to find out anything about.
func label(at: int) -> String:
	match row_at(at):
		Row.SOUND:
			return "Sound: %s" % _sound if not _sound.is_empty() else "Sound"
		Row.WINDOW:
			return "Window: %s" % _window if not _window.is_empty() else "Window"
		Row.FIGHTS:
			return _play_label("Fights", PlayChoices.FIGHTS)
	return ""


func _play_label(title: String, axis: StringName) -> String:
	var word := str(_play.get(axis, ""))
	return "%s: %s" % [title, word] if not word.is_empty() else title
