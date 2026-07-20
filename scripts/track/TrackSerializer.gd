class_name TrackSerializer
extends RefCounted
## Save/load tracks as JSON and enumerate the local track library (SPEC.md §M6).
## Format: { version, name, author, grid:[{cell_x,cell_y,def_id,rotation,
## elevation_level}], start_cell:[x,y], metadata }.

const VERSION := 1
const USER_DIR := "user://tracks"
const BUNDLED := ["res://tracks/sample_oval.json"]
const NONE := Vector2i(2147483647, 2147483647)


static func to_dict(grid: TrackGrid, lib: TileLibrary, track_name: String, author: String) -> Dictionary:
	var cells: Array = []
	for cell in grid.tiles:
		var p: PlacedTile = grid.tiles[cell]
		cells.append({
			"cell_x": cell.x, "cell_y": cell.y,
			"def_id": String(p.def_id), "rotation": p.rotation,
			"elevation_level": p.elevation_level,
		})
	var props: Array = []
	for cell in grid.props:
		var p: PlacedProp = grid.props[cell]
		props.append({
			"cell_x": cell.x, "cell_y": cell.y,
			"kind": int(p.kind), "variant": p.variant, "rotation": p.rotation,
		})
	var start: Vector2i = lib.find_start_cell(grid)
	var start_arr: Array = [start.x, start.y] if start != NONE else [0, 0]
	var terrain_data: Variant = null
	if GameState.current_terrain != null:
		terrain_data = {
			"type": GameState.current_terrain.type,
			"seed": GameState.current_terrain.seed_value,
			# Hand-sculpted corners, flat [i, j, level, ...]. Absent/empty means the
			# terrain is exactly what the noise preset generates.
			"edits": GameState.current_terrain.edits_to_array(),
			# Hand-placed lakes, flat [cell_x, cell_y, rim_level, ...].
			"lakes": GameState.current_terrain.lakes_to_array(),
		}
	return {
		"version": VERSION, "name": track_name, "author": author,
		"grid": cells, "props": props, "start_cell": start_arr,
		"terrain": terrain_data, "metadata": {},
	}


static func save(grid: TrackGrid, lib: TileLibrary, path: String, track_name: String, author: String) -> bool:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(grid, lib, track_name, author), "  "))
	f.close()
	return true


## Returns { grid: TrackGrid, name: String, author: String, terrain: Terrain } or
## {} on failure.
static func load_track(path: String, lib: TileLibrary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return from_dict(data, lib)


## Rebuild a track from an already-parsed dict (the shape `to_dict` produces). Split
## out from load_track so the editor can snapshot/restore state in memory for undo
## without going through a file.
static func from_dict(data: Dictionary, lib: TileLibrary) -> Dictionary:
	var grid := TrackGrid.new(lib.definitions)
	for c in data.get("grid", []):
		grid.place(
			Vector2i(int(c.get("cell_x", 0)), int(c.get("cell_y", 0))),
			StringName(c.get("def_id", "")),
			int(c.get("rotation", 0)),
			int(c.get("elevation_level", 0)))
	for p in data.get("props", []):
		grid.place_prop(
			Vector2i(int(p.get("cell_x", 0)), int(p.get("cell_y", 0))),
			PlacedProp.make(int(p.get("kind", 0)), int(p.get("variant", 0)), int(p.get("rotation", 0))))
	var terrain: Terrain = null
	var td: Variant = data.get("terrain", null)
	if typeof(td) == TYPE_DICTIONARY:
		terrain = Terrain.new()
		terrain.setup(int(td.get("type", 1)), int(td.get("seed", 0)))
		terrain.edits_from_array(td.get("edits", []))
		terrain.lakes_from_array(td.get("lakes", []))
	return {"grid": grid, "name": data.get("name", "Track"), "author": data.get("author", ""), "terrain": terrain}


static func default_save_path(track_name: String) -> String:
	var safe := track_name.strip_edges().to_lower().replace(" ", "_")
	if safe == "":
		safe = "track_%d" % int(Time.get_unix_time_from_system())
	return "%s/%s.json" % [USER_DIR, safe]


## Is `path` one of the tracks the game manages (i.e. in the user library)?
## Bundled res:// tracks and files loaded from elsewhere on disk are not.
static func is_in_library(path: String) -> bool:
	return path.begins_with(USER_DIR)


## Copy an external track file into the user library so it shows up in the track
## list. Returns the new path, or "" on failure. Names are made unique rather than
## overwriting: importing must never quietly destroy a track you already had.
static func import_track(src_path: String, lib: TileLibrary) -> String:
	var result := load_track(src_path, lib)
	if result.is_empty():
		return ""
	var track_name: String = result.get("name", "")
	if track_name.strip_edges() == "":
		track_name = src_path.get_file().get_basename()
	var dest := _unique_path(track_name)
	# Re-serialize rather than copying the bytes: it validates the file and
	# normalizes anything an older version wrote.
	var grid: TrackGrid = result.grid
	var prev_terrain: Terrain = GameState.current_terrain
	GameState.current_terrain = result.get("terrain", null)
	var ok := save(grid, lib, dest, track_name, result.get("author", "imported"))
	GameState.current_terrain = prev_terrain
	return dest if ok else ""


static func _unique_path(track_name: String) -> String:
	var base := default_save_path(track_name)
	if not FileAccess.file_exists(base):
		return base
	var stem := base.get_basename()
	for i in range(2, 1000):
		var candidate := "%s_%d.json" % [stem, i]
		if not FileAccess.file_exists(candidate):
			return candidate
	return base


## Delete a track from the user library. Bundled tracks are refused — they ship
## with the game and there is no way to get them back.
static func delete_track(path: String) -> bool:
	if not is_in_library(path):
		return false
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK \
		or DirAccess.remove_absolute(path) == OK


## All available tracks as [{ path, name, builtin }], bundled first.
static func list_tracks() -> Array:
	var out: Array = []
	for path in BUNDLED:
		if FileAccess.file_exists(path):
			out.append({"path": path, "name": _name_in(path), "builtin": true})
	var dir := DirAccess.open(USER_DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".json"):
				var p := "%s/%s" % [USER_DIR, file]
				out.append({"path": p, "name": _name_in(p), "builtin": false})
	return out


static func _name_in(path: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY and data.has("name"):
		return data["name"]
	return path.get_file().get_basename()
