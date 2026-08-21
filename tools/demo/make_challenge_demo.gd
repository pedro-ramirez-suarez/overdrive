extends Node
## Build the example challenge that ships in `examples/`.
##
## It makes a track that is deliberately NOT in the game's track list, drives a
## pace lap round it, and packs both into one `.ovc` file — so importing that file
## is a real test of the case that matters: a challenge arriving for a track you
## have never seen.
##
## Run with:
##   godot --headless --path . tools/demo/make_challenge_demo.tscn
##
## The lap is synthesised, not driven: it follows the racing line at a plausible
## pace, which is all a ghost is. The challenge says so — its author is "Pace Car".

const NAME := "Crosswind Circuit"
const CAR := "Marlin GT"      ## the car the pace lap is driven in
const OUT_DIR := "res://examples"
const FPS := 60.0
const BASE_SPEED := 26.0        ## m/s on the straights
const CORNER_SPEED := 13.0      ## m/s through a 90-degree turn
const RIDE_HEIGHT := 0.55       ## the car's body above the road surface

## N, E, S, W — the same order the tile sockets use.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## The circuit as a walk: [direction, cells]. Two long straights, a jog that works
## as a chicane, a tight inner section, and enough corners to have to think.
const WALK: Array = [
	[1, 14], [2, 6], [3, 4], [2, 4], [1, 8], [2, 6],
	[3, 18], [0, 6], [1, 4], [0, 4], [3, 4], [0, 6],
]

## Cells (by index into the lap) where the road steps up or down a level. The climb
## runs up the back straight and comes down the long one, so the lap returns to
## where it started.
const CLIMBS: Array = [[37, 1], [39, 1], [41, 1]]
const DROPS: Array = [[50, 1], [52, 1], [54, 1]]


func _ready() -> void:
	var lib := TileLibrary.new()
	lib.build()

	var cells := _walk_cells()
	print(NAME, ": ", cells.size(), " cells")
	var levels := _levels(cells.size())
	var start_i := _start_index(cells, levels)
	var tiles := _tiles(cells, levels, start_i)
	var terrain := _terrain(cells, levels)

	# Through the serializer both ways, so what we hand out is exactly what the
	# game would have written itself.
	var data := {
		"format": TrackSerializer.SIGNATURE, "version": TrackSerializer.VERSION,
		"name": NAME, "author": "OVERDRIVE", "grid": tiles, "props": [],
		"start_cell": [cells[start_i].x, cells[start_i].y], "terrain": terrain,
		"metadata": {},
	}
	var loaded := TrackSerializer.from_dict(data, lib)
	if loaded.is_empty():
		print("FAILED: the track did not load back")
		get_tree().quit(1)
		return
	var grid: TrackGrid = loaded["grid"]
	GameState.current_terrain = loaded.get("terrain", null)
	var canonical := TrackSerializer.to_dict(grid, lib, NAME, "OVERDRIVE")

	# Piece-to-piece first. RacePath can leap a gap (that is what jump ramps are
	# for), so a complete route does not by itself prove the road actually joins up.
	var breaks := _breaks(grid, cells)
	print("  joins: ", cells.size() - breaks, " of ", cells.size(),
		"" if breaks == 0 else "  BROKEN in %d place(s)" % breaks)
	if breaks > 0:
		get_tree().quit(1)
		return

	var route: Array = RacePath.compute(grid, lib)
	print("  route: ", route.size(), " of ", cells.size(), " tiles  ",
		"COMPLETE" if route.size() >= cells.size() else "SHORT -- the lap breaks")
	var length: float = RacePath.route_length(grid, lib)
	print("  lap: ", int(length), " m")
	if route.size() < cells.size():
		get_tree().quit(1)
		return

	var ghost := _pace_lap(route, grid)
	var lap_time: float = ghost.duration()
	print("  pace lap: ", ghost.frame_count(), " frames, ", "%.2f s" % lap_time,
		", avg ", "%.1f" % (length / lap_time), " m/s")

	var c := Challenge.from_run(canonical, ghost, {
		"author": "Pace Car",
		"car": CAR,
		"lap_time": lap_time,
		"race_time": lap_time,
		"laps": 1,
		"reversed": false,
		"created": 1755734400,   # fixed, so rebuilding gives the same file
		"note": "A steady lap. Beating it is the easy part.",
	})
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/crosswind_circuit.%s" % [OUT_DIR, Challenge.EXT]
	if not c.save_to(path):
		print("FAILED to write ", path)
		get_tree().quit(1)
		return
	print("  wrote ", path, " (", FileAccess.open(path, FileAccess.READ).get_length() / 1024, " KB)")

	# It has to survive its own front door.
	var why := Challenge.file_error(path)
	print("  reads back: ", "ok" if why == "" else "REFUSED -- " + why)
	get_tree().quit(0 if why == "" else 1)


# --- The circuit -------------------------------------------------------------

func _walk_cells() -> Array:
	var cells: Array = []
	var at := Vector2i.ZERO
	for leg in WALK:
		var d: Vector2i = DIRS[int(leg[0])]
		for _i in range(int(leg[1])):
			cells.append(at)
			at += d
	if at != Vector2i.ZERO:
		print("  WARNING: the walk does not close, it ends at ", at)
	return cells


## Level each cell sits at, from the climbs and drops. A ramp cell carries the
## change; everything after it stays at the new height.
func _levels(n: int) -> Array:
	var levels: Array = []
	levels.resize(n)
	var level := 0
	var step := {}
	for c in CLIMBS:
		step[int(c[0])] = int(c[1])
	for d in DROPS:
		step[int(d[0])] = -int(d[1])
	for i in range(n):
		levels[i] = level
		if step.has(i):
			level += int(step[i])
	if level != 0:
		print("  WARNING: the lap ends ", level, " level(s) off where it started")
	return levels


## Where the start/finish line goes: a cell the road runs straight through, on the
## ground. Putting it on a corner would replace that corner with a straight piece
## and tear the lap open at the one place every race begins.
func _start_index(cells: Array, levels: Array) -> int:
	var n := cells.size()
	for i in range(n):
		var into: int = _dir_between(cells[(i - 1 + n) % n], cells[i])
		var out: int = _dir_between(cells[i], cells[(i + 1) % n])
		var flat: bool = int(levels[i]) == 0 and int(levels[(i + 1) % n]) == int(levels[i])
		if into == out and flat:
			return i
	push_warning("no straight, level cell to start on")
	return 0


func _tiles(cells: Array, levels: Array, start_i: int) -> Array:
	var n := cells.size()
	var tiles: Array = []
	for i in range(n):
		var c: Vector2i = cells[i]
		var into: int = _dir_between(cells[(i - 1 + n) % n], c)
		var out: int = _dir_between(c, cells[(i + 1) % n])
		var level: int = int(levels[i])
		var def := "straight"
		var rotation := out
		if into != out:
			# A corner: the same rule the track generator uses, so the pieces meet
			# the way the engine expects.
			var back: int = (into + 2) % 4
			def = "curve"
			rotation = back if out == (back + 1) % 4 else out
		elif int(levels[(i + 1) % n]) > level:
			def = "ramp_up"
		elif int(levels[(i + 1) % n]) < level:
			def = "ramp_down"
			level = int(levels[(i + 1) % n])
		if i == start_i:
			def = "start"
		tiles.append({"cell_x": c.x, "cell_y": c.y, "def_id": def,
			"rotation": rotation, "elevation_level": level})
	return tiles


## How many neighbouring pairs round the lap do not actually connect — sockets,
## elevations and slopes all agreeing, the way the editor's green light judges it.
func _breaks(grid: TrackGrid, cells: Array) -> int:
	var count := 0
	for i in range(cells.size()):
		var a: Vector2i = cells[i]
		var b: Vector2i = cells[(i + 1) % cells.size()]
		if grid.cells_connected(a, b):
			continue
		count += 1
		var pa: PlacedTile = grid.get_placed(a)
		var pb: PlacedTile = grid.get_placed(b)
		print("    break at %s: %s rot %d level %d -> %s %s rot %d level %d" % [
			a, pa.def_id, pa.rotation, pa.elevation_level,
			b, pb.def_id, pb.rotation, pb.elevation_level])
	return count


static func _dir_between(a: Vector2i, b: Vector2i) -> int:
	var d := b - a
	for i in range(4):
		if DIRS[i] == d:
			return i
	return 1


# --- The ground --------------------------------------------------------------

## Plains, flattened under the track and for a couple of cells either side so the
## road never has a bank standing over it, then left to its own devices.
func _terrain(cells: Array, levels: Array) -> Dictionary:
	var edits := {}
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		var level: int = int(levels[i])
		for dx in range(-2, 4):
			for dy in range(-2, 4):
				var corner := Vector2i(c.x + dx, c.y + dy)
				# The highest track piece touching a corner wins, exactly as the
				# terrain itself resolves a corner shared by two tiles.
				edits[corner] = maxi(int(edits.get(corner, -99)), level)
	var flat: Array = []
	for corner in edits:
		flat.append(corner.x)
		flat.append(corner.y)
		flat.append(int(edits[corner]))
	return {"type": Terrain.Type.PLAINS, "seed": 20260821, "edits": flat, "lakes": []}


# --- The pace lap ------------------------------------------------------------

## Drive the racing line: the route smoothed into a curve, walked at a speed that
## eases off for the corners. It is a ghost — recorded positions and rotations —
## so this is all one has to be.
func _pace_lap(route: Array, grid: TrackGrid) -> Replay:
	var line: Array = []
	for cell in route:
		var placed: PlacedTile = grid.get_placed(cell)
		var level: int = placed.elevation_level if placed != null else 0
		line.append(TileLibrary.cell_to_world(cell, level) + Vector3(0.0, RIDE_HEIGHT, 0.0))
	line = _smooth(_smooth(_smooth(line)))

	# Speed at each point, from how sharply the line turns there.
	var n := line.size()
	var speeds: Array = []
	for i in range(n):
		var a: Vector3 = line[(i - 2 + n) % n]
		var b: Vector3 = line[i]
		var d: Vector3 = line[(i + 2) % n]
		var v1: Vector3 = (b - a)
		var v2: Vector3 = (d - b)
		var turn := 0.0
		if v1.length() > 0.01 and v2.length() > 0.01:
			turn = absf(v1.normalized().angle_to(v2.normalized()))
		speeds.append(lerpf(BASE_SPEED, CORNER_SPEED, clampf(turn / (PI * 0.4), 0.0, 1.0)))
	speeds = _smooth_floats(_smooth_floats(speeds))

	var r := Replay.new()
	r.fps = FPS
	# The ghost is rebuilt from what is recorded here, so it carries a real car the
	# way a recorded race does — car_infos without a model spawns nothing to look at.
	r.init_cars([_car_info()])
	var seg := 0
	var t := 0.0            # 0..1 along the current segment
	var frames := 0
	var max_frames := 60 * 60 * 5
	while seg < n and frames < max_frames:
		var a: Vector3 = line[seg]
		var b: Vector3 = line[(seg + 1) % n]
		var seg_len: float = a.distance_to(b)
		var pos: Vector3 = a.lerp(b, t)
		var fwd: Vector3 = (b - a)
		if fwd.length() < 0.001:
			fwd = Vector3.FORWARD
		r.capture(0, _facing(pos, fwd.normalized()))
		frames += 1
		var speed: float = lerpf(float(speeds[seg]), float(speeds[(seg + 1) % n]), t)
		if seg_len < 0.001:
			seg += 1
			t = 0.0
			continue
		t += (speed / FPS) / seg_len
		while t >= 1.0:
			t -= 1.0
			seg += 1
			if seg >= n:
				break
	return r


## The ghost's car, in the shape ReplayRecorder writes: enough for the race to
## rebuild the same model, at the same size, in its own colour.
func _car_info() -> Dictionary:
	var profile: CarProfile = null
	for p in GameState.roster:
		if p.display_name == CAR:
			profile = p
	if profile == null:
		push_warning("no car named %s in the roster; the ghost will have no model" % CAR)
		return {"name": CAR, "is_player": false, "color": Color(0.85, 0.85, 0.9)}
	return {
		"name": CAR, "is_player": false, "color": profile.body_color,
		"model_path": profile.model_scene.resource_path if profile.model_scene != null else "",
		"model_scale": profile.model_scale,
		"model_y_offset": profile.model_y_offset,
		"model_yaw": profile.model_yaw,
		"model_fit_width": profile.model_fit_width,
		"model_fit_length": profile.model_fit_length,
	}


## A transform at `pos` facing `fwd`. Godot's -Z is forward, which is what
## `looking_at` builds.
static func _facing(pos: Vector3, fwd: Vector3) -> Transform3D:
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	var basis := Basis.looking_at(fwd, Vector3.UP)
	return Transform3D(basis, pos)


static func _smooth(pts: Array) -> Array:
	var n := pts.size()
	var out: Array = []
	for i in range(n):
		var a: Vector3 = pts[(i - 1 + n) % n]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[(i + 1) % n]
		out.append(a * 0.25 + b * 0.5 + c * 0.25)
	return out


static func _smooth_floats(vals: Array) -> Array:
	var n := vals.size()
	var out: Array = []
	for i in range(n):
		out.append(float(vals[(i - 1 + n) % n]) * 0.25 + float(vals[i]) * 0.5
			+ float(vals[(i + 1) % n]) * 0.25)
	return out
