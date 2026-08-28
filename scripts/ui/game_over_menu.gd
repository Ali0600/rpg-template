class_name GameOverMenu
extends SlotMenu
## What a beaten player is pointing at. The rules are SlotMenu's; this is the wording, and one
## extra way on that a title screen does not need.
##
## The same shape as PauseMenu and split for the same reason, but it answers a different
## question: a pause asks "what do you want to do while you are here", and this asks "how do
## you want to carry on", where staying is not one of the options.

## The third way on, one past the rows every slot menu has. A CONSTANT rather than a second
## Row enum, because GDScript refuses to let a subclass redeclare an inherited member - and
## re-listing Continue and New game here in order to append one row would be two lists that
## have to agree about the first two. Appended rather than slotted in, so the one scripted
## session that counts presses down this page keeps landing where it did.
const ROW_TITLE := Row.NEW_GAME + 1


static func of(slots: Array[SaveData]) -> GameOverMenu:
	var menu := GameOverMenu.new()
	menu._slots = slots.duplicate()
	# Deliberately NOT _open_on_a_pressable_row(), which the title does. The argument for it
	# there is that a player's very first press of the game should not be a dud; the argument
	# AGAINST it here is stronger, and a scripted session proved it: this screen arrives at the
	# end of a lost fight, where a player is already pressing, and opening on "Start again"
	# turns one more press into a restarted run with no beat in between. A refusal that says
	# "nothing saved" is the better thing to walk into.
	return menu


func row_count() -> int:
	return ROW_TITLE + 1


## The third way on. Answered here rather than in SlotMenu because a title screen cannot offer
## a route to itself, and a row that only one of two screens has is exactly what this seam is
## for.
func top_pick(at: int) -> Pick:
	if at == ROW_TITLE:
		return Pick.of(Kind.TITLE)
	return super(at)


func top_label(at: int) -> String:
	if at == ROW_TITLE:
		return "Title"
	if at == Row.NEW_GAME:
		return "Start again"
	return _continue_label()
