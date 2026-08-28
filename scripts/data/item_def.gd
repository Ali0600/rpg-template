class_name ItemDef
extends Resource
## A thing the player can carry, as data.
##
## An item is a NOUN with a name, a description and - since M13 - what it does when drunk in a
## fight. It has no icon, no weight, no general use verb and no stack limit, because every one
## of those is a decision a game makes and the template would be guessing at.
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

## Hit points restored when this is used from the battle menu. ZERO MEANS NOT USABLE IN A
## FIGHT, the same "zero is off" shape as GameConfig.grid_step_pixels - so the field is both
## the amount and the answer to "does this belong in the battle item list", and the two cannot
## disagree.
##
## This is the only use verb the template has. A general "use" from the pause menu is still a
## game's own business (see docs/DECISIONS.md): a potion heals in every RPG ever written,
## where "use the rope on the well" is a puzzle, and a template that grew a verb for the
## second one would be designing somebody's game.
@export var battle_heal: int = 0


## What a shop charges for one of these. ZERO MEANS NOT TRADABLE, the same "zero is off"
## shape battle_heal uses - so a shop cannot stock it and the sell page will not list it.
##
## Off by default on purpose: a quest item that becomes sellable is a quest that can be sold
## away, and the failure lands hours later on a locked door. An item joins the economy by
## being given a price, never by being forgotten.
@export var price: int = 0


## Everything wrong with this item, in the idiom of every other problems() here: all of them,
## not the first, so "what is broken about this item" is one read rather than three runs.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("item has no id")
	if name.is_empty():
		out.append("item '%s' has no name" % id)
	# Negative healing is a weapon wearing a potion's clothes. If a game wants one, it wants a
	# different verb, not a sign flip on this one.
	if battle_heal < 0:
		out.append("item '%s' heals %d" % [id, battle_heal])
	if price < 0:
		out.append("item '%s' is priced at %d" % [id, price])
	return out
