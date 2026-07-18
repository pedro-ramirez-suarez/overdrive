extends Node3D
## Race orchestration (SPEC.md §M4): build the track, spawn the player and AI on
## the start grid, run a countdown, count laps via ordered checkpoints, handle
## respawns and standings, and show a results screen. Root of Race.tscn.

const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"
const REPLAY_SCENE := "res://scenes/replay/Replay.tscn"
const CAR_SCENE := "res://scenes/vehicle/Car.tscn"
const CHASE_CAM := "res://scripts/vehicle/ChaseCamera.gd"

const CAR_COLORS: Array[Color] = [
	Color(0.85, 0.11, 0.13),  # player - red
	Color(0.15, 0.45, 0.85),  # blue
	Color(0.20, 0.70, 0.30),  # green
	Color(0.95, 0.75, 0.15),  # amber
	Color(0.60, 0.25, 0.75),  # purple
	Color(0.90, 0.45, 0.15),  # orange
]

enum Phase { COUNTDOWN, RACING, FINISHED }

var _phase: Phase = Phase.COUNTDOWN
var _laps_total: int = 3
var _countdown: float = 3.0
var _race_time: float = 0.0
var _finish_counter: int = 0

var _path: Array[Vector2i] = []
var _waypoints: PackedVector3Array = PackedVector3Array()
var _checkpoints: Array[Checkpoint] = []
var _racers: Array[Racer] = []
var _ai: Array[AIController] = []
var _player: Racer
var _player_position: int = 1
var _recorder: ReplayRecorder = ReplayRecorder.new()

# HUD
var _countdown_label: Label
var _info_label: Label
var _results_label: Label
var _quit_dialog: Control
var _minimap: MiniMap


func _ready() -> void:
	var grid: TrackGrid = GameState.current_grid
	var lib: TileLibrary = GameState.library
	_laps_total = maxi(1, GameState.race_laps)

	TrackWorld.populate(self, grid, lib)
	_build_hud()

	_path = RacePath.compute(grid, lib)
	if _path.size() < 2:
		_add_camera(Vector3(0, 20, 30))
		_results_label.text = "This track has no drivable loop yet.\nBuild a connected circuit with a Start tile.\n\nEsc: go back"
		_results_label.visible = true
		_minimap.visible = false  # nothing to map
		_phase = Phase.FINISHED
		return

	_build_waypoints(grid)
	_build_track_points(grid)
	_create_checkpoints()
	_spawn_racers(grid, lib)
	if _minimap != null:
		_minimap.setup(_track_points, _racers)
	_add_camera(Vector3(0, 4, 12))
	_set_active(false)


# --- Setup ------------------------------------------------------------------

func _build_waypoints(grid: TrackGrid) -> void:
	_waypoints = PackedVector3Array()
	for cell in _path:
		_waypoints.append(TileLibrary.cell_to_world(cell, grid.tiles[cell].elevation_level))


func _create_checkpoints() -> void:
	for i in range(_path.size()):
		var cp := Checkpoint.new()
		cp.setup(i, _waypoints[i], Constants.CELL_SIZE)
		cp.passed.connect(_on_checkpoint_passed)
		cp.exited.connect(_on_checkpoint_exited)
		add_child(cp)
		_checkpoints.append(cp)


func _spawn_racers(grid: TrackGrid, lib: TileLibrary) -> void:
	var count: int = 1 + maxi(0, GameState.race_ai_count)
	var forward: Vector3 = _forward_at(0)
	var right: Vector3 = Vector3.UP.cross(forward).normalized()
	var ai_profiles := _random_ai_profiles(count - 1)

	for i in range(count):
		var is_player: bool = (i == 0)
		var row: int = i / 2
		var col: int = i % 2
		var offset: Vector3 = right * (col * 3.2 - 1.6) - forward * (row * 4.5 + 4.0)
		var spawn: Vector3 = _waypoints[0] + offset + Vector3(0, 1.4, 0)

		var profile: CarProfile = GameState.selected_car if is_player else ai_profiles[i - 1]
		var color: Color = profile.body_color if is_player else CAR_COLORS[i % CAR_COLORS.size()]
		var car: ArcadeCar = load(CAR_SCENE).instantiate()
		car.name = "Player" if is_player else "AI%d" % i
		car.player_controlled = is_player
		car.self_reset_enabled = false
		if profile != null:
			car.profile = profile
		car.get_node("Visual").set("body_color", color)
		add_child(car)
		car.respawn(spawn, forward)

		var racer := Racer.new()
		racer.car = car
		racer.is_player = is_player
		racer.color = color
		racer.display_name = "You" if is_player else "CPU %d" % i
		racer.last_checkpoint_pos = spawn
		racer.last_checkpoint_forward = forward
		_racers.append(racer)

		if is_player:
			_player = racer
		else:
			var ai := AIController.new()
			ai.car = car
			ai.waypoints = _waypoints
			ai.target_index = 1 % _waypoints.size()
			add_child(ai)
			_ai.append(ai)


## Pick `n` random cars from the roster for the opponents (distinct while the
## roster lasts, then repeating).
func _random_ai_profiles(n: int) -> Array:
	randomize()
	var pool: Array = GameState.roster.duplicate()
	pool.shuffle()
	var out: Array = []
	for i in range(n):
		out.append(pool[i % pool.size()])
	return out


func _add_camera(pos: Vector3) -> void:
	var cam := Camera3D.new()
	cam.set_script(load(CHASE_CAM))
	cam.current = true
	if _player != null:
		cam.set("target_path", _player.car.get_path())
	cam.position = pos
	add_child(cam)


# --- Phases -----------------------------------------------------------------

func _process(delta: float) -> void:
	match _phase:
		Phase.COUNTDOWN:
			_countdown -= delta
			_update_countdown_hud()
			if _countdown <= 0.0:
				_start_race()
		Phase.RACING:
			_race_time += delta
			_update_offroute_penalty()
			_update_rubberband()
			_check_respawns(delta)
			_update_ranks()
			_update_hud()
		Phase.FINISHED:
			pass


func _physics_process(_delta: float) -> void:
	if _phase == Phase.RACING:
		_recorder.capture()


func _start_race() -> void:
	_phase = Phase.RACING
	_race_time = 0.0
	for r in _racers:
		r.timer.start(0.0)
	_recorder.start(_racers)
	_set_active(true)
	_countdown_label.text = "GO!"


func _set_active(active: bool) -> void:
	if _player != null:
		_player.car.control_enabled = active
	for ai in _ai:
		ai.active = active


# --- Checkpoints & laps -----------------------------------------------------

func _on_checkpoint_passed(index: int, body: Node3D) -> void:
	var r := _racer_for_body(body)
	if r == null or r.finished or _phase != Phase.RACING:
		return

	# Crossing the finish line always counts a lap once we've left and returned —
	# no checkpoint-order gate (shortcuts are penalized by speed, not lap denial).
	if index == 0 and r.left_finish:
		r.left_finish = false
		_complete_lap(r)
		return

	# In-order checkpoint: advances ranking progress and the respawn point.
	if index == r.expected_next:
		r.cp_this_lap += 1
		r.expected_next = (index + 1) % _path.size()
		r.last_checkpoint_pos = _waypoints[index] + Vector3(0, 1.4, 0)
		r.last_checkpoint_forward = _forward_at(index)


func _on_checkpoint_exited(index: int, body: Node3D) -> void:
	if index != 0:
		return
	var r := _racer_for_body(body)
	if r != null:
		r.left_finish = true


func _complete_lap(r: Racer) -> void:
	r.lap += 1
	r.cp_this_lap = 0
	r.expected_next = 1
	r.timer.complete_lap(_race_time)
	if r.lap >= _laps_total:
		r.finished = true
		r.finish_time = _race_time
		_finish_counter += 1
		r.finish_rank = _finish_counter
		if r.is_player:
			_finish_race()


func _finish_race() -> void:
	_phase = Phase.FINISHED
	if _player != null:
		_player.car.control_enabled = false
	for ai in _ai:
		ai.active = false
	AudioManager.set_warning(false)
	GameState.last_replay = _recorder.replay
	_show_results()


# --- Respawns ---------------------------------------------------------------

func _check_respawns(delta: float) -> void:
	var terrain: Terrain = GameState.current_terrain
	for r in _racers:
		if r.finished:
			continue
		var car := r.car
		var upright: float = car.global_transform.basis.y.dot(Vector3.UP)
		var slow: bool = car.linear_velocity.length() < 2.0
		# Drowning is per-cell: a lake can sit on a plateau, so there is no single
		# water height to test against any more. Cars on the track are exempt — a
		# road may legitimately bridge a lake, and it clears the water by inches.
		var in_lake := false
		if terrain != null and not car.on_track:
			var cell := Vector2i(
				roundi(car.global_position.x / Constants.CELL_SIZE),
				roundi(car.global_position.z / Constants.CELL_SIZE))
			if terrain.is_water(cell):
				in_lake = car.global_position.y < terrain.water_surface(cell) + 0.6
		if car.global_position.y < -8.0 or in_lake:
			_respawn(r)
		elif upright < 0.2 and slow:
			r.stuck_time += delta
			if r.stuck_time > 2.5:
				_respawn(r)
		else:
			r.stuck_time = 0.0
			# An AI car wedged upright (against a wall, scenery, another car) never
			# trips the flipped check above, so it can sit there forever. If a CPU
			# car barely moves for a few seconds while racing, put it back on the
			# line. Not applied to the player — they may stop on purpose and have R.
			if not r.is_player and car.linear_velocity.length() < 1.5:
				r.slow_time += delta
				if r.slow_time > 3.0:
					_respawn(r)
			else:
				r.slow_time = 0.0


func _respawn(r: Racer) -> void:
	r.stuck_time = 0.0
	r.slow_time = 0.0
	r.car.respawn(r.last_checkpoint_pos, r.last_checkpoint_forward)


## How many waypoints back along the racing line R puts you.
##
## Not the checkpoint you last passed: waypoints sit one per tile, so that point is
## typically a meter or two behind the car. Respawning exactly there moves nothing
## and only zeroes your speed — it reads as an instant brake rather than a reset.
## Three tiles back is a visible reposition with room to get going again.
const RESET_BACKTRACK := 3


## R during a race: back onto the racing line, upright, facing the right way, with
## a short run-up. Keyed off the NEAREST waypoint rather than checkpoint
## bookkeeping, so it works even if you are flung far off the track — which is
## exactly when it is wanted.
func _manual_reset(r: Racer) -> void:
	if _waypoints.is_empty():
		r.car.reset_to_safe()
		return
	var idx: int = _nearest_waypoint_index(r.car.global_position)
	idx = posmod(idx - RESET_BACKTRACK, _waypoints.size())
	r.stuck_time = 0.0
	r.car.respawn(_waypoints[idx] + Vector3(0, 1.4, 0), _forward_at(idx))


func _nearest_waypoint_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in range(_waypoints.size()):
		var d: float = Vector2(pos.x - _waypoints[i].x, pos.z - _waypoints[i].z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Ranking ----------------------------------------------------------------

# Straying far from the TRACK slows the car toward 5% of max speed and warns the
# player, but never denies the lap (SPEC.md §M6).
#
# Measured against the track itself, not the racing line. The line is one path
# through the track and says nothing about how wide it is: a multi-cell tile
# contributes a single line point but covers up to nine cells, so a car driving
# perfectly across a banked curve reads as tens of meters "off route". The
# question this asks is "have you left the road", so it measures the road.
#
# A cell centre is at most 5.7 m from anywhere on its own cell, so the lenience
# below leaves roughly 5 m of genuine off-track roaming before anything bites.
const OFFROUTE_LENIENT := 11.0    # meters off the track you may roam freely
const OFFROUTE_MAX := 45.0        # at/beyond this, the full penalty applies
const OFFROUTE_MIN_FRAC := 0.05

## Centre of every cell the track occupies — including each multi-cell tile's
## interior, which the racing line never visits.
var _track_points: PackedVector3Array = PackedVector3Array()


func _build_track_points(grid: TrackGrid) -> void:
	_track_points = PackedVector3Array()
	for anchor in grid.tiles:
		var placed: PlacedTile = grid.tiles[anchor]
		var def: TileDefinition = grid.get_def(anchor)
		if def == null:
			continue
		for c in TrackGrid.footprint_cells(anchor, def, placed.rotation):
			_track_points.append(TileLibrary.cell_to_world(c, placed.elevation_level))


func _update_offroute_penalty() -> void:
	var player_penalized := false
	for r in _racers:
		if r.finished:
			r.car.external_speed_frac = 1.0
			continue
		var dist := _distance_from_track(r.car.global_position)
		var t := clampf((dist - OFFROUTE_LENIENT) / (OFFROUTE_MAX - OFFROUTE_LENIENT), 0.0, 1.0)
		r.car.external_speed_frac = lerpf(1.0, OFFROUTE_MIN_FRAC, t)
		if r.is_player and t > 0.02:
			player_penalized = true
	AudioManager.set_warning(player_penalized)


## Horizontal distance to the nearest piece of track. Horizontal only: the top of
## a loop is 24 m up but is still very much on the road.
func _distance_from_track(pos: Vector3) -> float:
	var best := INF
	for p in _track_points:
		best = minf(best, Vector2(pos.x - p.x, pos.z - p.z).length_squared())
	return sqrt(best) if best < INF else 0.0


func _update_rubberband() -> void:
	for ai in _ai:
		var racer := _racer_for_body(ai.car)
		if racer == null or _player == null:
			continue
		ai.speed_factor = 1.08 if _progress(racer) < _progress(_player) else 0.94


func _update_ranks() -> void:
	var order := _racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool: return _progress(a) > _progress(b))
	for i in range(order.size()):
		if order[i] == _player:
			_player_position = i + 1
			break


func _progress(r: Racer) -> float:
	if r.finished:
		return 1.0e9 - r.finish_rank
	# Laps dominate; in-order checkpoints this lap break ties (so a clean racer
	# outranks a shortcutter on the same lap).
	var n: int = maxi(_path.size(), 1)
	return float(r.lap) + float(r.cp_this_lap) / float(n)


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# A styled pause menu, so it matches the rest of the UI and a controller can
	# drive it. The race keeps running behind it, paused; it processes while paused
	# and unpauses when it closes.
	var back_label: String = "Back to Editor" if GameState.return_scene.ends_with("Editor.tscn") else "Leave Race"
	_quit_dialog = MenuUI.menu_overlay("Paused", [
		{"text": "Resume", "cb": _close_pause, "primary": true},
		{"text": back_label, "cb": func() -> void:
			get_tree().paused = false
			get_tree().change_scene_to_file(GameState.return_scene), "icon": "back"},
		{"text": "Exit Game", "cb": func() -> void: get_tree().quit(), "icon": "exit"},
	])
	layer.add_child(_quit_dialog)

	# Track map in the bottom-right corner.
	_minimap = MiniMap.new()
	var map_size := 190.0
	var map_margin := 16.0
	_minimap.custom_minimum_size = Vector2(map_size, map_size)
	_minimap.anchor_left = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = -(map_size + map_margin)
	_minimap.offset_top = -(map_size + map_margin)
	_minimap.offset_right = -map_margin
	_minimap.offset_bottom = -map_margin
	layer.add_child(_minimap)

	_info_label = Label.new()
	_info_label.position = Vector2(14, 12)
	_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_info_label.add_theme_constant_override("outline_size", 4)
	_info_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_info_label)

	_countdown_label = Label.new()
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.35
	_countdown_label.offset_left = -100
	_countdown_label.offset_right = 100
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.add_theme_font_size_override("font_size", 72)
	layer.add_child(_countdown_label)

	_results_label = Label.new()
	_results_label.anchor_left = 0.5
	_results_label.anchor_top = 0.3
	_results_label.offset_left = -220
	_results_label.offset_right = 220
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_results_label.add_theme_constant_override("outline_size", 5)
	_results_label.add_theme_font_size_override("font_size", 26)
	_results_label.visible = false
	layer.add_child(_results_label)

	var hint := Label.new()
	hint.text = "Esc: editor    R: respawn"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 14
	hint.offset_top = -34
	hint.offset_bottom = -8
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(hint)


func _update_countdown_hud() -> void:
	_countdown_label.text = str(ceili(_countdown))


func _update_hud() -> void:
	if _countdown_label.text == "GO!" and _race_time > 1.2:
		_countdown_label.text = ""
	if _player == null:
		return
	var lap_display: int = mini(_player.lap + 1, _laps_total)
	_info_label.text = "P%d/%d    Lap %d/%d\nTime  %s\nBest  %s" % [
		_player_position, _racers.size(), lap_display, _laps_total,
		LapTimer.format(_player.timer.current(_race_time)),
		LapTimer.format(_player.timer.best_lap)]


func _show_results() -> void:
	_countdown_label.text = ""
	var order := _racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool: return _progress(a) > _progress(b))
	var lines: Array[String] = ["FINISH"]
	for i in range(order.size()):
		var r: Racer = order[i]
		var time_text: String = LapTimer.format(r.finish_time) if r.finished else "DNF"
		lines.append("%d.  %s   %s   best %s" % [
			i + 1, r.display_name, time_text, LapTimer.format(r.timer.best_lap)])
	lines.append("")
	lines.append("Enter: watch replay      Esc: leave race")
	_results_label.text = "\n".join(lines)
	_results_label.visible = true


# --- Helpers & input --------------------------------------------------------

func _close_pause() -> void:
	_quit_dialog.hide()
	get_tree().paused = false


func _racer_for_body(body: Node) -> Racer:
	for r in _racers:
		if r.car == body:
			return r
	return null


func _forward_at(index: int) -> Vector3:
	if _waypoints.size() < 2:
		return Vector3.FORWARD
	var next_index: int = (index + 1) % _waypoints.size()
	var dir: Vector3 = _waypoints[next_index] - _waypoints[index]
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


func _exit_tree() -> void:
	AudioManager.set_warning(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Toggle the pause menu (Resume / leave / exit game). Openable and operable
		# with a controller now that ui_cancel carries a joypad button.
		if _quit_dialog.visible:
			_close_pause()
		else:
			get_tree().paused = true
			_quit_dialog.show()
	elif event.is_action_pressed("ui_accept") and _phase == Phase.FINISHED and GameState.last_replay != null:
		get_tree().change_scene_to_file(REPLAY_SCENE)
	elif event.is_action_pressed("reset_car") and _phase == Phase.RACING and _player != null:
		_manual_reset(_player)
