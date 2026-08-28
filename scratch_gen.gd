extends Node
## TEMP generator #2: a freeform winding circuit ("Serpentine Ridge"), shaped from a
## rectilinear polygon outline (auto-closing), with mountains on the long runs and the
## same conformed mountain terrain + lakes. Writes serpentine_ridge.json — leaves
## alpine_pass.json untouched.

const N := TrackGrid.N
const E := TrackGrid.E
const S := TrackGrid.S
const W := TrackGrid.W

const DIR_IDX := {
	Vector2i(0, -1): N, Vector2i(1, 0): E, Vector2i(0, 1): S, Vector2i(-1, 0): W,
}
const TURN_ROT := {
	Vector2i(N, E): 1, Vector2i(N, W): 2, Vector2i(E, S): 2, Vector2i(E, N): 3,
	Vector2i(S, W): 3, Vector2i(S, E): 0, Vector2i(W, N): 0, Vector2i(W, S): 1,
}

var _grid: TrackGrid
var _lib: TileLibrary
var _warns: int = 0


func _ready() -> void:
	_lib = TileLibrary.new()
	_lib.build()
	_grid = TrackGrid.new(_lib.definitions)

	var cells := _cells_from_verts(_make_verts())
	var levels := _assign_levels(cells)
	_place_loop(cells, levels)

	var terrain := Terrain.new()
	terrain.setup(Terrain.Type.MOUNTAINS, 71077345)
	_conform_terrain(terrain)
	_scenic_peaks(terrain)
	var lakes := _add_lakes(terrain)
	lakes += _tarns(terrain)
	var boulders := _scatter_boulders(terrain)

	GameState.current_grid = _grid
	GameState.current_terrain = terrain
	var dict := TrackSerializer.to_dict(_grid, _lib, "Serpentine Ridge", "OVERDRIVE")
	for path in ["res://tracks/serpentine_ridge.json", "user://tracks/serpentine_ridge.json"]:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(dict, "  "))
			f.close()

	var route: Array = RacePath.compute(_grid, _lib)
	var closed := false
	if route.size() >= 2:
		var a: Vector3 = TileLibrary.cell_to_world(route[0], _grid.tiles[route[0]].elevation_level)
		var b: Vector3 = TileLibrary.cell_to_world(route[-1], _grid.tiles[route[-1]].elevation_level)
		closed = a.distance_to(b) < 60.0
	var minx := 99999; var maxx := -99999; var miny := 99999; var maxy := -99999
	var curves := 0
	for c in _grid.tiles:
		minx = mini(minx, c.x); maxx = maxi(maxx, c.x); miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
		if _grid.tiles[c].def_id == &"curve": curves += 1
	print("GEN tiles=%d route=%d closed=%s warns=%d span=%dx%d curves=%d lakes=%d boulders=%d" % [
		_grid.tiles.size(), route.size(), closed, _warns, maxx - minx, maxy - miny, curves, lakes, boulders])
	get_tree().quit()


# --- Shape ------------------------------------------------------------------

## Corners of a winding closed rectilinear polygon (fingers on top and bottom, like
## the sketch). Consecutive corners share a row or column. y is DOWN.
func _make_verts() -> Array:
	return [
		Vector2i(0, 12), Vector2i(0, -24), Vector2i(8, -24), Vector2i(8, -12),
		Vector2i(15, -12), Vector2i(15, -34), Vector2i(24, -34), Vector2i(24, -14),
		Vector2i(31, -14), Vector2i(31, -32), Vector2i(40, -32), Vector2i(40, -10),
		Vector2i(48, -10), Vector2i(48, -30), Vector2i(56, -30), Vector2i(56, 12),
		Vector2i(48, 12), Vector2i(48, 2), Vector2i(40, 2), Vector2i(40, 16),
		Vector2i(31, 16), Vector2i(31, 4), Vector2i(23, 4), Vector2i(23, 16),
		Vector2i(15, 16), Vector2i(15, 4), Vector2i(7, 4), Vector2i(7, 12),
	]


## Ordered loop cells, each once (vertex included, next vertex excluded).
func _cells_from_verts(verts: Array) -> Array:
	var cells: Array = []
	for i in range(verts.size()):
		var a: Vector2i = verts[i]
		var b: Vector2i = verts[(i + 1) % verts.size()]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while c != b:
			cells.append(c)
			c += step
	return cells


func _is_corner(cells: Array, j: int) -> bool:
	var n := cells.size()
	var din: Vector2i = cells[j] - cells[(j - 1 + n) % n]
	var dout: Vector2i = cells[(j + 1) % n] - cells[j]
	return din != dout


## Level (elevation at each cell's exit). 0 at corners; a net-zero mountain sits in
## the middle of every long straight run.
func _assign_levels(cells: Array) -> Array:
	var n := cells.size()
	var levels: Array = []
	levels.resize(n)
	levels.fill(0)
	var j := 0
	while j < n:
		if _is_corner(cells, j):
			j += 1
			continue
		var start := j
		while j < n and not _is_corner(cells, j):
			j += 1
		var run := j - start
		if run >= 16:
			var peak: int = clampi(run / 6, 2, 5)
			var crest := 3
			var span := 2 * peak + crest
			var idx := start + (run - span) / 2
			var lvl := 0
			for k in range(peak):
				lvl += 1; levels[idx] = lvl; idx += 1
			for k in range(crest):
				levels[idx] = lvl; idx += 1
			for k in range(peak):
				lvl -= 1; levels[idx] = lvl; idx += 1
	return levels


func _place_loop(cells: Array, levels: Array) -> void:
	var n := cells.size()
	var start_done := false
	for j in range(n):
		var cell: Vector2i = cells[j]
		var prev_cell: Vector2i = cells[(j - 1 + n) % n]
		var din: Vector2i = cell - prev_cell
		var dout: Vector2i = cells[(j + 1) % n] - cell
		var hi: int = DIR_IDX[din]
		var ho: int = DIR_IDX[dout]
		var lvl: int = levels[j]
		var prev_lvl: int = levels[(j - 1 + n) % n]
		var def_id := ""
		var rot := 0
		var elev := lvl
		if hi != ho:
			def_id = "curve"; rot = TURN_ROT[Vector2i(hi, ho)]; elev = lvl
		elif lvl == prev_lvl:
			def_id = "straight"; rot = 0 if (ho == N or ho == S) else 1; elev = lvl
		elif lvl == prev_lvl + 1:
			def_id = "ramp_up"; rot = ho; elev = prev_lvl
		else:
			def_id = "ramp_down"; rot = ho; elev = lvl
		# Drop the start/finish onto the first flat N-S straight.
		if not start_done and def_id == "straight" and (ho == N or ho == S) and lvl == 0:
			def_id = "start"; start_done = true
		if _grid.has_tile(cell):
			_warns += 1; print("  WARN collision at %v" % cell)
		_grid.place(cell, StringName(def_id), rot, elev)
		if j > 0 and not _grid.cells_connected(prev_cell, cell):
			_warns += 1
			print("  WARN no connect %v -> %v (%s rot %d elev %d)" % [prev_cell, cell, def_id, rot, elev])


# --- Terrain ----------------------------------------------------------------

func _conform_terrain(terrain: Terrain) -> void:
	for cell in _grid.tiles:
		var placed: PlacedTile = _grid.tiles[cell]
		var def: TileDefinition = _lib.definitions[placed.def_id]
		for fc in TrackGrid.footprint_cells(cell, def, placed.rotation):
			terrain.level_to(fc, placed.elevation_level)


## Sharp, tall summits: a single cell shoved to (near) the max height relaxes into a
## steep cone — one level per cell is the steepest the ground can be, so these read as
## craggy peaks rather than rounded hills.
func _scenic_peaks(terrain: Terrain) -> void:
	for spec in [[20, -2, 16], [36, -3, 15], [11, -1, 14], [46, 7, 13], [28, -20, 16],
			[5, -30, 15], [52, -24, 14], [33, 10, 13]]:
		terrain.level_to(Vector2i(spec[0], spec[1]), spec[2])


func _add_lakes(terrain: Terrain) -> int:
	var count := 0
	for spot in [Vector2i(20, 9), Vector2i(4, 4), Vector2i(52, 6)]:
		for dx in range(2):
			for dz in range(2):
				terrain.level_to(spot + Vector2i(dx, dz), 0)
		for dx in range(2):
			for dz in range(2):
				if terrain.add_lake(spot + Vector2i(dx, dz)):
					count += 1
	return count


## High alpine tarns: a small flat shelf sculpted UP to a plateau, with the pool in
## its centre. A hand lake is a walled basin, so perched high it shows a short
## vertical face at the waterline — the closest thing to a cliff the ground allows.
func _tarns(terrain: Terrain) -> int:
	var count := 0
	for spec in [[13, -20, 6], [43, -22, 7], [27, 1, 5]]:
		var base := Vector2i(spec[0], spec[1])
		# Level a 4x4 shelf flat so the inner pool has no lower ground within a cell.
		for dx in range(4):
			for dz in range(4):
				terrain.level_to(base + Vector2i(dx - 1, dz - 1), spec[2])
		for dx in range(2):
			for dz in range(2):
				if terrain.add_lake(base + Vector2i(dx, dz)):
					count += 1
	return count


## Scatter boulders across the higher ground and ridgelines for a rocky, craggy look.
## Never on the road or in water; denser the higher (and steeper) the terrain.
func _scatter_boulders(terrain: Terrain) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var count := 0
	for x in range(-3, 60):
		for y in range(-37, 20):
			var cell := Vector2i(x, y)
			if _grid.has_tile(cell) or terrain.has_lake(cell):
				continue
			var lv := terrain.height_level(cell)
			if lv < 3:
				continue
			# Low per-cell odds, rising with height, so they spread evenly and thin out
			# on the low ground — no cap, no clustering in the first-scanned corner.
			if rng.randf() < clampf(0.006 + lv * 0.006, 0.0, 0.11):
				_grid.place_prop(cell, PlacedProp.make(PropGeo.Kind.SCENERY, 0, rng.randi() % 4))
				count += 1
	return count
