class_name TerrainWorld
extends RefCounted
## Builds the terrain surface (low-poly hills, coloured by height) with trimesh
## collision, plus translucent water for lakes (SPEC.md §M6). The car drives on
## the terrain off-track; the surface is tagged "offtrack" for the speed penalty.

const MARGIN := 24      # cells of terrain beyond the track bounds
## Cap on terrain size per axis, in cells. Big enough for the largest bundled
## track plus its margins: past the cap the ground simply stops, which reads as a
## hole in the world rather than a saving. Each extra 100 cells of span costs
## roughly a third of a second of build time.
const MAX_SPAN := 280


## Build terrain sized to the track bounds (+ margin).
static func build(parent: Node3D, terrain: Terrain, grid: TrackGrid) -> void:
	var lo := Vector2i(-10, -10)
	var hi := Vector2i(10, 10)
	if not grid.tiles.is_empty():
		var first := true
		for cell in grid.tiles:
			if first:
				lo = cell
				hi = cell
				first = false
			else:
				lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
				hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
		lo -= Vector2i(MARGIN, MARGIN)
		hi += Vector2i(MARGIN, MARGIN)
	hi.x = mini(hi.x, lo.x + MAX_SPAN)
	hi.y = mini(hi.y, lo.y + MAX_SPAN)
	build_region(parent, terrain, grid, lo, hi)


## Build terrain over an explicit cell region (used to fill the editor grid).
## Terrain cells under a track tile are flattened to that tile's level so the
## track always sits on a flat square; the transition falls to the neighbours.
static func build_region(parent: Node3D, terrain: Terrain, grid: TrackGrid, lo: Vector2i, hi: Vector2i,
		with_collision: bool = true, with_fence: bool = true) -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = Constants.ROAD_BIT
	body.collision_mask = 0
	body.add_to_group(TrackWorld.OFFTRACK_GROUP)
	parent.add_child(body)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var water_quads: Array[Vector3] = []

	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			# A hand-placed lake replaces its cell's surface with a walled basin, so
			# it stays entirely inside its own square and leaves neighbours alone.
			if terrain.lake_level(Vector2i(cx, cz)) != Terrain.NO_LAKE:
				_add_lake_basin(st, faces, terrain, Vector2i(cx, cz))
				water_quads.append(Vector3(cx * Constants.CELL_SIZE,
					terrain.water_surface(Vector2i(cx, cz)), cz * Constants.CELL_SIZE))
				continue
			var p00 := _corner(terrain, grid, cx, cz)
			var p10 := _corner(terrain, grid, cx + 1, cz)
			var p01 := _corner(terrain, grid, cx, cz + 1)
			var p11 := _corner(terrain, grid, cx + 1, cz + 1)
			_tri(st, faces, p00, p10, p11)
			_tri(st, faces, p00, p11, p01)
			if not grid.has_tile(Vector2i(cx, cz)) and terrain.is_water(Vector2i(cx, cz)):
				water_quads.append(Vector3(cx * Constants.CELL_SIZE,
					Terrain.WATER_SURFACE, cz * Constants.CELL_SIZE))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _terrain_material()
	body.add_child(mesh_instance)

	if with_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)

	if not water_quads.is_empty():
		_add_water(parent, water_quads)

	if with_fence:
		_add_perimeter_fence(parent, terrain, lo, hi)


## A wall around the map boundary so the car can't drive off the edge into the
## void. Built from four solid box walls (thick BoxShapes — no tunnelling like a
## thin trimesh) on the wall layer.
static func _add_perimeter_fence(parent: Node3D, _terrain: Terrain, lo: Vector2i, hi: Vector2i) -> void:
	var body := StaticBody3D.new()
	body.name = "MapFence"
	body.collision_layer = Constants.WALL_BIT
	body.collision_mask = 0
	parent.add_child(body)

	var min_x: float = (lo.x - 0.5) * Constants.CELL_SIZE
	var max_x: float = (hi.x + 0.5) * Constants.CELL_SIZE
	var min_z: float = (lo.y - 0.5) * Constants.CELL_SIZE
	var max_z: float = (hi.y + 0.5) * Constants.CELL_SIZE
	var cx: float = (min_x + max_x) * 0.5
	var cz: float = (min_z + max_z) * 0.5

	var y_bottom: float = -4.0
	var y_top: float = Constants.MAX_TERRAIN_LEVEL * Constants.ELEVATION_STEP + 6.0
	var cy: float = (y_bottom + y_top) * 0.5
	var h: float = y_top - y_bottom
	var thick: float = 1.0
	var len_x: float = (max_x - min_x) + thick
	var len_z: float = (max_z - min_z) + thick

	# [size, centre] for the south, north, west, east collision walls. These are
	# invisible now — physics only — with the ring of mountains standing in for the
	# visible boundary.
	var walls := [
		[Vector3(len_x, h, thick), Vector3(cx, cy, min_z)],
		[Vector3(len_x, h, thick), Vector3(cx, cy, max_z)],
		[Vector3(thick, h, len_z), Vector3(min_x, cy, cz)],
		[Vector3(thick, h, len_z), Vector3(max_x, cy, cz)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[0]
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = w[1]
		body.add_child(cs)

	_add_mountain_ring(parent, min_x, max_x, min_z, max_z)


## A ridge of low-poly mountains around the map edge — the visible boundary, in
## place of the old translucent wall. Purely decorative: the invisible collision
## walls above still catch the car. Peaks vary in height with a fixed seed, so the
## range is stable between runs, and are coloured dark slate rising to snow.
static func _add_mountain_ring(parent: Node3D, min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 725

	# The four edges, each as a start, end, and the outward (away-from-map) normal.
	var edges := [
		[Vector2(min_x, min_z), Vector2(max_x, min_z), Vector2(0.0, -1.0)],  # south
		[Vector2(max_x, max_z), Vector2(min_x, max_z), Vector2(0.0, 1.0)],   # north
		[Vector2(min_x, max_z), Vector2(min_x, min_z), Vector2(-1.0, 0.0)],  # west
		[Vector2(max_x, min_z), Vector2(max_x, max_z), Vector2(1.0, 0.0)],   # east
	]
	for e in edges:
		_add_mountain_edge(st, e[0], e[1], e[2], rng)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "MountainRing"
	mi.mesh = mesh
	mi.material_override = _mountain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


const MTN_SPACING := 26.0   # meters between peaks
const MTN_DEPTH := 20.0     # how far the ridge sits outward from the boundary
const MTN_BASE := -6.0      # skirt bottom, below ground so there's no gap


static func _add_mountain_edge(st: SurfaceTool, a: Vector2, b: Vector2, outward: Vector2, rng: RandomNumberGenerator) -> void:
	var length: float = a.distance_to(b)
	var along: Vector2 = (b - a) / maxf(length, 0.001)
	var count: int = maxi(3, int(length / MTN_SPACING))

	# Precompute a peak height at each sample; alternate tall peaks with lower
	# saddles so the silhouette reads as separate mountains, not a sawtooth.
	var heights: Array[float] = []
	for i in range(count + 1):
		var tall: bool = i % 2 == 0
		heights.append(rng.randf_range(46.0, 72.0) if tall else rng.randf_range(20.0, 34.0))

	for i in range(count):
		var pa: Vector2 = a + along * (length * float(i) / float(count))
		var pb: Vector2 = a + along * (length * float(i + 1) / float(count))
		var ridge_a := outward * MTN_DEPTH
		var ridge_b := outward * MTN_DEPTH
		var out_a := outward * (MTN_DEPTH * 2.0)
		var out_b := outward * (MTN_DEPTH * 2.0)

		# Ridge tops, inner skirt (at the boundary), outer skirt (further out).
		var ra := Vector3(pa.x + ridge_a.x, heights[i], pa.y + ridge_a.y)
		var rb := Vector3(pb.x + ridge_b.x, heights[i + 1], pb.y + ridge_b.y)
		var ia := Vector3(pa.x, MTN_BASE, pa.y)
		var ib := Vector3(pb.x, MTN_BASE, pb.y)
		var oa := Vector3(pa.x + out_a.x, MTN_BASE, pa.y + out_a.y)
		var ob := Vector3(pb.x + out_b.x, MTN_BASE, pb.y + out_b.y)

		# Inner slope (faces the map) and outer slope.
		_mtn_tri(st, ia, ra, rb)
		_mtn_tri(st, ia, rb, ib)
		_mtn_tri(st, ra, oa, ob)
		_mtn_tri(st, ra, ob, rb)


static func _mtn_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n  # visible faces are slopes, so orient them upward for the sun
	for v in [a, b, c]:
		st.set_color(_mountain_color(v.y))
		st.set_normal(n)
		st.add_vertex(v)


static func _mountain_color(y: float) -> Color:
	var t: float = clampf(y / 72.0, 0.0, 1.0)
	if t < 0.55:
		return Color(0.22, 0.27, 0.30).lerp(Color(0.34, 0.38, 0.46), t / 0.55)  # slate
	return Color(0.34, 0.38, 0.46).lerp(Color(0.90, 0.92, 0.96), (t - 0.55) / 0.45)  # snow caps


static func _mountain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## How finely a lake cell is subdivided. The bed is a curved bowl, so it needs
## more than one quad to read as anything but a box.
const LAKE_SUBDIV := 8
## How hard the noise warps the shoreline. 0 would give a tidy rounded rectangle.
const LAKE_WARP := 0.75

static var _lake_noise: FastNoiseLite = null


static func _shore_noise() -> FastNoiseLite:
	if _lake_noise == null:
		_lake_noise = FastNoiseLite.new()
		_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		# Fractal: the low octave carves bays across a big lake, the high ones give
		# a lone cell's shore detail finer than the cell itself. A single octave at
		# lake scale barely changes within one cell, which left small ponds looking
		# like rounded squares.
		_lake_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_lake_noise.fractal_octaves = 3
		_lake_noise.frequency = 0.045
		_lake_noise.seed = 1337        # fixed, so a lake doesn't wobble on rebuild
	return _lake_noise


## A hand-placed lake, as a bowl dug into its own cell.
##
## The bed rises back to the rim exactly on the lake's outer boundary, so it meets
## the surrounding land flush with no wall and no gap, and neighbouring cells are
## left untouched (which is what lets a lake sit on a plateau or a peak). The
## visible shoreline is not the cell edge but the contour where the bed crosses
## the water surface — warped by noise, so it wanders instead of being a rectangle.
static func _add_lake_basin(st: SurfaceTool, faces: PackedVector3Array, terrain: Terrain, cell: Vector2i) -> void:
	var lv: int = terrain.lake_level(cell)
	var rim: float = lv * Constants.ELEVATION_STEP - Terrain.TRACK_CLEARANCE
	# Depth at each cell corner: 1 in open water, 0 where the shore reaches it.
	var d00: float = 1.0 if terrain.lake_corner_interior(cell.x, cell.y, lv) else 0.0
	var d10: float = 1.0 if terrain.lake_corner_interior(cell.x + 1, cell.y, lv) else 0.0
	var d01: float = 1.0 if terrain.lake_corner_interior(cell.x, cell.y + 1, lv) else 0.0
	var d11: float = 1.0 if terrain.lake_corner_interior(cell.x + 1, cell.y + 1, lv) else 0.0

	var n := LAKE_SUBDIV
	var pts: Array[Vector3] = []
	for iu in range(n + 1):
		for iv in range(n + 1):
			pts.append(_lake_point(cell, float(iu) / n, float(iv) / n, rim, d00, d10, d01, d11))
	for iu in range(n):
		for iv in range(n):
			var a: Vector3 = pts[iu * (n + 1) + iv]
			var b: Vector3 = pts[(iu + 1) * (n + 1) + iv]
			var c: Vector3 = pts[(iu + 1) * (n + 1) + iv + 1]
			var e: Vector3 = pts[iu * (n + 1) + iv + 1]
			_tri(st, faces, a, b, c, LAKE_BED)
			_tri(st, faces, a, c, e, LAKE_BED)


static func _lake_point(cell: Vector2i, u: float, v: float, rim: float,
		d00: float, d10: float, d01: float, d11: float) -> Vector3:
	var h: float = Constants.CELL_SIZE * 0.5
	var x: float = cell.x * Constants.CELL_SIZE - h + u * Constants.CELL_SIZE
	var z: float = cell.y * Constants.CELL_SIZE - h + v * Constants.CELL_SIZE

	# Bilinear over the corner depths. A cell edge depends only on its own two
	# corners, so two lake cells agree exactly along a shared edge and the surface
	# stays watertight — no seams, no walls.
	var bil: float = lerpf(lerpf(d00, d10, u), lerpf(d01, d11, u), v)
	# Radial cone: 1 at the cell's centre, 0 across its whole boundary (the corners
	# sit outside the radius and clamp away). This is what gives a lone cell a
	# round pond; the obvious tensor-product bubble is subtly square and read as
	# one. It vanishes on the edges, so shared edges stay watertight either way.
	var cone: float = clampf(1.0 - Vector2(u - 0.5, v - 0.5).length() / 0.5, 0.0, 1.0)
	var depth: float = maxf(bil, cone)
	# Warp with noise. MULTIPLYING is deliberate: it leaves depth==0 exactly zero,
	# so the shore still meets the land flush while the waterline wanders.
	depth = clampf(depth * (1.0 + LAKE_WARP * _shore_noise().get_noise_2d(x, z)), 0.0, 1.0)
	return Vector3(x, rim - Terrain.WATER_DEPTH * depth, z)


const NO_TRACK := -2147483648


static func _corner(terrain: Terrain, grid: TrackGrid, i: int, j: int) -> Vector3:
	var y: float
	var track_level := _track_corner_level(grid, i, j)
	if track_level != NO_TRACK:
		# Flatten to the track level (minus clearance) so the road sits flat on top.
		y = track_level * Constants.ELEVATION_STEP - Terrain.TRACK_CLEARANCE
	else:
		# Discrete terraced corner height: flat plateaus, equal-angle ramp bands.
		y = terrain.corner_height(i, j)
	return Vector3((i - 0.5) * Constants.CELL_SIZE, y, (j - 0.5) * Constants.CELL_SIZE)


## Highest track level any touching tile wants at corner (i, j), or NO_TRACK if
## no touching cell has a tile. Flat tiles want their level at every corner; ramp
## tiles want the low level on their low edge and +1 on their high edge, so the
## terrain slopes to match the ramp.
static func _track_corner_level(grid: TrackGrid, i: int, j: int) -> int:
	var best := NO_TRACK
	for c in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if grid.has_tile(c):
			best = maxi(best, _cell_corner_level(grid, c, i, j))
	return best


static func _cell_corner_level(grid: TrackGrid, cell: Vector2i, i: int, j: int) -> int:
	var placed: PlacedTile = grid.get_placed(cell)
	var def: TileDefinition = grid.get_def(cell)
	if def == null or def.category != TileDefinition.Category.RAMP or def.sockets.size() < 4:
		return placed.elevation_level

	# The ramp's high edge is the socket with the greatest (relative) elevation.
	var base_high := 0
	for k in range(1, 4):
		if def.sockets[k].elevation_level > def.sockets[base_high].elevation_level:
			base_high = k
	var high_dir := (base_high + placed.rotation) % 4

	# Which two edges of `cell` this corner sits on.
	var dir_ns := 0 if (j - cell.y) == 0 else 2  # N (0) or S (2)
	var dir_we := 3 if (i - cell.x) == 0 else 1  # W (3) or E (1)
	var on_high: bool = (dir_ns == high_dir) or (dir_we == high_dir)
	return placed.elevation_level + (1 if on_high else 0)


## Silt colour for a hand-placed lake's bed. Needed because those sit at any
## height, and the height ramp would otherwise paint a mountain-top lake bed the
## same grey as the peak around it.
const LAKE_BED := Color(0.38, 0.34, 0.26)
const NO_TINT := Color(0.0, 0.0, 0.0, 0.0)


static func _tri(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3,
		tint: Color = NO_TINT) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	for v in [a, b, c]:
		st.set_color(tint if tint.a > 0.0 else _height_color(v.y))
		st.set_normal(normal)
		st.add_vertex(v)
	faces.push_back(a); faces.push_back(b); faces.push_back(c)


## Ground colour by height. The grass band is deliberately wide: a map should read
## as countryside with bare rock only on real summits, rather than going sandy
## halfway up every hill.
##
## These are ALBEDO, not what you see: sun plus sky ambient lift the ground a long
## way, and the grass texture multiplies in on top. Values that look right here
## read as washed-out pastel in game, so the greens are set deep and saturated.
static func _height_color(y: float) -> Color:
	if y < -0.6:
		return Color(0.26, 0.22, 0.14)  # lake bed
	var t: float = clampf(y / (Constants.MAX_TERRAIN_LEVEL * Constants.ELEVATION_STEP), 0.0, 1.0)
	if t < 0.58:
		# Deep meadow green -> drier upland green. Covers plains and hills whole.
		return Color(0.07, 0.22, 0.06).lerp(Color(0.13, 0.26, 0.09), t / 0.58)
	if t < 0.82:
		return Color(0.13, 0.26, 0.09).lerp(Color(0.30, 0.28, 0.19), (t - 0.58) / 0.24)
	return Color(0.30, 0.28, 0.19).lerp(Color(0.60, 0.62, 0.66), (t - 0.82) / 0.18)


static var _ground_mat: StandardMaterial3D = null


## Cached: the terrain is rebuilt on every sculpt tick, and rebuilding the texture
## each time would stall the drag.
static func _terrain_material() -> StandardMaterial3D:
	if _ground_mat != null:
		return _ground_mat
	var mat := StandardMaterial3D.new()
	# The height ramp (vertex colours) owns the hue; the texture only modulates it,
	# so the ground has grain instead of reading as flat plastic.
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = ProcTexture.grass()
	# Triplanar, because the terrain mesh has no UVs — it is regenerated constantly
	# and unwrapping it would be wasted work. This derives them from world position.
	mat.uv1_triplanar = true
	var s: float = 1.0 / ProcTexture.GRASS_METERS
	mat.uv1_scale = Vector3(s, s, s)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_mat = mat
	return mat


static func _add_water(parent: Node3D, centers: Array[Vector3]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = Constants.CELL_SIZE * 0.5
	for c in centers:
		var a := c + Vector3(-h, 0, -h)
		var b := c + Vector3(h, 0, -h)
		var d := c + Vector3(-h, 0, h)
		var e := c + Vector3(h, 0, h)
		for v in [a, b, e, a, e, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.1
	mi.material_override = mat
	parent.add_child(mi)
