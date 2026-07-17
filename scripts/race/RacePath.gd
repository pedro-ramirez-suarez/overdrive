class_name RacePath
extends RefCounted
## Derives an ordered path of cells through a track by walking road connections
## from the Start tile (SPEC.md §M4). Used for checkpoints and the AI racing line.

const NONE := Vector2i(2147483647, 2147483647)
## Caps on the circuit search. The walk backtracks, so a pathological layout could
## in principle explore forever; real tracks finish in a few hundred steps.
const SEARCH_BUDGET := 60000
const MAX_PATH := 2048
## How many cells past its lip a launch ramp may be considered to land.
const JUMP_GAP_CELLS := 6


## Ordered ANCHOR cells forming the route — one entry per tile, never a tile's
## interior cells. Empty if there is no track. For a closed circuit the first
## entry is the start/finish and the route does not repeat it.
##
## Walking tiles rather than cells matters. A cell-level walk treats a multi-cell
## tile's interior as ordinary road: the cells of one tile all report connected to
## each other, so the walk wanders inside a loop or a banked curve, marks those
## cells visited, and dead-ends — leaving most of the circuit off the path. It also
## yields cells that are not anchors, which nothing downstream can look up.
## The search BACKTRACKS, and takes the longest circuit that returns to the start.
## A greedy walk cannot do this: a jump ramp has road on one edge only — you launch
## off its lip — so it is a spur, and a walk that steps onto one dead-ends there and
## abandons the rest of the lap. Taking the longest closing route also skips
## shortcuts across a track that crosses itself.
static func compute(grid: TrackGrid, lib: TileLibrary) -> Array[Vector2i]:
	if grid.tiles.is_empty():
		return []

	var start: Vector2i = lib.find_start_cell(grid)
	if start == NONE:
		start = grid.tiles.keys()[0]

	var path: Array[Vector2i] = [start]
	var state := {
		"grid": grid,
		"start": start,
		"budget": SEARCH_BUDGET,
		"cycle": [] as Array[Vector2i],   # longest route back to the start
		"open": path.duplicate(),         # longest route of any kind, as a fallback
	}
	_walk(state, start, path, {start: true})

	var cycle: Array[Vector2i] = state["cycle"]
	if not cycle.is_empty():
		return cycle
	# No closed circuit (an unfinished track): the longest run is the best we have.
	var open: Array[Vector2i] = state["open"]
	return open


static func _walk(state: Dictionary, current: Vector2i, path: Array[Vector2i], visited: Dictionary) -> void:
	state["budget"] -= 1
	if state["budget"] <= 0 or path.size() >= MAX_PATH:
		return
	if path.size() > (state["open"] as Array).size():
		state["open"] = path.duplicate()

	for n in tile_neighbors(state["grid"], current):
		if n == state["start"]:
			# Back at the start: a complete lap. Longest wins.
			if path.size() > 2 and path.size() > (state["cycle"] as Array).size():
				state["cycle"] = path.duplicate()
			continue
		if visited.has(n):
			continue
		visited[n] = true
		path.append(n)
		_walk(state, n, path, visited)
		path.pop_back()
		visited.erase(n)


## Anchors of the tiles whose road joins the tile at `anchor`. Every cell of the
## tile is checked, since a multi-cell tile connects only at its road connectors,
## which may be nowhere near its anchor.
static func tile_neighbors(grid: TrackGrid, anchor: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var placed: PlacedTile = grid.tiles.get(anchor)
	var def: TileDefinition = grid.get_def(anchor)
	if placed == null or def == null:
		return out
	var seen := {}
	for c in TrackGrid.footprint_cells(anchor, def, placed.rotation):
		for dir in range(4):
			var n: Vector2i = c + TrackGrid.OFFSETS[dir]
			var n_anchor: Vector2i = grid.get_anchor(n)
			if n_anchor == TrackGrid.NONE or n_anchor == anchor or seen.has(n_anchor):
				continue
			if grid.cells_connected(c, n):
				seen[n_anchor] = true
				out.append(n_anchor)

	# A launch ramp joins the road it throws you onto, across the gap between.
	var landing := jump_landing(grid, anchor)
	if landing != NONE and not seen.has(landing):
		out.append(landing)
	return out


## Where a launch ramp at `anchor` lands, or NONE.
##
## A ramp presents road on exactly one edge — you leave over the far lip, so there
## is deliberately no socket there and no tile touching it. Sockets therefore
## cannot describe the link, and without this a jump reads as a dead end: the lap
## route stops at the ramp and the rest of the circuit is never found.
static func jump_landing(grid: TrackGrid, anchor: Vector2i) -> Vector2i:
	var placed: PlacedTile = grid.tiles.get(anchor)
	var def: TileDefinition = grid.get_def(anchor)
	if placed == null or def == null or def.footprint != Vector2i.ONE:
		return NONE

	var road_dir := -1
	var roads := 0
	for dir in 4:
		var s: Dictionary = TrackGrid.effective_socket(
			def, placed.rotation, placed.elevation_level, anchor, anchor, dir)
		if s.get("has_road", false):
			road_dir = dir
			roads += 1
	if roads != 1:
		return NONE  # not a launch ramp

	var launch: int = TrackGrid.opposite(road_dir)
	for step in range(1, JUMP_GAP_CELLS + 1):
		var c: Vector2i = anchor + TrackGrid.OFFSETS[launch] * step
		var a: Vector2i = grid.get_anchor(c)
		if a == TrackGrid.NONE or a == anchor:
			continue
		# The first tile beyond the lip must face back at the ramp to be a landing.
		var lp: PlacedTile = grid.tiles[a]
		var ld: TileDefinition = grid.get_def(a)
		if lp == null or ld == null:
			return NONE
		var s2: Dictionary = TrackGrid.effective_socket(
			ld, lp.rotation, lp.elevation_level, a, c, TrackGrid.opposite(launch))
		return a if s2.get("has_road", false) else NONE
	return NONE
