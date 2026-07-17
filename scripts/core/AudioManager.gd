extends Node
## Audio autoload (SPEC.md §M6): sets up an SFX and Music bus, holds the shared
## procedurally-generated streams, plays one-shot impacts, and persists volume
## settings.

const CONFIG_PATH := "user://settings.cfg"

## Typed as the base AudioStream, not AudioStreamWAV — they hold either the
## synthesized WAV fallback or a loaded mp3/ogg/wav file.
var engine_stream: AudioStream
var skid_stream: AudioStream
var impact_stream: AudioStream
var warning_stream: AudioStream

var _warning_player: AudioStreamPlayer

## Music: every .mp3 in AUDIO_DIR becomes a track, shuffled and played back to back
## on the Music bus across menus and races. Silenced when the Music volume is off.
var _music_player: AudioStreamPlayer
var _music: Array[AudioStream] = []
var _music_index: int = -1


## Where to drop replacement sound files. A file here overrides the synthesized
## fallback with the same name — engine.ogg, skid.ogg, impact.ogg, warning.ogg
## (.wav also accepted). Engine, skid and warning must be seamless loops.
const AUDIO_DIR := "res://assets/audio"


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	# Each falls back to the code-synthesized stream until a file is supplied.
	engine_stream = _load_sound("engine", true, SoundBank.engine())
	skid_stream = _load_sound("skid", true, SoundBank.skid())
	impact_stream = _load_sound("impact", false, SoundBank.impact())
	warning_stream = _load_sound("warning", true, SoundBank.warning())
	_warning_player = AudioStreamPlayer.new()
	_warning_player.stream = warning_stream
	_warning_player.bus = "SFX"
	add_child(_warning_player)
	load_settings()
	_setup_music()  # after load_settings, so the saved Music volume is applied first


## Start/stop the looping off-track warning beep.
func set_warning(active: bool) -> void:
	if active and not _warning_player.playing:
		_warning_player.play()
	elif not active and _warning_player.playing:
		_warning_player.stop()


# --- Music ------------------------------------------------------------------

## Basenames reserved for sound effects — never treated as music, whatever their
## extension, so an mp3 engine/skid/crash clip in AUDIO_DIR isn't played as a song.
const SFX_NAMES := ["engine", "skid", "impact", "warning"]


## Collect the music tracks (every audio file in AUDIO_DIR that ISN'T a reserved
## SFX name) and start playback. One player on the Music bus, added to this
## autoload, so the music carries seamlessly from menu into a race.
func _setup_music() -> void:
	var dir := DirAccess.open(AUDIO_DIR)
	if dir != null:
		for f in dir.get_files():
			var low := f.to_lower()
			if not (low.ends_with(".mp3") or low.ends_with(".ogg") or low.ends_with(".wav")):
				continue
			if f.get_basename().to_lower() in SFX_NAMES:
				continue  # that's a sound effect, not a track
			var s: AudioStream = load("%s/%s" % [AUDIO_DIR, f])
			if s != null:
					if s is AudioStreamMP3:
						(s as AudioStreamMP3).loop = false  # advance to the next track, don't repeat
					_music.append(s)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_play_next_track)
	add_child(_music_player)
	_update_music()


func _play_next_track() -> void:
	if _music.is_empty():
		return
	var idx: int = _music_index
	if _music.size() > 1:
		while idx == _music_index:  # random, but never the same track twice running
			idx = randi() % _music.size()
	else:
		idx = 0
	_music_index = idx
	_music_player.stream = _music[idx]
	_music_player.play()


## Play while the Music volume is up, stop when it is off. Called on startup and
## whenever the Music slider changes.
func _update_music() -> void:
	if _music_player == null:
		return
	var wanted: bool = not _music.is_empty() and get_volume("Music") > 0.02
	if wanted and not _music_player.playing:
		_play_next_track()
	elif not wanted and _music_player.playing:
		_music_player.stop()


## Load `name`.ogg / `name`.wav from AUDIO_DIR if present, else use `fallback`.
## When `loop`, the returned stream is forced to loop so it plays seamlessly (the
## importer's own loop flag is easy to forget, so we set it here regardless).
func _load_sound(name: String, loop: bool, fallback: AudioStream) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var path := "%s/%s.%s" % [AUDIO_DIR, name, ext]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream != null:
				_apply_loop(stream, loop)
				return stream
	return fallback


func _apply_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamWAV and loop:
		var w := stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# --- Volume (linear 0..1) ---------------------------------------------------

func set_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	if bus_name == "Music":
		_update_music()  # start when turned up, stop when turned to zero


func get_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


# --- One-shots --------------------------------------------------------------

func play_impact(strength: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = impact_stream
	p.bus = "SFX"
	p.volume_db = linear_to_db(clampf(strength, 0.2, 1.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# --- Settings persistence ---------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", get_volume("Master"))
	cfg.set_value("audio", "sfx", get_volume("SFX"))
	cfg.set_value("audio", "music", get_volume("Music"))
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		set_volume("Master", cfg.get_value("audio", "master", 1.0))
		set_volume("SFX", cfg.get_value("audio", "sfx", 0.9))
		set_volume("Music", cfg.get_value("audio", "music", 0.6))
	else:
		set_volume("SFX", 0.9)
		set_volume("Music", 0.6)
