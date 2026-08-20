class_name FileSoundSource
extends SoundSource
## Reads the committed WAVs under assets/generated/<style>/sfx/. What the GAME uses.
##
## Startup does no synthesis: rendering sixteen cues is fast, but it is work done on every
## machine on every boot to produce a file that is already in the repository. The sprite side
## made the same call for the same reason.
##
## This uses load(), not SoundFile - it wants the imported resource, exactly like every other
## asset the running game asks for. SoundFile is for tooling that must see the committed bytes.

const SFX_SUBDIR := "sfx"

var _root := ""


func _init(style_id: StringName, generated_root: String = "res://assets/generated") -> void:
	_root = "%s/%s/%s" % [generated_root, style_id, SFX_SUBDIR]


func cue(cue_id: StringName) -> AudioStreamWAV:
	var path := path_for(cue_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStreamWAV


func path_for(cue_id: StringName) -> String:
	return "%s/%s.wav" % [_root, cue_id]


func root() -> String:
	return _root
