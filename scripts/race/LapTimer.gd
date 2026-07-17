class_name LapTimer
extends RefCounted
## Per-racer lap timing (SPEC.md §M4): current lap time, last lap, best lap.
## Times are in seconds against the shared race clock. -1 means "not set yet".

var current_lap_start: float = 0.0
var last_lap: float = -1.0
var best_lap: float = -1.0


func start(race_time: float) -> void:
	current_lap_start = race_time


func complete_lap(race_time: float) -> void:
	last_lap = race_time - current_lap_start
	if best_lap < 0.0 or last_lap < best_lap:
		best_lap = last_lap
	current_lap_start = race_time


func current(race_time: float) -> float:
	return race_time - current_lap_start


static func format(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.--"
	var minutes: int = int(seconds) / 60
	var secs: float = seconds - minutes * 60
	return "%d:%05.2f" % [minutes, secs]
