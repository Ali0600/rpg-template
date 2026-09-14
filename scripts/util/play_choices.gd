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
## and the world resolves the word; this is the one list of which axes exist, so the file, the page and
## the world cannot disagree about it.

## How an encounter is resolved: a CombatDef.STYLES word.
const FIGHTS := &"fights"
## Free movement or one tile per press: a GameScaffold.MOVEMENTS word.
const MOVEMENT := &"movement"
## Where a game may be saved: a GameConfig.SAVE_POLICIES word.
const SAVING := &"saving"

## Every axis, in the order the Options page draws its rows. APPENDED to, never reordered: a scripted
## session lands on a row by counting presses.
const AXES: Array[StringName] = [FIGHTS, MOVEMENT, SAVING]
