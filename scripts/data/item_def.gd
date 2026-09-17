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
## FIGHT, the same "zero is off" shape as GameConfig.footstep_tiles - so the field is both
## the amount and the answer to "does this belong in the battle item list", and the two cannot
## disagree.
##
## This is the only use verb the template has. A general "use" from the pause menu is still a
## game's own business (see docs/DECISIONS.md): a potion heals in every RPG ever written,
## where "use the rope on the well" is a puzzle, and a template that grew a verb for the
## second one would be designing somebody's game.
@export var battle_heal: int = 0


## Every slot the template knows about, in the order the equipment page draws them. The one
## list: problems() refuses anything outside it, and the world builds a page row per entry -
## so adding a third slot is one edit, and it grows the screen for free.
##
## A game wanting one is adding a noun, not flipping a switch, and that is recorded in
## docs/DECISIONS.md rather than smuggled in here.
const SLOTS: Array[StringName] = [&"weapon", &"armor"]

## Which body slot this occupies, or empty for a thing that is only carried.
@export var slot: StringName = &""

## Added to the wearer's attack while equipped. Meaningful only with a slot - a modifier on a
## slotless item would silently do nothing, so problems() refuses the combination.
@export var attack: int = 0

## Added to the wearer's defense while equipped, on the same terms.
@export var defense: int = 0

## What a shop charges for one of these. ZERO MEANS NOT TRADABLE, the same "zero is off"
## shape battle_heal uses - so a shop cannot stock it and the sell page will not list it.
##
## Off by default on purpose: a quest item that becomes sellable is a quest that can be sold
## away, and the failure lands hours later on a locked door. An item joins the economy by
## being given a price, never by being forgotten.
@export var price: int = 0

## How a fighter is drawn in a fight while this is worn: the art they are drawn with otherwise, to the
## art they are drawn with instead (docs/DECISIONS.md, M50.4). A sword is drawn only in the swing, so
## carrying a different one is a different character whose slash rows differ - the hero wearing a
## saber is drawn as `quest_wanderer_saber`.
##
## KEYED BY THE WEARER, because a party has more than one body. A sword naming one character would
## draw a companion who picked it up as the hero; keyed, they are drawn as themselves unless the item
## names art for them too. Empty, the default, is gear that moves the numbers and never the picture,
## which is all gear was before M50.4.
@export var worn_art: Dictionary = {}


## The art `wearer` is drawn with while this is worn: its entry, or the wearer's own. The one reader of
## `worn_art`, the `EnemyDef.resistance_to` shape, so a missing entry means "as themselves" in exactly
## one place.
func art_for(wearer: StringName) -> StringName:
	return StringName(str(worn_art.get(wearer, wearer)))


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
	if slot != &"" and not SLOTS.has(slot):
		# A typo'd slot must fail the build, not quietly become a trinket.
		out.append("item '%s' names unknown slot '%s'" % [id, slot])
	if attack < 0 or defense < 0:
		# Cursed gear is a game's design decision, not a sign flip here - see DECISIONS.
		out.append("item '%s' has negative equipment stats" % id)
	if slot == &"" and (attack != 0 or defense != 0):
		out.append("item '%s' has equipment stats but no slot - they would do nothing" % id)
	out.append_array(_worn_art_problems())
	return out


## Everything wrong with the art map, separately for `EnemyDef._resistance_problems`' reason: every
## fault here is silent in play. Art on a thing nobody can wear is never drawn, and an entry with no
## name on one side is a sword that swings the wearer's own blade or draws a body that does not exist.
## Whether the art EXISTS is a question about a style, so the content gate asks it.
func _worn_art_problems() -> Array[String]:
	var out: Array[String] = []
	if slot == &"" and not worn_art.is_empty():
		out.append("item '%s' names art to wear but no slot - it can never be worn" % id)
	for wearer: Variant in worn_art:
		var drawn := str(worn_art[wearer])
		if str(wearer).is_empty() or drawn.is_empty():
			out.append("item '%s' names worn art with no character on one side" % id)
		elif drawn == str(wearer):
			# An entry that reads like a decision and changes nothing: the resistance-of-100 rule.
			out.append("item '%s' draws '%s' as themselves, which is what it would do anyway"
				% [id, drawn])
	return out
