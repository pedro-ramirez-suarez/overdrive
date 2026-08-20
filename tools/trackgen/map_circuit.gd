extends SceneTree
## Draw a circuit's raceway network with a lat/lon graticule, so anchors can be
## read straight off the picture.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/trackgen/data/%s.json" % id))
	var lo := Vector2(999.0, 999.0)     # (lat, lon)
	var hi := Vector2(-999.0, -999.0)
	var oneway := 0
	var total := 0
	for w in data["elements"]:
		if not w.has("geometry") or String(w.get("tags", {}).get("highway", "")) != "raceway":
			continue
		total += 1
		if String(w.get("tags", {}).get("oneway", "")) == "yes":
			oneway += 1
		for g in w["geometry"]:
			lo = Vector2(minf(lo.x, g["lat"]), minf(lo.y, g["lon"]))
			hi = Vector2(maxf(hi.x, g["lat"]), maxf(hi.y, g["lon"]))
	var pad := 0.0015
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	var size := Vector2i(1100, 850)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.97, 0.95))
	# graticule every 0.002 degrees, brighter every 0.01
	var g_lat := snappedf(lo.x, 0.002)
	while g_lat < hi.x:
		var y := int((hi.x - g_lat) / (hi.x - lo.x) * size.y)
		var col := Color(0.85, 0.88, 0.93) if fmod(g_lat, 0.01) > 0.0005 else Color(0.5, 0.65, 0.9)
		for x in range(size.x):
			if y >= 0 and y < size.y:
				img.set_pixel(x, y, col)
		g_lat += 0.002
	var g_lon := snappedf(lo.y, 0.002)
	while g_lon < hi.y:
		var x := int((g_lon - lo.y) / (hi.y - lo.y) * size.x)
		var col := Color(0.85, 0.88, 0.93) if fmod(g_lon, 0.01) > 0.0005 else Color(0.5, 0.65, 0.9)
		for y in range(size.y):
			if x >= 0 and x < size.x:
				img.set_pixel(x, y, col)
		g_lon += 0.002
	for w in data["elements"]:
		if not w.has("geometry"):
			continue
		var tags: Dictionary = w.get("tags", {})
		var is_race: bool = String(tags.get("highway", "")) == "raceway"
		var name: String = String(tags.get("name", ""))
		var col := Color(0.6, 0.6, 0.62)
		if is_race:
			col = Color(0.85, 0.3, 0.05)
			if name.contains("Pit") or name.contains("pit") or name.contains("Kart") or name.contains("kart"):
				col = Color(0.2, 0.6, 0.9)
		elif not is_race:
			continue
		var prev := Vector2.INF
		for g in w["geometry"]:
			var p := Vector2((float(g["lon"]) - lo.y) / (hi.y - lo.y) * size.x,
				(hi.x - float(g["lat"])) / (hi.x - lo.x) * size.y)
			if prev != Vector2.INF:
				var steps := int(maxf(absf(p.x - prev.x), absf(p.y - prev.y))) + 1
				for i in range(steps + 1):
					var q := prev.lerp(p, float(i) / float(steps))
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var x := int(q.x) + dx
							var y := int(q.y) + dy
							if x >= 0 and y >= 0 and x < size.x and y < size.y:
								img.set_pixel(x, y, col)
			prev = p
	img.save_png("res://tools/trackgen/out/%s_map.png" % id)
	print(id, ": lat ", lo.x, "..", hi.x, "  lon ", lo.y, "..", hi.y,
		"  (top-left = ", hi.x, ",", lo.y, ")  oneway ", oneway, "/", total)
	quit()
