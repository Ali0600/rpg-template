class_name ItemDef
extends Resource
## A thing the player can carry, as data.
##
## An item is a NOUN with a name and a description, and nothing else. It has no icon, no
## weight, no use verb and no stack limit, because every one of those is a decision a game
## makes and the template would be guessing at.
##
## The absent stack limit is the load-bearing one. A cap means a pickup can FAIL, and a chest
## marked `once` has already recorded that it was opened by the time the give is applied - so
## a full bag would eat the key and leave the door shut forever, with nothing on screen saying
## why. Unbounded counts cannot produce that, and a game that needs a cap can enforce it in
## its own hooks where it can also say so.
##
## Registered automatically: Registry buckets every resource under data/ by its class_name, so
## a new file in data/items/ is reachable as Registry.get_resource(&"ItemDef", id) with no
## registration step to forget.

## Matched on everywhere - maps, dialog, saves. The content gate requires it to equal the
## file's own name, so "which file is this item" is answerable without opening any of them.
@export var id: StringName = &""

## Shown to the player, in the pause menu's item list.
@export var name: String = ""

## One line, shown under the list when this item is selected. Empty is allowed: a key that
## says "a key" twice is worse than a key that says it once.
@export var description: String = ""


## Everything wrong with this item, in the idiom of every other problems() here: all of them,
## not the first, so "what is broken about this item" is one read rather than three runs.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("item has no id")
	if name.is_empty():
		out.append("item '%s' has no name" % id)
	return out
