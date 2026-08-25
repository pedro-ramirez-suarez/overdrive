extends Node
## Builds "Emerald Sound" -- a large city circuit inspired by Seattle.
##
## Not traced from a map. The map generator (tools/trackgen) lays a real road onto
## the grid, and a real road has no loops or corkscrews in it. This one is laid out
## by hand around the same geography instead -- a sound down the west side, a ship
## canal, a lake in the middle, hills on every side of it -- and the stunt pieces
## are built into the lap where the city gives them a reason to be there.
##
##   godot --headless --path . tools/citygen/build_emerald_sound.tscn
##
## Reproducible: the same command writes the same bytes every time.

const N := TrackGrid.N
const E := TrackGrid.E
const S := TrackGrid.S
const W := TrackGrid.W

const TRACK_NAME := "Emerald Sound"
const OUT_PATH := "res://tracks/emerald_sound.json"
## Fixed so the terrain noise and every scattered tree land in the same place on
## every run.
const SEED := 19620421

## Where the lap starts, and the level the waterfront runs at. One level is 3 m, so
## the city sits on a quay 3 m above the water.
const START_CELL := Vector2i(26, 110)
const ROAD_LEVEL := 1

var _lib: TileLibrary
var _grid: TrackGrid

# --- turtle -----------------------------------------------------------------
## The cell the NEXT piece will be entered at, the direction of travel into it,
## and the road level at that entry socket.
var _cell: Vector2i
var _head: int
var _level: int
## Exit cell of the piece just laid, so the next one can be checked against it.
var _prev := Vector2i.ZERO
var _has_prev := false
var _warns := 0
## Cells carrying a bridge deck: their ground stays down at the water rather than
## being pulled up to the road.
var _deck := {}
## Every water cell inside the ground the game draws, worked out once.
var _water_cache: Array[Vector2i] = []
## Cells a jump flies over -> the level to cut them down to.
var _pit := {}


func _ready() -> void:
	_lib = TileLibrary.new()
	_lib.build()
	_grid = TrackGrid.new(_lib.definitions)

	_drive()
	_check_lap()

	var terrain := Terrain.new()
	terrain.setup(Terrain.Type.PLAINS, SEED)
	_sculpt_hills(terrain)
	_conform(terrain)
	_carve_water(terrain)
	var lakes := _flood(terrain)
	var props := _scenery(terrain)

	GameState.current_grid = _grid
	GameState.current_terrain = terrain
	_save(terrain)
	_report(lakes, props)
	get_tree().quit(1 if _warns > 0 else 0)


# --- The lap ----------------------------------------------------------------

func _drive() -> void:
	_cell = START_CELL
	_head = N
	_level = ROAD_LEVEL

	# --- the waterfront: start/finish, then the long blast north along the quay
	_flat("start")
	_run_to(52)
	_bridge_water(2)                # over the mouth of the ship canal
	_run_to(38)
	_banked_corner(true, 2, 2)      # the sweep at the north end of the docks

	# --- the north side: a kink through the mill district, the ridge, the roll
	_run_to(40)
	_curve(true)
	_run_to(36)
	_curve(false)
	_run_to(46)
	_ramps(3)                       # up over the ridge
	_run_to(53)
	_ramps(-3)
	_run_to(58)
	_corkscrew()                    # nine cells of barrel roll below the bridge
	_run_to(74)
	_loop()                         # and the loop, out by the lake
	_run_to(86)
	_curve(false)                   # jog north around the campus
	_run_to(28)
	_curve(true)
	_run_to(112)
	_banked_corner(true, 2, 2)      # north-east sweep

	# --- the east side: the long bridge, then the spiral down to the yards
	_run_to(58)
	_bridge_water(2)                # the floating bridge over the arm of the lake
	_run_to(86)
	_curve(true)                    # step back west, in under the ridge
	_run_to(108)
	_curve(false)
	_helix(true)                    # spiral up onto the elevated stretch
	_deck_to(94)                    # which is a viaduct, on piers
	_helix(false)                   # and down again
	_run_to(103)
	_banked_corner(true, 2, 2)      # south-east sweep

	# --- the south side: the rail yards, and the jump over the cut
	_run_to(84)
	_jump(2)
	_run_to(60)
	_curve(true)                    # round the container terminal
	_run_to(104)
	_curve(false)
	_run_to(48)
	_banked_corner(true, 2, 2)      # south-west sweep, into the stadium district

	# --- downtown: four blocks of it, then out over the waterfront and home
	_run_to(93)
	_curve(false)
	_run_to(34)
	_curve(true)
	_ramps(2)                       # up the hill the city is built on
	_tunnel(3)                      # and through the shoulder of it
	_run_to(86)
	_curve(true)
	_run_to(40)
	_curve(false)
	_run_to(80)
	_curve(false)
	_run_to(34)
	_ramps(-1)
	_run_to(29)
	_crossing(5)                    # the flyover, straight over the waterfront
	_ramps(-1)
	_run_to(22)
	_curve(false)
	_run_to(111)                    # the shore road, water on your right
	_curve(false)
	_run_to(26)
	_curve(false)                   # onto the quay, and across the line


# --- Turtle -----------------------------------------------------------------

## Lay a piece so that its `in_*` connector meets the road we are driving on, and
## walk the turtle out of its `out_*` connector. Every piece in the library is
## described by those two connectors (TileLibrary's sockets and road_connectors),
## so one function places all of them -- rotation, anchor and base level fall out
## of the arithmetic instead of being counted by hand.
func _emit(id: String, in_cell: Vector2i, in_dir: int, in_elev: int,
		out_cell: Vector2i, out_dir: int, out_elev: int, overwrite: bool = false) -> void:
	var rot: int = posmod(_head + 2 - in_dir, 4)
	var anchor: Vector2i = _cell - TrackGrid.rotate_offset(in_cell, rot)
	var base: int = _level - in_elev
	var def: TileDefinition = _lib.definitions[StringName(id)]
	if not overwrite:
		for fc in TrackGrid.footprint_cells(anchor, def, rot):
			if _grid.has_tile(fc):
				_warn("%s at %v lands on top of %s" % [id, fc, _grid.get_placed(fc).def_id])
	_grid.place(anchor, StringName(id), rot, base)
	if _has_prev and not _grid.cells_connected(_prev, _cell):
		_warn("%s at %v does not join the road at %v" % [id, _cell, _prev])
	_prev = anchor + TrackGrid.rotate_offset(out_cell, rot)
	_has_prev = true
	_level = base + out_elev
	_head = posmod(out_dir + rot, 4)
	_cell = _prev + TrackGrid.OFFSETS[_head]


## A one-cell piece with road on its north and south edges, laid along the way we
## are already going. `mirror` turns it half round -- which changes nothing about
## how it connects, but flips which way a banked piece leans.
func _flat(id: String, mirror: bool = false) -> void:
	if _grid.has_tile(_cell):
		_warn("%s at %v lands on top of %s" % [id, _cell, _grid.get_placed(_cell).def_id])
	_grid.place(_cell, StringName(id), posmod(_head + (2 if mirror else 0), 4), _level)
	if _has_prev and not _grid.cells_connected(_prev, _cell):
		_warn("%s at %v does not join the road at %v" % [id, _cell, _prev])
	_prev = _cell
	_has_prev = true
	_cell += TrackGrid.OFFSETS[_head]


## Plain road until the next cell reaches `target` -- an x when we are running east
## or west, a y when north or south. Waypoints rather than counted tiles, so moving
## one corner does not shift every piece after it.
func _run_to(target: int) -> void:
	var axis_x: bool = _head == E or _head == W
	var guard := 0
	while target != (_cell.x if axis_x else _cell.y):
		_flat("straight")
		guard += 1
		if guard > 400:
			_warn("run_to(%d) never got there" % target)
			return


func _curve(right: bool) -> void:
	if right:
		_emit("curve", Vector2i.ZERO, E, 0, Vector2i.ZERO, N, 0)
	else:
		_emit("curve", Vector2i.ZERO, N, 0, Vector2i.ZERO, E, 0)


## `n` ramps in a row: up if positive, down if negative. One ramp is one level.
func _ramps(n: int) -> void:
	for i in range(absi(n)):
		if n > 0:
			_emit("ramp_up", Vector2i.ZERO, S, 0, Vector2i.ZERO, N, 1)
		else:
			_emit("ramp_down", Vector2i.ZERO, S, 1, Vector2i.ZERO, N, 0)


func _tunnel(n: int) -> void:
	for i in range(n):
		_flat("tunnel")


## A 3x3 banked sweep, with the roll into and out of the bank either side of it and
## `lead_in`/`lead_out` banked straights holding the angle.
##
## Entry and exit are mirrors of each other, not rotations, so one hand of corner
## takes the pair the other way round and half turned -- otherwise the road leans
## the wrong way and the corner is off camber. Same rule the map generator uses.
func _banked_corner(right: bool, lead_in: int, lead_out: int) -> void:
	_flat("banked_exit" if right else "banked_entry", right)
	for i in range(lead_in):
		_flat("banked_straight", right)
	if right:
		_emit("banked_curve", Vector2i.ZERO, S, 0, Vector2i(2, -2), E, 0)
	else:
		_emit("banked_curve", Vector2i(2, -2), E, 0, Vector2i.ZERO, S, 0)
	for i in range(lead_out):
		_flat("banked_straight", right)
	_flat("banked_entry" if right else "banked_exit", right)


func _loop() -> void:
	# In and out the same way, one cell over: the loop stands across the road
	# rather than in line with it, so the exit is offset to the right.
	_emit("loop", Vector2i.ZERO, S, 0, Vector2i(1, -1), N, 0)


func _corkscrew() -> void:
	_emit("corkscrew", Vector2i(1, 0), S, 0, Vector2i(1, -8), N, 0)


## The spiral ramp: a full circle over a 3x3 block, one level up (or down).
##
## What it climbs to has to be DECK, not ordinary raised road -- see `_deck_to`.
## The whole 3x3 block is one tile at one level, and terrain corners are pulled up
## to the highest tile touching them, so a straight sitting a level above the helix
## drags the corner they share up with it. That corner belongs to the middle of the
## spiral too, where the road is still climbing, and the ground closes over it.
func _helix(up: bool) -> void:
	if up:
		_emit("helix", Vector2i.ZERO, S, 0, Vector2i(0, -2), N, 1)
	else:
		_emit("helix", Vector2i(0, -2), N, 1, Vector2i.ZERO, S, 0)


## Bridge the water ahead, with `margin` cells of deck on dry land at each end.
##
## An overpass tile carries its deck one level above its own base and stands it on
## piers, so a deck with its base at the waterline is a bridge -- and it is the only
## piece in the library with anything underneath it. The span is measured off the
## water rather than counted out here, so reshaping a lake re-sizes its bridge.
func _bridge_water(margin: int) -> void:
	var step: Vector2i = TrackGrid.OFFSETS[_head]
	var first := -1
	var last := -1
	for i in range(80):
		if _is_water(_cell + step * i):
			if first < 0:
				first = i
			last = i
	if first < 0:
		_warn("bridge at %v has no water ahead of it" % _cell)
		return
	if first < margin:
		_warn("bridge at %v starts in the water" % _cell)
		return
	for i in range(first - margin):
		_flat("straight")
	for i in range(last - first + 1 + 2 * margin):
		_deck_one()


## One cell of deck: an overpass whose base is a level below the road, so the ground
## keeps to the base while the road rides over it.
func _deck_one() -> void:
	_deck[_cell] = true
	_emit("overpass", Vector2i.ZERO, S, 1, Vector2i.ZERO, N, 1)


## Deck until the next cell reaches `target`. This is what a raised stretch on dry
## land is built from, rather than straights a level up: an overpass tile carries
## its road above its OWN level, so the ground under it -- and the corners it shares
## with whatever it joins -- stay down where they were.
func _deck_to(target: int) -> void:
	var axis_x: bool = _head == E or _head == W
	var guard := 0
	while target != (_cell.x if axis_x else _cell.y):
		_deck_one()
		guard += 1
		if guard > 200:
			_warn("deck_to(%d) never got there" % target)
			return


## The same deck, but crossing over road that is already there: one of these cells
## replaces a straight with an overpass, which carries both roads at once. Several
## cells, not one -- terrain corners are pulled up to the highest tile touching
## them, so a deck that stepped down to ordinary raised road in the next cell would
## drag the ground up and fill in the underpass.
func _crossing(n: int) -> void:
	var over := 0
	for i in range(n):
		var under: PlacedTile = _grid.get_placed(_cell)
		if under != null:
			over += 1
			if String(under.def_id) != "straight" or under.elevation_level != _level - 1:
				_warn("the flyover at %v runs over a %s at level %d" % [
					_cell, under.def_id, under.elevation_level])
		_emit("overpass", Vector2i.ZERO, S, 1, Vector2i.ZERO, N, 1, true)
	if over != 1:
		_warn("the flyover crosses %d roads, not 1" % over)


## A launch ramp, `gap` cells of nothing, and a landing ramp facing back at it. The
## jump's road is on one edge only -- you leave off the lip -- so the turtle steps
## over the gap itself instead of being walked out of an exit socket.
func _jump(gap: int) -> void:
	_flat("jump")
	for i in range(gap):
		# The gap is a cut, not a field: dropping it a level keeps whatever the
		# noise left in there from catching the car in mid-air.
		_pit[_cell + TrackGrid.OFFSETS[_head] * i] = maxi(0, _level - 1)
	_cell += TrackGrid.OFFSETS[_head] * gap
	_has_prev = false      # nothing joins across the gap: that is the point
	_flat("jump", true)


func _warn(msg: String) -> void:
	_warns += 1
	if _warns <= 20:
		print("  WARN ", msg)


## The lap has to hand back to the start tile, and no road may stand in the water
## unless it is on a bridge.
func _check_lap() -> void:
	if _cell != START_CELL or _head != N or _level != ROAD_LEVEL:
		_warn("lap does not close: ends at %v heading %s level %d (wanted %v N %d)" % [
			_cell, ["N", "E", "S", "W"][_head], _level, START_CELL, ROAD_LEVEL])
	elif not _grid.cells_connected(_prev, START_CELL):
		_warn("the last piece at %v does not join the start" % _prev)
	for cell in _grid.tiles:
		var placed: PlacedTile = _grid.tiles[cell]
		var def: TileDefinition = _lib.definitions[placed.def_id]
		for fc in TrackGrid.footprint_cells(cell, def, placed.rotation):
			if _is_water(fc) and not _deck.has(fc):
				_warn("%s at %v is standing in the water" % [placed.def_id, fc])
		# Nothing may stand a level above a helix and share ground with it: the
		# corner they share is pulled up to the taller tile, and that corner is
		# also the middle of the spiral, where the road has not climbed yet.
		if placed.def_id != &"helix":
			continue
		for conn in def.road_connectors:
			var end: Vector2i = cell + TrackGrid.rotate_offset(conn["cell"], placed.rotation)
			var out: int = posmod(int(conn["dir"]) + placed.rotation, 4)
			var nb: PlacedTile = _grid.get_placed(end + TrackGrid.OFFSETS[out])
			if nb != null and nb.elevation_level > placed.elevation_level:
				_warn("the helix at %v meets a %s standing a level over it -- the ground closes over the spiral; use deck" % [
					cell, nb.def_id])


# --- Water ------------------------------------------------------------------

## A blob of water: an ellipse with a wobbly edge. A shoreline that runs straight
## for a hundred metres reads as a swimming pool, so every lake gets a couple of
## harmonics around its rim and the bays fall out of where two blobs overlap.
func _blob(c: Vector2i, cx: float, cy: float, rx: float, ry: float,
		wobble: float, phase: float) -> bool:
	var dx: float = (float(c.x) - cx) / rx
	var dy: float = (float(c.y) - cy) / ry
	var r: float = sqrt(dx * dx + dy * dy)
	if r > 1.0 + 2.0 * wobble:
		return false
	var a: float = atan2(dy, dx)
	return r < 1.0 + wobble * (sin(3.0 * a + phase) + 0.6 * sin(5.0 * a - 1.7 * phase))


func _is_water(c: Vector2i) -> bool:
	# The sound, in three overlapping lobes down the west side, between the seawall
	# along the quay and the wooded shore on the far side. Both shores are held off
	# the map's own edges: water that runs to the edge of the terrain shows the car
	# where the world stops.
	if c.x <= 19 and float(c.x) > 5.0 + 2.0 * sin(float(c.y) * 0.09) + sin(float(c.y) * 0.23):
		if _blob(c, 0.0, 80.0, 21.0, 46.0, 0.10, 0.7):
			return true
		if _blob(c, -7.0, 36.0, 17.0, 22.0, 0.12, 2.1):
			return true
		if _blob(c, 1.0, 120.0, 18.0, 18.0, 0.12, 4.0):
			return true
	# The ship canal, running east off the sound into the lake. Its centreline
	# wanders, but not where the waterfront crosses it.
	if c.x >= 12 and c.x <= 70:
		var mid: float = 46.0 + 1.7 * sin(float(c.x - 26) * 0.16)
		if absf(float(c.y) - mid) <= 2.0:
			return true
	if _blob(c, 76.0, 55.0, 15.0, 13.0, 0.13, 1.2):     # the lake in the middle
		return true
	if _blob(c, 55.0, 14.0, 7.0, 6.0, 0.15, 0.4):       # the little one up north
		return true
	# The big lake, east. Held clear of the road on one side and of the map's edge
	# on the other, which leaves it a channel between two banks.
	if c.x >= 121 and c.x <= 130 and _blob(c, 126.0, 66.0, 14.0, 44.0, 0.09, 3.3):
		return true
	if _blob(c, 116.0, 71.0, 12.0, 9.0, 0.08, 1.9):     # and its western arm
		return true
	return false


## The ground the game will actually build: the track's own bounds plus the margin
## TerrainWorld draws around them. Water outside it would be stored in the file and
## never seen.
func _terrain_region() -> Rect2i:
	var lo := Vector2i(99999, 99999)
	var hi := Vector2i(-99999, -99999)
	for cell in _grid.tiles:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return Rect2i(lo - Vector2i(TerrainWorld.MARGIN, TerrainWorld.MARGIN),
		hi - lo + Vector2i(2 * TerrainWorld.MARGIN + 1, 2 * TerrainWorld.MARGIN + 1))


func _water_cells() -> Array[Vector2i]:
	if not _water_cache.is_empty():
		return _water_cache
	var region := _terrain_region()
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var c := Vector2i(x, y)
			if _is_water(c):
				_water_cache.append(c)
	return _water_cache


# --- Ground -----------------------------------------------------------------

## The hills the city is built on, and the mountain it looks at: peak cell, height
## in levels, and how far the shoulders spread. A single cell shoved up relaxes
## into a cone -- one level per cell is the steepest ground the engine allows -- so
## each of these is really a peak plus a scatter of lower ones around it, which is
## what keeps them from all being the same tidy pyramid.
const HILLS := [
	[34, 64, 10, 7],     # the big hill north of downtown
	[98, 60, 9, 8],      # the ridge east of the lake
	[38, 88, 5, 4],      # the rise downtown climbs over
	[70, 92, 7, 6],      # above the yards
	[9, 20, 9, 7],       # the headland at the top of the sound
	[30, 16, 5, 5], [66, 24, 4, 4], [104, 22, 6, 5], [58, 76, 3, 3], [92, 94, 5, 4],
	# the wooded shore on the far side of the water. The carve cuts these back to
	# whatever fits beside the sound -- they only have to close the view.
	[-1, 44, 8, 5], [0, 68, 8, 5], [-1, 92, 9, 5], [0, 114, 8, 5],
	# hills standing where the ground runs out, north, east and south, so the edge
	# of the world is a skyline rather than a horizon that stops
	[46, 8, 11, 6], [86, 6, 12, 7], [135, 26, 12, 7], [137, 52, 10, 6], [138, 96, 10, 6],
	[56, 130, 12, 7], [96, 132, 11, 6],
	# the mountain, a long way off and always there, with two lesser summits so it
	# reads as a massif rather than one tidy pyramid
	[120, 120, 18, 12], [110, 128, 13, 7], [131, 112, 14, 8],
]


func _sculpt_hills(terrain: Terrain) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 11
	for h in HILLS:
		var peak := Vector2i(int(h[0]), int(h[1]))
		var level: int = int(h[2])
		var spread: int = int(h[3])
		# Shoulders first, the summit last, so nothing carves a notch out of it.
		for i in range(spread * 2):
			var a: float = rng.randf() * TAU
			var d: float = float(spread) * sqrt(rng.randf())
			terrain.level_to(
				peak + Vector2i(int(round(cos(a) * d)), int(round(sin(a) * d))),
				int(round(float(level) * rng.randf_range(0.4, 0.85))))
		terrain.level_to(peak, level)


## Pull the ground under every tile up (or down) to the tile's own level, so the
## road rests on it instead of in it.
func _conform(terrain: Terrain) -> void:
	var decks: Array[Vector2i] = []
	for cell in _grid.tiles:
		var placed: PlacedTile = _grid.tiles[cell]
		var def: TileDefinition = _lib.definitions[placed.def_id]
		for fc in TrackGrid.footprint_cells(cell, def, placed.rotation):
			if _deck.has(fc):
				decks.append(fc)
			elif not _is_water(fc):
				terrain.level_to(fc, placed.elevation_level)
	# Bridges last, and only where they are over dry land: a deck sits a level
	# above its own base, so levelling the abutment to the base drops the shore
	# away from the deck instead of climbing up to meet it.
	for fc in decks:
		if not _is_water(fc):
			terrain.level_to(fc, _grid.get_placed(fc).elevation_level)
	for c in _pit:
		if not _is_water(c):
			terrain.level_to(c, int(_pit[c]))


## Flatten every water cell, and a cell of shore around it, down to the waterline.
## Water needs a basin: the square must be flat and nothing within one square of it
## may be lower, or the lake refuses to sit there.
func _carve_water(terrain: Terrain) -> void:
	var seen := {}
	for c in _water_cells():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not seen.has(n):
					seen[n] = true
					terrain.level_to(n, 0)


func _flood(terrain: Terrain) -> int:
	var count := 0
	for c in _water_cells():
		if terrain.add_lake(c):
			count += 1
		else:
			_warn("no water at %v: %s" % [c, terrain.lake_blocker(c)])
	return count


# --- Scenery ----------------------------------------------------------------

const TREE := PropGeo.Kind.TREE
const HOUSE := PropGeo.Kind.HOUSE
const BUILDING := PropGeo.Kind.BUILDING
const SCENERY := PropGeo.Kind.SCENERY

## How far from the road scenery is worth building. Every prop is a solid body with
## its own mesh, so a city you cannot see from the car is only a frame rate.
const BUILD_REACH := 16
const TREE_REACH := 14

var _near: Dictionary = {}      ## cell -> cells from the nearest tile
var _blocked: Dictionary = {}   ## cells the road wants kept clear

## The districts, in the order they are built: rect, what goes up in it, how far
## apart, and how often. A building stands on a 2x2 plot and a house on a 1x2 one,
## so a step of 3 leaves a street between them.
const DISTRICTS := [
	# downtown: one long strip of towers along the quay, from the docks in the
	# south to the blocks below the hill, thinning into mid-rise as it goes north
	{"rect": Rect2i(28, 92, 15, 17), "kind": 2, "variants": [0, 0, 1, 3], "step": Vector2i(3, 3), "fill": 0.95},
	{"rect": Rect2i(28, 58, 15, 34), "kind": 2, "variants": [1, 0, 3, 1], "step": Vector2i(3, 3), "fill": 0.8},
	# south of the lake
	{"rect": Rect2i(44, 60, 18, 18), "kind": 2, "variants": [1, 3, 1, 2], "step": Vector2i(3, 4), "fill": 0.6},
	# the yards: long low sheds
	{"rect": Rect2i(46, 92, 56, 9), "kind": 2, "variants": [2, 2, 2, 1], "step": Vector2i(4, 4), "fill": 0.5},
	# the piers, on the strip between the quay and the water
	{"rect": Rect2i(20, 56, 5, 50), "kind": 1, "variants": [1, 3], "step": Vector2i(2, 4), "fill": 0.5},
	# houses: the ridge east of the lake
	{"rect": Rect2i(90, 34, 25, 62), "kind": 1, "variants": [0, 1, 2, 3], "step": Vector2i(2, 3), "fill": 0.5},
	# houses: the north of the city
	{"rect": Rect2i(24, 6, 92, 20), "kind": 1, "variants": [0, 1, 2, 3], "step": Vector2i(2, 3), "fill": 0.45},
	# houses: the streets between downtown and the yards
	{"rect": Rect2i(46, 80, 40, 10), "kind": 1, "variants": [0, 3, 1, 2], "step": Vector2i(2, 3), "fill": 0.4},
	# houses: along the canal, west of the lake
	{"rect": Rect2i(28, 50, 34, 8), "kind": 1, "variants": [0, 1, 3, 2], "step": Vector2i(2, 3), "fill": 0.4},
	# and a handful of towers in the middle of it all, too far off the road to
	# drive past but close enough to be the skyline you see across the water
	{"rect": Rect2i(46, 62, 20, 26), "kind": 2, "variants": [0, 0, 3, 1], "step": Vector2i(6, 7),
		"fill": 0.85, "reach": 999},
	# the treeline on the far shore, which is all anyone sees of it
	{"rect": Rect2i(-2, 32, 8, 92), "kind": 0, "variants": [0, 0, 1, 2], "step": Vector2i(2, 3),
		"fill": 0.55, "reach": 999},
]


func _scenery(terrain: Terrain) -> int:
	_mark_track()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var count := 0
	for d in DISTRICTS:
		count += _fill_district(d, rng)
	count += _street_furniture()
	count += _trees(terrain, rng)
	return count


## Distance in cells from the road, out as far as anything is placed, and the cells
## kept clear of scenery: the tarmac and one cell around it. Close enough to shave,
## not close enough to be a wall on the racing line.
func _mark_track() -> void:
	var frontier: Array[Vector2i] = []
	for cell in _grid.tiles:
		var placed: PlacedTile = _grid.tiles[cell]
		var def: TileDefinition = _lib.definitions[placed.def_id]
		for fc in TrackGrid.footprint_cells(cell, def, placed.rotation):
			if not _near.has(fc):
				_near[fc] = 0
				frontier.append(fc)
	for fc in frontier:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_blocked[fc + Vector2i(dx, dy)] = true
	var reach: int = maxi(BUILD_REACH, TREE_REACH)
	var d := 0
	while d < reach and not frontier.is_empty():
		var next: Array[Vector2i] = []
		for c in frontier:
			for o in TrackGrid.OFFSETS:
				var n: Vector2i = c + o
				if not _near.has(n):
					_near[n] = d + 1
					next.append(n)
		frontier = next
		d += 1


func _room_for(anchor: Vector2i, kind: int, rot: int, reach: int) -> bool:
	for c in TrackGrid.prop_cells(anchor, kind, rot):
		if _blocked.has(c) or _grid.has_prop(c) or _is_water(c):
			return false
		if int(_near.get(c, 999)) > reach:
			return false
	return true


func _put(anchor: Vector2i, kind: int, variant: int, rot: int, reach: int) -> bool:
	if not _room_for(anchor, kind, rot, reach):
		return false
	_grid.place_prop(anchor, PlacedProp.make(kind, variant, rot))
	return true


func _fill_district(d: Dictionary, rng: RandomNumberGenerator) -> int:
	var rect: Rect2i = d["rect"]
	var kind: int = int(d["kind"])
	var variants: Array = d["variants"]
	var step: Vector2i = d["step"]
	var fill: float = float(d["fill"])
	var reach: int = int(d.get("reach", BUILD_REACH if kind == BUILDING else TREE_REACH))
	var count := 0
	var x: int = rect.position.x
	while x < rect.end.x:
		var y: int = rect.position.y
		while y < rect.end.y:
			if rng.randf() < fill:
				var v: int = int(variants[rng.randi() % variants.size()])
				var rot: int = 0 if kind == BUILDING else (rng.randi() % 2) * 2
				if _put(Vector2i(x, y), kind, v, rot, reach):
					count += 1
			y += step.y
		x += step.x
	return count


## Lamps down the quay, hoardings where the road is quick, and a water tower on top
## of each of the hills the city is built over.
func _street_furniture() -> int:
	var count := 0
	for y in range(56, 108, 4):
		if _put(Vector2i(24, y), SCENERY, 3, 0, BUILD_REACH):
			count += 1
	for y in range(58, 108, 6):
		if _put(Vector2i(28, y), SCENERY, 3, 0, BUILD_REACH):
			count += 1
	for x in range(52, 104, 7):
		if _put(Vector2i(x, 110), SCENERY, 2, 0, BUILD_REACH):
			count += 1
	for x in range(44, 110, 9):
		if _put(Vector2i(x, 30), SCENERY, 2, 0, BUILD_REACH):
			count += 1
	for h in HILLS:
		if int(h[2]) >= 5 and int(h[2]) < 20:
			if _put(Vector2i(int(h[0]) + 1, int(h[1]) + 1), SCENERY, 1, 0, 999):
				count += 1
	return count


## Trees everywhere that is left: thick on the hills and the parks, thin between
## the houses, next to none downtown.
func _trees(terrain: Terrain, rng: RandomNumberGenerator) -> int:
	var count := 0
	for cell in _near:
		var c: Vector2i = cell
		if int(_near[c]) > TREE_REACH or int(_near[c]) < 2:
			continue
		if _is_water(c) or _blocked.has(c) or _grid.has_prop(c):
			continue
		var lv: int = terrain.height_level(c)
		var chance := 0.06
		if lv >= 5:
			chance = 0.30          # wooded hillside
		elif lv >= 3:
			chance = 0.16
		if Rect2i(26, 92, 18, 20).has_point(c) or Rect2i(26, 58, 14, 22).has_point(c):
			chance = 0.02          # downtown: the odd street tree
		if rng.randf() < chance:
			_grid.place_prop(c, PlacedProp.make(TREE, rng.randi() % 4, rng.randi() % 4))
			count += 1
	return count


# --- Saving and reporting ---------------------------------------------------

func _save(terrain: Terrain) -> void:
	var dict := TrackSerializer.to_dict(_grid, _lib, TRACK_NAME, "OVERDRIVE", terrain)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		_warn("could not write " + OUT_PATH)
		return
	f.store_string(JSON.stringify(dict, "  "))
	f.close()


func _report(lakes: int, props: int) -> void:
	var lo := Vector2i(99999, 99999)
	var hi := Vector2i(-99999, -99999)
	var kinds := {}
	for cell in _grid.tiles:
		var placed: PlacedTile = _grid.tiles[cell]
		kinds[placed.def_id] = int(kinds.get(placed.def_id, 0)) + 1
		var def: TileDefinition = _lib.definitions[placed.def_id]
		for fc in TrackGrid.footprint_cells(cell, def, placed.rotation):
			lo = lo.min(fc)
			hi = hi.max(fc)
	var route: Array = RacePath.compute(_grid, _lib)
	print("EMERALD SOUND  tiles=%d  route=%d %s  lap=%d m  span=%dx%d  props=%d  lakes=%d  warns=%d" % [
		_grid.tiles.size(), route.size(),
		"COMPLETE" if route.size() >= _grid.tiles.size() else "SHORT",
		int(RacePath.route_length(_grid, _lib)),
		hi.x - lo.x, hi.y - lo.y, props, lakes, _warns])
	var line := "  pieces:"
	for id in kinds:
		line += " %s=%d" % [id, kinds[id]]
	print(line)
