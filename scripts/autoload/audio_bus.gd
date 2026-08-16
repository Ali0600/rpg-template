extends Node
## Plays sounds by id, from data. A stub with a real seam rather than a real mixer.
##
## The template ships no audio files, so this cannot play anything - but every system that
## wants a sound should ask for one BY NAME from the start, or adding audio later means
## hunting down every place that should have made a noise. Dropping .ogg files into
## data/audio and listing them turns the whole thing on with no code change.
##
## An unknown id warns rather than failing silently. A fallback that says nothing is how a
## missing sound survives to release: nobody notices a noise that was never there.

const SOUND_DIR := "res://data/audio"
const SOUND_EXTS: Array[String] = ["ogg", "wav", "mp3"]

var _sounds: Dictionary = {}
var _warned: Dictionary = {}
var _sfx := AudioStreamPlayer.new()
var _music := AudioStreamPlayer.new()
var _enabled := true


func _ready() -> void:
	add_child(_sfx)
	add_child(_music)
	reload()
	EventBus.sound_requested.connect(_on_sound_requested)
	EventBus.system_ready.emit({"system": &"AudioBus"})


func reload() -> void:
	_sounds.clear()
	_warned.clear()
	for path in ContentScan.files(SOUND_DIR, SOUND_EXTS):
		var stream := load(path) as AudioStream
		if stream != null:
			# Keyed by filename, not by path, so sounds can be filed into subdirectories
			# without the id a game asks for changing.
			_sounds[StringName(path.get_file().get_basename())] = stream


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _sounds.keys():
		out.append(k)
	out.sort()
	return out


func has_sound(id: StringName) -> bool:
	return _sounds.has(id)


func set_enabled(value: bool) -> void:
	_enabled = value


func play_sfx(id: StringName) -> bool:
	return _play(_sfx, id)


func play_music(id: StringName) -> bool:
	return _play(_music, id)


func stop_music() -> void:
	_music.stop()


func _play(player: AudioStreamPlayer, id: StringName) -> bool:
	if not _sounds.has(id):
		# Warned ONCE per id: a sound requested every frame would otherwise bury the log in
		# the same line and make every other warning unreadable.
		if not _warned.has(id):
			_warned[id] = true
			push_warning("AudioBus: no sound '%s' in %s" % [id, SOUND_DIR])
		return false
	if not _enabled:
		return false
	player.stream = _sounds[id]
	player.play()
	return true


func _on_sound_requested(info: Dictionary) -> void:
	var id := StringName(str(info.get("id", "")))
	if str(info.get("kind", "sfx")) == "music":
		play_music(id)
	else:
		play_sfx(id)
