extends SceneTree
## Build an OVERDRIVE track from a real circuit: a lap traced out of OpenStreetMap
## (see find_loop.gd) laid onto the tile grid, with the ground under it sculpted
## from SRTM elevation.
##
##   route json -> rotate/scale into grid space
##              -> relax so stretches that pass close never share a cell
##              -> route a simple lattice cycle (A* per leg, avoiding used cells
##                 and their halo)
##              -> sweeping corners where a 2x2 wide curve fits, banked corners
##                 where a 3x3 one does and the track is fast enough to want it
##              -> elevation from the DEM, realised as ramps
##              -> tiles, scenery, terrain -> <out>.json
##
## Run with: --script build_track.gd -- <id>

# Everything the tool reads and writes lives beside it. `data` holds the OSM
# extracts and the SRTM tiles -- both downloaded, both far too big for the repo,
# both gitignored. See README.md.
const DATA := "res://tools/trackgen/data"
const ROUTES := "res://tools/trackgen/routes"
const OUT := "res://tools/trackgen/out"
const DIM := 3601
const CELL := 8.0
const MAX_LEVEL := 16             ## ceiling for road and ground, in levels; the engine allows 32

const CIRCUITS := {
	# A divided road rather than a circuit: the lap runs out along one carriageway
	# and back along the other, so each is nudged to its own right and the pair is
	# kept apart. Its route comes from ordinary roads, not raceways.
	"tres_marias": {
		"name": "Tres Marias", "out": "tres_marias", "route": "tres_marias_route",
		"lat0": 19.712, "lon0": -101.125, "m_per_lat": 110574.0,
		"scale": 0.40, "lateral": 0.8, "vstep": 19.0, "knee": 15.0, "knee_scale": 0.3,
		"smooth": 6, "start_near": [19.72602, -101.11599],
		"resample": 6.0, "turn_cost": 3.5, "drift_cost": 0.65,
		"tree_reach": 999, "building_reach": 999, "tree_step": 3,
		"tree_variants": 3, "seed": 20260818,
	},
	"eifelschleife": {
		"name": "Eifelschleife", "out": "eifelschleife", "route": "eifelschleife_route",
		"lat0": 50.3555, "lon0": 6.9650,
		"scale": 0.35, "vstep": 21.0, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 5, "start_near": [50.3385, 6.9534],
		"resample": 6.0, "turn_cost": 3.0,
		"tree_reach": 9, "building_reach": 13, "tree_step": 3,
		"tree_conifer": 0.7, "seed": 20260819,
	},
	# A mountain pass, not a circuit. Retracing the road to close the lap does not
	# work -- two ribbons and the clear cell between them need more room than the
	# shelves of a hairpin stack leave -- so find_loop brings it home on a road of
	# its own, swung wide of the stack (see its "out_back" mode). The scale is up
	# at 1.5 to hold the hairpins apart, and max_level lifts the ceiling to the 32
	# the engine now allows: a pass wants its whole height.
	"stelvio": {
		"name": "Stelvia Pass", "out": "stelvia_pass",
		"scale": 1.50, "vstep": 8.0, "knee": 999.0, "knee_scale": 1.0,
		"smooth": 3, "start_near": [46.53075, 10.45945],
		"separation": 2.6, "resample": 3.0, "max_level": 32,
		"tree_reach": 6, "building_reach": 10, "tree_step": 4,
	},
	"spa": {
		"name": "Spaa Francorchant", "out": "spaa_francorchant",
		"scale": 0.70, "vstep": 7.5, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 5, "start_near": [50.4443, 5.9682],
		"tree_reach": 8, "building_reach": 12, "tree_step": 3,
	},
	"zuzuka": {
		"name": "Zuzuka", "out": "zuzuka",
		"scale": 0.90, "vstep": 3.5, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 5, "start_near": [34.8447, 136.5395],
		"tree_reach": 7, "building_reach": 11, "tree_step": 3,
		# The figure-of-eight: one stretch crosses the other on a bridge, which is
		# the overpass piece -- deck one level up, road underneath at ground. The
		# bridge is tagged in OSM (way 175231434); its two ends say where the
		# crossing is and which way the deck runs.
		"crossing": [[34.8440256, 136.5304341], [34.8439151, 136.5308102]],
	},
	"momako": {
		"name": "Momako", "out": "momako",
		"scale": 1.00, "vstep": 3.0, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 4, "start_near": [43.7343, 7.4215],
		"tree_reach": 5, "building_reach": 12, "tree_step": 4,
		# the long tunnel under the hotel, in lat/lon bounds
		"tunnels": [[43.7380, 7.4288, 43.7398, 7.4305]],
	},
	"mexico": {
		"name": "Autodromo Hermanos Ramirez", "out": "hermanos_ramirez",
		"scale": 1.00, "vstep": 8.0, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 6, "start_near": [19.4058, -99.0885],
		"tree_reach": 6, "building_reach": 12, "tree_step": 4,
		"banking": true,
	},
	"baytona": {
		"name": "Baytona Oval", "out": "baytona_oval",
		"scale": 1.00, "vstep": 3.0, "knee": 15.0, "knee_scale": 0.35,
		"smooth": 6, "start_near": [29.1900, -81.0680],
		"tree_reach": 5, "building_reach": 9, "tree_step": 5,
		"banking": true,
	},
}

# --- Tuning ---------------------------------------------------------------
# Defaults; any circuit may override them in its entry above. The two earliest
# tracks were built before this tool was one tool, so they carry the numbers they
# were made with -- which is why re-running the generator still reproduces them.
const SEPARATION := 2.6           ## closest two stretches of track may run, in cells
const RESAMPLE := 4.0             ## real metres between resampled route points
const LEG := 10.0                 ## cells between router waypoints
const TURN_COST := 3.2            ## A* penalty for a 90-degree turn, in cells
const DRIFT_COST := 0.8           ## A* penalty per cell of drift off the real line
const HUG_COST := 0.35            ## A* penalty for running alongside built track
const MARGIN := 26                ## cells of sculpted terrain beyond the track
const M_PER_LAT := 111132.0       ## metres per degree of latitude
const RAMP_GAP := 8               ## flat cells between ramps that still counts as a staircase
const RAMP_RUN_MAX := 4           ## longest run to roll a staircase into, in ramps
const RAMP_OFF_MAX := 2           ## levels the road may sit off the ground to do it
const DIP_GAP := 10                ## flat cells between a descent and the climb out of it
const DIP_SPAN := 26              ## longest dip to carry straight across, in cells
const DIP_MAX := 5                ## levels of dip to cancel; deeper ones keep their edges

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var cfg := {}
var dem := {}
var lat0 := 0.0
var lon0 := 0.0
var scale_f := 1.0
var vstep := 10.0
var knee := 15.0
var knee_scale := 0.35
var smooth := 5
var rot := 0.0
var center := Vector2.ZERO
var used := {}
var guide: Array = []
var near := {}
var prop_lo := Vector2i.ZERO
var prop_hi := Vector2i.ZERO
## Where the lap crosses itself, if it does. The router may lay track through this
## one cell twice; everything else stays a simple loop.
var crossing_cell := Vector2i(2147483647, 2147483647)
var crossing_deck := Vector2.ZERO   ## which way the upper road runs, in cell space

# tuning, resolved per circuit in _init
var separation := SEPARATION
var resample_m := RESAMPLE
var leg_cells := LEG
var turn_cost := TURN_COST
var drift_cost := DRIFT_COST
var hug_cost := HUG_COST
var margin := MARGIN
var m_per_lat := M_PER_LAT
var lateral := 0.0
var max_level := MAX_LEVEL

# --- DEM ------------------------------------------------------------------

static func tile_name(lat: float, lon: float) -> String:
	var la := int(floor(lat))
	var lo := int(floor(lon))
	return "%s%02d%s%03d" % ["N" if la >= 0 else "S", absi(la), "E" if lo >= 0 else "W", absi(lo)]

func raw(data: PackedByteArray, row: int, col: int) -> float:
	row = clampi(row, 0, DIM - 1)
	col = clampi(col, 0, DIM - 1)
	var i := (row * DIM + col) * 2
	var v := (data[i] << 8) | data[i + 1]
	if v >= 32768:
		v -= 65536
	return float(v)

func elevation(lat: float, lon: float) -> float:
	var key := tile_name(lat, lon)
	if not dem.has(key):
		dem[key] = FileAccess.get_file_as_bytes("%s/%s.hgt" % [DATA, key])
		if (dem[key] as PackedByteArray).is_empty():
			print("  MISSING DEM tile ", key)
	var data: PackedByteArray = dem[key]
	if data.is_empty():
		return 0.0
	var r := (float(int(floor(lat)) + 1) - lat) * 3600.0
	var c := (lon - float(int(floor(lon)))) * 3600.0
	var r0 := int(floor(r))
	var c0 := int(floor(c))
	var a: float = lerp(raw(data, r0, c0), raw(data, r0, c0 + 1), c - c0)
	var b: float = lerp(raw(data, r0 + 1, c0), raw(data, r0 + 1, c0 + 1), c - c0)
	return float(lerp(a, b, r - r0))

func unproj(p: Vector2) -> Vector2:  # local metres -> (lat, lon)
	return Vector2(lat0 - p.y / m_per_lat, lon0 + p.x / (111320.0 * cos(deg_to_rad(lat0))))

func unproj_inv(lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)), -(lat - lat0) * m_per_lat)

func elevation_at_cell(c: Vector2) -> float:
	var ll := unproj(cell_to_real(c))
	return elevation(ll.x, ll.y)

func to_level(metres_above_base: float) -> float:
	var lvl := metres_above_base / vstep
	return lvl if lvl <= knee else knee + (lvl - knee) * knee_scale

# --- Transform ------------------------------------------------------------

func real_to_cell(p: Vector2) -> Vector2:
	var d := (p - center) * scale_f
	return Vector2(d.x * cos(rot) - d.y * sin(rot), d.x * sin(rot) + d.y * cos(rot)) / CELL

func cell_to_real(c: Vector2) -> Vector2:
	var d: Vector2 = c * CELL
	var u := Vector2(d.x * cos(-rot) - d.y * sin(-rot), d.x * sin(-rot) + d.y * cos(-rot))
	return center + u / scale_f

# --- Polyline -------------------------------------------------------------

static func resample(points: Array, step: float) -> Array:
	var out: Array = [points[0]]
	var carry := 0.0
	for i in range(1, points.size() + 1):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i % points.size()]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		var t := step - carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	return out

static func best_rotation(pts: Array) -> float:
	var best_angle := 0.0
	var best_cost := INF
	for deg in range(0, 90):
		var a := deg_to_rad(float(deg))
		var cost := 0.0
		for i in range(pts.size()):
			var d: Vector2 = pts[(i + 1) % pts.size()] - pts[i]
			var l := d.length()
			if l < 0.001:
				continue
			var ang := atan2(d.y, d.x) + a
			var off: float = absf(fmod(ang + TAU + PI / 4.0, PI / 2.0) - PI / 4.0) / (PI / 4.0)
			cost += l * off * off
		if cost < best_cost:
			best_cost = cost
			best_angle = a
	return best_angle

## `exempt` marks a spot where two stretches are *meant* to meet -- a crossing --
## so the separation rule is not applied within `exempt_r` cells of it.
static func relax(pts: Array, sep: float, skip: int, iterations: int,
		exempt: Vector2 = Vector2.INF, exempt_r: float = 0.0) -> Array:
	var n := pts.size()
	var cur: Array = pts.duplicate()
	for it in range(iterations):
		var buckets := {}
		for i in range(n):
			var key := Vector2i(int(floor(cur[i].x / sep)), int(floor(cur[i].y / sep)))
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(i)
		var push: Array = []
		push.resize(n)
		push.fill(Vector2.ZERO)
		var worst := INF
		for i in range(n):
			var p: Vector2 = cur[i]
			if exempt != Vector2.INF and p.distance_to(exempt) < exempt_r:
				continue
			var key := Vector2i(int(floor(p.x / sep)), int(floor(p.y / sep)))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for j in buckets.get(key + Vector2i(dx, dy), []):
						var gap: int = mini(absi(i - j), n - absi(i - j))
						if gap <= skip:
							continue
						var d: Vector2 = p - cur[j]
						var l := d.length()
						if l < 0.0001 or l >= sep:
							continue
						worst = minf(worst, l)
						push[i] += d.normalized() * (sep - l) * 0.5
		if worst == INF:
			print("  relax: clear after ", it, " iterations")
			return cur
		var next: Array = []
		for i in range(n):
			var p: Vector2 = cur[i] + (push[i] as Vector2).limit_length(sep * 0.25)
			var a: Vector2 = cur[(i - 1 + n) % n]
			var b: Vector2 = cur[(i + 1) % n]
			next.append(p.lerp((a + b) * 0.5, 0.10))
		cur = next
	print("  relax: gave up short of ", sep, " cells")
	return cur

## Do segments a0-a1 and b0-b1 cross?
static func segments_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var d1 := a1 - a0
	var d2 := b1 - b0
	var den := d1.cross(d2)
	if absf(den) < 1e-9:
		return false
	var t: float = (b0 - a0).cross(d2) / den
	var u: float = (b0 - a0).cross(d1) / den
	return t > 0.0 and t < 1.0 and u > 0.0 and u < 1.0

# --- Lattice router -------------------------------------------------------

func pick_waypoints() -> Array:
	var out: Array = []
	var indices: Array = []
	var travelled := 0.0
	for i in range(guide.size()):
		var p: Vector2 = guide[i]
		if i > 0:
			travelled += p.distance_to(guide[i - 1])
		if out.is_empty() or travelled >= leg_cells:
			var c := Vector2i(int(round(p.x)), int(round(p.y)))
			if out.is_empty() or c != out[out.size() - 1]:
				out.append(c)
				indices.append(i)
			travelled = 0.0
	return [out, indices]

func drift(cell: Vector2i, from_i: int, to_i: int) -> float:
	var best := INF
	var i := from_i
	var v := Vector2(cell)
	while i != to_i:
		best = minf(best, v.distance_to(guide[i]))
		i = (i + 1) % guide.size()
	return best

static func key_of(cell: Vector2i, heading: int) -> int:
	return ((cell.x + 4096) * 8192 + (cell.y + 4096)) * 8 + heading + 1

## Cells touching track laid earlier. Terrain corners are flattened to the highest
## tile touching them, so two unrelated stretches sharing a corner would lift the
## lower one's verge over its own tarmac; a clear cell between them rules it out.
func build_halo(path: Array, tail_exempt: int, head_exempt: int) -> Dictionary:
	var halo := {}
	for idx in range(path.size()):
		if idx >= path.size() - tail_exempt or idx < head_exempt:
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				halo[(path[idx] as Vector2i) + Vector2i(dx, dy)] = true
	# The bridge cell and its approaches are meant to be shared -- that is what a
	# crossing is -- so the clearance rule is lifted right around it.
	if crossing_cell.x != 2147483647:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				halo.erase(crossing_cell + Vector2i(dx, dy))
	return halo

func route_leg(a: Vector2i, b: Vector2i, from_i: int, to_i: int, allow_goal: bool,
		halo: Dictionary) -> Array:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i(16, 16)
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i(16, 16)
	var open := {}
	var g := {}
	var came := {}
	var cell_of := {}
	var head_of := {}
	var drift_cache := {}
	var sk := key_of(a, -1)
	g[sk] = 0.0
	open[sk] = 0.0
	cell_of[sk] = a
	head_of[sk] = -1
	var goal_key := 0
	while not open.is_empty():
		var best_k := 0
		var best_f := INF
		for k in open:
			if open[k] < best_f:
				best_f = open[k]
				best_k = k
		open.erase(best_k)
		var cell: Vector2i = cell_of[best_k]
		var heading: int = head_of[best_k]
		if cell == b:
			goal_key = best_k
			break
		for d in range(4):
			var nxt: Vector2i = cell + DIRS[d]
			if nxt.x < lo.x or nxt.y < lo.y or nxt.x > hi.x or nxt.y > hi.y:
				continue
			if heading != -1 and d == (heading + 2) % 4:
				continue
			var free: bool = (nxt == b and allow_goal) or nxt == crossing_cell
			if (used.has(nxt) or halo.has(nxt)) and not free:
				continue
			var step := 1.0
			if heading != -1 and d != heading:
				step += turn_cost
			if not drift_cache.has(nxt):
				drift_cache[nxt] = drift(nxt, from_i, to_i)
			step += drift_cost * float(drift_cache[nxt])
			for side in DIRS:
				if used.has(nxt + side):
					step += hug_cost
			var nk := key_of(nxt, d)
			var ng: float = float(g[best_k]) + step
			if not g.has(nk) or ng < float(g[nk]) - 0.0001:
				g[nk] = ng
				came[nk] = best_k
				cell_of[nk] = nxt
				head_of[nk] = d
				open[nk] = ng + float(absi(nxt.x - b.x) + absi(nxt.y - b.y))
	if goal_key == 0:
		return []
	var path: Array = []
	var k := goal_key
	while true:
		path.append(cell_of[k])
		if not came.has(k):
			break
		k = came[k]
	path.reverse()
	return path

func free_near(c: Vector2i, halo: Dictionary) -> Vector2i:
	if not used.has(c) and not halo.has(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if not used.has(n) and not halo.has(n):
					return n
	return c

func route_circuit() -> Array:
	var wp_data := pick_waypoints()
	var wps: Array = wp_data[0]
	var idx: Array = wp_data[1]
	print("  waypoints: ", wps.size())
	var path: Array = []
	used.clear()
	var start: Vector2i = wps[0]
	path.append(start)
	used[start] = true
	var failures := 0
	for k in range(wps.size()):
		var a: Vector2i = path[path.size() - 1]
		var last: bool = k == wps.size() - 1
		var halo := build_halo(path, 3, 3 if last else 0)
		var b: Vector2i = wps[(k + 1) % wps.size()]
		if not last:
			b = free_near(b, halo)
		var leg := route_leg(a, b, idx[k], idx[(k + 1) % idx.size()], last, halo)
		if leg.is_empty():
			failures += 1
			continue
		for i in range(1, leg.size()):
			var c: Vector2i = leg[i]
			if last and c == start:
				continue
			path.append(c)
			used[c] = true
	if failures > 0:
		print("  ", failures, " legs failed")
	return path

# --- Corner pieces --------------------------------------------------------

static func curve_rotation(back: int, fwd: int) -> int:
	return back if fwd == (back + 1) % 4 else fwd

## Cells a corner piece of `span` x `span` would cover, given the run of path
## cells it replaces. The block is the bounding box of those cells.
static func block_of(cells: Array, head: int, tail: int) -> Array:
	var n := cells.size()
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	var i := head
	while true:
		var c: Vector2i = cells[i]
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		if i == tail:
			break
		i = (i + 1) % n
	var out: Array = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			out.append(Vector2i(x, y))
	return out

## Sweeping corners. A tight curve turns inside one cell; a wide curve sweeps the
## same 90 degrees across a 2x2 block, and a banked curve across a 3x3 one. Both
## enter the south edge of their anchor and leave the east edge of the far cell,
## so wherever the lap runs straight-corner-straight with room to spare, those
## cells become one flowing corner. `span` is 2 for wide, 3 for banked.
func plan_corners(cells: Array, span: int, cover: Array, kind: String) -> Array:
	var n := cells.size()
	var reach: int = span - 1        # straights consumed on each side
	var out: Array = []
	for i in range(n):
		var din: int = DIRS.find(cells[i] - cells[(i - 1 + n) % n])
		var dout: int = DIRS.find(cells[(i + 1) % n] - cells[i])
		if din == dout:
			continue
		var head: int = (i - reach + n) % n
		var tail: int = (i + reach) % n
		# every cell this would swallow must run straight through and be free
		var ok := true
		for k in range(-reach, reach + 1):
			var j: int = (i + k + n) % n
			if cover[j] != -1:
				ok = false
			if k == 0:
				continue
			var jd_in: int = DIRS.find(cells[j] - cells[(j - 1 + n) % n])
			var jd_out: int = DIRS.find(cells[(j + 1) % n] - cells[j])
			if jd_in != jd_out:
				ok = false
		if not ok:
			continue
		var block := block_of(cells, head, tail)
		if block.size() != span * span:
			continue
		var busy := false
		for c in block:
			if used.has(c) and not on_path_between(cells, c, head, tail):
				busy = true
		if busy:
			continue
		# A banked corner cannot rise straight out of flat road: the roll into and
		# out of the bank is its own piece, so a cell is reserved either side.
		var wants_ramps: bool = span == 3
		var before: int = (head - 1 + n) % n
		var after: int = (tail + 1) % n
		if wants_ramps:
			for j in [before, after]:
				if cover[j] != -1:
					ok = false
				var jd_in: int = DIRS.find(cells[j] - cells[(j - 1 + n) % n])
				var jd_out: int = DIRS.find(cells[(j + 1) % n] - cells[j])
				if jd_in != jd_out:
					ok = false
			if not ok:
				continue
		var right: bool = dout == (din + 1) % 4
		out.append({
			"kind": kind, "span": span,
			"anchor": cells[head] if right else cells[tail],
			"rotation": din if right else (din + 1) % 4,
			"head": head, "tail": tail, "right": right,
			"entry": before if wants_ramps else -1,
			"exit": after if wants_ramps else -1,
		})
		for k in range(-reach, reach + 1):
			cover[(i + k + n) % n] = out.size() - 1 + 1000 * span
		if wants_ramps:
			cover[before] = 900000 + out.size() - 1     # banked entry
			cover[after] = 800000 + out.size() - 1      # banked exit
	return out

static func on_path_between(cells: Array, c: Vector2i, head: int, tail: int) -> bool:
	var n := cells.size()
	var i := head
	for _step in range(n):
		if cells[i] == c:
			return true
		if i == tail:
			break
		i = (i + 1) % n
	return false

# --- Elevation ------------------------------------------------------------

func target_levels(cells: Array, base: float, pins: Dictionary) -> Array:
	var n := cells.size()
	var e: Array = []
	for c in cells:
		e.append(elevation_at_cell(Vector2(c)))
	var out: Array = []
	for i in range(n):
		var sum := 0.0
		for k in range(-smooth, smooth + 1):
			sum += float(e[(i + k + n * 2) % n])
		out.append(clampi(int(round(to_level(sum / float(smooth * 2 + 1) - base))), 0, max_level - 2))
	for i in pins:
		out[int(i)] = int(pins[i])
	return out

func plan_elevation(cells: Array, rampable: Array, target: Array) -> Dictionary:
	var n := cells.size()
	var entry: Array = []
	var ramp: Array = []
	entry.resize(n)
	ramp.resize(n)
	ramp.fill(0)
	var level: int = target[0]
	var first := level
	for i in range(n):
		entry[i] = level
		if rampable[i] and target[i] != level:
			var step: int = signi(target[i] - level)
			ramp[i] = step
			level += step
	var debt: int = first - level
	var i := n - 1
	while debt != 0 and i > 0:
		if rampable[i] and ramp[i] == 0:
			ramp[i] = signi(debt)
			debt -= signi(debt)
		i -= 1
	if debt != 0:
		print("  WARNING: elevation loop does not close, ", debt, " levels short")
	level = first
	for k in range(n):
		entry[k] = level
		level += ramp[k]
	return {"entry": entry, "ramp": ramp}

## Carry the road straight across a dip instead of diving into it.
##
## Where the ground falls away and rises again within a few cells, following it
## puts a V in the road: down four levels, along, up four levels, all inside a
## couple of hundred metres. Real roads do not do that -- they cross on an
## embankment. Cancelling the descent against the ascent leaves the road level,
## and since the ground under a tile is flattened to that tile, the embankment
## builds itself.
##
## Only short dips: a long one is a valley, and crossing a valley on a causeway
## would look sillier than driving through it.
func flatten_dips(n: int, rampable: Array, ramp: Array, frozen: Dictionary) -> int:
	var runs := ramp_runs(n, ramp)
	var flattened := 0
	for i in range(runs.size() - 1):
		var a: Dictionary = runs[i]
		var b: Dictionary = runs[i + 1]
		if int(a["dir"]) != -int(b["dir"]):
			continue                      # both the same way: a slope, not a dip
		if int(a["dir"]) > 0:
			continue                      # up then down is a crest, and crests are fine
		var gap: int = int(b["from"]) - int(a["to"]) - 1
		if gap > DIP_GAP:
			continue
		var span: int = int(b["to"]) - int(a["from"]) + 1
		if span > DIP_SPAN:
			continue
		var depth: int = mini(mini(int(a["len"]), int(b["len"])), DIP_MAX)
		if depth < 1:
			continue
		var blocked := false
		for k in range(depth):
			if frozen.has(int(a["to"]) - k) or frozen.has(int(b["from"]) + k):
				blocked = true
		if blocked:
			continue
		# take them off the bottom of the descent and the bottom of the climb, so
		# what is left of a deeper dip still drops away at its edges
		for k in range(depth):
			ramp[int(a["to"]) - k] = 0
			ramp[int(b["from"]) + k] = 0
		flattened += 1
	return flattened

## The runs of consecutive ramps in the plan, as { from, to, dir, len }.
static func ramp_runs(n: int, ramp: Array) -> Array:
	var runs: Array = []
	var i := 0
	while i < n:
		var dir: int = int(ramp[i])
		if dir == 0:
			i += 1
			continue
		var j := i
		while j + 1 < n and int(ramp[j + 1]) == dir:
			j += 1
		runs.append({"from": i, "to": j, "dir": dir, "len": j - i + 1})
		i = j + 1
	return runs

## Roll a staircase into a slope.
##
## A ramp climbs exactly one level per cell, and the planner lays one down
## wherever the ground steps up -- so a hillside comes out flat, up, flat, up:
## stairs. Where those ramps fall close together they are slid into a single
## continuous run, so the road climbs once, in one incline, and then holds its
## level. The count and direction of the ramps never change, so the lap still
## comes home to the level it left at.
func compact_ramps(n: int, rampable: Array, ramp: Array, entry: Array, target: Array,
		frozen: Dictionary, max_gap: int) -> int:
	var merged := 0
	var i := 0
	while i < n:
		if int(ramp[i]) == 0:
			i += 1
			continue
		var dir: int = int(ramp[i])
		var group: Array = [i]
		var j := i + 1
		var gap := 0
		while j < n and gap <= max_gap and group.size() < RAMP_RUN_MAX:
			if int(ramp[j]) == dir:
				group.append(j)
				gap = 0
			elif int(ramp[j]) != 0:
				break      # the ground turns over; that is a crest, not a staircase
			else:
				gap += 1
			j += 1
		var k: int = group.size()
		if k > 1:
			var first: int = group[0]
			var last: int = group[k - 1]
			var start := find_ramp_run(rampable, ramp, frozen, first, last, k, dir)
			# Climbing all at once means the road leaves the ground it is lying on
			# for a while: fine for a shallow cutting or embankment, wrong if it
			# turns into a trench. Merge only while it stays close.
			if start != -1 and off_ground_if_merged(entry, target, group, start, k, dir) <= RAMP_OFF_MAX:
				for idx in group:
					ramp[idx] = 0
				for m in range(k):
					ramp[start + m] = dir
				merged += k - 1
		i = j
	return merged

## How far the road would sit from the ground, in levels, if `group`'s ramps were
## all slid into the run starting at `start`.
static func off_ground_if_merged(entry: Array, target: Array, group: Array,
		start: int, k: int, dir: int) -> int:
	var first: int = group[0]
	var base: int = int(entry[first])
	var worst := 0
	for x in range(first, group[k - 1] + 2):
		var level: int = base + dir * clampi(x - start, 0, k)
		worst = maxi(worst, absi(level - int(target[x])))
	return worst

## `k` consecutive cells inside [first, last] that can all carry a ramp, searched
## outward from the middle so the incline sits where the ground actually rises.
static func find_ramp_run(rampable: Array, ramp: Array, frozen: Dictionary,
		first: int, last: int, k: int, dir: int) -> int:
	var mid: int = (first + last - k) / 2
	for off in range(0, last - first + 2):
		for s in [mid + off, mid - off]:
			if s < first or s + k - 1 > last:
				continue
			var ok := true
			for m in range(k):
				if not rampable[s + m] or frozen.has(s + m) or int(ramp[s + m]) == -dir:
					ok = false
					break
			if ok:
				return s
	return -1

## A corner piece is one flat tile spanning several cells, so any that would land
## beside track at another level is given back and the corner stays tight.
func drop_conflicting(cells: Array, cover: Array, pieces: Array, entry: Array, ramp: Array) -> int:
	var n := cells.size()
	var span_of := {}
	for i in range(n):
		var lo: int = int(entry[i])
		var hi: int = lo
		if ramp[i] > 0:
			hi += 1
		elif ramp[i] < 0:
			lo -= 1
		span_of[cells[i]] = [lo, hi]
	for p in pieces:
		var level: int = int(entry[int(p["head"])])
		for c in block_of(cells, int(p["head"]), int(p["tail"])):
			if not span_of.has(c):
				span_of[c] = [level, level]
	var dropped := 0
	for p in pieces:
		if p.get("dropped", false):
			continue
		var level: int = int(entry[int(p["head"])])
		var block := block_of(cells, int(p["head"]), int(p["tail"]))
		var neighbours := {}
		for c in block:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					neighbours[(c as Vector2i) + Vector2i(dx, dy)] = true
		for c in block:
			neighbours.erase(c)
		neighbours.erase(cells[(int(p["head"]) - 1 + n) % n])
		neighbours.erase(cells[(int(p["tail"]) + 1) % n])
		var clash := false
		for nb in neighbours:
			if not span_of.has(nb):
				continue
			var s: Array = span_of[nb]
			if int(s[0]) != level or int(s[1]) != level:
				clash = true
				break
		if clash:
			p["dropped"] = true
			dropped += 1
			if int(p.get("entry", -1)) >= 0:
				cover[int(p["entry"])] = -1
				cover[int(p["exit"])] = -1
			var i := int(p["head"])
			while true:
				cover[i] = -1
				if i == int(p["tail"]):
					break
				i = (i + 1) % n
	return dropped

# --- Main -----------------------------------------------------------------

func _init() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	cfg = CIRCUITS[id]
	scale_f = cfg["scale"]
	vstep = cfg["vstep"]
	knee = cfg["knee"]
	knee_scale = cfg["knee_scale"]
	smooth = cfg["smooth"]
	separation = cfg.get("separation", SEPARATION)
	resample_m = cfg.get("resample", RESAMPLE)
	leg_cells = cfg.get("leg", LEG)
	turn_cost = cfg.get("turn_cost", TURN_COST)
	drift_cost = cfg.get("drift_cost", DRIFT_COST)
	hug_cost = cfg.get("hug_cost", HUG_COST)
	margin = cfg.get("margin", MARGIN)
	m_per_lat = cfg.get("m_per_lat", M_PER_LAT)
	lateral = cfg.get("lateral", 0.0)
	max_level = cfg.get("max_level", MAX_LEVEL)
	var route_name: String = String(cfg.get("route", id + "_route"))
	var route: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/%s.json" % [ROUTES, route_name]))
	lat0 = cfg.get("lat0", route.get("lat0", 0.0))
	lon0 = cfg.get("lon0", route.get("lon0", 0.0))
	var pts: Array = []
	for p in route["points"]:
		var v := Vector2(float(p["x"]), float(p["y"]))
		if pts.is_empty() or (pts[pts.size() - 1] as Vector2).distance_to(v) > 0.5:
			pts.append(v)

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	center = (lo + hi) * 0.5
	rot = best_rotation(pts)
	print(id, ": ", pts.size(), " points, bbox ", hi - lo, " m, rotation ", int(rad_to_deg(rot)), " deg")

	var bridge: Array = cfg.get("crossing", [])
	if not bridge.is_empty():
		var b0 := real_to_cell(unproj_inv(bridge[0][0], bridge[0][1]))
		var b1 := real_to_cell(unproj_inv(bridge[1][0], bridge[1][1]))
		var mid: Vector2 = (b0 + b1) * 0.5
		crossing_cell = Vector2i(int(round(mid.x)), int(round(mid.y)))
		crossing_deck = (b1 - b0).normalized()
		print("  crossing at ", crossing_cell, ", deck heading ", crossing_deck)

	var dense: Array = resample(pts, resample_m)
	var cell_pts: Array = []
	for i in range(dense.size()):
		# a divided road is two carriageways, each nudged to its own right so the
		# pair never quantises onto one line
		var prev: Vector2 = dense[(i - 1 + dense.size()) % dense.size()]
		var next: Vector2 = dense[(i + 1) % dense.size()]
		var dir: Vector2 = (next - prev).normalized()
		var right := Vector2(-dir.y, dir.x)
		cell_pts.append(real_to_cell(dense[i] + right * (lateral * CELL / scale_f)))
	guide = relax(cell_pts, separation, 10, 600,
		Vector2(crossing_cell) if crossing_cell.x != 2147483647 else Vector2.INF, 6.0)

	var cells: Array = route_circuit()
	var n := cells.size()
	print("  circuit: ", n, " cells, ", n * CELL, " m, closes: ",
		(cells[0] - cells[n - 1]).length() == 1)

	var c_lo := Vector2i(999999, 999999)
	var c_hi := Vector2i(-999999, -999999)
	for c in cells:
		c_lo = Vector2i(mini(c_lo.x, c.x), mini(c_lo.y, c.y))
		c_hi = Vector2i(maxi(c_hi.x, c.x), maxi(c_hi.y, c.y))
	print("  span ", c_hi - c_lo, " (terrain needs ", (c_hi - c_lo) + Vector2i(48, 48), ")")

	var in_dirs: Array = []
	var out_dirs: Array = []
	for i in range(n):
		in_dirs.append(DIRS.find(cells[i] - cells[(i - 1 + n) % n]))
		out_dirs.append(DIRS.find(cells[(i + 1) % n] - cells[i]))

	# --- the bridge, if this lap crosses itself ---
	#
	# A crossing is three overpass tiles, not one. Terrain corners are flattened to
	# the highest tile touching them, so a deck that steps up to ordinary road in
	# the very next cell drags the ground up with it and fills in the underpass.
	# Carrying the deck across three overpass cells keeps the raised road two cells
	# away from the middle one, so the ground under it stays down where the road
	# passing beneath needs it.
	var bridge_at: Array = []
	for i in range(n):
		if cells[i] == crossing_cell:
			bridge_at.append(i)
	var bridge_cells := {}
	var upper := -1
	var lower := -1
	var deck_dir := -1
	if bridge_at.size() == 2:
		upper = bridge_at[0]
		lower = bridge_at[1]
		if Vector2(DIRS[int(out_dirs[upper])]).dot(crossing_deck) < 0.0:
			upper = bridge_at[1]
			lower = bridge_at[0]
		deck_dir = int(out_dirs[upper])
		bridge_cells[crossing_cell] = true
		for k in [-1, 1]:
			var idx: int = (upper + k + n) % n
			if cells[idx] == crossing_cell + DIRS[deck_dir] * k:
				bridge_cells[cells[idx]] = true
			else:
				print("  note: the deck turns beside the crossing, bridge shortened")
		print("  bridge: ", bridge_cells.size(), " overpass cells along ", DIRS[deck_dir])
	elif crossing_cell.x != 2147483647:
		print("  WARNING: the lap passes the bridge cell ", bridge_at.size(), " times")

	# --- corner pieces: banked first (it wants the most room), then wide ---
	var cover: Array = []
	cover.resize(n)
	cover.fill(-1)
	# the bridge is its own piece; no corner may swallow those cells, and neither
	# road may change level on them
	for i in range(n):
		if bridge_cells.has(cells[i]):
			cover[i] = 500000
	var banked: Array = []
	if bool(cfg.get("banking", false)):
		banked = plan_corners(cells, 3, cover, "banked_curve")
	var wides := plan_corners(cells, 2, cover, "wide_curve")
	var tight := 0
	for i in range(n):
		if in_dirs[i] != out_dirs[i] and cover[i] == -1:
			tight += 1
	print("  corners: ", banked.size(), " banked, ", wides.size(), " wide, ", tight, " tight")

	# --- elevation ---
	var rampable: Array = []
	for i in range(n):
		rampable.append(in_dirs[i] == out_dirs[i] and cover[i] == -1)
	var track_lo := INF
	for c in cells:
		track_lo = minf(track_lo, elevation_at_cell(Vector2(c)))
	var base: float = track_lo - vstep
	var plan := plan_elevation(cells, rampable, target_levels(cells, base, {}))
	var entry: Array = plan["entry"]
	var ramp: Array = plan["ramp"]
	# Second pass for a crossing: the deck has to sit exactly one level over the
	# road beneath it, so the upper pass is pinned there and the ramps either side
	# are left to the planner.
	if upper >= 0:
		# Pin a short run either side, not just the cell itself: no bridge cell can
		# ramp, so the climb onto the deck has to happen on the approach.
		var deck_level: int = int(entry[lower])
		var pins := {}
		for k in range(-7, 8):
			pins[(lower + k + n) % n] = deck_level
		for k in range(-6, 7):
			pins[(upper + k + n) % n] = deck_level + 1
		plan = plan_elevation(cells, rampable, target_levels(cells, base, pins))
		entry = plan["entry"]
		ramp = plan["ramp"]
		print("  bridge: deck at level ", entry[upper], " over ", entry[lower],
			" (", "ok" if int(entry[upper]) == int(entry[lower]) + 1 else "MISMATCH", ")")
	# Turn the staircases into slopes. The bridge and its approach keep the levels
	# the deck needs, so nothing there is allowed to move.
	var frozen := {}
	if upper >= 0:
		for k in range(-9, 10):
			frozen[(upper + k + n) % n] = true
			frozen[(lower + k + n) % n] = true
	var target_for_slopes := target_levels(cells, base, {})
	var before_off := 0
	for i in range(n):
		before_off = maxi(before_off, absi(int(entry[i]) - int(target_for_slopes[i])))
	var dips := flatten_dips(n, rampable, ramp, frozen)
	var merged := compact_ramps(n, rampable, ramp, entry, target_for_slopes, frozen, RAMP_GAP)
	# Rolling staircases together can push a descent and a climb into each other,
	# making a V that was not there a moment ago, so sweep for dips once more.
	dips += flatten_dips(n, rampable, ramp, frozen)
	var level_now: int = int(entry[0])
	for i in range(n):
		entry[i] = level_now
		level_now += int(ramp[i])
	var off_ground := 0
	var target_now := target_levels(cells, base, {})
	for i in range(n):
		off_ground = maxi(off_ground, absi(int(entry[i]) - int(target_now[i])))
	print("  slopes: ", dips, " dips carried across, ", merged, " steps rolled into runs, ",
		"road off the ground ", before_off, " -> ", off_ground, " level(s)")

	var dropped_b := drop_conflicting(cells, cover, banked, entry, ramp)
	var dropped_w := drop_conflicting(cells, cover, wides, entry, ramp)
	if dropped_b + dropped_w > 0:
		print("  gave back ", dropped_b, " banked and ", dropped_w, " wide corners for clearance")
	var ups := 0
	var downs := 0
	var min_lvl := 99
	var max_lvl := -99
	for i in range(n):
		if ramp[i] > 0:
			ups += 1
		elif ramp[i] < 0:
			downs += 1
		min_lvl = mini(min_lvl, int(entry[i]))
		max_lvl = maxi(max_lvl, int(entry[i]))
	print("  elevation: levels ", min_lvl, "..", max_lvl, " (", (max_lvl - min_lvl) * 3, " m), ",
		ups, " up, ", downs, " down")

	# --- start/finish ---
	var start_ll: Array = cfg["start_near"]
	var start_at := unproj_inv(start_ll[0], start_ll[1])
	var start_cell := Vector2i.ZERO
	var start_i := -1
	var best_d := INF
	for i in range(n):
		if not rampable[i] or ramp[i] != 0:
			continue
		var d: float = cell_to_real(Vector2(cells[i])).distance_to(start_at)
		if d < best_d:
			best_d = d
			start_i = i
			start_cell = cells[i]
	print("  start/finish ", start_cell, " (", int(best_d), " m from the real line)")

	# --- tiles ---
	var tunnels: Array = cfg.get("tunnels", [])
	# the cells reserved either side of a surviving banked corner
	#
	# Which way the roll leans is the rotation; entry and exit are MIRRORS of each
	# other, not rotations (see TileGeo). The banked curve is a right-hander in its
	# base orientation, but it is anchored and rotated differently depending on
	# which way the lap turns through it -- so plain entry/exit at the direction of
	# travel lean correctly into one hand of corner and exactly the wrong way, off
	# camber, into the other. That hand takes the mirrored pair instead: the other
	# piece, turned half round, which keeps the flat end where it belongs and puts
	# the high side on the other side of the road.
	var bank_ends := {}
	var bank_flipped := {}
	for p in banked:
		if p.get("dropped", false) or int(p["entry"]) < 0:
			continue
		var mirror: bool = bool(p["right"])
		bank_ends[int(p["entry"])] = "banked_exit" if mirror else "banked_entry"
		bank_ends[int(p["exit"])] = "banked_entry" if mirror else "banked_exit"
		if mirror:
			bank_flipped[int(p["entry"])] = true
			bank_flipped[int(p["exit"])] = true
	var grid: Array = []
	var bridge_built := {}
	for i in range(n):
		var c: Vector2i = cells[i]
		if bridge_cells.has(c):
			# One tile per bridge cell, however many times the lap goes through it:
			# the deck runs along the upper road, the lower road crosses underneath.
			if bridge_built.has(c):
				continue
			bridge_built[c] = true
			grid.append({"cell_x": c.x, "cell_y": c.y, "def_id": "overpass",
				"rotation": deck_dir, "elevation_level": int(entry[lower])})
			continue
		if bank_ends.has(i):
			grid.append({"cell_x": c.x, "cell_y": c.y, "def_id": bank_ends[i],
				"rotation": (int(out_dirs[i]) + 2) % 4 if bank_flipped.has(i) else int(out_dirs[i]),
				"elevation_level": entry[i]})
			continue
		if cover[i] != -1:
			continue
		var def := "straight"
		var rotation: int = out_dirs[i]
		var level: int = entry[i]
		if in_dirs[i] != out_dirs[i]:
			def = "curve"
			rotation = curve_rotation((int(in_dirs[i]) + 2) % 4, int(out_dirs[i]))
		elif ramp[i] > 0:
			def = "ramp_up"
		elif ramp[i] < 0:
			def = "ramp_down"
			level = int(entry[i]) - 1
		elif not tunnels.is_empty():
			var ll := unproj(cell_to_real(Vector2(c)))
			for t in tunnels:
				if ll.x > float(t[0]) and ll.x < float(t[2]) and ll.y > float(t[1]) and ll.y < float(t[3]):
					def = "tunnel"
		if i == start_i:
			def = "start"
		grid.append({"cell_x": c.x, "cell_y": c.y, "def_id": def,
			"rotation": rotation, "elevation_level": level})
	var tunnel_tiles := 0
	for t in grid:
		if t["def_id"] == "tunnel":
			tunnel_tiles += 1
	for p in banked + wides:
		if p.get("dropped", false):
			continue
		var anchor: Vector2i = p["anchor"]
		grid.append({"cell_x": anchor.x, "cell_y": anchor.y, "def_id": p["kind"],
			"rotation": p["rotation"], "elevation_level": int(entry[int(p["head"])])})
	if tunnel_tiles > 0:
		print("  tunnel: ", tunnel_tiles, " tiles")

	# --- terrain ---
	var edits: Array = []
	var t_lo := Vector2i(c_lo.x - margin, c_lo.y - margin)
	var t_hi := Vector2i(c_hi.x + margin, c_hi.y + margin)
	var ground_hi := -99
	for i in range(t_lo.x, t_hi.x + 2):
		for j in range(t_lo.y, t_hi.y + 2):
			var e: float = elevation_at_cell(Vector2(float(i) - 0.5, float(j) - 0.5))
			var lvl: int = clampi(int(round(to_level(e - base))), 0, max_level)
			ground_hi = maxi(ground_hi, lvl)
			edits.append(i)
			edits.append(j)
			edits.append(lvl)
	print("  terrain: ", edits.size() / 3, " corners, up to level ", ground_hi)

	var track := {
		"format": "OVERDRIVE_TRACK", "version": 1,
		"name": cfg["name"], "author": "OVERDRIVE",
		"grid": grid,
		"props": build_props(id, cells, t_lo + Vector2i(2, 2), t_hi - Vector2i(2, 2)),
		"start_cell": [start_cell.x, start_cell.y],
		"terrain": {"type": 1, "seed": int(cfg.get("seed", 20260819)), "edits": edits, "lakes": []},
		"metadata": {},
	}
	var out_name: String = cfg["out"]
	var f := FileAccess.open("%s/%s.json" % [OUT, out_name], FileAccess.WRITE)
	f.store_string(JSON.stringify(track))
	f.close()
	print("  wrote ", out_name, ".json (",
		FileAccess.get_file_as_bytes("%s/%s.json" % [OUT, out_name]).size() / 1024, " KB, ",
		grid.size(), " tiles)")
	report_fidelity(cells)
	draw_debug(id, cells, cover)
	quit()

# --- Scenery --------------------------------------------------------------

static func distance_from_track(track_cells: Array, reach: int) -> Dictionary:
	var dist := {}
	var frontier: Array = []
	for c in track_cells:
		dist[c] = 0
		frontier.append(c)
	for step in range(1, reach + 1):
		var next: Array = []
		for c in frontier:
			for d in DIRS:
				var nb: Vector2i = (c as Vector2i) + d
				if not dist.has(nb):
					dist[nb] = step
					next.append(nb)
		frontier = next
	return dist

func build_props(id: String, track_cells: Array, region_lo: Vector2i, region_hi: Vector2i) -> Array:
	prop_lo = region_lo
	prop_hi = region_hi
	var props: Array = []
	var path := "%s/%s_props.json" % [DATA, String(cfg.get("route", id + "_route")).replace("_route", "")]
	if not FileAccess.file_exists(path):
		print("  props: no source data")
		return props
	var raw_text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(raw_text)
	if typeof(data) != TYPE_DICTIONARY:
		print("  props: source data unreadable")
		return props
	var tree_reach: int = cfg.get("tree_reach", 8)
	var building_reach: int = cfg.get("building_reach", 12)
	near = distance_from_track(track_cells, maxi(tree_reach, building_reach))
	var blocked := {}
	for c in track_cells:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				blocked[(c as Vector2i) + Vector2i(dx, dy)] = true
	var taken := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 20260819))
	var buildings := 0
	var trees := 0
	var step: int = cfg.get("tree_step", 3)
	for w in (data as Dictionary)["elements"]:
		if not w.has("geometry"):
			continue
		var tags: Dictionary = w.get("tags", {})
		var ring: Array = []
		for g in w["geometry"]:
			ring.append(real_to_cell(unproj_inv(g["lat"], g["lon"])))
		if ring.size() < 3:
			continue
		if tags.has("building"):
			var mid := Vector2.ZERO
			for p in ring:
				mid += p
			mid /= float(ring.size())
			var kind: int = 2 if absf(ring_area(ring)) > 20.0 else 1
			if place_prop(props, blocked, taken, Vector2i(int(round(mid.x)), int(round(mid.y))),
					kind, rng.randi_range(0, 3), rng.randi_range(0, 3), building_reach):
				buildings += 1
			continue
		var b_lo := Vector2(INF, INF)
		var b_hi := Vector2(-INF, -INF)
		for p in ring:
			b_lo = Vector2(minf(b_lo.x, p.x), minf(b_lo.y, p.y))
			b_hi = Vector2(maxf(b_hi.x, p.x), maxf(b_hi.y, p.y))
		var x := int(b_lo.x)
		while x < int(b_hi.x) + 1:
			var y := int(b_lo.y)
			while y < int(b_hi.y) + 1:
				var cell := Vector2i(x, y) + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				if point_in_ring(Vector2(cell), ring):
					var variant: int
					if int(cfg.get("tree_variants", 0)) > 0:
						variant = rng.randi_range(0, int(cfg["tree_variants"]) - 1)
					else:
						variant = 0 if rng.randf() < float(cfg.get("tree_conifer", 0.6)) else 1
					if place_prop(props, blocked, taken, cell, 0, variant, 0, tree_reach):
						trees += 1
				y += step
			x += step
	print("  props: ", buildings, " buildings, ", trees, " trees")
	return props

func place_prop(props: Array, blocked: Dictionary, taken: Dictionary, anchor: Vector2i,
		kind: int, variant: int, rotation: int, reach: int) -> bool:
	if anchor.x < prop_lo.x or anchor.y < prop_lo.y or anchor.x > prop_hi.x or anchor.y > prop_hi.y:
		return false
	if not near.has(anchor) or int(near[anchor]) > reach:
		return false
	var size: Vector2i = Vector2i(2, 2) if kind == 2 else (Vector2i(1, 2) if kind == 1 else Vector2i.ONE)
	var cells: Array = []
	for dx in range(size.x):
		for dz in range(size.y):
			var off := Vector2i(dx, -dz)
			for _r in range(posmod(rotation, 4)):
				off = Vector2i(-off.y, off.x)
			cells.append(anchor + off)
	for c in cells:
		if blocked.has(c) or taken.has(c):
			return false
	for c in cells:
		taken[c] = true
	props.append({"cell_x": anchor.x, "cell_y": anchor.y,
		"kind": kind, "variant": variant, "rotation": rotation})
	return true

static func ring_area(ring: Array) -> float:
	var sum := 0.0
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * 0.5

static func point_in_ring(p: Vector2, ring: Array) -> bool:
	var inside := false
	var n := ring.size()
	for i in range(n):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		if (a.y > p.y) != (b.y > p.y):
			var t: float = (p.y - a.y) / (b.y - a.y)
			if p.x < a.x + t * (b.x - a.x):
				inside = not inside
	return inside

# --- Reporting ------------------------------------------------------------

func report_fidelity(cells: Array) -> void:
	var total := 0.0
	var worst := 0.0
	for c in cells:
		var best := INF
		for p in guide:
			best = minf(best, Vector2(c).distance_to(p))
		total += best
		worst = maxf(worst, best)
	print("  fidelity: mean ", snappedf(total / float(cells.size()) * CELL / scale_f, 0.1),
		" m off the real line, worst ", snappedf(worst * CELL / scale_f, 0.1), " m")

func draw_debug(id: String, cells: Array, cover: Array) -> void:
	var lo := Vector2i(999999, 999999)
	var hi := Vector2i(-999999, -999999)
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var pad := 4
	var px := 4
	var size := Vector2i(hi.x - lo.x + pad * 2, hi.y - lo.y + pad * 2) * px
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.99, 0.99, 0.97))
	for p in guide:
		var v: Vector2 = (p - Vector2(lo) + Vector2(pad, pad)) * px
		if v.x >= 0 and v.y >= 0 and v.x < size.x and v.y < size.y:
			img.set_pixel(int(v.x), int(v.y), Color(0.75, 0.75, 0.8))
	var seen := {}
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		var col := Color(0.1, 0.3, 0.8)
		if seen.has(c):
			col = Color(0.9, 0.1, 0.1)
		elif cover[i] >= 3000:
			col = Color(0.6, 0.2, 0.8)        # banked
		elif cover[i] >= 2000:
			col = Color(0.95, 0.6, 0.0)       # wide
		seen[c] = true
		if i == 0:
			col = Color(0.0, 0.7, 0.2)
		var base := (c - lo + Vector2i(pad, pad)) * px
		for dx in range(px):
			for dy in range(px):
				var x := base.x + dx
				var y := base.y + dy
				if x >= 0 and y >= 0 and x < size.x and y < size.y:
					img.set_pixel(x, y, col)
	img.save_png("%s/%s_lattice.png" % [OUT, id])
