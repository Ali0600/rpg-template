class_name MusicTrack
extends RefCounted
## The tune a voice performs, from data/music/<id>.json. The music counterpart of SoundBank,
## loaded the same way and just as unaware of what it will sound like.
##
## A track is NOTES, not samples: three styles perform one tune the way three sprite styles
## draw one rig. Nothing here knows about waveforms - Tune does that, and needs a style to do
## it, which is why the two are separate files.
##
## Voices are written as arrays of BAR STRINGS rather than as arrays of note objects, because
## that is how a map's ground is written in this project and for the same reason: a bar per
## line lines up in a diff, and a wrong note is visible as a wrong column.

const DIR := "res://data/music"

## The longest track this template will render. 22050 Hz mono 16-bit is 43 KB a SECOND, per
## voice, and three voices are committed - so a minute of music is four megabytes of build
## output in a repo whose entire generated tree is under one. A number rather than a rule of
## thumb, because the cost is arithmetic and the failure is a repo that got heavy one track at
## a time, each addition individually reasonable.
const MAX_SECONDS := 20.0

## A rest, and a hit on an instrument that has no pitch. Both are written as tokens rather than
## as absences so a bar always says how long it is.
const REST := -2
const NOISE := -1

const PITCHES: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


## One note, already placed. `step` is ABSOLUTE from the first step of the track - see
## sample_at() for why that matters.
class Note:
	var step: int = 0
	var steps: int = 1
	var semitone: int = REST

	static func of(at: int, length: int, pitch: int) -> Note:
		var out := Note.new()
		out.step = at
		out.steps = length
		out.semitone = pitch
		return out


var id: StringName = &""
var bpm: int = 120
var beats_per_bar: int = 4
var steps_per_beat: int = 4
## Instrument name -> its shape: wave, gain, attack_ms, release_ms. The same vocabulary a cue
## shape uses, minus the parts a note supplies for itself.
var instruments: Dictionary = {}
## [{"instrument": StringName, "notes": Array[Note]}], in the order the file declares them -
## which is the order they are summed, so the mix is a fixed result rather than a set.
var voices: Array[Dictionary] = []
var _load_error := ""
var _bars: int = 0


## Every track this game has, sorted. The generator's work list and AudioBus's completeness
## list, the way Sfx.ids() is for cues - except that this one is DISCOVERED rather than named
## in an enum, because a cue is the template's own vocabulary and a track is a game's content.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path in ContentScan.files_of(DIR, "json"):
		out.append(StringName(path.get_file().get_basename()))
	return out


## The track named, or one carrying a load error. Never null: a caller reporting "track 'x'
## could not be read" beside its own context is more use than a null check.
static func load_from(track_id: StringName) -> MusicTrack:
	var track := MusicTrack.new()
	track.id = track_id
	var file := JsonFile.read("%s/%s.json" % [DIR, track_id])
	if not file.ok:
		track._load_error = "track '%s': %s" % [track_id, file.error]
		return track
	track.bpm = file.get_int("bpm", 120)
	track.beats_per_bar = file.get_int("beats_per_bar", 4)
	track.steps_per_beat = file.get_int("steps_per_beat", 4)
	var raw_instruments: Variant = file.data.get("instruments", {})
	if raw_instruments is Dictionary:
		for key: Variant in raw_instruments as Dictionary:
			var shape: Variant = (raw_instruments as Dictionary)[key]
			if shape is Dictionary:
				track.instruments[StringName(str(key))] = shape
	track._read_voices(file.get_array("voices"))
	return track


func _read_voices(raw: Array) -> void:
	for entry: Variant in raw:
		if not entry is Dictionary:
			continue
		var voice: Dictionary = entry
		var bars: Array = voice.get("bars", []) as Array
		_bars = maxi(_bars, bars.size())
		var notes: Array[Note] = []
		# How long each bar came out, kept PER BAR rather than as a running total. A running
		# total can only see the tune's whole length, where one short bar and one long one
		# cancel out - and everything between them is off the beat.
		var lengths: Array[int] = []
		var at := 0
		for bar: Variant in bars:
			var used := 0
			for token in str(bar).split(" ", false):
				var pair := token.split(":")
				var length := int(pair[1]) if pair.size() > 1 else 0
				notes.append(Note.of(at, length, semitone_of(pair[0])))
				at += length
				used += length
			lengths.append(used)
		voices.append({
			"instrument": StringName(str(voice.get("instrument", ""))),
			"bars": bars.size(),
			"lengths": lengths,
			"notes": notes,
		})


## The pitch a token names, as semitones above C0. -2 for a rest, -1 for a noise hit, -3 for
## a token this does not understand - which problems() reports rather than rendering silence,
## because a mistyped note that plays nothing is a bar that still sums correctly.
static func semitone_of(token: String) -> int:
	if token == "-":
		return REST
	if token == "x":
		return NOISE
	var name := token.substr(0, token.length() - 1)
	var octave := token.substr(token.length() - 1)
	if not octave.is_valid_int():
		return -3
	var index := PITCHES.find(name.to_upper())
	if index < 0:
		return -3
	return octave.to_int() * 12 + index


func steps_per_bar() -> int:
	return beats_per_bar * steps_per_beat


func bars() -> int:
	return _bars


func total_steps() -> int:
	return _bars * steps_per_bar()


## The first sample of a step, from its ABSOLUTE index. Never by adding one step's length to
## the last one's: a sixteenth at 22050/120/4 is 2756.25 samples, and rounding that per step
## walks the last bar of a tune off the beat by however much the error accumulated. Rounding
## once, here, from the absolute step means every boundary is at most half a sample out and
## never twice.
func sample_at(step: int, mix_rate: int) -> int:
	var per_beat := maxi(steps_per_beat, 1)
	return (step * mix_rate * 60) / maxi(bpm * per_beat, 1)


func total_samples(mix_rate: int) -> int:
	return sample_at(total_steps(), mix_rate)


func seconds() -> float:
	return float(total_steps() * 60) / float(maxi(bpm * maxi(steps_per_beat, 1), 1))


## Everything wrong with this track, all of it.
func problems() -> Array[String]:
	var out: Array[String] = []
	if not _load_error.is_empty():
		out.append(_load_error)
		return out
	# A track sharing a name with a cue would shadow it: AudioBus keeps one table for both, so
	# that a game can replace either by dropping a file into data/audio. One table is what makes
	# the override seam work and what makes this collision possible, so it is refused here.
	if Sfx.of(id) >= 0:
		out.append("track '%s' is named after a cue, which it would shadow" % id)
	if bpm < 20 or bpm > 400:
		out.append("track '%s' runs at %d bpm" % [id, bpm])
	if beats_per_bar < 1 or steps_per_beat < 1:
		out.append("track '%s' has a bar of %d beats of %d steps"
			% [id, beats_per_bar, steps_per_beat])
	if voices.is_empty():
		out.append("track '%s' has no voices" % id)
	if seconds() > MAX_SECONDS:
		out.append("track '%s' is %.1f seconds, past the %.0f this template renders - three "
			% [id, seconds(), MAX_SECONDS]
			+ "voices of it are committed, at 43 KB a second each")
	for voice: Dictionary in voices:
		out.append_array(_voice_problems(voice))
	return out


func _voice_problems(voice: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var name := StringName(str(voice.get("instrument", "")))
	if not instruments.has(name):
		out.append("track '%s' plays a voice on '%s', which it does not describe" % [id, name])
		return out
	if int(voice.get("bars", 0)) != _bars:
		out.append("track '%s' has a voice of %d bars where the longest is %d"
			% [id, int(voice.get("bars", 0)), _bars])
	var pitched := str((instruments[name] as Dictionary).get("wave", "tone")) != "noise"
	# Every bar, individually. A bar one step short and the next one step long sum correctly
	# over the whole tune and still walk everything between them off the beat.
	var lengths: Array[int] = voice.get("lengths", [] as Array[int])
	for bar in lengths.size():
		if lengths[bar] != steps_per_bar():
			out.append("track '%s' bar %d adds up to %d steps, not %d"
				% [id, bar + 1, lengths[bar], steps_per_bar()])
	for note: Note in voice.get("notes", []) as Array[Note]:
		if note.steps < 1:
			out.append("track '%s' has a note of %d steps" % [id, note.steps])
			return out
		if note.semitone == -3:
			out.append("track '%s' has a note this cannot read" % id)
		elif note.semitone == NOISE and pitched:
			out.append("track '%s' hits a pitched instrument" % id)
		elif note.semitone >= 0 and not pitched:
			out.append("track '%s' plays a note on an instrument with no pitch" % id)
		elif note.semitone >= 0 and (note.semitone < 12 or note.semitone > 108):
			out.append("track '%s' is outside the octaves this renders" % id)
	return out
