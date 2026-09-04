class_name UiPalette
extends Resource
## A window's colours, chosen by the PLAYER rather than by the style.
##
## Every screen in this game reads its colours from the running SpriteStyle, and until now that
## was the whole story: a game decided what its windows looked like and nobody else had a say.
## This is the other half - a named set of the same eight roles, which the world lays over the
## style when the player has picked one. See docs/GENRE_CONVENTIONS.md 16b for what the
## references offer and why this is a list of palettes rather than three colour bars.
##
## The roles are SpriteStyle.UI_ROLES and the completeness check is SpriteStyle.role_problems -
## the same function the style itself is checked with, so a palette and a style cannot come to
## disagree about what a full set is. A palette missing `hp` would draw a bar in whatever the
## style underneath happened to say, which is the one kind of wrong that looks deliberate.
##
## Hex strings rather than Colors, for SpriteStyle's own reason: a palette is a thing a person
## edits and reviews in a diff, and "#d9a066" survives that where four floats do not.

## Found by the Registry from this file's own name, like every other content resource.
@export var id: StringName = &""

## What the Options row says when this one is chosen. A player-facing WORD, so it belongs in the
## data beside the colours rather than being derived from the id - "Parchment" is not "parchment"
## and a screen should not be in the business of capitalising somebody's content.
@export var name: String = ""

## Role -> hex, over SpriteStyle.UI_ROLES. Every role, or problems() refuses it.
@export var colors: Dictionary = {}


func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("palette has no id")
	if name.strip_edges().is_empty():
		out.append("palette '%s' has no name; the Options row would draw an empty word" % id)
	out.append_array(SpriteStyle.role_problems(colors, "palette '%s'" % id))
	return out
