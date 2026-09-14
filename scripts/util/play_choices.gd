class_name PlayChoices
extends RefCounted
## How the game PLAYS, as choices a player makes rather than facts a game states (M51).
##
## A game's data still declares its systems - a CombatDef names a fight style, a GameConfig says
## whether a step is a tile and where saving happens - and those are its DEFAULTS. The player may pick
## among what the build can honour for that game, on the Options screen, at any time, and a pick takes
## hold the next time it is read. See docs/DECISIONS.md, M51, and docs/GENRE_CONVENTIONS.md §16c.
##
## Pure, like every menu and rule here, and it names no singleton, so the per-file parse gate keeps it
## along with every suite that depends on it. The player's own settings file stores a word per axis
## and the world asks this class what the word means; this is the one list of which axes exist, what a
## game offers on each, and which value is in effect, so the file, the page and the world cannot
## disagree about any of it.

## How an encounter is resolved: a CombatDef.STYLES word.
const FIGHTS := &"fights"
## Free movement or one tile per press.
const MOVEMENT := &"movement"
## Where a game may be saved: a GameConfig.SAVE_POLICIES word.
const SAVING := &"saving"

## Every axis, in the order the Options page draws its rows. APPENDED to, never reordered: a scripted
## session lands on a row by counting presses.
const AXES: Array[StringName] = [FIGHTS, MOVEMENT, SAVING]

## Movement's two words. A GameConfig spells movement as a bool, `grid_step`; these are the words
## `tools/new_game.sh --movement=` already takes, so the settings file and a new game's command line
## say it the same way, and test_play_choices holds the two lists to one.
const MOVE_FREE := &"free"
const MOVE_GRID := &"grid"

## What each value is called on the Options page. Short on purpose: a row is a name and a word in a
## 168px window, and test_options_layout measures every one of them with the real font.
const WORDS: Dictionary = {
	CombatDef.STYLE_TURNS: "Turns",
	CombatDef.STYLE_ARENA: "Sword",
	MOVE_FREE: "Free",
	MOVE_GRID: "Tiles",
	GameConfig.SAVE_ANYWHERE: "Anywhere",
	GameConfig.SAVE_AT_POINT: "Save points",
}


## The values `manifest` offers on `axis`, in the order the row cycles through them. Fights only for a
## game that can fight - a null `combat` is a legal shape forever, and it has nothing to choose about
## fighting. Movement and saving for any game with a config. Nothing for an axis this class does not
## name.
static func offered(manifest: GameManifest, axis: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if manifest == null:
		return out
	if axis == FIGHTS:
		if manifest.combat != null:
			out.assign(CombatDef.STYLES)
		return out
	if manifest.config == null:
		return out
	if axis == MOVEMENT:
		out.assign([MOVE_FREE, MOVE_GRID])
	elif axis == SAVING:
		out.assign(GameConfig.SAVE_POLICIES)
	return out


## What `manifest` itself declares on `axis`: the value a player who never chose gets.
static func declared(manifest: GameManifest, axis: StringName) -> StringName:
	if manifest == null:
		return &""
	if axis == FIGHTS:
		return manifest.combat.style if manifest.combat != null else &""
	if manifest.config == null:
		return &""
	if axis == MOVEMENT:
		return MOVE_GRID if manifest.config.grid_step else MOVE_FREE
	if axis == SAVING:
		return manifest.config.save_policy
	return &""


## The value in effect: the player's word when the game offers it, and the game's own otherwise. The
## ONE place an unknown or unoffered word falls back. Silently, because it is a legal state rather than
## a fault: the settings file is the player's across every game, so a word one game offered sits there
## while another game that does not offer it is played.
static func effective(chosen: StringName, offered_values: Array[StringName], own: StringName) -> StringName:
	return chosen if offered_values.has(chosen) else own


## The value after `current`, wrapping - what one press on the row turns it to. A `current` that is not
## offered counts as coming before the first.
static func next(offered_values: Array[StringName], current: StringName) -> StringName:
	if offered_values.is_empty():
		return current
	return offered_values[(offered_values.find(current) + 1) % offered_values.size()]


## Whether a row about these values is a choice at all. It takes two: a row that cycles among one value
## is a key that does nothing, which is why the pause menu hides its Save row rather than refusing it.
static func choosable(values: Array[StringName]) -> bool:
	return values.size() >= 2


## A value's word on the page, or the value itself for one this class has no word for - which
## test_play_choices refuses for every value an axis offers, so it shows only in data nobody shipped.
static func word(value: StringName) -> String:
	return str(WORDS.get(value, String(value)))
