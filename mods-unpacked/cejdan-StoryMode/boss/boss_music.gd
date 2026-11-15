extends Node

# Music for the boss sequence: the mod's own score (#172), written by
# art/music/score.py into music/boss_<cue>_<layer>.ogg. Each cue is a loop in
# layers that start together and stay in step; the director turns layers up
# and down with the fight:
#
#   fight    1 the pulse alone in phase 1; 2 war drums and brass join in
#            phase 2; 3 Velle's theme, choir and crashes on top in phase 3.
#   chase    1 the run; 2 what is behind you, louder the closer the
#            tentacles are.
#   finale   both layers, full.
#
# The mining music is held off while any of this plays, and everything fades
# when the sequence ends (the endings bring their own music). The OGGs are
# read from their bytes, like the mod's PNGs, so they need no import step.

const DIR := "res://mods-unpacked/cejdan-StoryMode/music/"
const CUES := {"fight": 3, "chase": 2, "finale": 2}
const SILENT := -60.0
const FADE_DB_PER_S := 30.0
# Layer volumes (dB) per state.
const FIGHT := [[2.0, SILENT, SILENT], [0.0, 0.0, SILENT], [0.0, 0.0, 0.0]]
const CHASE_FAR := -16.0
const FINALE := [0.0, 0.0]

static var _streams: Dictionary = {}   # path -> AudioStreamOggVorbis

var cues: Dictionary = {}    # cue -> [AudioStreamPlayer, ...]
var goals: Dictionary = {}   # cue -> [dB, ...]
var mode: String = ""        # "", fight, chase, finale
var _hold_t: float = 0.0


func _ready() -> void:
	name = "BossMusic"


static func stream(cue: String, layer: int) -> AudioStream:
	var path: String = DIR + "boss_%s_%d.ogg" % [cue, layer]
	if not _streams.has(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var s: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_buffer(bytes) if not bytes.is_empty() else null
		if s == null:
			push_error("StoryMode: missing or bad music file " + path)
		else:
			s.loop = true
			s.resource_name = path.get_file()
		_streams[path] = s
	return _streams[path]


# Starts every layer of `cue` together, silent; the goals bring them in.
func _start(cue: String) -> void:
	if mode == cue:
		return
	if mode != "":
		goals[mode] = _silence(mode)
	mode = cue
	if not cues.has(cue):
		var list: Array = []
		for i in CUES[cue]:
			var p := AudioStreamPlayer.new()
			p.bus = &"Music"
			p.volume_db = SILENT
			p.stream = stream(cue, i + 1)
			add_child(p)
			list.append(p)
		cues[cue] = list
	for p: AudioStreamPlayer in cues[cue]:
		if p.stream != null:
			p.volume_db = SILENT
			p.play()
	goals[cue] = _silence(cue)


func _silence(cue: String) -> Array:
	var out: Array = []
	for i in CUES[cue]:
		out.append(SILENT)
	return out


# The chamber fight; `phase` 0..2.
func fight(phase: int) -> void:
	_start("fight")
	goals["fight"] = FIGHT[clampi(phase, 0, 2)].duplicate()


# The chase; `closeness` 0 (far behind) .. 1 (on the keeper).
func chase(closeness: float) -> void:
	_start("chase")
	goals["chase"] = [0.0, lerpf(CHASE_FAR, 0.0, clampf(closeness, 0.0, 1.0))]


func finale() -> void:
	_start("finale")
	goals["finale"] = FINALE.duplicate()


func stop() -> void:
	if mode != "":
		goals[mode] = _silence(mode)
	mode = ""


# What is audible now, for playtests: file names, volumes and play positions.
func playing() -> Array:
	var out: Array = []
	for cue: String in cues:
		for p: AudioStreamPlayer in cues[cue]:
			if p.playing and p.volume_db > -40.0 and p.stream != null:
				out.append({"file": p.stream.resource_name, "db": snappedf(p.volume_db, 0.1), "pitch": p.pitch_scale, "pos": snappedf(p.get_playback_position(), 0.01)})
	return out


func _process(delta: float) -> void:
	for cue: String in cues:
		var g: Array = goals.get(cue, _silence(cue))
		var all_out: bool = true
		for i in cues[cue].size():
			var p: AudioStreamPlayer = cues[cue][i]
			if not p.playing:
				continue
			p.volume_db = move_toward(p.volume_db, g[i], FADE_DB_PER_S * delta)
			all_out = all_out and g[i] <= SILENT and p.volume_db <= SILENT + 0.5
		# A cue that has faded right out stops.
		if all_out:
			for p: AudioStreamPlayer in cues[cue]:
				p.stop()
	if mode == "":
		return
	# The mining music steps aside.
	_hold_t -= delta
	if _hold_t <= 0.0:
		_hold_t = 0.5
		if Audio.isMusicPlaying():
			Audio.stopMusic(0.0, 1.5)
