class_name SlotSummary
extends RefCounted
## What one save slot holds, as a menu needs to draw it: the save, or nothing, or a file that
## is THERE and cannot be read.
##
## The third case is the one this exists for. `SaveManager._read` has always known the
## difference — it carries `exists` and a list of `faults` — and `peek()` threw it away, so a
## slot holding an unreadable file drew as "empty". That is not a cosmetic gap: an empty row is
## an invitation to save over it, and the thing being saved over is the file a player would want
## back. The genre says so out loud rather than showing a blank — Pokémon's "The file data is
## destroyed!" is decided by a checksum and stated to the player.
##
## ONE OBJECT RATHER THAN TWO ARRAYS. The obvious shape is to keep passing `Array[SaveData]`
## and add an `Array[bool]` beside it, and it is the shape this repo has a rule against: two
## paths answering one question drift, and the drift here pairs one slot's data with another
## slot's verdict. A summary cannot be mispaired with itself.
##
## RefCounted rather than a Resource among `scripts/data/`'s Resources, deliberately: this is a
## READING, made fresh every time a menu is drawn. Nothing saves it, loads it or exports it, and
## making it a Resource would put it in the registry's way for no gain.

## What is in the slot, or null. Null and `damaged` false is an empty slot; null and `damaged`
## true is a file that could not be read.
var data: SaveData = null

## A file exists in this slot and `_read` refused it - wrong JSON, failed validation, or a save
## that names a different game. The reason is NOT carried: the menu says one thing either way,
## and `load_slot` is where a fault list gets pushed as an error with all of it.
var damaged := false


## Nothing in this slot at all.
static func empty() -> SlotSummary:
	return SlotSummary.new()


static func of(save: SaveData) -> SlotSummary:
	var out := SlotSummary.new()
	out.data = save
	return out


## A file is there and cannot be read. Named for what the player is told rather than for the
## fault, because every fault reaches the same row.
static func broken() -> SlotSummary:
	var out := SlotSummary.new()
	out.damaged = true
	return out


## Whether there is something here to load. False for both an empty slot and a damaged one -
## which is why the LOAD page's existing refusal needed no change at all when damage became
## visible: it already refused anything with no data behind it, and only the wording was missing.
func has_save() -> bool:
	return data != null
