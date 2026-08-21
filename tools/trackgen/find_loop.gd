extends SceneTree
## Pull one racing lap out of an OSM extract: build the directed road graph (the
## one-way tags are what keep a circuit going the right way round), then find the
## shortest directed cycle that visits every anchor in turn. Writes
## <id>_route.json in metres, plus a picture to check it by eye.
##
## Run with: --script find_loop.gd -- <id>

const DATA := "res://tools/trackgen/data"
const ROUTES := "res://tools/trackgen/routes"
const OUT := "res://tools/trackgen/out"

const CIRCUITS := {
	# The pass: up the hairpins from the valley to the top, and back down. Nothing
	# to exclude -- there is only one road up there.
	"stelvio": {
		"lat0": 46.5330, "lon0": 10.4700,
		"include": ["road"],
		"exclude": ["Umbrail"],
		"mode": "out_back",
		"ignore_oneway": true,
		# the summit, and the foot of the hairpin stack below it
		"anchors": [[46.52855, 10.45265], [46.53430, 10.49180]],
		"climb_m": 2600.0,
	},
	"spa": {
		"lat0": 50.4400, "lon0": 5.9700,
		"include": ["raceway"],
		"exclude": ["Pit Lane", "Support Pit", "Kart", "kart"],
		# La Source, Les Combes (top of Kemmel), the run down to Pouhon,
		# Fagnes/Stavelot, Blanchimont
		"anchors": [[50.4460, 5.9638], [50.43845, 5.97443], [50.4315, 5.9772],
			[50.43042, 5.96587], [50.43515, 5.96713]],
	},
	"zuzuka": {
		"lat0": 34.8430, "lon0": 136.5400,
		"include": ["raceway"],
		"exclude": ["Pit Lane", "Kart", "kart", "カート", "アドバンス", "アドベンチャー",
			"チララ", "DREAM", "ene-1", "West Circuit", "East Circuit", "南コース"],
		# main straight, turn 1/2, the esses, Spoon, the run back past 130R
		"anchors": [[34.8440, 136.5390], [34.8460, 136.5366], [34.8447, 136.5347],
			[34.8432, 136.5313], [34.8471, 136.5304], [34.8481, 136.5220],
			[34.8411, 136.5410]],
	},
	# Monte Carlo is public street, and OSM maps only fragments of it as raceway,
	# so the lap cannot be walked or routed between distant anchors without the
	# shortest path ducking down a side street. Instead the circuit is traced by
	# hand off the street map, corner by corner, and every traced point is snapped
	# to the nearest real road node -- so the geometry is still the actual streets,
	# just told which ones to use.
	"momako": {
		"lat0": 43.7385, "lon0": 7.4245,
		"include": ["raceway", "road"],
		"exclude": ["Voie des stands", "Sortie des stands"],
		"anchors": [[43.7343, 7.4215], [43.7368, 7.4204]],
		"mode": "traced",
		"ignore_oneway": true,
		"trace_top_left": [43.7425, 7.4185],
		"trace_per_px": [0.000012224, 0.000011250],
		"trace_px": [
			[390, 800], [350, 745], [320, 690], [300, 640], [285, 590], [275, 540],
			[267, 490], [263, 455],                                   # Sainte Devote
			[300, 420], [380, 390], [470, 355], [560, 320], [650, 290], [730, 265],
			[800, 245],                                               # Casino
			[860, 225], [900, 200], [915, 188],                       # Fairmont hairpin
			[940, 165], [970, 140], [995, 118],                       # Portier
			[1000, 160], [985, 230], [965, 290], [930, 350],          # the tunnel
			[897, 401],                                               # chicane
			[850, 440], [790, 480], [740, 510],                       # Tabac
			[700, 540], [660, 570], [631, 597],                       # swimming pool
			[590, 630], [540, 670], [490, 710], [440, 750],           # Rascasse
			[410, 775], [370, 790],
		],
	},
	"momako_unused": {
		"lat0": 43.7385, "lon0": 7.4245,
		"include": ["raceway", "road"],
		"exclude": ["Voie des stands", "Sortie des stands"],
		"mode": "legs",
		# street one-ways run for traffic, not for racing, so they are ignored and
		# the lap is pinned by anchors at the corners instead
		"ignore_oneway": true,
		"anchors": [[43.7343, 7.4215], [43.7368, 7.4204], [43.73753, 7.42519],
			[43.73830, 7.42777], [43.74030, 7.42860], [43.74102, 7.42863],
			[43.73960, 7.42930], [43.73887, 7.42969], [43.73760, 7.42800],
			[43.73716, 7.42477], [43.73560, 7.42330], [43.73455, 7.42235],
			[43.73264, 7.42247], [43.73298, 7.42206]],
	},
	"mexico": {
		"lat0": 19.4045, "lon0": -99.0900,
		"include": ["raceway"],
		"exclude": ["Pit Lane", "pit lane", "Kart", "kart"],
		# main straight, the far end, the esses, the run back, the stadium loop
		"anchors": [[19.4056, -99.0877], [19.4038, -99.0833], [19.3978, -99.0863],
			[19.4020, -99.0898], [19.4045, -99.0961]],
	},
	"baytona": {
		"lat0": 29.1850, "lon0": -81.0700,
		"include": ["raceway"],
		"exclude": ["Pit", "pit", "Kart", "kart", "Road Course", "road course", "Infield", "infield"],
		# the four quarters of the tri-oval
		"anchors": [[29.1916, -81.0658], [29.1895, -81.0709], [29.1831, -81.0744],
			[29.1786, -81.0720], [29.1799, -81.0669], [29.1884, -81.0625]],
	},
}

var lat0 := 0.0
var lon0 := 0.0
var pos := {}
var geo := {}
var adj := {}

func proj(lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)), -(lat - lat0) * 111132.0)

func unproj(p: Vector2) -> Vector2:
	return Vector2(lat0 - p.y / 111132.0, lon0 + p.x / (111320.0 * cos(deg_to_rad(lat0))))

func add_edge(a: int, b: int) -> void:
	if not adj.has(a):
		adj[a] = []
	adj[a].append([b, pos[a].distance_to(pos[b])])

func build_graph(elements: Array, cfg: Dictionary) -> void:
	var want_road: bool = (cfg["include"] as Array).has("road")
	for w in elements:
		if not w.has("geometry") or not w.has("nodes"):
			continue
		var tags: Dictionary = w.get("tags", {})
		var hw: String = String(tags.get("highway", ""))
		var name: String = String(tags.get("name", ""))
		if hw != "raceway" and not want_road:
			continue
		var skip := false
		for bad in cfg["exclude"]:
			if name.contains(bad) or String(tags.get("raceway", "")).contains(bad):
				skip = true
		if skip:
			continue
		var ids: Array = w["nodes"]
		var g: Array = w["geometry"]
		if ids.size() != g.size():
			continue
		for i in range(ids.size()):
			pos[int(ids[i])] = proj(g[i]["lat"], g[i]["lon"])
			geo[int(ids[i])] = Vector2(g[i]["lat"], g[i]["lon"])
		var oneway: String = String(tags.get("oneway", ""))
		if bool(cfg.get("ignore_oneway", false)):
			oneway = ""
		var forward := oneway != "-1"
		var backward := not (oneway == "yes" or oneway == "1" or oneway == "true")
		if oneway == "-1":
			backward = true
		for i in range(ids.size() - 1):
			if forward:
				add_edge(int(ids[i]), int(ids[i + 1]))
			if backward:
				add_edge(int(ids[i + 1]), int(ids[i]))

func nearest_node(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for id in pos:
		if not adj.has(id):
			continue
		var d: float = pos[id].distance_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best

func shortest_path(src: int, dst: int) -> Array:
	var dist := {src: 0.0}
	var prev := {}
	var visited := {}
	var frontier := {src: 0.0}
	while not frontier.is_empty():
		var u := -1
		var best := INF
		for k in frontier:
			if frontier[k] < best:
				best = frontier[k]
				u = k
		frontier.erase(u)
		if visited.has(u):
			continue
		visited[u] = true
		if u == dst:
			break
		for e in adj.get(u, []):
			var v: int = e[0]
			var nd: float = float(dist[u]) + float(e[1])
			if not dist.has(v) or nd < float(dist[v]) - 1e-6:
				dist[v] = nd
				prev[v] = u
				frontier[v] = nd
	if not dist.has(dst):
		return []
	var path: Array = [dst]
	var cur := dst
	while cur != src:
		cur = prev[cur]
		path.append(cur)
	path.reverse()
	return path

## Drive the graph like a car would: from `start`, take the outgoing edge that
## bends least, and keep going until you are back where you began. A circuit
## whose pit lanes and side tracks have been filtered out is very nearly a simple
## cycle, so this traces the lap exactly -- including a crossover, which is two
## ways passing on a bridge with no junction between them.
func walk_lap(start: int, first_hop: int) -> Array:
	var lap: Array = [start, first_hop]
	var prev := start
	var cur := first_hop
	for _step in range(20000):
		var heading: Vector2 = (pos[cur] - pos[prev]).normalized()
		var best := -1
		var best_dot := -2.0
		for e in adj.get(cur, []):
			var nxt: int = e[0]
			if nxt == prev:
				continue
			var d: float = heading.dot((pos[nxt] - pos[cur]).normalized())
			if d > best_dot:
				best_dot = d
				best = nxt
		if best == -1:
			print("  walk: dead end after ", lap.size(), " nodes")
			return []
		if best == start:
			return lap
		lap.append(best)
		prev = cur
		cur = best
	print("  walk: never came home")
	return []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "spa"
	var cfg: Dictionary = CIRCUITS[id]
	lat0 = cfg["lat0"]
	lon0 = cfg["lon0"]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [DATA, id]))
	build_graph(data["elements"], cfg)
	print(id, ": graph ", pos.size(), " nodes")

	var anchors: Array = cfg["anchors"]
	# Start on the first anchor, heading towards the second: that fixes both where
	# the lap begins and which way round it runs.
	var start := nearest_node(proj(anchors[0][0], anchors[0][1]))
	var toward := nearest_node(proj(anchors[1][0], anchors[1][1]))
	var first_hop := -1
	var best_score := -INF
	var aim: Vector2 = (pos[toward] - pos[start]).normalized()
	for e in adj.get(start, []):
		var d: float = aim.dot((pos[e[0]] - pos[start]).normalized())
		if d > best_score:
			best_score = d
			first_hop = e[0]
	var route_nodes: Array = []
	var extra: Array = []   ## synthetic points appended after the real road
	if String(cfg.get("mode", "walk")) == "out_back":
		# A mountain pass is not a loop, and the game needs one. Retracing the road
		# does not work: two ribbons and the clear cell the generator keeps between
		# them need more room than the shelves of a hairpin stack leave. So the lap
		# climbs the real hairpins and comes back down a road of our own -- an arc
		# swung wide of the stack, dropping the whole height down the open flank.
		var up := shortest_path(nearest_node(proj(anchors[0][0], anchors[0][1])),
			nearest_node(proj(anchors[1][0], anchors[1][1])))
		if up.is_empty():
			print("  NO PATH between the two ends")
			quit(1)
			return
		# optionally only the top of the pass: the climb is cut at climb_m of road
		var limit: float = float(cfg.get("climb_m", 0.0))
		if limit > 0.0:
			var run := 0.0
			var cut := up.size()
			for k in range(1, up.size()):
				run += pos[up[k]].distance_to(pos[up[k - 1]])
				if run > limit:
					cut = k + 1
					break
			up = up.slice(0, cut)
		# anchors[0] is the summit, so the road as found comes down. Turn it round:
		# the lap should climb the hairpins first and use the descent as the payoff.
		up.reverse()
		route_nodes = up.duplicate()
		var climb: Array = []
		for nid in up:
			climb.append(pos[nid])
		var foot: Vector2 = climb[0]
		var top: Vector2 = climb[climb.size() - 1]
		var clear_m: float = float(cfg.get("return_clear_m", 30.0))
		var join_m: float = float(cfg.get("return_join_m", 70.0))
		# Bow the return away from the stack, taking the first side and offset that
		# clears every hairpin. Both sides are tried because which one is open
		# depends on which way the road happens to lie.
		var arc: Array = []
		for off in range(60, 620, 20):
			for side_v in [1.0, -1.0]:
				var side := float(side_v)
				var dir: Vector2 = (foot - top).normalized()
				var nrm := Vector2(-dir.y, dir.x) * side * float(off)
				var ctrl: Vector2 = (top + foot) * 0.5 + nrm
				var try_arc: Array = []
				var worst := INF
				for s in range(1, 121):
					var t := float(s) / 121.0
					var p: Vector2 = top.lerp(ctrl, t).lerp(ctrl.lerp(foot, t), t)
					try_arc.append(p)
					if p.distance_to(top) < join_m or p.distance_to(foot) < join_m:
						continue
					for q in climb:
						worst = minf(worst, p.distance_to(q))
				if worst >= clear_m:
					arc = try_arc
					print("  return: bowed ", off, " m to the ",
						"left" if side > 0.0 else "right", ", clears by ", int(worst), " m")
					break
			if not arc.is_empty():
				break
		if arc.is_empty():
			print("  NO ROOM for a return that clears the stack")
			quit(1)
			return
		extra = arc
		print("  climb: ", up.size(), " points, with the return: ",
			up.size() + arc.size())
	elif String(cfg.get("mode", "walk")) == "traced":
		# Each traced point is only a hundred metres or so from the next, so the
		# shortest path between them has nowhere to wander off to.
		var tl: Array = cfg["trace_top_left"]
		var per: Array = cfg["trace_per_px"]
		var trace: Array = []
		for px in cfg["trace_px"]:
			trace.append(nearest_node(proj(float(tl[0]) - float(px[1]) * float(per[0]),
				float(tl[1]) + float(px[0]) * float(per[1]))))
		for i in range(trace.size()):
			var seg := shortest_path(trace[i], trace[(i + 1) % trace.size()])
			if seg.is_empty():
				print("  NO PATH from traced point ", i)
				quit(1)
				return
			for k in range(seg.size()):
				if k == 0 and not route_nodes.is_empty():
					continue
				route_nodes.append(seg[k])
	elif String(cfg.get("mode", "walk")) == "legs":
		# A street circuit has junctions everywhere, so it is stitched from shortest
		# paths between corner anchors instead of driven round.
		for i in range(anchors.size()):
			var from_n := nearest_node(proj(anchors[i][0], anchors[i][1]))
			var to_n := nearest_node(proj(anchors[(i + 1) % anchors.size()][0],
				anchors[(i + 1) % anchors.size()][1]))
			var seg := shortest_path(from_n, to_n)
			if seg.is_empty():
				print("  NO PATH from anchor ", i)
				quit(1)
				return
			for k in range(seg.size()):
				if k == 0 and not route_nodes.is_empty():
					continue
				route_nodes.append(seg[k])
	else:
		route_nodes = walk_lap(start, first_hop)
	if route_nodes.is_empty():
		quit(1)
		return
	# Snapping a traced point onto a quay or a slip road makes the route dart out
	# and back; those spurs are not part of any lap, so they go. An out-and-back
	# retraces the same road on purpose, so it is exempt from both sweeps.
	var retrace: bool = String(cfg.get("mode", "walk")) == "out_back"
	var pruned := 1 if not retrace else 0
	while pruned > 0:
		pruned = 0
		var kept: Array = []
		var i := 0
		while i < route_nodes.size():
			var nxt: int = (i + 1) % route_nodes.size()
			var prv: int = kept.size() - 1
			if prv >= 0 and route_nodes[nxt] == kept[prv]:
				kept.remove_at(prv)
				i += 2
				pruned += 1
				continue
			kept.append(route_nodes[i])
			i += 1
		route_nodes = kept
	# The same, for a detour that goes out one road and comes back on another: any
	# node visited twice close together brackets a loop that is not part of the lap.
	if not retrace:
		var seen := {}
		var clean: Array = []
		for nid in route_nodes:
			if seen.has(nid) and clean.size() - int(seen[nid]) < 80:
				while clean.size() > int(seen[nid]) + 1:
					seen.erase(clean.pop_back())
				continue
			seen[nid] = clean.size()
			clean.append(nid)
		route_nodes = clean
	# Real road nodes, then any road of our own making, as one closed polyline.
	var poly: Array = []
	for nid in route_nodes:
		poly.append(pos[nid])
	for p in extra:
		poly.append(p)
	var total := 0.0
	for k in range(1, poly.size()):
		total += (poly[k] as Vector2).distance_to(poly[k - 1])
	total += (poly[0] as Vector2).distance_to(poly[poly.size() - 1])
	print("  lap: ", poly.size(), " points, ", int(total), " m")

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pts: Array = []
	for pp in poly:
		var p: Vector2 = pp
		var ll: Vector2 = unproj(p)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		pts.append({"x": p.x, "y": p.y, "lat": ll.x, "lon": ll.y})
	print("  bbox: ", hi - lo, " m")
	var f := FileAccess.open("%s/%s_route.json" % [ROUTES, id], FileAccess.WRITE)
	f.store_string(JSON.stringify({"points": pts, "length_m": total,
		"lat0": lat0, "lon0": lon0}))
	f.close()

	draw(id, data["elements"], pts, lo, hi)
	quit()

func draw(id: String, elements: Array, pts: Array, lo: Vector2, hi: Vector2) -> void:
	var pad := 120.0
	var mpp: float = maxf((hi.x - lo.x + pad * 2) / 1100.0, (hi.y - lo.y + pad * 2) / 850.0)
	var origin := lo - Vector2(pad, pad)
	var size := Vector2i(int((hi.x - lo.x + pad * 2) / mpp), int((hi.y - lo.y + pad * 2) / mpp))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.97, 0.95))
	for w in elements:
		if not w.has("geometry"):
			continue
		var prev := Vector2.INF
		for g in w["geometry"]:
			var p: Vector2 = (proj(g["lat"], g["lon"]) - origin) / mpp
			if prev != Vector2.INF:
				line(img, prev, p, Color(0.65, 0.65, 0.65), size)
			prev = p
	for i in range(1, pts.size()):
		var a: Vector2 = (Vector2(float(pts[i - 1]["x"]), float(pts[i - 1]["y"])) - origin) / mpp
		var b: Vector2 = (Vector2(float(pts[i]["x"]), float(pts[i]["y"])) - origin) / mpp
		line(img, a, b, Color(0.9, 0.1, 0.1), size, 1)
	img.save_png("%s/%s_route.png" % [OUT, id])
	print("  wrote ", id, "_route.png ", size)

static func line(img: Image, a: Vector2, b: Vector2, c: Color, size: Vector2i, w: int = 0) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		for dx in range(-w, w + 1):
			for dy in range(-w, w + 1):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < size.x and y < size.y:
					img.set_pixel(x, y, c)
