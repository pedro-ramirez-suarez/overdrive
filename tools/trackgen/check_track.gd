extends Node
## Check a built track the way the game will read it.
##
## Loads a track file, walks the lap the race does, and looks for road buried in
## its own ground -- the two things a generated track can get wrong that reading
## the JSON will not show.
##
## It needs the autoloads, so it runs as a scene rather than with --script:
##
##   godot --headless --path . tools/trackgen/check_track.tscn -- tracks/zuzuka.json

## Pieces whose road is allowed to stop: the overpass keeps a stub of road under
## its deck even where nothing crosses, and a jump ramp is supposed to end in air.
const OPEN_BY_DESIGN := ["overpass", "jump"]

func _ready() -> void:
	var lib := TileLibrary.new()
	lib.build()
	var path: String = OS.get_cmdline_user_args()[0]
	var data: Dictionary = TrackSerializer.load_track(path, lib)
	if data.is_empty():
		print("FAILED to load ", path)
		get_tree().quit(1)
		return
	var grid: TrackGrid = data["grid"]
	# A tile the size of a corner piece covers several cells but is walked once.
	var anchors := {}
	for cell in grid.tiles:
		anchors[grid.get_anchor(cell)] = true
	var route: Array = RacePath.compute(grid, lib)
	print(data["name"], ": ", anchors.size(), " tiles, route ", route.size(),
		"  ", "COMPLETE" if route.size() >= anchors.size() else "SHORT -- the lap breaks")
	print("  lap ", int(RacePath.route_length(grid, lib)), " m")

	# Road that stops. RacePath can leap a gap -- that is what jump ramps are for --
	# so a complete route does not prove the pieces actually join. Every socket with
	# road on it should meet another one, and a track with open ends has a hole in
	# it somewhere, however well the lap walks.
	var open_ends := 0
	var by_design := 0
	for cell in grid.tiles:
		for dir in range(4):
			var s: Dictionary = grid.get_socket(cell, dir)
			if s.is_empty() or not s.has_road:
				continue
			if grid.cells_connected(cell, cell + TrackGrid.OFFSETS[dir]):
				continue
			# Some pieces are meant to have road going nowhere: an overpass carries a
			# stub of road under its deck whether or not anything crosses there, and a
			# jump ramp ends in mid-air on purpose.
			if String(grid.get_placed(cell).def_id) in OPEN_BY_DESIGN:
				by_design += 1
				continue
			open_ends += 1
			if open_ends <= 8:
				print("    road stops at ", cell, " (", grid.get_placed(cell).def_id,
					") facing ", ["N", "E", "S", "W"][dir])
	print("  open road ends: ", open_ends,
		"" if by_design == 0 else "  (%d more under bridges and off jumps, as intended)" % by_design)

	# Terrain corners are flattened to the highest tile touching them, so ground
	# standing over a tile means the road is buried in its own verge.
	var terrain: Terrain = data["terrain"]
	var over := 0
	var worst := 0
	var buried := 0
	var deep := 0
	for cell in grid.tiles:
		var lv: int = (grid.get_placed(cell) as PlacedTile).elevation_level
		var lo := 999
		for dx in [0, 1]:
			for dy in [0, 1]:
				var h: int = terrain.corner_level(cell.x + dx, cell.y + dy) if terrain else 0
				lo = mini(lo, h)
				if h > lv:
					over += 1
					worst = maxi(worst, h - lv)
		if lo > lv:
			buried += 1
			deep = maxi(deep, lo - lv)
	print("  ground over a tile at ", over, " corners (worst ", worst, " level(s))")
	print("  cells with ground over all four corners: ", buried, " (worst ", deep, ")")
	get_tree().quit()
