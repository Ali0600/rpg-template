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
var style_id: StringName = &"gb16"


static func load_from(path: String) -> MapData:
	var map := MapData.new()
	var file := JsonFile.read(path)
	if not file.ok:
		map.error = file.error
		return map

	map.id = StringName(file.get_string("id", path.get_file().get_basename()))
	map.style_id = StringName(file.get_string("style", "gb16"))
	map.legend = file.get_dict("legend")
	map.ground = JsonFile.to_string_array(file.data.get("ground", []))
	map.decor = JsonFile.to_string_array(file.data.get("decor", []))
	map.spawns = file.get_dict("spawns")
	map.npcs = file.get_array("npcs")
	map.warps = file.get_array("warps")
	map.objects = file.get_array("objects")
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
				"locked_dialog": StringName(str(warp.get("locked_dialog", ""))),
			}
	return {}


## Whether a warp will actually fire. Pure, so "a locked door needs its key" is a test that
## reads a result rather than one that walks a player into a wall for 300 frames.
##
## A warp with no requires_flag is open, which is what every warp written before this existed
## means - adding the field must not quietly lock the doors that already work.
static func warp_allowed(warp: Dictionary, flags: Dictionary) -> bool:
	var requires := StringName(str(warp.get("requires_flag", "")))
	if String(requires).is_empty():
		return true
	return bool(flags.get(requires, false))


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
		var kind := str(object.get("kind", ""))
		if says.is_empty() and sets.is_empty() and kind.is_empty():
			out.append("object '%s' does nothing - give it a dialog, a set_flag, or a kind its game handles" % object_id)
	return out


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
