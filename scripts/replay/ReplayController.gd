extends Node3D
## Replay playback scene (SPEC.md §M5). Rebuilds the track, spawns physics-less
## "ghost" cars driven by recorded transforms, offers scrub/pause/slow-mo and the
## cycling replay cameras, and can save/reload the replay file. Root of
## Replay.tscn.

const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"
const CAR_SCENE := "res://scenes/vehicle/Car.tscn"

var _replay: Replay
var _player: ReplayPlayer
var _camera: ReplayCamera
var _ghosts: Array = []       # Array[ArcadeCar], index matches replay cars
var _focused: Node3D

var _status_label: Label
var _controls_label: Label
var _bar: ProgressBar
var _save_label: Label
var _save_timer: float = 0.0


func _ready() -> void:
	_replay = GameState.last_replay
	if _replay == null:
		_replay = Replay.load_from(Replay.latest_saved_path())

	_build_hud()

	if _replay == null or _replay.frame_count() < 2:
		_status_label.text = "No replay to show.\nFinish a race first (Race from the editor)."
		_add_static_camera()
		return

	TrackWorld.populate(self, GameState.current_grid, GameState.library)
	_spawn_ghosts()
	_build_camera()

	_player = ReplayPlayer.new()
	_player.replay = _replay


func _spawn_ghosts() -> void:
	for i in range(_replay.car_count()):
		var info: Dictionary = _replay.car_infos[i]
		var ghost: ArcadeCar = load(CAR_SCENE).instantiate()
		var model_path: String = info.get("model_path", "")
		if model_path != "":
			# Prefer the live roster profile (correct auto-fit); fall back to a stub
			# rebuilt from the recorded fields for a car no longer in the roster.
			var prof: CarProfile = GameState.profile_for_model(model_path)
			if prof == null:
				prof = CarProfile.new()
				prof.model_scene = load(model_path)
				prof.model_scale = info.get("model_scale", 1.0)
				prof.model_y_offset = info.get("model_y_offset", 0.0)
				prof.model_yaw = info.get("model_yaw", 0.0)
				prof.model_fit_width = info.get("model_fit_width", 0.0)
				prof.model_fit_length = info.get("model_fit_length", 0.0)
			ghost.profile = prof
		else:
			ghost.get_node("Visual").set("body_color", info.get("color", Color(0.8, 0.1, 0.12)))
		add_child(ghost)
		# Turn the car into a purely visual, transform-driven prop.
		ghost.set_physics_process(false)
		ghost.freeze = true
		ghost.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		ghost.global_transform = _replay.sample(i, 0.0)
		_ghosts.append(ghost)
		if info.get("is_player", false):
			_focused = ghost
	if _focused == null and not _ghosts.is_empty():
		_focused = _ghosts[0]


func _build_camera() -> void:
	_camera = ReplayCamera.new()
	_camera.current = true
	_camera.target = _focused
	_camera.trackside_points = _build_trackside_points()
	add_child(_camera)


func _build_trackside_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var path: Array[Vector2i] = RacePath.compute(GameState.current_grid, GameState.library)
	if path.is_empty():
		return points
	var waypoints: Array[Vector3] = []
	var centroid := Vector3.ZERO
	for cell in path:
		var wp := TileLibrary.cell_to_world(cell, GameState.current_grid.tiles[cell].elevation_level)
		waypoints.append(wp)
		centroid += wp
	centroid /= float(waypoints.size())
	for i in range(0, waypoints.size(), 2):
		var outward := waypoints[i] - centroid
		outward.y = 0.0
		if outward.length() < 1.0:
			outward = Vector3.FORWARD
		points.append(waypoints[i] + outward.normalized() * 10.0 + Vector3.UP * 6.0)
	return points


# --- Per-frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_label.text = ""

	if _player == null:
		return

	# Continuous scrub while an arrow key is held.
	if Input.is_physical_key_pressed(KEY_LEFT):
		_player.seek_frames(-_replay.fps * delta * 2.0)
	elif Input.is_physical_key_pressed(KEY_RIGHT):
		_player.seek_frames(_replay.fps * delta * 2.0)

	_player.advance(delta)
	for i in range(_ghosts.size()):
		_ghosts[i].global_transform = _player.sample(i)
	if _camera != null:
		_camera.update(delta)
	_update_hud()


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(EDITOR_SCENE)
		return
	if _player == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_player.toggle_play()
		KEY_C:
			_camera.cycle()
		KEY_R:
			_player.restart()
		KEY_UP:
			_player.cycle_speed(1)
		KEY_DOWN:
			_player.cycle_speed(-1)
		KEY_S:
			_do_save()
		KEY_L:
			_do_load()


func _do_save() -> void:
	var path := Replay.default_save_path()
	if _replay.save_to(path):
		_save_label.text = "Saved: %s" % path
	else:
		_save_label.text = "Save failed."
	_save_timer = 4.0


func _do_load() -> void:
	var path := Replay.latest_saved_path()
	var loaded := Replay.load_from(path)
	if loaded != null and loaded.frame_count() >= 2:
		_replay = loaded
		_player.replay = _replay
		_player.restart()
		_save_label.text = "Loaded: %s" % path
	else:
		_save_label.text = "No replay file to load."
	_save_timer = 4.0


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_status_label = Label.new()
	_status_label.position = Vector2(14, 12)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_status_label)

	_save_label = Label.new()
	_save_label.position = Vector2(14, 84)
	_save_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_save_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_save_label)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0001
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 14
	_bar.offset_right = -14
	_bar.offset_top = -46
	_bar.offset_bottom = -34
	layer.add_child(_bar)

	_controls_label = Label.new()
	_controls_label.text = "Space: play/pause   ←/→: scrub   ↑/↓: speed   C: camera   R: restart   S: save   L: load   Esc: editor"
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.offset_left = 14
	_controls_label.offset_top = -28
	_controls_label.offset_bottom = -6
	_controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_controls_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_controls_label)


func _update_hud() -> void:
	var t: float = _player.time / _replay.fps
	var dur: float = _replay.duration()
	var state: String = "PLAY" if _player.playing else "PAUSE"
	_status_label.text = "%s   %.1fx   %s cam\n%s / %s" % [
		state, _player.speed, _camera.mode_name(),
		LapTimer.format(t), LapTimer.format(dur)]
	_bar.value = _player.fraction()


func _add_static_camera() -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 20, 30)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)
