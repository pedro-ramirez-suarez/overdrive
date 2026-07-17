class_name TrackGrid
extends RefCounted
## The placed-tile grid and the connection contract (SPEC.md §M3, §5.2).
##
## Maps grid cells (Vector2i) to PlacedTile. Grid X maps to world X, grid Y maps
## to world Z. Directions are indexed N/E/S/W = 0/1/2/3.
##
## Tiles may be multi-cell (TileDefinition.footprint > 1x1). Their anchor cell
## holds the PlacedTile; the other footprint cells map to the anchor in
## `_occupancy`. Multi-cell tiles connect to neighbours only at their listed
## `road_connectors`; cells within one tile are internally connected.

const N: int = 0
const E: int = 1
const S: int = 2
const W: int = 3

const NONE := Vector2i(2147483647, 2147483647)

## Grid-cell offset for each direction, in [N, E, S, W] order.
const OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),  # N -> -Z
	Vector2i(1, 0),   # E -> +X
	Vector2i(0, 1),   # S -> +Z
	Vector2i(-1, 0),  # W -> -X
]

## StringName -> TileDefinition (shared, owned by TileLibrary).
var _library: Dictionary
## Anchor cell -> PlacedTile.
var tiles: Dictionary = {}
## Every occupied cell -> its anchor cell.
var _occupancy: Dictionary = {}
## Anchor cell -> PlacedProp. Scenery lives alongside the road network but plays
## no part in it: props have no sockets and never connect. Multi-cell props (a
## building's plot) keep their PlacedProp at the anchor; the other cells map to it
## in `_prop_cells`.
var props: Dictionary = {}
## Every cell a prop covers -> its anchor cell.
var _prop_cells: Dictionary = {}


## Cells a prop of `kind` at `anchor` covers, rotated. Mirrors footprint_cells.
static func prop_cells(anchor: Vector2i, kind: int, rotation: int) -> Array[Vector2i]:
	var size: Vector2i = PropGeo.cell_size(kind)
	var out: Array[Vector2i] = []
	for dx in range(size.x):
		for dz in range(size.y):
			out.append(anchor + rotate_offset(Vector2i(dx, -dz), rotation))
	return out


## Anchor of the prop covering `cell`, or NONE.
func prop_anchor(cell: Vector2i) -> Vector2i:
	if _prop_cells.has(cell):
		return _prop_cells[cell]
	return cell if props.has(cell) else NONE


func has_prop(cell: Vector2i) -> bool:
	return prop_anchor(cell) != NONE


## Place `prop` with `anchor` as its origin, clearing any props it overlaps.
func place_prop(anchor: Vector2i, prop: PlacedProp) -> void:
	var cells := prop_cells(anchor, prop.kind, prop.rotation)
	for c in cells:
		if has_prop(c):
			remove_prop(c)
	props[anchor] = prop
	for c in cells:
		_prop_cells[c] = anchor


## Remove the prop covering `cell` (from any of its cells), or do nothing.
func remove_prop(cell: Vector2i) -> void:
	var anchor := prop_anchor(cell)
	if anchor == NONE:
		return
	var prop: PlacedProp = props.get(anchor)
	if prop != null:
		for c in prop_cells(anchor, prop.kind, prop.rotation):
			_prop_cells.erase(c)
	props.erase(anchor)


func _init(library: Dictionary = {}) -> void:
	_library = library


static func opposite(dir: int) -> int:
	return (dir + 2) % 4


# --- Rotation & footprint ---------------------------------------------------

static func rotate_offset(off: Vector2i, r: int) -> Vector2i:
	var o := off
	for i in range(posmod(r, 4)):
		o = Vector2i(-o.y, o.x)  # 90 degrees clockwise
	return o


static func unrotate_offset(off: Vector2i, r: int) -> Vector2i:
	return rotate_offset(off, 4 - posmod(r, 4))


## World cells a tile with `def` at `anchor`/`rotation` occupies. The base
## footprint extends +X and -Z (north) from the anchor.
static func footprint_cells(anchor: Vector2i, def: TileDefinition, rotation: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(def.footprint.x):
		for dz in range(def.footprint.y):
			out.append(anchor + rotate_offset(Vector2i(dx, -dz), rotation))
	return out


# --- Placement --------------------------------------------------------------

func has_tile(cell: Vector2i) -> bool:
	return _occupancy.has(cell) or tiles.has(cell)


func get_anchor(cell: Vector2i) -> Vector2i:
	if _occupancy.has(cell):
		return _occupancy[cell]
	if tiles.has(cell):
		return cell
	return NONE


func get_placed(cell: Vector2i) -> PlacedTile:
	var anchor := get_anchor(cell)
	return tiles.get(anchor) if anchor != NONE else null


func get_def(cell: Vector2i) -> TileDefinition:
	var placed := get_placed(cell)
	return _library.get(placed.def_id) if placed != null else null


func place(cell: Vector2i, def_id: StringName, rotation: int = 0, elevation_level: int = 0) -> void:
	var def: TileDefinition = _library.get(def_id)
	if def == null:
		return
	var cells := footprint_cells(cell, def, rotation)
	for fc in cells:  # clear anything already occupying these cells
		if has_tile(fc):
			remove(fc)
	tiles[cell] = PlacedTile.new(def_id, rotation, elevation_level)
	for fc in cells:
		_occupancy[fc] = cell


func remove(cell: Vector2i) -> void:
	var anchor := get_anchor(cell)
	if anchor == NONE:
		return
	var placed: PlacedTile = tiles.get(anchor)
	var def: TileDefinition = _library.get(placed.def_id) if placed != null else null
	if def != null:
		for fc in footprint_cells(anchor, def, placed.rotation):
			_occupancy.erase(fc)
	tiles.erase(anchor)


# --- Sockets & connections --------------------------------------------------

## Effective socket for `cell` facing world direction `dir` as a Dictionary
## {has_road, elevation_level, slope}, or {} if `cell` is empty.
func get_socket(cell: Vector2i, dir: int) -> Dictionary:
	var anchor := get_anchor(cell)
	if anchor == NONE:
		return {}
	var placed: PlacedTile = tiles[anchor]
	var def: TileDefinition = _library.get(placed.def_id)
	if def == null:
		return {}
	return effective_socket(def, placed.rotation, placed.elevation_level, anchor, cell, dir)


## Socket a (possibly-unplaced) tile presents at `cell` facing `world_dir`.
static func effective_socket(def: TileDefinition, rotation: int, base_elev: int,
		anchor: Vector2i, cell: Vector2i, world_dir: int) -> Dictionary:
	var base_dir: int = (world_dir - rotation + 4) % 4
	if def.footprint == Vector2i.ONE:
		if def.sockets.size() < 4:
			return {}
		var s: TileSocket = def.sockets[base_dir]
		return {"has_road": s.has_road, "elevation_level": base_elev + s.elevation_level, "slope": s.slope}
	# Multi-cell: road only at the listed connectors.
	var local := unrotate_offset(cell - anchor, rotation)
	for conn in def.road_connectors:
		if conn["cell"] == local and conn["dir"] == base_dir:
			return {
				"has_road": true,
				"elevation_level": base_elev + int(conn.get("elevation", 0)),
				"slope": TileSocket.Slope.FLAT,
			}
	return {"has_road": false, "elevation_level": base_elev, "slope": TileSocket.Slope.FLAT}


## Do the tiles at cellA and cellB connect across their shared edge?
func cells_connected(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	var dir: int = OFFSETS.find(cell_b - cell_a)
	if dir == -1:
		return false
	var anchor_a := get_anchor(cell_a)
	var anchor_b := get_anchor(cell_b)
	if anchor_a != NONE and anchor_a == anchor_b:
		return true  # two cells of the same multi-cell tile
	return TrackGrid.sockets_connect(get_socket(cell_a, dir), get_socket(cell_b, opposite(dir)))


static func sockets_connect(sa: Dictionary, sb: Dictionary) -> bool:
	if sa.is_empty() or sb.is_empty():
		return false
	if not sa.has_road or not sb.has_road:
		return false
	if sa.elevation_level != sb.elevation_level:
		return false
	return slopes_complementary(sa.slope, sb.slope)


static func slopes_complementary(a: int, b: int) -> bool:
	if a == TileSocket.Slope.FLAT and b == TileSocket.Slope.FLAT:
		return true
	if a == TileSocket.Slope.UP and b == TileSocket.Slope.DOWN:
		return true
	if a == TileSocket.Slope.DOWN and b == TileSocket.Slope.UP:
		return true
	return false
