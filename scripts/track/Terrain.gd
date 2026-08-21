class_name Terrain
extends RefCounted
## Procedural terrain heightfield for a track (SPEC.md §M6). Preset styles drive
## noise-based per-cell height (0..MAX_TERRAIN_LEVEL levels) and lakes. The track
## drapes over this — tile elevations follow `height_level` and you drive on the
## hills off-track.

## NOTE: append new presets only. A saved track stores this enum's integer value,
## so inserting a type would silently re-interpret the terrain of every existing
## save (FLAT is last for exactly that reason, even though it leads the palette).
enum Type { PLAINS, HILLS, LAKES, MOUNTAINS, FLAT }
const TYPE_NAMES: Array[String] = ["Plains", "Hills", "Lakes", "Mountains", "Flat"]

## How far a lake bed is dug below its rim level, in meters.
const WATER_DEPTH := 2.0
## Water surface, in meters relative to the lake's rim level. Fall below it and
## you're in the lake. (Level 0 for the procedural lakes, so -0.3 absolute.)
const WATER_SURFACE := -0.3
## Returned by lake_corner_level() when no lake touches a corner.
const NO_LAKE := -1
## The terrain surface sits this far below the matching track level so the road
## rests on top of it (avoids z-fighting).
const TRACK_CLEARANCE := 0.05

## Corner offsets of a cell, in corner-index space (SW, SE, NW, NE).
const CELL_CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const CORNER_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var type: Type = Type.HILLS
var seed_value: int = 0

var _height_noise: FastNoiseLite = FastNoiseLite.new()
var _water_noise: FastNoiseLite = FastNoiseLite.new()
var _amplitude: float = 3.0
var _water_threshold: float = 9.0  # >1 disables water

## Hand-sculpted corner levels (Vector2i corner -> int level), overriding the
## noise. Only edited corners are stored, so an untouched map costs nothing.
var _edits: Dictionary = {}

## Hand-placed lakes (Vector2i cell -> rim level). Unlike the procedural lakes,
## which only flood the low ground, these sit at any height — on a plateau or a
## mountain top — because each carries its own level.
var _lakes: Dictionary = {}


func setup(p_type: int, p_seed: int) -> void:
	type = p_type as Type
	seed_value = p_seed
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.seed = p_seed
	_water_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_water_noise.seed = p_seed + 7919
	_water_noise.frequency = 0.05

	# NOTE: amplitude * frequency must stay <= ~0.45 so the terraced field never
	# steps more than one level between neighbouring cells (equal-angle ramps, no
	# cliffs). Taller terrain therefore also gets broader — as real hills are.
	match type:
		Type.FLAT:
			# Zero amplitude: dead-level ground at level 0, no lakes — a blank
			# canvas for the editor's sculpt tools. The seed is irrelevant here.
			_height_noise.frequency = 0.05
			_amplitude = 0.0
			_water_threshold = 9.0
		Type.PLAINS:
			_height_noise.frequency = 0.04
			_amplitude = 3.0    # gentle, ~9 m
			_water_threshold = 9.0
		Type.HILLS:
			_height_noise.frequency = 0.03
			_amplitude = 8.0    # rolling, ~24 m
			_water_threshold = 9.0
		Type.LAKES:
			_height_noise.frequency = 0.035
			_amplitude = 6.0    # ~18 m with water in the low ground
			_water_threshold = 0.30
		Type.MOUNTAINS:
			_height_noise.frequency = 0.015
			# Held at 16 rather than the ceiling: the preset is what it always was,
			# and raising the ceiling is for hand-sculpted mountains, not for making
			# every Mountains map twice as tall as the one someone already built.
			_amplitude = 16.0   # ~48 m peaks
			_water_threshold = 9.0


# Continuous (fractional) height in levels at a grid position. Sampled at cell
# centres for tiles and at cell corners for the mesh.
func _level_value(x: float, y: float) -> float:
	return (_height_noise.get_noise_2d(x, y) + 1.0) * 0.5 * _amplitude


## Integer terrain height of a cell, 0..MAX_TERRAIN_LEVEL — the level a track
## tile placed here sits at. Averaged from the cell's four corners (rather than
## sampled at its centre) so a tile always agrees with the ground under it, and
## so sculpting a corner moves the tiles resting on it.
func height_level(cell: Vector2i) -> int:
	var total := 0
	for o in CELL_CORNERS:
		total += corner_level(cell.x + o.x, cell.y + o.y)
	return clampi(int(round(total / 4.0)), 0, Constants.MAX_TERRAIN_LEVEL)


## Integer terrain level at cell corner (i, j) — the SW corner of cell (i, j).
## A sculpted corner overrides the noise field. Rounding a smooth field gives
## terraces: flat plateaus separated by single-level bands.
func corner_level(i: int, j: int) -> int:
	var key := Vector2i(i, j)
	if _edits.has(key):
		return _edits[key]
	return clampi(int(round(_level_value(i - 0.5, j - 0.5))), 0, Constants.MAX_TERRAIN_LEVEL)


func is_water_at(x: float, y: float) -> bool:
	if _water_threshold > 1.0:
		return false
	# Only the low ground floods (scaled to the terrain's amplitude).
	return _water_noise.get_noise_2d(x, y) > _water_threshold and _level_value(x, y) <= _amplitude * 0.25


# --- Hand-placed lakes ------------------------------------------------------

func has_lake(cell: Vector2i) -> bool:
	return _lakes.has(cell)


## Why a lake cannot sit at `cell`, or "" if it can.
##
## Water needs a basin, so the square must be flat and nothing within one square
## of it may be lower. That is what stops a lake being perched on the edge of a
## plateau or mountain, where it would sit on a slope or pour over the side.
## Neighbouring lakes are fine: they never change the land level, and the
## terracing invariant means two adjacent flat squares are necessarily at the
## same level — so every lake touching a corner shares one rim height.
func lake_blocker(cell: Vector2i) -> String:
	var lv := corner_level(cell.x, cell.y)
	for o in CELL_CORNERS:
		if corner_level(cell.x + o.x, cell.y + o.y) != lv:
			return "square isn't flat"
	for dx in range(-1, 3):
		for dz in range(-1, 3):
			if corner_level(cell.x + dx, cell.y + dz) < lv:
				return "too near an edge — the water would spill"
	return ""


## Flood `cell` if it can hold water. Returns false (and does nothing) if not.
func add_lake(cell: Vector2i) -> bool:
	if lake_blocker(cell) != "":
		return false
	_lakes[cell] = corner_level(cell.x, cell.y)
	return true


func remove_lake(cell: Vector2i) -> void:
	_lakes.erase(cell)


## Rim level of the lake in `cell`, or NO_LAKE if it holds no water.
func lake_level(cell: Vector2i) -> int:
	return _lakes.get(cell, NO_LAKE)


## True when all four cells touching corner (i, j) hold the same lake — i.e. the
## corner is out in open water rather than on the shore. Drives the bed's depth,
## which is what shapes the shoreline.
func lake_corner_interior(i: int, j: int, lv: int) -> bool:
	for c in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if _lakes.get(c, NO_LAKE) != lv:
			return false
	return true


## Height of `cell`'s water surface. Only meaningful when is_water(cell).
func water_surface(cell: Vector2i) -> float:
	if _lakes.has(cell):
		return _lakes[cell] * Constants.ELEVATION_STEP + WATER_SURFACE
	return WATER_SURFACE


## Re-check every lake after the ground moved: sculpting beside one can open its
## edge, and water left perched on a slope would be nonsense. Survivors follow the
## ground up or down.
func _settle_lakes() -> void:
	for cell in _lakes.keys():
		if lake_blocker(cell) != "":
			_lakes.erase(cell)
		else:
			_lakes[cell] = corner_level(cell.x, cell.y)


func lakes_to_array() -> Array:
	var out: Array = []
	for c in _lakes:
		out.append(c.x)
		out.append(c.y)
		out.append(int(_lakes[c]))
	return out


func lakes_from_array(a: Array) -> void:
	_lakes.clear()
	var i := 0
	while i + 2 < a.size():
		_lakes[Vector2i(int(a[i]), int(a[i + 1]))] = clampi(int(a[i + 2]), 0, Constants.MAX_TERRAIN_LEVEL)
		i += 3


func is_water(cell: Vector2i) -> bool:
	if _lakes.has(cell):
		return true
	if not is_water_at(cell.x, cell.y):
		return false
	# Sculpted ground beats the procedural lake mask: raise a lake bed and it
	# drains to dry land.
	for o in CELL_CORNERS:
		var key := Vector2i(cell.x + o.x, cell.y + o.y)
		if _edits.has(key) and _edits[key] > 0:
			return false
	return true


# --- Sculpting (SimCity 2000-style raise / lower) ----------------------------

## Raise (delta > 0) or lower (delta < 0) the ground under `cell` by one level,
## then pull the neighbours along so the terracing invariant still holds — no two
## adjacent corners ever differ by more than one level, so every square stays
## flat or a single-level ramp and cliffs can't be sculpted.
##
## A click also flattens the square: raising a slope fills it to its low corner
## + 1, lowering cuts it to its high corner - 1. On flat ground that is simply
## +/- one level.
func sculpt(cell: Vector2i, delta: int) -> void:
	var lo := Constants.MAX_TERRAIN_LEVEL
	var hi := 0
	for o in CELL_CORNERS:
		var lv := corner_level(cell.x + o.x, cell.y + o.y)
		lo = mini(lo, lv)
		hi = maxi(hi, lv)
	level_to(cell, (lo + 1) if delta > 0 else (hi - 1))


## Flatten the square under `cell` to an absolute `level` — the tool for slicing
## a hilltop off at a chosen height. Neighbours are pulled along exactly as with
## sculpt(), so the cut skirts down to the surrounding land as single-level ramps
## instead of leaving a wall. Idempotent: levelling the same square twice is a
## no-op, so it is safe to drag over an area repeatedly.
func level_to(cell: Vector2i, level: int) -> void:
	var target: int = clampi(level, 0, Constants.MAX_TERRAIN_LEVEL)
	var corners: Array[Vector2i] = []
	for o in CELL_CORNERS:
		var c := Vector2i(cell.x + o.x, cell.y + o.y)
		corners.append(c)
		_set_corner(c, target)
	_relax(corners.duplicate())
	_settle_lakes()


func _set_corner(c: Vector2i, level: int) -> void:
	_edits[c] = clampi(level, 0, Constants.MAX_TERRAIN_LEVEL)


## Flood outward from `queue`, dragging any corner that sits more than one level
## from a settled neighbour. Terminates: every step moves a corner strictly
## closer to its neighbour, and levels are clamped to a finite range.
func _relax(queue: Array[Vector2i]) -> void:
	var guard := 0
	while not queue.is_empty():
		guard += 1
		if guard > 500000:
			push_warning("Terrain._relax failed to converge; terrain may have a cliff.")
			return
		var c: Vector2i = queue.pop_front()
		var lv := corner_level(c.x, c.y)
		for d in CORNER_NEIGHBOURS:
			var n: Vector2i = c + d
			var nv := corner_level(n.x, n.y)
			if nv < lv - 1:
				_set_corner(n, lv - 1)
				queue.append(n)
			elif nv > lv + 1:
				_set_corner(n, lv + 1)
				queue.append(n)


func has_edits() -> bool:
	return not _edits.is_empty()


## Sculpted corners as a flat [i, j, level, ...] array, for saving.
func edits_to_array() -> Array:
	var out: Array = []
	for c in _edits:
		out.append(c.x)
		out.append(c.y)
		out.append(int(_edits[c]))
	return out


func edits_from_array(a: Array) -> void:
	_edits.clear()
	var i := 0
	while i + 2 < a.size():
		_set_corner(Vector2i(int(a[i]), int(a[i + 1])), int(a[i + 2]))
		i += 3


## Ground surface height (meters) at a cell centre — basin for lakes, else level.
func world_height(cell: Vector2i) -> float:
	if is_water(cell):
		return -WATER_DEPTH
	return height_level(cell) * Constants.ELEVATION_STEP


## Ground surface height at a cell corner (terraced, discrete levels), dropped a
## little below the track level so the road sits on top of it.
func corner_height(i: int, j: int) -> float:
	# NB: hand-placed lakes deliberately do NOT dig the corners. Corners are shared
	# with the eight surrounding cells, so digging them would dent every neighbour
	# into a dry crater around the water. A hand lake is instead built as a walled
	# basin entirely inside its own cell — see TerrainWorld._add_lake_basin.
	# A sculpted corner always uses its own level, never the procedural basin.
	if not _edits.has(Vector2i(i, j)) and is_water_at(i - 0.5, j - 0.5):
		return -WATER_DEPTH
	return corner_level(i, j) * Constants.ELEVATION_STEP - TRACK_CLEARANCE


func type_name() -> String:
	return TYPE_NAMES[type]
