class_name MapData
extends RefCounted
## A map, parsed from data/maps/<id>.json and validated before anything builds it.
##
## Maps are ASCII rows plus a legend, because a map you can read in a diff and generate from
## a script is worth more in a template than one that needs the editor open - and it keeps
## "add a game" inside data/.
##
## Every fault is reported with its row and column. A map is hand-authored text, so the
## failure modes are a ragged row, a legend entry pointing at a tile that does not exist, and
## a spawn outside the map - all of which build SOMETHING and leave you looking at an empty
## screen wondering which system broke.

var id: StringName = &""
var ok: bool = false
var error: String = ""

## Legend character -> tile id, e.g. {".": "grass", "#": "wall"}.
var legend: Dictionary = {}
## Rows of the ground layer, top to bottom.
var ground: Array[String] = []
## Rows of the decor layer (same size; a space means nothing there). Optional.
var decor: Array[String] = []
## spawn id -> tile coordinates.
var spawns: Dictionary = {}
## Array of {"id", "character", "tile", "facing", "dialog", "behavior"}.
var npcs: Array = []
## Array of {"tile", "map", "spawn", "requires_flag", "locked_dialog"}.
var warps: Array = []
## Things that are not people but can be pressed: signs, chests, levers. Each is
## {"id", "tile", "kind", "dialog", "set_flag", "once"} plus anything a game invents.
##
## An object is an INTERACTION POINT, not a sprite. What you see is the decor tile it stands
## on, and whether it blocks you comes from that tile's own metadata - so adding a chest is
## an art change plus four lines of data, and MapBuilder gains no rendering code at all.
var objects: Array = []
## Things that fight back. Each is {"id", "enemy", "tile", "facing"} plus an optional
## {"group": [...]}, where every name is an EnemyDef under data/enemies/.
##
## ONE RECORD IS ONE ENCOUNTER, however many foes it names. The body on the tile is the first of
## them and `group` rides with it, which is Super Mario RPG's shape - you walk into one sprite
## and a formation is what it opens. Adjacent records never merge into one fight, which is
## EarthBound's model and refused here: its manual says other enemies join "occasionally", and a
## roll over where wandering bodies happen to stand is exactly the randomness in the movement
## loop that visible encounters exist to avoid.
##
## Unlike an object, an enemy IS a sprite - it stands on its tile with generated art, and
## walking next to it starts the fight. It is not an interaction target: there is no pressing
## a monster, and one that had to be pressed would be one the player could simply walk past.
##
## Being beaten is remembered as a `seen` key, exactly as a chest remembers being opened, so
## "defeated enemies stay gone" needed no new persistence and migrates for free.
var enemies: Array = []
var style_id: StringName = &"gb16"
## The tune this map plays, or empty for silence. STATED either way and never inherited: a map
## that said nothing would sound like whichever door the player came through, so the cave would
## be quiet or loud depending on the route.
var music_id: StringName = &""


static func load_from(path: String) -> MapData:
	var map := MapData.new()
	var file := JsonFile.read(path)
	if not file.ok:
		map.error = file.error
		return map

	map.id = StringName(file.get_string("id", path.get_file().get_basename()))
	map.style_id = StringName(file.get_string("style", "gb16"))
	map.music_id = StringName(file.get_string("music", ""))
	map.legend = file.get_dict("legend")
	map.ground = JsonFile.to_string_array(file.data.get("ground", []))
	map.decor = JsonFile.to_string_array(file.data.get("decor", []))
	map.spawns = file.get_dict("spawns")
	map.npcs = file.get_array("npcs")
	map.warps = file.get_array("warps")
	map.objects = file.get_array("objects")
	map.enemies = file.get_array("enemies")
	map.ok = true
	return map


func size() -> Vector2i:
	if ground.is_empty():
		return Vector2i.ZERO
	return Vector2i(ground[0].length(), ground.size())


## The tile id at a coordinate on a layer, or "" if there is nothing there. Out-of-bounds is
## "" rather than an error: callers ask about neighbours at the edges all the time.
func tile_at(layer: Array[String], at: Vector2i) -> String:
	if at.y < 0 or at.y >= layer.size():
		return ""
	var row := layer[at.y]
	if at.x < 0 or at.x >= row.length():
		return ""
	var ch := row[at.x]
	if ch == " ":
		return ""
	return str(legend.get(ch, ""))


func ground_at(at: Vector2i) -> String:
	return tile_at(ground, at)


func decor_at(at: Vector2i) -> String:
	return tile_at(decor, at)


## Tile coordinates of a named spawn, or a sentinel the caller must check. Returning (0,0)
## for an unknown spawn would drop the player in the corner of the map, which reads as a
## movement bug rather than as a missing entry.
func spawn(spawn_id: StringName) -> Vector2i:
	var raw := JsonFile.to_int_array(spawns.get(String(spawn_id), []))
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(raw[0], raw[1])


func spawn_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in spawns.keys():
		out.append(str(k))
	out.sort()
	return out


## The warp on a tile, as {"map": StringName, "spawn": StringName}, or an empty dictionary.
## Looked up by tile rather than by proximity so stepping onto the tile is the whole rule -
## a radius would fire while the player is still visibly beside the door.
func warp_at(at: Vector2i) -> Dictionary:
	for entry: Variant in warps:
		var warp: Dictionary = entry
		var raw := JsonFile.to_int_array(warp.get("tile", []))
		if raw.size() == 2 and Vector2i(raw[0], raw[1]) == at:
			return {
				"map": StringName(str(warp.get("map", ""))),
				"spawn": StringName(str(warp.get("spawn", "start"))),
				"requires_flag": StringName(str(warp.get("requires_flag", ""))),
				# Projected, not read from the raw entry later: this dictionary is the ONLY
				# thing _check_warp sees, so a requirement missing here is a lock that passes
				# every test built from a literal warp and opens in the live game.
				"requires_item": StringName(str(warp.get("requires_item", ""))),
				"requires_count": int(warp.get("requires_count", 1)),
				"locked_dialog": StringName(str(warp.get("locked_dialog", ""))),
			}
	return {}


## The enemy standing on a tile, fully projected, or an empty dictionary.
##
## Projected for the same reason warp_at is: this dictionary is the ONLY thing the encounter
## check sees, so a field left out here is a fight that silently never starts - and a fight
## that never starts looks exactly like a map that has not been given its enemies yet.
func enemy_at(at: Vector2i) -> Dictionary:
	for entry: Variant in enemies:
		var enemy: Dictionary = entry
		# `spot` rather than warp_at's `raw`: the two lookups would otherwise be
		# character-identical, and a find-and-replace aimed at one of them - a mutant, a
		# codemod, a rename - silently edits both and reports a verdict about the wrong one.
		var spot := JsonFile.to_int_array(enemy.get("tile", []))
		if spot.size() == 2 and Vector2i(spot[0], spot[1]) == at:
			return {
				"id": StringName(str(enemy.get("id", ""))),
				"enemy": StringName(str(enemy.get("enemy", ""))),
				"foes": _formation_of(enemy),
				"tile": Vector2i(spot[0], spot[1]),
				"facing": str(enemy.get("facing", "")),
			}
	return {}


## Everything a record fights with, in order: the body on the tile, then its group. The world
## reads this rather than `enemy`, so a record that names no group is a formation of one and
## needs no branch anywhere downstream.
static func _formation_of(enemy: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	_add_foe(out, enemy.get("enemy", ""))
	for extra: Variant in enemy.get("group", []):
		_add_foe(out, extra)
	return out


## Appends one foe, KEEPING DUPLICATES. A formation is an ordered list of bodies, not a set of
## names: two slinks are two slinks, and "3 Slimes appear!" is the genre's commonest crowd.
##
## Its own function rather than `_add_ref` because that one deduplicates, which is right for
## `enemy_refs` - a scan asking "does every enemy this map names exist" wants each name once -
## and silently wrong here. M28 shipped this collapse and nothing caught it: the only formation
## it authored was a slink AND a gloom, so no same-species pair ever existed to come out short.


## Every EnemyDef this map names, for the content gate. The item_refs precedent: a misspelt
## enemy id is a fight that cannot open, and the map would look merely empty.
func enemy_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Variant in enemies:
		for named: StringName in _formation_of(entry as Dictionary):
			_add_ref(out, named)
	return out


## Whether a warp will actually fire. Pure, so "a locked door needs its key" is a test that
## reads a result rather than one that walks a player into a wall for 300 frames.
##
## A warp with neither requirement is open, which is what every warp written before these
## existed means - adding a field must not quietly lock the doors that already work. With both,
## both must pass: a door wanting a key AND a promise is one door, not two.
static func warp_allowed(warp: Dictionary, flags: Dictionary, items: Dictionary = {}) -> bool:
	var requires := StringName(str(warp.get("requires_flag", "")))
	if not String(requires).is_empty() and not bool(flags.get(requires, false)):
		return false
	var item := StringName(str(warp.get("requires_item", "")))
	if not String(item).is_empty() and not Inventory.has_in(items, item, int(warp.get("requires_count", 1))):
		return false
	return true


## The world position of a tile's CENTRE, in pixels. Actors stand on tile centres, so this
## is the one conversion; a caller doing its own multiply is a caller that will forget the
## half-tile offset.
static func tile_to_world(at: Vector2i, tile_size: int) -> Vector2:
	return Vector2(at.x * tile_size + tile_size / 2.0, at.y * tile_size + tile_size / 2.0)


static func world_to_tile(at: Vector2, tile_size: int) -> Vector2i:
	return Vector2i(floori(at.x / tile_size), floori(at.y / tile_size))


## Every tile on the map's border that a character could walk onto.
##
## An open edge with nothing beyond it lets the player walk off the map into empty space -
## which does not error, does not look like a bug from the code's side, and is the first
## thing a playtester finds. A deliberately open edge is expressed by putting a warp on it,
## so "you can leave here" is stated in the data rather than left as an absence.
func open_edges(solid_tiles: Array[String]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bounds := size()
	var warp_tiles: Array[Vector2i] = []
	for entry: Variant in warps:
		var raw := JsonFile.to_int_array((entry as Dictionary).get("tile", []))
		if raw.size() == 2:
			warp_tiles.append(Vector2i(raw[0], raw[1]))

	for y in bounds.y:
		for x in bounds.x:
			if x != 0 and y != 0 and x != bounds.x - 1 and y != bounds.y - 1:
				continue
			var at := Vector2i(x, y)
			if warp_tiles.has(at):
				continue
			if solid_tiles.has(ground_at(at)) or solid_tiles.has(decor_at(at)):
				continue
			out.append(at)
	return out


## Everything wrong with this map, all of it, with coordinates.
## What is wrong with one npc's movement. Separate because a behaviour is the one part of an
## npc record that can soft-lock a game: an NPC parked on the only warp out of a room is a
## door that cannot be used, and it looks like a broken map rather than a bad record.
func _behavior_problems(npc: Dictionary, bounds: Vector2i, solid_tiles: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var npc_id := str(npc.get("id", "?"))
	var raw_name := str(npc.get("behavior", "static"))
	var kind := NpcBrain.kind_from_name(raw_name)
	if kind < 0:
		# A typo'd behaviour must fail the build. Falling back to standing still would make
		# "wonder" look like a shy NPC rather than a misspelling, which is the kind of fault
		# that survives a whole milestone.
		out.append("npc '%s' has unknown behavior '%s', expected one of %s"
			% [npc_id, raw_name, ", ".join(PackedStringArray(NpcBrain.NAMES.keys()))])
		return out
	if kind == NpcBrain.Kind.WANDER and int(npc.get("range", 2)) < 1:
		out.append("npc '%s' wanders with range %d, which is standing still"
			% [npc_id, int(npc.get("range", 2))])
	if kind != NpcBrain.Kind.PATROL:
		return out

	var path: Array = npc.get("path", [])
	if path.size() < 2:
		out.append("npc '%s' patrols a path of %d point(s); a patrol needs at least 2"
			% [npc_id, path.size()])
	for i in path.size():
		var pair := JsonFile.to_int_array(path[i])
		if pair.size() != 2:
			out.append("npc '%s' patrol point %d is not a tile" % [npc_id, i])
			continue
		var point := Vector2i(pair[0], pair[1])
		if point.x < 0 or point.y < 0 or point.x >= bounds.x or point.y >= bounds.y:
			out.append("npc '%s' patrol point %d at %s is outside the %s map"
				% [npc_id, i, point, bounds])
			continue
		# A waypoint inside a wall is a target the NPC can never reach, so it walks into the
		# wall until the stuck counter gives up - forever, and silently.
		# `point`, not `at`: the open-edge check a few functions up reads identically with `at`,
		# and a mutant anchored there silently retargets onto whichever comes first in the file.
		if solid_tiles.has(ground_at(point)) or solid_tiles.has(decor_at(point)):
			out.append("npc '%s' patrol point %d at %s is a solid tile" % [npc_id, i, point])
		# A patroller that parks on a warp is a door that cannot be used - the player walks
		# into a body where the exit is. It presents as a broken map, not a bad record.
		if not warp_at(point).is_empty():
			out.append("npc '%s' patrol point %d at %s stands on a warp" % [npc_id, i, point])
	return out


func problems(known_tiles: Array[String], solid_tiles: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	if not ok:
		out.append("map did not load: " + error)
		return out
	if String(id).is_empty():
		out.append("map has no id")
	if ground.is_empty():
		out.append("map has no ground rows")
		return out

	var width := ground[0].length()
	for y in ground.size():
		if ground[y].length() != width:
			out.append("ground row %d is %d wide, expected %d" % [y, ground[y].length(), width])
	for y in decor.size():
		if decor[y].length() != width:
			out.append("decor row %d is %d wide, expected %d" % [y, decor[y].length(), width])
	if not decor.is_empty() and decor.size() != ground.size():
		out.append("decor has %d rows, ground has %d" % [decor.size(), ground.size()])

	# A legend entry naming a tile the tileset does not have draws nothing at all, and an
	# empty patch of map looks exactly like a patch nobody filled in.
	for ch: Variant in legend.keys():
		var tile := str(legend[ch])
		if not known_tiles.has(tile):
			out.append("legend '%s' names unknown tile '%s'" % [ch, tile])

	out.append_array(_unknown_characters(ground, "ground", width))
	out.append_array(_unknown_characters(decor, "decor", width))

	var bounds := size()
	if spawns.is_empty():
		out.append("map has no spawns; nothing can enter it")
	for spawn_id in spawn_ids():
		var at := spawn(StringName(spawn_id))
		if at == Vector2i(-1, -1):
			out.append("spawn '%s' is not a pair of coordinates" % spawn_id)
		elif at.x < 0 or at.y < 0 or at.x >= bounds.x or at.y >= bounds.y:
			out.append("spawn '%s' at %s is outside the %s map" % [spawn_id, at, bounds])

	for entry: Variant in npcs:
		var npc: Dictionary = entry
		var raw := JsonFile.to_int_array(npc.get("tile", []))
		if raw.size() != 2:
			out.append("npc '%s' has no tile" % npc.get("id", "?"))
			continue
		var at := Vector2i(raw[0], raw[1])
		if at.x < 0 or at.y < 0 or at.x >= bounds.x or at.y >= bounds.y:
			out.append("npc '%s' at %s is outside the %s map" % [npc.get("id", "?"), at, bounds])
		if str(npc.get("character", "")).is_empty():
			out.append("npc '%s' names no character" % npc.get("id", "?"))
		out.append_array(_behavior_problems(npc, bounds, solid_tiles))

	for entry: Variant in warps:
		var warp: Dictionary = entry
		var raw := JsonFile.to_int_array(warp.get("tile", []))
		if raw.size() != 2:
			out.append("a warp has no tile")
			continue
		var at := Vector2i(raw[0], raw[1])
		if at.x < 0 or at.y < 0 or at.x >= bounds.x or at.y >= bounds.y:
			out.append("warp at %s is outside the %s map" % [at, bounds])
		if str(warp.get("map", "")).is_empty():
			out.append("warp at %s names no destination map" % at)
		# A locked door with no line to say is a door that ignores you: the player presses
		# into it and nothing at all happens, which reads as the warp being broken.
		if not str(warp.get("requires_flag", "")).is_empty() and str(warp.get("locked_dialog", "")).is_empty():
			out.append("warp at %s is locked behind '%s' but says nothing when refused"
				% [at, warp.get("requires_flag", "")])
		if not str(warp.get("requires_item", "")).is_empty() and str(warp.get("locked_dialog", "")).is_empty():
			out.append("warp at %s needs item '%s' but says nothing when refused"
				% [at, warp.get("requires_item", "")])

	out.append_array(_object_problems(bounds))

	if not solid_tiles.is_empty():
		var open := open_edges(solid_tiles)
		if not open.is_empty():
			# Reported as a handful plus a count: a map missing its whole outer wall would
			# otherwise bury every other fault under a hundred identical lines.
			var shown := open.slice(0, mini(4, open.size()))
			out.append("the map's edge is open at %s%s - a character can walk off it. Wall it in, or put a warp there."
				% [shown, "" if open.size() <= 4 else " and %d more" % (open.size() - 4)])
	return out


## Everything wrong with this map's objects.
##
## Separate from problems() only because the id-uniqueness check needs a set that the other
## loops do not, and folding it in would put a second concern inside a loop that already has
## one - which is how a scan quietly stops covering half of what it claims.
func _object_problems(bounds: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var taken: Dictionary = {}
	# Objects and NPCs are both interaction targets, so they share one id namespace: two
	# things answering to "chest" makes "which one did the player press" a coin toss.
	for entry: Variant in npcs:
		var npc: Dictionary = entry
		taken[str(npc.get("id", ""))] = true

	for entry: Variant in objects:
		var object: Dictionary = entry
		var object_id := str(object.get("id", ""))
		if object_id.is_empty():
			out.append("an object has no id")
			continue
		if taken.has(object_id):
			# Two chests sharing an id share the memory of having been opened, so the second
			# one is found already empty - a bug that reads as a missing item.
			out.append("object id '%s' is used twice" % object_id)
		taken[object_id] = true

		var raw := JsonFile.to_int_array(object.get("tile", []))
		if raw.size() != 2:
			out.append("object '%s' has no tile" % object_id)
			continue
		var at := Vector2i(raw[0], raw[1])
		if at.x < 0 or at.y < 0 or at.x >= bounds.x or at.y >= bounds.y:
			out.append("object '%s' at %s is outside the %s map" % [object_id, at, bounds])

		# An object with nothing to say, no flag to set and no kind for a game to recognise is
		# a dead button: the player walks up, presses, and nothing happens.
		var says := str(object.get("dialog", ""))
		var sets := str(object.get("set_flag", ""))
		var gives := str(object.get("give_item", ""))
		var takes := str(object.get("take_item", ""))
		var kind := str(object.get("kind", ""))
		if says.is_empty() and sets.is_empty() and gives.is_empty() and takes.is_empty() and kind.is_empty():
			out.append("object '%s' does nothing - give it a dialog, a set_flag, an item to give or take, or a kind its game handles" % object_id)
		# The same rule as a locked door, for the same reason: an object that can refuse and
		# has no line to refuse with is a button that does nothing on the one press that
		# matters most - the one before you have found the thing it wants.
		var needs := str(object.get("requires_item", ""))
		if (not needs.is_empty() or not takes.is_empty()) and str(object.get("locked_dialog", "")).is_empty():
			out.append("object '%s' needs an item but says nothing when refused" % object_id)

	# Enemies share the same id namespace, and the reason is sharper than for objects: being
	# beaten is recorded as the same map-scoped `seen` key an opened chest uses. An enemy and a
	# chest called "guard" are one memory - beat the guard and the chest is already empty.
	var occupied := {}
	for entry: Variant in enemies:
		var enemy: Dictionary = entry
		var enemy_id := str(enemy.get("id", ""))
		if enemy_id.is_empty():
			out.append("an enemy has no id")
			continue
		if taken.has(enemy_id):
			out.append("enemy id '%s' is used twice" % enemy_id)
		taken[enemy_id] = true

		if str(enemy.get("enemy", "")).is_empty():
			out.append("enemy '%s' names no EnemyDef" % enemy_id)
		# A group entry that names nothing would open a fight one foe short, and the fight would
		# still look deliberate - so it is refused here rather than push_error'd at the trigger.
		for extra: Variant in enemy.get("group", []):
			if str(extra).is_empty():
				out.append("enemy '%s' fights beside something with no name" % enemy_id)
		var spot := JsonFile.to_int_array(enemy.get("tile", []))
		if spot.size() != 2:
			out.append("enemy '%s' has no tile" % enemy_id)
			continue
		var stands := Vector2i(spot[0], spot[1])
		if stands.x < 0 or stands.y < 0 or stands.x >= bounds.x or stands.y >= bounds.y:
			out.append("enemy '%s' at %s is outside the %s map" % [enemy_id, stands, bounds])
		# Two records on one tile is a fight that cannot be reached: enemy_at answers with the
		# first one it finds, so the second is a body nobody can walk into and a formation
		# nobody can open. It reads as a placement that simply does not work.
		if occupied.has(stands):
			out.append("enemy '%s' stands on %s, where '%s' already is"
				% [enemy_id, stands, occupied[stands]])
		occupied[stands] = enemy_id
	return out


## Every item id this map names, from its objects, its people and its doors. The content gate
## reads this: an item named nowhere on disk is a lock that can never open or a chest that
## hands over nothing, and both look like level-design mistakes rather than typos.
func item_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Variant in objects:
		_collect_items(out, entry as Dictionary)
	for entry: Variant in npcs:
		_collect_items(out, entry as Dictionary)
	for entry: Variant in warps:
		_add_ref(out, (entry as Dictionary).get("requires_item", ""))
	return out


static func _collect_items(out: Array[StringName], record: Dictionary) -> void:
	for key in ["give_item", "take_item", "requires_item"]:
		_add_ref(out, record.get(key, ""))


static func _add_foe(out: Array[StringName], raw: Variant) -> void:
	var id := StringName(str(raw))
	if not String(id).is_empty():
		out.append(id)


static func _add_ref(out: Array[StringName], raw: Variant) -> void:
	var id := StringName(str(raw))
	if not String(id).is_empty() and not out.has(id):
		out.append(id)


func _unknown_characters(layer: Array[String], label: String, width: int) -> Array[String]:
	var out: Array[String] = []
	var reported: Array[String] = []
	for y in layer.size():
		var row := layer[y]
		for x in mini(row.length(), width):
			var ch := row[x]
			if ch == " " or legend.has(ch):
				continue
			if reported.has(ch):
				continue
			reported.append(ch)
			out.append("%s row %d col %d uses '%s', which the legend does not define" % [label, y, x, ch])
	return out
