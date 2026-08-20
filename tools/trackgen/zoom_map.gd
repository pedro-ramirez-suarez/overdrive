extends SceneTree
## Zoomed map of a lat/lon window, for picking anchors precisely.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var lo := Vector2(float(a[1]), float(a[2]))   # lat, lon
	var hi := Vector2(float(a[3]), float(a[4]))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/trackgen/data/%s.json" % id))
	var size := Vector2i(1200, 900)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.99, 0.98, 0.96))
	var step := 0.001
	var g := snappedf(lo.x, step)
	while g < hi.x:
		var y := int((hi.x - g) / (hi.x - lo.x) * size.y)
		for x in range(size.x):
			if y >= 0 and y < size.y:
				img.set_pixel(x, y, Color(0.55, 0.7, 0.92) if fmod(g, 0.005) < 0.0002 else Color(0.87, 0.9, 0.94))
		g += step
	g = snappedf(lo.y, step)
	while g < hi.y:
		var x := int((g - lo.y) / (hi.y - lo.y) * size.x)
		for y in range(size.y):
			if x >= 0 and x < size.x:
				img.set_pixel(x, y, Color(0.55, 0.7, 0.92) if fmod(g, 0.005) < 0.0002 else Color(0.87, 0.9, 0.94))
		g += step
	for w in data["elements"]:
		if not w.has("geometry"):
			continue
		var hw: String = String(w.get("tags", {}).get("highway", ""))
		var name: String = String(w.get("tags", {}).get("name", ""))
		var col := Color(0.75, 0.75, 0.78) if hw != "raceway" else Color(0.85, 0.3, 0.05)
		if name.contains("Pit") or name.contains("Kart") or name.contains("カート"):
			col = Color(0.2, 0.6, 0.9)
		var prev := Vector2.INF
		for gp in w["geometry"]:
			var p := Vector2((float(gp["lon"]) - lo.y) / (hi.y - lo.y) * size.x,
				(hi.x - float(gp["lat"])) / (hi.x - lo.x) * size.y)
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
	img.save_png("res://tools/trackgen/out/%s_zoom.png" % id)
	print("top-left ", hi.x, ",", lo.y, "  bottom-right ", lo.x, ",", hi.y,
		"  lat/px ", (hi.x - lo.x) / size.y, "  lon/px ", (hi.y - lo.y) / size.x)
	quit()
