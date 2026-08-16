class_name Rig
extends RefCounted
## The shapes a character is built from, loaded from data/rigs/<id>.json.
##
## Parts are ASCII grids: '.' is transparent, '1'/'2'/'3' are the shadow/base/light tones of
## whatever ramp the character assigned to that slot, and 'o' forces an outline pixel. A
## part therefore has no colour of its own - the same head is a pale elf or a dark-skinned
## guard depending only on the ramp, which is what makes one rig serve a whole cast.
##
## Pixel art is authored as text because text is what survives review: a one-pixel change to
## a sleeve is one visible character in a diff. A binary or a packed resource hides it.
##
## Every part is stored per VIEW (front/side/back), never per direction: left is right
## mirrored, so a rig draws three views and gets four directions.

const TONE_CHARS := "123"
const TRANSPARENT_CHAR := "."
const OUTLINE_CHAR := "o"

var id: StringName = &""
var cell: Vector2i = Vector2i(16, 24)
var ok: bool = false
var error: String = ""

var _slot_order: Dictionary = {}  # view name -> Array[String] of slots, back to front
var _slot_defaults: Dictionary = {}  # slot -> ramp name
var _slot_ramp_from: Dictionary = {}  # slot -> slot it copies its ramp from
var _parts: Dictionary = {}  # part id -> Dictionary


static func load_from(path: String) -> Rig:
	var rig := Rig.new()
	var file := JsonFile.read(path)
	if not file.ok:
		rig.error = file.error
		return rig

	rig.id = StringName(file.get_string("id", ""))
	var cell_raw := JsonFile.to_int_array(file.data.get("cell", []))
	if cell_raw.size() == 2:
		rig.cell = Vector2i(cell_raw[0], cell_raw[1])

	for view: Variant in file.get_dict("slot_order").keys():
		rig._slot_order[str(view)] = JsonFile.to_string_array(file.get_dict("slot_order")[view])
	rig._slot_defaults = file.get_dict("slot_defaults")
	rig._slot_ramp_from = file.get_dict("slot_ramp_from")
	rig._parts = file.get_dict("parts")
	rig.ok = true
	return rig


## Slots in draw order for a view, back to front.
func slot_order(view: StringName) -> Array[String]:
	var raw: Variant = _slot_order.get(String(view), [])
	var out: Array[String] = []
	for v: Variant in raw as Array:
		out.append(str(v))
	return out


## Every slot the rig knows about, in front-view draw order. This is the list a
## CharacterSpec fills in.
func slots() -> Array[String]:
	var out := slot_order(&"front")
	for view in _slot_order.keys():
		for slot in slot_order(StringName(str(view))):
			if not out.has(slot):
				out.append(slot)
	return out


func part_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _parts.keys():
		out.append(str(k))
	out.sort()
	return out


func part_ids_for_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for pid in part_ids():
		if slot_of(pid) == slot:
			out.append(pid)
	return out


func has_part(part_id: String) -> bool:
	return _parts.has(part_id)


func slot_of(part_id: String) -> String:
	return str(_part(part_id).get("slot", ""))


## Whether this part rides the walk bob. Legs and feet must not: they carry the stride, and
## a foot lifted by the bob leaves the ground row, which is exactly what the grounding gate
## exists to catch.
func bobs(part_id: String) -> bool:
	return bool(_part(part_id).get("bob", true))


## Whether the outline pass hugs this part. Off for anything that is already a silhouette
## in its own right, like a cast shadow.
func outlined(part_id: String) -> bool:
	return bool(_part(part_id).get("outline", true))


func default_ramp_for_slot(slot: String) -> String:
	return str(_slot_defaults.get(slot, ""))


## Slots whose colour must follow another slot's. Bare arms are the same skin as the face,
## so the arms slot copies the head's ramp; without this, a randomised dark-skinned villager
## gets pale hands and the mistake reads as a rendering bug rather than a data one.
## Returns "" when the slot picks its own ramp.
func ramp_source_slot(slot: String) -> String:
	return str(_slot_ramp_from.get(slot, ""))


## The pixels of one part, in one view, on one walk frame: {"at": Vector2i, "rows":
## Array[String]}. An empty rows array means this part is not drawn in this view - the face
## from behind, for instance - which is a legitimate answer, not a failure.
func stamp(part_id: String, view: StringName, frame: int) -> Dictionary:
	var views: Dictionary = _part(part_id).get("views", {})
	if not views.has(String(view)):
		return {"at": Vector2i.ZERO, "rows": [] as Array[String]}
	var v: Dictionary = views[String(view)]
	var frames: Array = v.get("frames", [])
	if frames.is_empty():
		return {"at": Vector2i.ZERO, "rows": [] as Array[String]}

	# frame_map lets a four-frame walk reuse three drawings: the two passing poses are the
	# same picture, so authoring it twice would just be two places to fix a typo.
	var idx := frame
	var map := JsonFile.to_int_array(v.get("frame_map", []))
	if not map.is_empty():
		idx = map[frame % map.size()]
	idx = clampi(idx, 0, frames.size() - 1)

	var at_raw := JsonFile.to_int_array(v.get("at", []))
	var at := Vector2i(at_raw[0], at_raw[1]) if at_raw.size() == 2 else Vector2i.ZERO
	return {"at": at, "rows": JsonFile.to_string_array(frames[idx])}


func _part(part_id: String) -> Dictionary:
	var p: Variant = _parts.get(part_id, {})
	return p as Dictionary if p is Dictionary else {}


## Everything structurally wrong with this rig, all of it, named. A rig is hand-authored
## text, so the failure modes are ragged rows and typo'd characters - both of which draw
## something plausible-looking rather than erroring.
func problems() -> Array[String]:
	var out: Array[String] = []
	if not ok:
		out.append("rig did not load: " + error)
		return out
	if String(id).is_empty():
		out.append("rig has no id")
	if cell.x <= 0 or cell.y <= 0:
		out.append("rig cell must be positive, got %s" % cell)
	if _slot_order.is_empty():
		out.append("rig has no slot_order")
	if _parts.is_empty():
		out.append("rig has no parts")

	var known_chars := TONE_CHARS + TRANSPARENT_CHAR + OUTLINE_CHAR
	for view: Variant in _slot_order.keys():
		for slot in slot_order(StringName(str(view))):
			if part_ids_for_slot(slot).is_empty():
				out.append("view '%s' draws slot '%s', which no part fills" % [view, slot])

	for pid in part_ids():
		var part := _part(pid)
		if str(part.get("slot", "")).is_empty():
			out.append("part '%s' has no slot" % pid)
		var views: Dictionary = part.get("views", {})
		if views.is_empty():
			out.append("part '%s' has no views" % pid)
		for view_name: Variant in views.keys():
			var v: Dictionary = views[view_name]
			var at := JsonFile.to_int_array(v.get("at", []))
			if at.size() != 2:
				out.append("part '%s' view '%s' has no 'at' position" % [pid, view_name])
				continue
			var frames: Array = v.get("frames", [])
			if frames.is_empty():
				out.append("part '%s' view '%s' has no frames" % [pid, view_name])
			for fi in frames.size():
				var rows := JsonFile.to_string_array(frames[fi])
				if rows.is_empty():
					out.append("part '%s' view '%s' frame %d is empty" % [pid, view_name, fi])
					continue
				var width := rows[0].length()
				for ri in rows.size():
					var row := rows[ri]
					if row.length() != width:
						out.append("part '%s' view '%s' frame %d row %d is %d wide, expected %d"
							% [pid, view_name, fi, ri, row.length(), width])
					for ci in row.length():
						if not known_chars.contains(row[ci]):
							out.append("part '%s' view '%s' frame %d row %d has unknown pixel '%s'"
								% [pid, view_name, fi, ri, row[ci]])
				# A stamp that hangs off the cell is silently clipped, which reads as a
				# missing limb rather than as a placement mistake.
				if at[0] < 0 or at[1] < 0 or at[0] + width > cell.x or at[1] + rows.size() > cell.y:
					out.append("part '%s' view '%s' frame %d at %s size %dx%d falls outside the %s cell"
						% [pid, view_name, fi, at, width, rows.size(), cell])
			var map := JsonFile.to_int_array(v.get("frame_map", []))
			for m in map:
				if m < 0 or m >= frames.size():
					out.append("part '%s' view '%s' frame_map points at frame %d of %d"
						% [pid, view_name, m, frames.size()])
	return out
