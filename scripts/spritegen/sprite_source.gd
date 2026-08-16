class_name SpriteSource
extends RefCounted
## Where a character's art comes from - the seam that keeps the game independent of it.
##
## Two implementations ship: ProceduralSpriteSource composes from the rig in memory (used by
## Sprite Lab and by the tests, so nothing has to be on disk to be checked), and
## FileSpriteSource reads the committed PNG + JSON (used by the game, so startup does no
## generation work).
##
## A third - an AI generator such as PixelLab - is a backlog item and needs no change here:
## produce the same PNG + sheet.json pair, or subclass this and answer `sheet()`. The
## direction aliases in Dir already accept compass-named rows, which is how such exports
## usually label them.

## {"texture": Texture2D, "meta": SheetMeta} - or an empty dictionary on failure, with the
## reason pushed as an error by the implementation.
func sheet(_character_id: StringName) -> Dictionary:
	push_error("SpriteSource.sheet is abstract; use ProceduralSpriteSource or FileSpriteSource")
	return {}


## Convenience: the finished SpriteFrames, or null. Every implementation gets this for free,
## which is what stops a new source from inventing its own animation naming.
func sprite_frames(character_id: StringName) -> SpriteFrames:
	var s := sheet(character_id)
	if s.is_empty():
		return null
	return SpriteFramesFactory.build(s["texture"], s["meta"])
