class_name PlacementValidator
extends RefCounted
## Advisory placement feedback for the editor (SPEC.md §M3).
##
## Given a candidate placement, reports which neighbour edges connect and which
## conflict, and a traffic-light status. Validation is advisory only — the
## editor may still place a dangling tile.

enum Status {
	GREEN,   ## Connects to at least one neighbour, no conflicts.
	YELLOW,  ## Legal but dangling — connects to nothing.
	RED,     ## At least one hard conflict (both edges road, but rule fails).
}


## Returns {status, connections: Array[int], conflicts: Array[int]}. Handles
## multi-cell footprints: overlapping another tile is a conflict, and only the
## tile's outward perimeter edges are checked against neighbours.
static func validate(grid: TrackGrid, cell: Vector2i, def: TileDefinition,
		rotation: int, elevation_level: int) -> Dictionary:
	var connections: Array[int] = []
	var conflicts: Array[int] = []

	var footprint: Array[Vector2i] = TrackGrid.footprint_cells(cell, def, rotation)

	# Overlap with a different tile is a hard conflict.
	for fc in footprint:
		var anchor := grid.get_anchor(fc)
		if anchor != TrackGrid.NONE and anchor != cell:
			return {"status": Status.RED, "connections": connections, "conflicts": [0]}

	for fc in footprint:
		for dir in range(4):
			var neighbor: Vector2i = fc + TrackGrid.OFFSETS[dir]
			if footprint.has(neighbor):
				continue  # internal edge
			var ours: Dictionary = TrackGrid.effective_socket(def, rotation, elevation_level, cell, fc, dir)
			if not ours.get("has_road", false):
				continue
			var theirs: Dictionary = grid.get_socket(neighbor, TrackGrid.opposite(dir))
			if theirs.is_empty() or not theirs.get("has_road", false):
				continue
			if TrackGrid.sockets_connect(ours, theirs):
				connections.append(dir)
			else:
				conflicts.append(dir)

	var status: Status
	if not conflicts.is_empty():
		status = Status.RED
	elif not connections.is_empty():
		status = Status.GREEN
	else:
		status = Status.YELLOW

	return {"status": status, "connections": connections, "conflicts": conflicts}
