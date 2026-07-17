class_name CarAudio
extends Node3D
## Per-car engine + tyre audio (SPEC.md §M6). Attached under a Car; drives a
## looping engine tone (pitch scaled by speed) and a tyre-screech loop while
## drifting. Speed is derived from position delta so it also works for the
## transform-driven ghost cars in replays.

var _car: ArcadeCar
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _last_pos: Vector3


func _ready() -> void:
	_car = get_parent() as ArcadeCar
	_last_pos = global_position

	_engine = _make_player(AudioManager.engine_stream, 12.0)
	_engine.play()
	_skid = _make_player(AudioManager.skid_stream, 9.0)


func _make_player(stream: AudioStream, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = unit_size
	p.max_distance = 120.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	if _car == null:
		return
	var pos := global_position
	var speed: float = (pos - _last_pos).length() / maxf(delta, 0.0001)
	_last_pos = pos

	var max_speed: float = _car.profile.max_speed if _car.profile != null else 55.0
	var ratio: float = clampf(speed / max_speed, 0.0, 1.4)
	_engine.pitch_scale = 0.7 + ratio * 1.5
	_engine.volume_db = lerpf(-14.0, -3.0, clampf(ratio, 0.0, 1.0))

	var drifting := false
	if _car.grounded:
		var lateral: float = absf(_car.linear_velocity.dot(_car.global_transform.basis.x))
		drifting = lateral > 4.0 or _car.handbrake
	if drifting and not _skid.playing:
		_skid.play()
	elif not drifting and _skid.playing:
		_skid.stop()
