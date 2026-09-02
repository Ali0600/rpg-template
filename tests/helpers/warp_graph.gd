class_name WarpGraph
extends RefCounted
## Which maps a game can actually be played into, walking its warps from the first one.
##
## Extracted from test_battle_content, which derives the party a fight is guaranteed to have by
## asking which maps are reachable when a flag is refused. A second reader wants the same walk
## for a different question - whether every room a player can reach is drawn at one size - and
## two implementations of "where can this game go" would eventually disagree about a locked
## door, which is exactly the kind of drift that makes one gate report on a game nobody plays.


## Every map reachable from the game's first, when every warp demanding `flag` is refused. Pass
## an empty flag to refuse nothing, which is the widest reach and therefore the strictest thing
## to assert over.
##
## A FIXPOINT rather than a plain walk, because a locked door moves with the key: the keep asks
## for `gate_key`, the key lies in the hollow, and the hollow asks for the flag - so refusing the
## flag closes the keep too, one room removed.
##
## An item NO map object grants is assumed obtainable (the smith's tonics, the hermit's oil,
## which come out of conversations). That direction is the safe one: assuming an item is
## available can only make MORE maps reachable, and every caller here is asserting something
## about all of them.
static func reachable(manifest: GameManifest, flag: StringName = &"") -> Dictionary:
	var granted := granted_items()
	var reached := {manifest.start_map: true}
	var changed := true
	while changed:
		changed = false
		for here: Variant in reached.keys():
			var map := MapData.load_from(MapData.path_of(StringName(str(here))))
			if not map.ok:
				continue
			for entry: Variant in map.warps:
				var warp: Dictionary = entry
				if StringName(str(warp.get("requires_flag", ""))) == flag and not String(flag).is_empty():
					continue
				var need := StringName(str(warp.get("requires_item", "")))
				if granted.has(need) and not reached.has(granted[need]):
					continue
				var there := StringName(str(warp.get("map", "")))
				if String(there).is_empty() or reached.has(there):
					continue
				reached[there] = true
				changed = true
	return reached


## Which map hands out each item, for the walk above. Only map OBJECTS are sourced; anything a
## conversation gives is deliberately absent, and `reachable` says why.
static func granted_items() -> Dictionary:
	var out := {}
	for path in ContentScan.files_of(MapData.root, "json"):
		var map := MapData.load_from(path)
		for entry: Variant in map.objects:
			var object: Dictionary = entry
			var gives := StringName(str(object.get("give_item", "")))
			if not String(gives).is_empty() and not out.has(gives):
				out[gives] = map.id
	return out
