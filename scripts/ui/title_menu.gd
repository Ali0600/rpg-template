class_name TitleMenu
extends SlotMenu
## What a player who has not started yet is pointing at. The rules are SlotMenu's; this is the
## wording, and there is nothing else to it - which is the point of the split.
##
## A title asks the same question a game over does, one moment earlier: carry on, or begin.
## The only difference a player can see is that one says "New game" and the other says "Start
## again", because after a death that is what it is.


## The third way on, one past the rows every slot menu has. A CONSTANT rather than a second Row
## enum, for the reason GameOverMenu's is one: GDScript refuses to let a subclass redeclare an
## inherited member, and re-listing Continue and New game here in order to append one row would be
## two lists that have to agree about the first two.
##
## APPENDED rather than slotted in above New game, even though the genre would put Credits last on
## a longer menu anyway - inserting a row re-aims every scripted session that lands on one by
## counting presses, and the sessions have no enum to name.
const ROW_CREDITS := Row.NEW_GAME + 1

## The fourth, appended for the reason Credits was: a scripted session lands on a row by counting
## presses and has no enum to name, so a row slotted in above moves every one of them silently.
## It sits below Credits because the genre puts the system rows last and because the sessions that
## already reach Credits keep their count.
const ROW_OPTIONS := ROW_CREDITS + 1


static func of(slots: Array[SlotSummary]) -> TitleMenu:
	var menu := TitleMenu.new()
	menu._slots = slots.duplicate()
	menu._open_on_a_pressable_row()
	return menu


func row_count() -> int:
	return ROW_OPTIONS + 1


## The third way on. Answered here rather than in SlotMenu because a game over has no business
## offering it: a player who has just died is being asked how to carry on, and a reading page is
## not one of the answers.
func top_pick(at: int) -> Pick:
	if at == ROW_CREDITS:
		return Pick.of(Kind.CREDITS)
	if at == ROW_OPTIONS:
		return Pick.of(Kind.OPTIONS)
	return super(at)


func top_label(at: int) -> String:
	if at == ROW_OPTIONS:
		return "Options"
	if at == ROW_CREDITS:
		return "Credits"
	if at == Row.NEW_GAME:
		return "New game"
	return _continue_label()
