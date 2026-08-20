class_name SoundBank
extends RefCounted
## The cue shapes a style plays. The audio counterpart of Rig, and loaded the same way.
##
## A bank is data with no voice in it: it says a footstep is 55 milliseconds of noise, and says
## nothing about what noise sounds like. That separation is what lets three styles share one
## bank, and it is why a game re-voicing the template does not re-author a single cue.

const BANK_DIR := "res://data/banks"

var id: StringName = &""
var cues: Dictionary = {}
var _load_error := ""


## The bank named by a style, or one carrying a load error. Never null: a caller reporting
## "bank 'x' could not be read" beside its own context is more use than a null check.
static func load_from(bank_id: StringName) -> SoundBank:
	var bank := SoundBank.new()
	bank.id = bank_id
	var path := "%s/%s.json" % [BANK_DIR, bank_id]
	var file := JsonFile.read(path)
	if not file.ok:
		bank._load_error = "bank '%s': %s" % [bank_id, file.error]
		return bank
	var raw: Variant = file.data.get("cues", {})
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary):
			var shape: Variant = (raw as Dictionary)[key]
			if shape is Dictionary:
				bank.cues[StringName(str(key))] = shape
	return bank


## The shape for one cue, or an empty dictionary. Empty is a fact the caller reports, not a
## default to render - a cue rendered from nothing would be a plausible-sounding blip standing
## in for a missing one, which is the failure this whole design is trying to avoid.
func shape(cue: StringName) -> Dictionary:
	return cues.get(cue, {})


func has_cue(cue: StringName) -> bool:
	return cues.has(cue)


## Everything wrong with this bank, INCLUDING every cue the vocabulary names and it does not
## have. That second half is the completeness check: Sfx is the work list, so a cue added to
## the enum without a shape here fails the build instead of going silent in play.
func problems() -> Array[String]:
	var out: Array[String] = []
	if not _load_error.is_empty():
		out.append(_load_error)
		return out
	if cues.is_empty():
		out.append("bank '%s' defines no cues" % id)
	for cue in Sfx.ids():
		if not cues.has(cue):
			out.append("bank '%s' has no shape for cue '%s'" % [id, cue])
	for cue: StringName in cues:
		if Sfx.of(cue) < 0:
			out.append("bank '%s' defines '%s', which is not a cue the template asks for"
				% [id, cue])
		out.append_array(Synth.problems(cue, cues[cue]))
	return out
