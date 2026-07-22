class_name TileLibrary
extends RefCounted
## The set of available tile definitions (SPEC.md §M3). Built in code for M3
## (the data model is still TileDefinition/TileSocket resources; authoring them
## as .tres can come later). Also knows how to instance tiles into the world.

var definitions: Dictionary = {}          ## StringName -> TileDefinition
var ordered: Array[TileDefinition] = []   ## palette order


## How many levels the overpass's deck clears its lower road by. MUST match
## TileGeo's overpass_levels export — the sockets promise what the mesh builds.
##
## One, not two: a ramp climbs exactly one level, so a deck any higher cannot be
## reached without chaining ramps, and the piece is useless on its own. One level
## is 3 m, which still clears a car several times over.
const OVERPASS_LEVELS := 1


func build() -> void:
	definitions.clear()
	ordered.clear()
	_add("straight", "Straight", "res://scenes/track/tiles/StraightTile.tscn",
		_road_sockets(), TileDefinition.Category.STRAIGHT, false)
	_add("start", "Start / Finish", "res://scenes/track/tiles/StartTile.tscn",
		_road_sockets(), TileDefinition.Category.START, false)
	_add("curve", "Curve", "res://scenes/track/tiles/CurveTile.tscn",
		_curve_sockets(), TileDefinition.Category.CORNER, false)
	_add_multicell("wide_curve", "Wide Curve", "res://scenes/track/tiles/WideCurveTile.tscn",
		Vector2i(2, 2), [
			{"cell": Vector2i(0, 0), "dir": TrackGrid.S, "elevation": 0},
			{"cell": Vector2i(1, -1), "dir": TrackGrid.E, "elevation": 0},
		], TileDefinition.Category.CORNER, false)
	# The banked family. All hold the same bank angle, so they chain:
	#   flat road -> banked entry -> banked straights / banked curves -> banked exit
	#             -> flat road
	# Entry and exit are separate pieces because they are mirrors of each other, and
	# no rotation mirrors a tile — see TileGeo's BANKED_ENTRY/BANKED_EXIT.
	_add("banked_entry", "Banked Entry", "res://scenes/track/tiles/BankedEntryTile.tscn",
		_road_sockets(), TileDefinition.Category.BANK, false)
	_add("banked_exit", "Banked Exit", "res://scenes/track/tiles/BankedExitTile.tscn",
		_road_sockets(), TileDefinition.Category.BANK, false)
	_add("banked_straight", "Banked Straight", "res://scenes/track/tiles/BankedStraightTile.tscn",
		_road_sockets(), TileDefinition.Category.BANK, false)
	# A 3x3 sweep — a banked corner needs room to be worth banking. Same corner as
	# the wide curve, one cell wider in radius: in at the anchor's S edge, out at
	# the far cell's E edge.
	_add_multicell("banked_curve", "Banked Curve", "res://scenes/track/tiles/BankedCurveTile.tscn",
		Vector2i(3, 3), [
			{"cell": Vector2i(0, 0), "dir": TrackGrid.S, "elevation": 0},
			{"cell": Vector2i(2, -2), "dir": TrackGrid.E, "elevation": 0},
		], TileDefinition.Category.BANK, false)
	_add("crossroads", "Crossroads", "res://scenes/track/tiles/CrossroadsTile.tscn",
		_cross_sockets(), TileDefinition.Category.SPECIAL, false)
	_add("overpass", "Overpass", "res://scenes/track/tiles/OverpassTile.tscn",
		_overpass_sockets(), TileDefinition.Category.BRIDGE, false)
	# Connects like a straight, so it drops into any run of road.
	_add("tunnel", "Tunnel", "res://scenes/track/tiles/TunnelTile.tscn",
		_road_sockets(), TileDefinition.Category.SPECIAL, false)
	# The entry flares a flat road out into a bore. Without one, a straight only
	# meets a pipe along its centreline and the road looks severed. Symmetric
	# sockets, so rotating it 180 degrees serves as the exit.
	#
	# One entry serves BOTH bores: the pipe-specific variant (TileGeo.PIPE_ENTRY,
	# withdrawn from the palette but kept for its enum slot and restorability)
	# curled the road right over into a full tube, which read worse than simply
	# flaring it into the pipe's lower half and letting the bore close above.
	_add("pipe_entry", "Pipe / Half-pipe Entry", "res://scenes/track/tiles/HalfPipeEntryTile.tscn",
		_road_sockets(), TileDefinition.Category.SPECIAL, true)
	_add("pipe", "Pipe", "res://scenes/track/tiles/PipeTile.tscn",
		_road_sockets(), TileDefinition.Category.SPECIAL, true)
	_add("half_pipe", "Half-pipe", "res://scenes/track/tiles/HalfPipeTile.tscn",
		_road_sockets(), TileDefinition.Category.SPECIAL, true)
	_add("ramp_up", "Ramp Up", "res://scenes/track/tiles/RampUpTile.tscn",
		_ramp_sockets(false), TileDefinition.Category.RAMP, false)
	_add("ramp_down", "Ramp Down", "res://scenes/track/tiles/RampDownTile.tscn",
		_ramp_sockets(true), TileDefinition.Category.RAMP, false)
	_add_multicell("loop", "Loop", "res://scenes/track/tiles/LoopTile.tscn",
		Vector2i(2, 2), [
			{"cell": Vector2i(0, 0), "dir": TrackGrid.S, "elevation": 0},   # enter column 0, south
			{"cell": Vector2i(1, -1), "dir": TrackGrid.N, "elevation": 0},  # exit column 1, north
		], TileDefinition.Category.LOOP, true)
	# Corkscrew: a 3x9 barrel roll, centred on the middle column so it runs straight
	# through — enters the S edge of the middle column and exits the N edge of the
	# middle column nine cells north, with the roll swinging into the flanking
	# columns (see TileGeo.Kind.CORKSCREW). (TileGeo.Kind must keep the CORKSCREW slot
	# at its enum value regardless, since tile scenes store the kind as an integer.)
	_add_multicell("corkscrew", "Corkscrew", "res://scenes/track/tiles/CorkscrewTile.tscn",
		Vector2i(3, 9), [
			{"cell": Vector2i(1, 0), "dir": TrackGrid.S, "elevation": 0},
			{"cell": Vector2i(1, -8), "dir": TrackGrid.N, "elevation": 0},
		], TileDefinition.Category.CORKSCREW, true)
	_add("jump", "Jump Ramp", "res://scenes/track/tiles/JumpRampTile.tscn",
		_jump_sockets(), TileDefinition.Category.SPECIAL, true)


func _add(id: String, display_name: String, mesh_path: String,
		sockets: Array[TileSocket], category: TileDefinition.Category, is_stunt: bool) -> void:
	var def := TileDefinition.new()
	def.id = StringName(id)
	def.display_name = display_name
	def.footprint = Vector2i.ONE
	def.mesh = load(mesh_path)
	def.sockets = sockets
	def.category = category
	def.is_stunt = is_stunt
	definitions[def.id] = def
	ordered.append(def)


func _add_multicell(id: String, display_name: String, mesh_path: String, footprint: Vector2i,
		connectors: Array, category: TileDefinition.Category, is_stunt: bool) -> void:
	var def := TileDefinition.new()
	def.id = StringName(id)
	def.display_name = display_name
	def.footprint = footprint
	def.mesh = load(mesh_path)
	def.road_connectors = connectors
	def.category = category
	def.is_stunt = is_stunt
	definitions[def.id] = def
	ordered.append(def)


func _socket(has_road: bool, elev: int, slope: TileSocket.Slope) -> TileSocket:
	var s := TileSocket.new()
	s.has_road = has_road
	s.elevation_level = elev
	s.slope = slope
	return s


# Road on N and S edges, closed E/W (straight, start, loop, corkscrew).
func _road_sockets() -> Array[TileSocket]:
	var closed := _socket(false, 0, TileSocket.Slope.FLAT)
	return [_socket(true, 0, TileSocket.Slope.FLAT), closed,
			_socket(true, 0, TileSocket.Slope.FLAT), closed]


# Road on all four edges (crossroads).
func _cross_sockets() -> Array[TileSocket]:
	return [_socket(true, 0, TileSocket.Slope.FLAT), _socket(true, 0, TileSocket.Slope.FLAT),
			_socket(true, 0, TileSocket.Slope.FLAT), _socket(true, 0, TileSocket.Slope.FLAT)]


# Overpass: the N-S deck sits OVERPASS_LEVELS up, the E-W road stays at ground.
# The mixed socket elevations are the whole trick — one tile carries both roads,
# so a track can cross over itself without the grid having to hold two tiles in a
# cell. Rotating the tile swaps which way the deck runs.
func _overpass_sockets() -> Array[TileSocket]:
	return [_socket(true, OVERPASS_LEVELS, TileSocket.Slope.FLAT),
			_socket(true, 0, TileSocket.Slope.FLAT),
			_socket(true, OVERPASS_LEVELS, TileSocket.Slope.FLAT),
			_socket(true, 0, TileSocket.Slope.FLAT)]


# Road on N and E edges (base 90-degree curve).
func _curve_sockets() -> Array[TileSocket]:
	var closed := _socket(false, 0, TileSocket.Slope.FLAT)
	return [_socket(true, 0, TileSocket.Slope.FLAT), _socket(true, 0, TileSocket.Slope.FLAT),
			closed, closed]


# Jump ramp: road enters the S edge at level 0, launches off the (closed) N lip.
func _jump_sockets() -> Array[TileSocket]:
	var closed := _socket(false, 0, TileSocket.Slope.FLAT)
	return [closed, closed, _socket(true, 0, TileSocket.Slope.FLAT), closed]


# Ramp: low edge at level 0, high edge at level 1. flip swaps which edge is high.
func _ramp_sockets(flip: bool) -> Array[TileSocket]:
	var n_level: int = 0 if flip else 1
	var s_level: int = 1 if flip else 0
	var closed := _socket(false, 0, TileSocket.Slope.FLAT)
	return [_socket(true, n_level, TileSocket.Slope.FLAT), closed,
			_socket(true, s_level, TileSocket.Slope.FLAT), closed]


# --- World placement helpers ------------------------------------------------

static func cell_to_world(cell: Vector2i, elevation_level: int) -> Vector3:
	return Vector3(
		cell.x * Constants.CELL_SIZE,
		elevation_level * Constants.ELEVATION_STEP,
		cell.y * Constants.CELL_SIZE)


static func tile_transform(cell: Vector2i, rotation: int, elevation_level: int) -> Transform3D:
	var basis := Basis(Vector3.UP, -rotation * PI / 2.0)
	return Transform3D(basis, cell_to_world(cell, elevation_level))


## Instance the tile for `placed` at `cell`, returning the world node (or null).
## Pass `grid` so context-dependent tiles can see their neighbours.
func instantiate_placed(cell: Vector2i, placed: PlacedTile, grid: TrackGrid = null) -> Node3D:
	var def: TileDefinition = definitions.get(placed.def_id)
	if def == null or def.mesh == null:
		return null
	var inst: Node3D = def.mesh.instantiate()
	inst.transform = tile_transform(cell, placed.rotation, placed.elevation_level)
	var geo := inst as TileGeo
	if geo != null and geo.kind == TileGeo.Kind.OVERPASS and grid != null:
		# Set before the caller adds it: _ready is what builds the mesh.
		geo.draw_lower = overpass_needs_lower(grid, cell, placed.rotation)
	return inst


## Does anything actually join an overpass's lower road? Its lower deck runs E-W
## in the tile's own frame, so rotation decides which pair of world edges to test.
static func overpass_needs_lower(grid: TrackGrid, cell: Vector2i, rotation: int) -> bool:
	for base_dir in [TrackGrid.E, TrackGrid.W]:
		var nb: Vector2i = cell + TrackGrid.OFFSETS[(base_dir + rotation) % 4]
		if grid.cells_connected(cell, nb):
			return true
	return false


## Find the start cell (first START-category tile), or Vector2i.MAX if none.
func find_start_cell(grid: TrackGrid) -> Vector2i:
	for cell in grid.tiles:
		var placed: PlacedTile = grid.tiles[cell]
		var def: TileDefinition = definitions.get(placed.def_id)
		if def != null and def.category == TileDefinition.Category.START:
			return cell
	return Vector2i(2147483647, 2147483647)
