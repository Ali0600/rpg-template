class_name CharacterSpec
extends Resource
## Who a character is, in the only terms the generator understands: a style, a seed, and a
## choice of part and ramp per slot.
##
## Anything left blank is filled from the seed, so a crowd of NPCs is one line of data each
## and still reproducible: the same seed always produces the same villager. That is what
## makes "regenerate the art" a safe operation rather than a reroll of the entire cast.

@export var id: StringName = &""

## Which SpriteStyle to draw with. Changing this one field re-skins the character.
@export var style_id: StringName = &"gb16"

## Deterministic input for every choice this spec does not make explicitly.
@export var seed: int = 0

## slot -> part id, e.g. {"hair": "hair_long"}. Slots absent here are chosen from the seed.
@export var parts: Dictionary = {}

## slot -> ramp name, e.g. {"hair": "hair_black"}. Same rule.
@export var ramps: Dictionary = {}


## A complete, explicit description: every slot the rig knows about resolved to a part and a
## ramp. The generator only ever consumes this, so a sprite can be traced back to exactly
## the choices that produced it.
##
## Each slot draws from its own derived stream, so adding a new slot - or a new option to
## one slot - cannot shift the choices already made for the others. Without that, adding a
## hat would restyle every existing NPC's hair.
func resolve(rig: Rig, style: SpriteStyle) -> Dictionary:
	var rng := SeededRng.new(seed)
	var chosen_parts: Dictionary = {}
	var chosen_ramps: Dictionary = {}

	for slot in rig.slots():
		var part_id := str(parts.get(slot, ""))
		if part_id.is_empty():
			var options := style.choices_for_part(slot)
			if options.is_empty():
				options = rig.part_ids_for_slot(slot)
			part_id = str(rng.derive("part:" + slot).pick(options, ""))
		if part_id.is_empty():
			continue
		chosen_parts[slot] = part_id

		var ramp_name := str(ramps.get(slot, ""))
		if ramp_name.is_empty():
			var ramp_options := style.choices_for_ramp(slot)
			if ramp_options.is_empty():
				ramp_name = style.default_ramp_for(slot)
			else:
				ramp_name = str(rng.derive("ramp:" + slot).pick(ramp_options, ""))
		if ramp_name.is_empty():
			ramp_name = rig.default_ramp_for_slot(slot)
		chosen_ramps[slot] = ramp_name

	# Followers resolve last, so a slot that must match another (bare arms and the face are
	# the same skin) copies a value that is already final. An explicit ramp on the spec still
	# wins: the alias fills a blank, it does not override an author.
	for slot: Variant in chosen_parts.keys():
		var source := rig.ramp_source_slot(str(slot))
		if source.is_empty() or not str(ramps.get(slot, "")).is_empty():
			continue
		if chosen_ramps.has(source):
			chosen_ramps[slot] = chosen_ramps[source]

	return {"parts": chosen_parts, "ramps": chosen_ramps}


## Reports what a resolved spec cannot draw, naming the slot. A part id that does not exist
## would otherwise simply not be drawn, and a character missing its head looks like a
## compositor bug rather than a typo in one data file.
func problems(rig: Rig, style: SpriteStyle) -> Array[String]:
	var out: Array[String] = []
	if String(id).is_empty():
		out.append("character has no id")
	if String(style_id) != String(style.id):
		out.append("character '%s' asks for style '%s' but was given '%s'" % [id, style_id, style.id])
	var resolved := resolve(rig, style)
	var chosen_parts: Dictionary = resolved["parts"]
	var chosen_ramps: Dictionary = resolved["ramps"]
	for slot: Variant in chosen_parts.keys():
		var part_id := str(chosen_parts[slot])
		if not rig.has_part(part_id):
			out.append("character '%s' slot '%s' names unknown part '%s'" % [id, slot, part_id])
		elif rig.slot_of(part_id) != str(slot):
			out.append("character '%s' puts part '%s' (a %s) in slot '%s'"
				% [id, part_id, rig.slot_of(part_id), slot])
		var ramp_name := str(chosen_ramps.get(slot, ""))
		if ramp_name.is_empty():
			out.append("character '%s' slot '%s' resolved to no ramp" % [id, slot])
		elif style.ramp(ramp_name).size() != 3:
			out.append("character '%s' slot '%s' names unknown ramp '%s'" % [id, slot, ramp_name])
	return out
