class_name ShopDef
extends Resource
## What one shopkeeper sells, as data.
##
## Registered automatically, like every other resource under data/: a new file in data/shops/
## is reachable as Registry.get_resource(&"ShopDef", id) with no registration step to forget.
##
## Stock is a list of item ids rather than prices, because a price belongs to the ITEM: two
## shopkeepers selling the same tonic for different money is a game's idea, not a template's,
## and one price per item is what keeps the sell side honest without a second table.

@export var id: StringName = &""

## What the keeper offers, in the order they are drawn. Ids rather than ItemDefs so a shop
## file names content the same way a map does - and so a typo is caught by the content gate
## rather than by a null at the counter.
@export var stock: Array[StringName] = []


## What the keeper says, so a merchant has a voice without a script. Empty falls back to the
## template's own lines (ShopMenu.DEFAULT_*), which is what lets a game ship a shop by
## listing stock and nothing else.
@export_multiline var greeting: String = ""
## After a deal. "Anything else?" is the classic, and the point of it is that the counter
## stays open.
@export_multiline var thanks: String = ""
## When the purse is short. Said out loud rather than only thudded: a refusal that makes no
## words reads as a dead key.
@export_multiline var poor_line: String = ""


## Everything wrong with this shop on its own terms. What it CANNOT check is whether the ids
## resolve or carry a price: that needs the Registry, which a resource has no business
## reaching. The content gate does it, the way TileGen.problems(bank, style) does.
func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("shop has no id")
	# A shopkeeper with nothing to sell opens an empty counter, which reads as a broken menu
	# rather than as an empty file.
	if stock.is_empty():
		out.append("shop '%s' stocks nothing" % id)
	var seen: Array[StringName] = []
	for item_id in stock:
		if String(item_id).is_empty():
			out.append("shop '%s' stocks an item with no id" % id)
		elif seen.has(item_id):
			# A duplicate draws the same row twice and makes the cursor lie about what it is
			# pointing at.
			out.append("shop '%s' stocks '%s' twice" % [id, item_id])
		else:
			seen.append(item_id)
	return out
