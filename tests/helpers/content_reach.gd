class_name ContentReach
extends RefCounted
## What each game on disk can actually reach, so a content gate can be about A game rather than
## about THE game.
##
## Every rule here used to be written as though one game shipped, which for eleven milestones it
## did: the map-reachability gate loaded `quest.tres` by literal path, and the portrait gate
## checked every conversation in the repo against every game's style. Both are correct with one
## game and wrong with two - the second game's start map is a map on disk nobody's walk reaches,
## and its style is one the first game's cast was never drawn in.
##
## The functions are pure and take what they walk, so `test_content_reach.gd` can hand them TWO
## manifests. That matters more than it looks: with one game shipped, "the union over every
## manifest" and "quest.tres, hardcoded" are the same function, so a mutant reverting the union
## would survive against the shipped data while saying nothing about the rule.


## Every map id any of these games can be played into. Fails no differently from the one-game
## version when there is one game, which is the point - it generalises the rule rather than
## loosening it.
static func reachable_union(manifests: Array[GameManifest]) -> Dictionary:
	var out := {}
	for manifest in manifests:
		for key: Variant in WarpGraph.reachable(manifest).keys():
			out[StringName(str(key))] = true
	return out


## Every conversation this game can open: the ones its maps name, plus the ones its own code
## names and no map does.
##
## Takes the maps rather than reaching for them, the `_scales_of` idiom - a gate that derives its
## own population from the thing under audit cannot be shown a case that must fail.
##
## The hooks half is load-bearing rather than defensive. Measured 2026-09-05: 19 files in
## data/dialog, 16 named by map records, and the other three named only by the warden's hooks.
## Without `GameHooks.dialog_ids()` those three are conversations no game can reach, and the
## membership rule below would refuse the game that ships.
static func dialogs_of(manifest: GameManifest, map_ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Variant in map_ids:
		var map := MapData.load_from(MapData.path_of(StringName(str(entry))))
		if not map.ok:
			continue
		for records: Variant in [map.npcs, map.objects, map.warps]:
			for record: Variant in (records as Array):
				var fields: Dictionary = record
				for key in ["dialog", "locked_dialog"]:
					var named := StringName(str(fields.get(key, "")))
					if not String(named).is_empty() and not out.has(named):
						out.append(named)
	var hooks := manifest.new_hooks()
	if hooks != null:
		for named in hooks.dialog_ids():
			if not out.has(named):
				out.append(named)
	return out
