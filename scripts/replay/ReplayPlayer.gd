class_name ReplayPlayer
extends RefCounted
## Playback clock for a Replay (SPEC.md §M5): play/pause, scrub, slow-mo,
## restart. `time` is measured in (fractional) frames.

var replay: Replay
var time: float = 0.0
var speed: float = 1.0
var playing: bool = true

const SPEEDS: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0]
var _speed_index: int = 3


func total_frames() -> int:
	return replay.frame_count()


func advance(delta: float) -> void:
	if not playing or replay == null:
		return
	var last: float = float(maxi(total_frames() - 1, 0))
	time += delta * replay.fps * speed
	if time >= last:
		time = last
		playing = false  # stop at the end
	time = maxf(time, 0.0)


func toggle_play() -> void:
	if not playing and time >= float(total_frames() - 1):
		time = 0.0  # replaying from the end restarts
	playing = not playing


func restart() -> void:
	time = 0.0
	playing = true


func seek_frames(frames: float) -> void:
	time = clampf(time + frames, 0.0, float(maxi(total_frames() - 1, 0)))


func seek_fraction(frac: float) -> void:
	time = clampf(frac, 0.0, 1.0) * float(maxi(total_frames() - 1, 0))


func fraction() -> float:
	var last: int = total_frames() - 1
	return time / float(last) if last > 0 else 0.0


func cycle_speed(direction: int) -> void:
	_speed_index = clampi(_speed_index + direction, 0, SPEEDS.size() - 1)
	speed = SPEEDS[_speed_index]


func sample(index: int) -> Transform3D:
	return replay.sample(index, time)
