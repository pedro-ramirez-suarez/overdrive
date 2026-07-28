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
## Sticky cursor: which route waypoint the player is currently at. Only ever moved
## a few steps at a time (see _track_player_progress), so on a track that passes
## near itself it can't snap to a horizontally-closer waypoint elsewhere on the lap.
var _player_wp: int = 0
## Distance (meters) from the car to its cursor waypoint. When the cursor is stranded
## — e.g. on a return stretch that has no waypoints of its own and passes near an
## unrelated leg — this grows huge, and the wrong-way check ignores the reading rather
## than trust a "forward" direction from a waypoint the car isn't actually near.
var _player_wp_dist: float = 0.0
## How long the wrong-way condition has held; the warning only shows after a beat,
## so a slope or a bump can't flash it.
var _wrongway_time: float = 0.0

## Cumulative route length up to each waypoint, and the total, in meters — used to
## turn positions into an along-route distance for live time gaps and medals.
var _wp_cum: PackedFloat32Array = PackedFloat32Array()
var _route_len: float = 0.0

## Waypoint indices that sit on a loop tile — handed to the AI so it drives up and
## over instead of cutting across the base.
var _loop_flags: Dictionary = {}

## "Beat your best" ghost: a translucent, transform-driven car replaying the best
## recorded run of this track, and the replay that drives it.
var _ghost_car: ArcadeCar
var _ghost_replay: Replay

# HUD
var _countdown_label: Label
var _info_label: Label
var _results_label: Label
var _results_panel: Control
var _wrongway_label: Label
var _speed_lines: ColorRect
var _speedo: Speedometer
## Controls hint, shown briefly at the start then faded out (it only distracts once
## you know the keys).
var _hint_label: Label
var _hint_time_left: float = 8.0
var _quit_dialog: Control
var _minimap: MiniMap

## Radial "wind streak" overlay shader — faint white streaks that stream outward
## from the centre, their strength driven by speed, so flat-out driving feels fast.
## Center is kept clear so it never obscures the road ahead.
const SPEED_LINES_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
float hash(float x) { return fract(sin(x * 12.9898) * 43758.5453); }
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.7; // widen so streaks fan across the screen, not a circle
	float r = length(uv);
	float ang = atan(uv.y, uv.x);
	float slice = floor(ang * 34.0);
	float pick = step(0.72, hash(slice));            // only some angular slices streak
	float flow = fract(r * 2.2 - TIME * 2.6 + hash(slice) * 6.0);
	float streak = smoothstep(0.55, 1.0, flow) * pick;
	float mask = smoothstep(0.18, 0.7, r);            // clear the middle of the view
	COLOR = vec4(vec3(1.0), streak * mask * intensity * 0.35);
}
"""


func _ready() -> void:
	var grid: TrackGrid = GameState.current_grid
	var lib: TileLibrary = GameState.library
	_laps_total = maxi(1, GameState.race_laps)

	TrackWorld.populate(self, grid, lib)
	_build_hud()

	_path = RacePath.compute(grid, lib)
	if _path.size() < 2:
		_add_camera(Vector3(0, 20, 30))
		_show_results_text("This track has no drivable loop yet.\nBuild a connected circuit with a Start tile.\n\nEsc: go back")
		_minimap.visible = false  # nothing to map
		_phase = Phase.FINISHED
		return

	# Wrong-way mode: keep the start cell first but walk the rest of the loop the
	# other way round, so waypoints, checkpoints, spawn heading and the AI all follow
	# the reversed route.
	if GameState.race_reversed and _path.size() > 2:
		var tail: Array[Vector2i] = _path.slice(1)
		tail.reverse()
		_path = [_path[0]] as Array[Vector2i]
		_path.append_array(tail)

	_build_waypoints(grid)
	_build_route_metrics()
	_build_loop_flags(grid)
	_build_track_points(grid)
	_create_checkpoints()
	_spawn_racers(grid, lib)
	_spawn_ghost()
	_add_skidmarks()
	if _speedo != null and _player != null:
		_speedo.car = _player.car
	if _minimap != null:
		_minimap.setup(_track_points, _racers)
	_add_camera(Vector3(0, 4, 12))
	_set_active(false)


## Cumulative along-route distance at each waypoint (and the loop total), so a
## world position can be turned into "how far round the lap" for time gaps.
func _build_route_metrics() -> void:
	_wp_cum = PackedFloat32Array()
	_route_len = 0.0
	if _waypoints.size() < 2:
		return
	_wp_cum.resize(_waypoints.size())
	var acc := 0.0
	for i in range(_waypoints.size()):
		_wp_cum[i] = acc
		acc += _waypoints[i].distance_to(_waypoints[(i + 1) % _waypoints.size()])
	_route_len = acc


## Flag which route waypoints sit on a loop tile, so the AI can commit to driving
## them rather than steering across the base.
func _build_loop_flags(grid: TrackGrid) -> void:
	_loop_flags = {}
	for i in range(_path.size()):
		var def: TileDefinition = grid.get_def(_path[i])
		if def != null and def.category in [
				TileDefinition.Category.LOOP, TileDefinition.Category.CORKSCREW]:
			_loop_flags[i] = true


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
			ai.loop_flags = _loop_flags
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


## Lay down the skid-mark surface and hand it the player's car. Off the player, so
## AI cars don't also scribble on the road.
func _add_skidmarks() -> void:
	if _player == null:
		return
	var marks := SkidMarks.new()
	marks.car = _player.car
	add_child(marks)


# --- Ghost ("beat your best") -----------------------------------------------

## Spawn the translucent ghost from this track's best-run replay, if one exists. It
## is a purely visual, transform-driven prop with no collision, so it never touches
## the player or the checkpoints. Hidden until the race starts.
func _spawn_ghost() -> void:
	_ghost_replay = Records.load_ghost(GameState.current_track_name)
	if _ghost_replay == null or _ghost_replay.frame_count() < 2:
		_ghost_replay = null
		return
	var info: Dictionary = _ghost_replay.car_infos[0]
	_ghost_car = load(CAR_SCENE).instantiate()
	_ghost_car.profile = CarProfile.for_replay(info)
	add_child(_ghost_car)
	# Turn it into a visual-only prop: no physics, no collision, faded and tinted so
	# it reads plainly as a ghost of a past run rather than a live rival.
	_ghost_car.set_physics_process(false)
	_ghost_car.freeze = true
	_ghost_car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_ghost_car.collision_layer = 0
	_ghost_car.collision_mask = 0
	_make_ghostly(_ghost_car)
	_ghost_car.global_transform = _ghost_replay.sample(0, 0.0)
	_ghost_car.visible = false


## Fade every mesh under `node` so the ghost car is see-through.
func _make_ghostly(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = 0.6
	for c in node.get_children():
		_make_ghostly(c)


## Drive the ghost to where the best run was at this race time. Once the best run
## has ended (you have outlasted it) the ghost simply disappears.
func _update_ghost() -> void:
	if _ghost_car == null:
		return
	var frame: float = _race_time * _ghost_replay.fps
	if frame <= float(_ghost_replay.frame_count() - 1):
		_ghost_car.visible = true
		_ghost_car.global_transform = _ghost_replay.sample(0, frame)
	else:
		_ghost_car.visible = false


# --- Phases -----------------------------------------------------------------

func _process(delta: float) -> void:
	_update_hint(delta)
	match _phase:
		Phase.COUNTDOWN:
			_countdown -= delta
			_update_countdown_hud()
			if _countdown <= 0.0:
				_start_race()
		Phase.RACING:
			_race_time += delta
			_track_player_progress()
			_update_offroute_penalty()
			_update_rubberband()
			_check_respawns(delta)
			_update_ranks()
			_update_ghost()
			_update_hud()
			_update_wrong_way(delta)
		Phase.FINISHED:
			pass


## Count the controls hint down and fade it out over its last second, so it's there
## long enough to read at the start but gone before it becomes clutter.
func _update_hint(delta: float) -> void:
	if _hint_label == null or not _hint_label.visible:
		return
	_hint_time_left -= delta
	if _hint_time_left <= 1.0:
		_hint_label.modulate.a = clampf(_hint_time_left, 0.0, 1.0)
	if _hint_time_left <= 0.0:
		_hint_label.visible = false


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
		r.last_checkpoint_index = index
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
	Haptics.stop()
	GameState.last_replay = _recorder.replay
	# Fold the run into this track's records; a beaten race time also saves the run
	# as the new ghost. Player is car 0 in the recording.
	var beat := {"lap": false, "race": false}
	if _player != null and _recorder.replay != null:
		var ghost: Replay = _recorder.replay.extract_car(0)
		beat = Records.submit(
			GameState.current_track_name, _player.timer.best_lap, _player.finish_time, ghost)
	_show_results(beat)


# --- Respawns ---------------------------------------------------------------

func _check_respawns(delta: float) -> void:
	var terrain: Terrain = GameState.current_terrain
	for r in _racers:
		if r.finished:
			continue
		var car := r.car
		var upright: float = car.global_transform.basis.y.dot(Vector3.UP)
		# "Settled" is generous on purpose: a car stranded on its roof often still
		# creeps or rocks a little (a slope, or throttle it can't use), so a tight
		# near-zero test would keep re-arming and never rescue it.
		var settled: bool = car.linear_velocity.length() < 4.0
		# A car sitting on its wheels is never "flipped", however upside-down it is in
		# WORLD space: on a loop or corkscrew crest it is inverted yet perfectly seated,
		# its up-axis aligned with the road it rides. Measuring flip against world-up
		# alone made a car that lost momentum there trip a bogus rescue every lap. Only
		# rescue when it is NOT seated on a surface (on its roof, off the track).
		var seated: bool = car.grounded and car.global_transform.basis.y.dot(car.surface_normal) > 0.3
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
		if car.global_position.y < -8.0:
			# Off the world entirely — nothing to recover, reset at once.
			_respawn(r, "fell y=%.1f" % car.global_position.y)
		elif in_lake:
			# Submerged and off the road, but a car blasting across a low causeway
			# reads that for only a fraction of a second while grounded on solid road
			# at speed. Only a car that has actually bogged down in the water (slow,
			# for a beat) is drowning — so a healthy crossing is never reset.
			if car.linear_velocity.length() < 6.0:
				r.lake_time += delta
			else:
				r.lake_time = 0.0
			if r.lake_time > 1.0:
				_respawn(r, "lake y=%.1f" % car.global_position.y)
		elif not r.is_player and upright < 0.2 and settled and not seated:
			# An AI car wheels-up (or on its side) and not riding a loop/corkscrew
			# surface is genuinely flipped — it can't press Reset, so right it after a
			# beat. The player is left to reset a flip themselves with R: a flipped car
			# is still on the track and recoverable, so auto-righting it would just take
			# control away (unlike falling off the world or drowning, which do reset).
			r.lake_time = 0.0
			r.stuck_time += delta
			if r.stuck_time > 1.5:
				_respawn(r, "flipped upright=%.2f" % upright)
		else:
			r.lake_time = 0.0
			r.stuck_time = 0.0
			# An AI car wedged upright (against a wall, scenery, another car) never
			# trips the flipped check above, so it can sit there forever. If a CPU
			# car barely moves for a few seconds while racing, put it back on the
			# line. Not applied to the player — they may stop on purpose and have R.
			if not r.is_player and car.linear_velocity.length() < 1.5:
				r.slow_time += delta
				if r.slow_time > 3.0:
					_respawn(r, "ai-stuck")
			else:
				r.slow_time = 0.0


func _respawn(r: Racer, _reason: String = "") -> void:
	r.stuck_time = 0.0
	r.slow_time = 0.0
	r.lake_time = 0.0
	# The player respawns from the reliable progress cursor, a few waypoints back for
	# a run-up — NOT from the last checkpoint, whose in-order bookkeeping stalls (and
	# drops you far back) when a checkpoint sphere gets skipped mid-jump or mid-loop.
	# AI cars keep the checkpoint respawn.
	if r == _player and not _waypoints.is_empty():
		var idx: int = posmod(_player_wp - RESET_BACKTRACK, _waypoints.size())
		r.car.respawn(_waypoints[idx] + Vector3(0, 1.4, 0), _forward_at(idx))
		_player_wp = idx
	else:
		r.car.respawn(r.last_checkpoint_pos, r.last_checkpoint_forward)


## How many waypoints back along the racing line R puts you.
##
## Not the checkpoint you last passed: waypoints sit one per tile, so that point is
## typically a meter or two behind the car. Respawning exactly there moves nothing
## and only zeroes your speed — it reads as an instant brake rather than a reset.
## Three tiles back is a visible reposition with room to get going again.
const RESET_BACKTRACK := 3


## R during a race: back onto the racing line, upright, facing the right way, with
## a short run-up. Keyed off the player's sticky progress cursor, so on a track that
## crosses near itself it puts you just behind where you actually are — not far back
## on an earlier lap section that happens to be horizontally close.
func _manual_reset(r: Racer) -> void:
	if _waypoints.is_empty():
		r.car.reset_to_safe()
		return
	var here: int = _player_wp if r == _player else _nearest_waypoint_index(r.car.global_position)
	var idx: int = posmod(here - RESET_BACKTRACK, _waypoints.size())
	r.stuck_time = 0.0
	r.car.respawn(_waypoints[idx] + Vector3(0, 1.4, 0), _forward_at(idx))
	if r == _player:
		_player_wp = idx


func _nearest_waypoint_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in range(_waypoints.size()):
		var d: float = Vector2(pos.x - _waypoints[i].x, pos.z - _waypoints[i].z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## Advance the player's sticky route cursor. Searches only a short window forward
## (and a little back, for spin-outs) of where it already is, so it follows the lap
## smoothly and CANNOT jump to a waypoint from a different part of a self-crossing
## track — the bug that made the wrong-way warning fire and reset land far back when
## a second set of loops/corkscrews sat near the first.
func _track_player_progress() -> void:
	if _player == null or _waypoints.size() < 2:
		return
	var pos: Vector3 = _player.car.global_position
	var n: int = _waypoints.size()
	var best: int = _player_wp
	# FULL 3D distance, not horizontal only: a road climbing a hill can pass near
	# itself in plan view (switchbacks) at different heights, and a flat compare would
	# confuse the legs. Height tells them apart.
	var best_d: float = pos.distance_squared_to(_waypoints[_player_wp])
	for off in range(-4, 13):
		var i: int = posmod(_player_wp + off, n)
		var d: float = pos.distance_squared_to(_waypoints[i])
		if d < best_d:
			best_d = d
			best = i
	_player_wp = best
	_player_wp_dist = sqrt(best_d)


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
		# On an actual road surface there is never an off-route penalty, however far
		# that road sits from the racing line. The horizontal distance test can't tell
		# a loop, bank or bridge — whose geometry bulges well outside its footprint
		# cells — from genuinely straying onto the terrain, so being physically on the
		# track (wheels on road) is the authoritative "on route" signal. Without this,
		# the inside of a loop reads as far off route and drags the car down like a
		# phantom brake, sometimes twice per loop.
		if r.car.on_track:
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


## Total distance travelled along the route, in meters (laps included). Used to
## measure the live time gap between the player and the car it is chasing.
func _metric_progress(r: Racer) -> float:
	if _wp_cum.is_empty():
		return 0.0
	# The player uses its sticky cursor; other cars fall back to a global search.
	var i: int = _player_wp if r == _player else _nearest_waypoint_index(r.car.global_position)
	return float(r.lap) * _route_len + _wp_cum[i]


## The time gap from the player to the racer one place ahead, as a string like
## "+1.2s", or "" when the player leads. Distance to the car ahead converted to
## seconds at the player's current speed — an approximation, but a stable, readable
## one that matches what the driver feels.
func _interval_to_ahead() -> String:
	if _player == null or _player_position <= 1:
		return ""
	var order := _racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool: return _progress(a) > _progress(b))
	var idx: int = order.find(_player)
	if idx <= 0:
		return ""
	var ahead: Racer = order[idx - 1]
	var gap_m: float = _metric_progress(ahead) - _metric_progress(_player)
	if gap_m <= 0.0:
		return ""
	var speed: float = maxf(_player.car.linear_velocity.length(), 8.0)
	return "+%.1fs" % (gap_m / speed)


# --- Wrong way --------------------------------------------------------------

## Flash a warning when the player is driving against the route. Compares the car's
## travel direction with the route's forward direction at the nearest waypoint; a
## strongly-opposed heading at speed lights the warning.
func _update_wrong_way(delta: float) -> void:
	if _wrongway_label == null:
		return
	var wrong := false
	if _player != null and not _player.finished and _waypoints.size() >= 2:
		var car: ArcadeCar = _player.car
		# Only meaningful when actually ON the road and on roughly level ground:
		# - off the road (exploring terrain / up a hillside off-track) you're not going
		#   the "wrong way", you're just off-route, so `on_track` gates it out;
		# - on a loop, wall or steep bank the chassis points up and over so its
		#   horizontal heading momentarily opposes the route even when correct, and
		#   airborne there is no heading — so a level surface is required too.
		# ...and only when the cursor is actually tracking the car. On a stretch with no
		# waypoints of its own the cursor strands on an unrelated leg far away, whose
		# "forward" points some random direction — never accuse the driver of going
		# backwards off a waypoint they aren't near.
		var cursor_ok: bool = _player_wp_dist < Constants.CELL_SIZE * 5.0
		if cursor_ok and car.grounded and car.on_track and car.surface_normal.dot(Vector3.UP) > 0.6:
			var vel: Vector3 = car.linear_velocity
			vel.y = 0.0
			if vel.length() > 4.0:
				wrong = vel.normalized().dot(_forward_at(_player_wp)) < -0.45
	# Require the condition to hold for over a second before showing, so a bump, a
	# slope, or the brief window where the cursor is drifting off a waypoint-less
	# stretch can't flash it; blink while shown so it reads as an alert.
	_wrongway_time = (_wrongway_time + delta) if wrong else 0.0
	_wrongway_label.visible = _wrongway_time > 1.2 and (int(_race_time * 3.0) % 2 == 0)


# --- Restart ----------------------------------------------------------------

## Restart the race from the grid. Rebuilds the scene from the same GameState, so
## the same track, car and field come back on the start line.
func _restart_race() -> void:
	get_tree().paused = false
	AudioManager.set_warning(false)
	get_tree().reload_current_scene()


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Speed-line overlay first, so all the HUD text and menus draw on top of it.
	var sh := Shader.new()
	sh.code = SPEED_LINES_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("intensity", 0.0)
	_speed_lines = ColorRect.new()
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines.material = mat
	layer.add_child(_speed_lines)

	# A styled pause menu, so it matches the rest of the UI and a controller can
	# drive it. The race keeps running behind it, paused; it processes while paused
	# and unpauses when it closes.
	var back_label: String = "Back to Editor" if GameState.return_scene.ends_with("Editor.tscn") else "Leave Race"
	_quit_dialog = MenuUI.menu_overlay("Paused", [
		{"text": "Resume", "cb": _close_pause, "primary": true},
		{"text": "Restart Race", "cb": _restart_race, "icon": "reroll"},
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

	_wrongway_label = Label.new()
	_wrongway_label.text = "◄ WRONG WAY ►"
	_wrongway_label.anchor_left = 0.5
	_wrongway_label.anchor_right = 0.5
	_wrongway_label.anchor_top = 0.55
	_wrongway_label.offset_left = -220
	_wrongway_label.offset_right = 220
	_wrongway_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrongway_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_wrongway_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_wrongway_label.add_theme_constant_override("outline_size", 6)
	_wrongway_label.add_theme_font_size_override("font_size", 40)
	_wrongway_label.visible = false
	layer.add_child(_wrongway_label)

	# Results sit inside a themed panel centred on screen, so the standings read
	# against a solid slab like the rest of the UI rather than floating over the map.
	_results_panel = PanelContainer.new()
	_results_panel.theme = MenuUI.build_theme()
	_results_panel.anchor_left = 0.5
	_results_panel.anchor_right = 0.5
	_results_panel.anchor_top = 0.5
	_results_panel.anchor_bottom = 0.5
	_results_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_results_panel.visible = false
	layer.add_child(_results_panel)

	var results_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		results_pad.add_theme_constant_override("margin_" + side, 30)
	_results_panel.add_child(results_pad)

	_results_label = Label.new()
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.add_theme_font_size_override("font_size", 24)
	results_pad.add_child(_results_label)

	# Speedometer, bottom-left corner. Its car is wired up once the player spawns.
	_speedo = Speedometer.new()
	_speedo.anchor_left = 0.0
	_speedo.anchor_top = 1.0
	_speedo.anchor_bottom = 1.0
	_speedo.offset_left = 16
	_speedo.offset_top = -184
	_speedo.offset_bottom = -16
	layer.add_child(_speedo)

	# Controls hint sits above the speedometer so the two don't overlap.
	var hint := Label.new()
	hint.text = "Esc: pause    R: respawn    C: camera"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16
	hint.offset_top = -212
	hint.offset_bottom = -188
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(hint)
	_hint_label = hint


func _update_countdown_hud() -> void:
	_countdown_label.text = str(ceili(_countdown))


func _update_hud() -> void:
	if _countdown_label.text == "GO!" and _race_time > 1.2:
		_countdown_label.text = ""
	if _player == null:
		return
	var lap_display: int = mini(_player.lap + 1, _laps_total)
	var interval: String = _interval_to_ahead()
	var pos_line: String = "P%d/%d    Lap %d/%d" % [
		_player_position, _racers.size(), lap_display, _laps_total]
	if interval != "":
		pos_line += "    %s" % interval  # gap to the car ahead
	_info_label.text = "%s\nTime  %s\nBest  %s" % [
		pos_line,
		LapTimer.format(_player.timer.current(_race_time)),
		LapTimer.format(_player.timer.best_lap)]

	# Speed lines fade in only over the top third of the car's speed range.
	if _speed_lines != null:
		var top: float = _player.car.profile.max_speed if _player.car.profile != null else 60.0
		var ratio: float = clampf(_player.car.linear_velocity.length() / maxf(top, 1.0), 0.0, 1.0)
		var lines_i: float = clampf((ratio - 0.65) / 0.35, 0.0, 1.0)
		(_speed_lines.material as ShaderMaterial).set_shader_parameter("intensity", lines_i)


func _show_results(beat: Dictionary = {"lap": false, "race": false}) -> void:
	_countdown_label.text = ""
	if _speed_lines != null:
		(_speed_lines.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
	var order := _racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool: return _progress(a) > _progress(b))
	var lines: Array[String] = ["FINISH", ""]
	for i in range(order.size()):
		var r: Racer = order[i]
		var time_text: String = LapTimer.format(r.finish_time) if r.finished else "DNF"
		var tag: String = "   ◄ You" if r == _player else ""
		lines.append("%d.  %s   %s%s" % [i + 1, r.display_name, time_text, tag])

	# The player's medal and how they measured up to par, plus any new records set.
	# The medal is judged on the best LAP against a one-lap par, so it means the same
	# thing however many laps the race was — and matches what track-select shows.
	if _player != null and _player.finished and _route_len > 0.0 and _player.timer.best_lap > 0.0:
		lines.append("")
		var medal: int = Records.medal(_player.timer.best_lap, _route_len)
		if medal != Records.Medal.NONE:
			lines.append("%s  %s" % [Records.MEDAL_GLYPHS[medal], Records.MEDAL_NAMES[medal]])
		lines.append("Lap par %s    Best lap %s" % [
			LapTimer.format(Records.par_time(_route_len)), LapTimer.format(_player.timer.best_lap)])
		if beat.get("race", false):
			lines.append("★ NEW RECORD TIME ★")
		if beat.get("lap", false):
			lines.append("★ NEW BEST LAP ★")

	lines.append("")
	var can_replay: bool = GameState.last_replay != null
	lines.append("Enter: watch replay      Esc: leave race" if can_replay else "Esc: leave race")
	_show_results_text("\n".join(lines))


## Fill the results panel with `text` and reveal it. Also used for the "no drivable
## loop" message.
func _show_results_text(text: String) -> void:
	_results_label.text = text
	_results_panel.visible = true


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
		# Once finished, Esc just leaves — no pause menu. (The results panel sits over
		# the pause overlay, so showing it here would trap an un-clickable dialog
		# behind the standings; and "leave race" is the only sensible action anyway.)
		if _phase == Phase.FINISHED:
			get_tree().paused = false
			get_tree().change_scene_to_file(GameState.return_scene)
			return
		# Otherwise toggle the pause menu (Resume / restart / leave / exit game).
		# Openable and operable with a controller now that ui_cancel carries a button.
		if _quit_dialog.visible:
			_close_pause()
		else:
			get_tree().paused = true
			_quit_dialog.show()
	elif event.is_action_pressed("ui_accept") and _phase == Phase.FINISHED and GameState.last_replay != null:
		get_tree().change_scene_to_file(REPLAY_SCENE)
	elif event.is_action_pressed("ui_accept") and _phase == Phase.COUNTDOWN:
		# Skip the wait: drop the countdown to a brief "GO!" flash.
		_countdown = minf(_countdown, 0.4)
	elif event.is_action_pressed("reset_car") and _phase == Phase.RACING and _player != null:
		_manual_reset(_player)
