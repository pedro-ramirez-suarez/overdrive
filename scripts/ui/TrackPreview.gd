class_name TrackPreview
extends SubViewportContainer
## A live 3D preview of a track, for the select screen (SPEC.md §M6).
##
## Builds the real tile, prop and terrain geometry into its own SubViewport world
## and frames the camera to the track's bounds, so what you see is what you drive
## rather than a schematic. Collision and the map fence are skipped — nothing here
## is simulated, it just turns.

## Degrees per second the view orbits. Slow: it should read as a display, not a
## carousel.
const SPIN_SPEED := 9.0
const PITCH := -32.0
## Cells of ground kept around the track, so it doesn't sit on a cliff edge.
const MARGIN := 5
## Track bounds are padded by this before framing, so nothing touches the edge.
const FRAME_PAD := 1.25

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _centre: Vector3 = Vector3.ZERO
var _distance: float = 60.0
var _yaw: float = 0.0
var _spinning: bool = false


func _init() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)


func _ready() -> void:
	set_process(true)


## Rebuild the preview for `grid`. Safe to call repeatedly — each call throws away
## the previous world.
func show_track(grid: TrackGrid, terrain: Terrain, lib: TileLibrary) -> void:
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	_viewport.add_child(_world)

	TrackWorld.add_environment(_world)
	var lo := Vector2i(-6, -6)
	var hi := Vector2i(6, 6)
	if not grid.tiles.is_empty():
		var first := true
		for cell in grid.tiles:
			if first:
				lo = cell
				hi = cell
				first = false
			else:
				lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
				hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
		lo -= Vector2i(MARGIN, MARGIN)
		hi += Vector2i(MARGIN, MARGIN)

	if terrain != null:
		TerrainWorld.build_region(_world, terrain, grid, lo, hi, false, false)
	else:
		TrackWorld.add_ground(_world)
	TrackWorld.add_tiles(_world, grid, lib)
	TrackWorld.add_props(_world, grid, terrain)

	_camera = Camera3D.new()
	_camera.current = true
	_world.add_child(_camera)
	_frame(lo, hi, terrain)
	_yaw = 45.0
	_spinning = true
	_update_camera()


## Aim at the middle of the track and stand far enough back to hold all of it.
func _frame(lo: Vector2i, hi: Vector2i, terrain: Terrain) -> void:
	var mid_x: float = (lo.x + hi.x) * 0.5 * Constants.CELL_SIZE
	var mid_z: float = (lo.y + hi.y) * 0.5 * Constants.CELL_SIZE
	var span_x: float = (hi.x - lo.x + 1) * Constants.CELL_SIZE
	var span_z: float = (hi.y - lo.y + 1) * Constants.CELL_SIZE

	var mid_y := 0.0
	if terrain != null:
		mid_y = terrain.height_level(Vector2i(
			roundi(mid_x / Constants.CELL_SIZE), roundi(mid_z / Constants.CELL_SIZE))) \
			* Constants.ELEVATION_STEP
	_centre = Vector3(mid_x, mid_y, mid_z)

	# Fit the larger span into the vertical FOV. The view orbits, so it must fit
	# from every angle — hence the larger of the two spans, not the one on screen.
	var radius: float = maxf(span_x, span_z) * 0.5 * FRAME_PAD
	var fov_rad: float = deg_to_rad(70.0)
	_distance = maxf(radius / tan(fov_rad * 0.5), 30.0)
	_camera.fov = 70.0
	_camera.far = maxf(4000.0, _distance * 4.0)


func clear() -> void:
	_spinning = false
	if _world != null:
		_world.queue_free()
		_world = null


func _process(delta: float) -> void:
	if not _spinning or _camera == null:
		return
	_yaw = fmod(_yaw + SPIN_SPEED * delta, 360.0)
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw_rad := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(PITCH)
	var dir := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		-sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad))
	_camera.global_position = _centre + dir * _distance
	_camera.look_at(_centre, Vector3.UP)
