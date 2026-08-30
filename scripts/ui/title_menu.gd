class_name TitleMenu
extends SlotMenu
## What a player who has not started yet is pointing at. The rules are SlotMenu's; this is the
## wording, and there is nothing else to it - which is the point of the split.
##
## A title asks the same question a game over does, one moment earlier: carry on, or begin.
## The only difference a player can see is that one says "New game" and the other says "Start
## again", because after a death that is what it is.


static func of(slots: Array[SlotSummary]) -> TitleMenu:
	var menu := TitleMenu.new()
	menu._slots = slots.duplicate()
	menu._open_on_a_pressable_row()
	return menu


func top_label(at: int) -> String:
	if at == Row.NEW_GAME:
		return "New game"
	return _continue_label()
