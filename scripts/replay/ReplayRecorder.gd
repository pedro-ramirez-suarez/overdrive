class_name ReplayRecorder
extends RefCounted
## Records per-car transform snapshots into a Replay during a race (SPEC.md §M5).
## Driven from RaceManager's physics step.

var replay: Replay
var _cars: Array = []  # Array[ArcadeCar], index matches replay car order.

## Safety cap so a long/abandoned race can't grow the buffer forever (~4 min).
var max_frames: int = 60 * 240


func start(racers: Array) -> void:
	replay = Replay.new()
	replay.fps = float(Engine.physics_ticks_per_second)
	_cars = []
	var infos: Array = []
	for r in racers:
		_cars.append(r.car)
		var profile: CarProfile = r.car.profile
		var has_model: bool = profile != null and profile.model_scene != null
		infos.append({
			"name": r.display_name, "is_player": r.is_player, "color": r.color,
			"model_path": profile.model_scene.resource_path if has_model else "",
			"model_scale": profile.model_scale if profile != null else 1.0,
			"model_y_offset": profile.model_y_offset if profile != null else 0.0,
			"model_yaw": profile.model_yaw if profile != null else 0.0,
			# The auto-fit fields matter too: without them a model that is sized by
			# fit (the hero cars) falls back to model_scale and renders at raw size.
			"model_fit_width": profile.model_fit_width if profile != null else 0.0,
			"model_fit_length": profile.model_fit_length if profile != null else 0.0,
		})
	replay.init_cars(infos)


func capture() -> void:
	if replay == null or replay.frame_count() >= max_frames:
		return
	for i in range(_cars.size()):
		replay.capture(i, _cars[i].global_transform)
