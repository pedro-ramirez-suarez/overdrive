class_name TileGeo
extends StaticBody3D
## Procedural geometry for a single track tile (SPEC.md §M3), on the `road`
## layer. Every kind is built as a swept road ribbon (ArrayMesh + trimesh
## collision) from a list of frames {pos, normal, lateral} in tile-local space.
##
## Tile-local space: origin is the cell centre; the cell spans x,z in [-4, 4]
## (one 8 m cell). Straight roads run along Z (N = -Z, S = +Z). Built at run
## time in _ready, so geometry appears when the scene is instanced/played.

## NOTE: append only. Each tile scene stores its kind as this enum's integer, so
## inserting one would silently repurpose every existing tile.
enum Kind {
	STRAIGHT, START, CURVE, RAMP, LOOP, CORKSCREW, JUMP, WIDE_CURVE, TUNNEL,
	BANKED_CURVE, CROSSROADS, OVERPASS, PIPE, HALF_PIPE, PIPE_ENTRY, HALF_PIPE_ENTRY,
	BANKED_STRAIGHT, BANKED_ENTRY, BANKED_EXIT,
}

const HALF_CELL: float = 4.0
## How far an overpass's piers stop below its deck, to keep their top faces from
## sitting coplanar with the road and z-fighting.
const PIER_GAP: float = 0.08

@export var kind: Kind = Kind.STRAIGHT
@export var road_width: float = 6.0
@export var segments: int = 48
## Number of cells the loop spans along its axis (its footprint length).
@export var cell_length: int = 1
## Loop height is 2 * loop_radius.
@export var loop_radius: float = 4.0
## Corkscrew helix radius (also half its roll height).
@export var corkscrew_radius: float = 2.0
## How high the corkscrew's roll is raised onto its lead-in/out ramps, so the
## banked road clears the ground instead of dipping under it.
@export var corkscrew_base: float = 1.2
## Vertical rise of a ramp across the tile (one elevation level).
@export var ramp_rise: float = 3.0
## Peak height of a jump ramp lip.
@export var jump_height: float = 4.5
## Segments used for the smooth ramp / jump profile.
@export var ramp_segments: int = 12
## Mirror along Z (turns a ramp-up into a ramp-down).
@export var flip_z: bool = false
## Tunnel: how far its shell stands clear of the road edge.
@export var tunnel_clearance: float = 0.8
## Tunnel: height of the vertical side walls before the arch takes over.
@export var tunnel_wall: float = 2.0
## Banked curve: peak roll, in radians, reached at the apex and eased to 0 at both
## ends so the tile still meets a flat straight square-on.
@export var bank_angle: float = 0.5
## Pipe / half-pipe: radius of the bore. At road_width * 0.5 the pipe's walls line
## up with the road's edges.
@export var pipe_radius: float = 3.0
## Pipe / half-pipe: points around a full turn of the section.
@export var pipe_segments: int = 20
## Overpass: how many elevation levels its upper deck clears the lower road by.
## MUST match TileLibrary's OVERPASS_LEVELS, which is what the sockets promise.
## Kept at one because a ramp climbs exactly one level.
@export var overpass_levels: int = 1
## Overpass: build the ground-level road under the deck? The spawner clears this
## when nothing joins underneath (TileLibrary.overpass_needs_lower), so a bridge
## carrying only its deck doesn't straddle a stub of road going nowhere. Set it
## before adding the tile to the tree — _ready is what builds the mesh.
@export var draw_lower: bool = true

const GEN_MESH := "GeneratedMesh"
const GEN_COLLISION := "GeneratedCollision"


func _ready() -> void:
	_build()


func _build() -> void:
	for child_name in [GEN_MESH, GEN_COLLISION]:
		var existing: Node = get_node_or_null(child_name)
		if existing != null:
			existing.free()

	var frames: Array[Dictionary] = _make_frames()
	var seg_count: int = frames.size() - 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()

	# Sweep each frame's cross-section into the next. For a flat road a section is
	# just its two edges, so this is the same single quad per segment as before;
	# a pipe returns an arc of points instead and the same loop tubes it.
	for i in range(seg_count):
		var s0: Array = _section(frames[i])
		var s1: Array = _section(frames[i + 1])
		for j in range(s0.size() - 1):
			var a: Dictionary = s0[j]
			var b: Dictionary = s0[j + 1]
			var c: Dictionary = s1[j + 1]
			var d: Dictionary = s1[j]
			_add_tri(st, faces, a.pos, b.pos, c.pos, a.normal, b.normal, c.normal)
			_add_tri(st, faces, a.pos, c.pos, d.pos, a.normal, c.normal, d.normal)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = GEN_MESH
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _road_material()
	add_child(mesh_instance)

	_add_markings(frames)

	# Extra geometry goes in before the collision is built, so it is solid too.
	match kind:
		Kind.TUNNEL: _add_tunnel_shell(faces)
		Kind.CROSSROADS: _add_cross_arms(faces)
		Kind.OVERPASS: _add_overpass_lower(faces)
		Kind.BANKED_CURVE, Kind.BANKED_STRAIGHT, Kind.BANKED_ENTRY, Kind.BANKED_EXIT:
			_add_bank_skirt(frames, faces)
		_: pass

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = GEN_COLLISION
	collision.shape = shape
	add_child(collision)

	if kind == Kind.START:
		_add_start_marker()


## The tunnel's shell: vertical side walls carried over by an arch, open at both
## ends so consecutive tunnel tiles chain into one bore. A single sheet, no
## thickness — the road material is cull-disabled, so it reads from inside and
## out. Its faces join the tile's collision, so you can't drive through a wall.
func _add_tunnel_shell(faces: PackedVector3Array) -> void:
	var half_w: float = road_width * 0.5 + tunnel_clearance

	# Cross-section, left jamb up over the arch and down the right jamb.
	var profile: Array[Vector2] = [Vector2(-half_w, 0.0), Vector2(-half_w, tunnel_wall)]
	var arc_steps := 16
	for i in range(arc_steps + 1):
		var a: float = lerpf(PI, 0.0, float(i) / float(arc_steps))
		profile.append(Vector2(half_w * cos(a), tunnel_wall + half_w * sin(a)))
	profile.append(Vector2(half_w, 0.0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The bore's rough centre, used only to aim each face's normal inward.
	var inside := Vector2(0.0, tunnel_wall)
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var edge: Vector2 = (p1 - p0).normalized()
		var n2 := Vector2(-edge.y, edge.x)
		if n2.dot(inside - (p0 + p1) * 0.5) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0.0)
		var a0 := Vector3(p0.x, p0.y, HALF_CELL)
		var b0 := Vector3(p1.x, p1.y, HALF_CELL)
		var b1 := Vector3(p1.x, p1.y, -HALF_CELL)
		var a1 := Vector3(p0.x, p0.y, -HALF_CELL)
		_add_tri(st, faces, a0, b0, b1, n, n, n)
		_add_tri(st, faces, a0, b1, a1, n, n, n)

	var mi := MeshInstance3D.new()
	mi.name = "TunnelShell"
	mi.mesh = st.commit()
	mi.material_override = _tunnel_material()
	add_child(mi)


## The crossroads' east-west arms. The north-south band already comes from the
## frames, so these are only the stubs either side of it — overlapping a second
## full band across the middle would z-fight with the first.
func _add_cross_arms(faces: PackedVector3Array) -> void:
	var hw: float = road_width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		var x0: float = hw * s
		var x1: float = HALF_CELL * s
		_add_tri(st, faces, Vector3(x0, 0, -hw), Vector3(x1, 0, -hw), Vector3(x1, 0, hw),
			Vector3.UP, Vector3.UP, Vector3.UP)
		_add_tri(st, faces, Vector3(x0, 0, -hw), Vector3(x1, 0, hw), Vector3(x0, 0, hw),
			Vector3.UP, Vector3.UP, Vector3.UP)
	_commit_extra(st, "CrossArms", _road_material())


## The overpass's ground-level road (crossing under the deck) and its piers.
func _add_overpass_lower(faces: PackedVector3Array) -> void:
	var hw: float = road_width * 0.5
	var deck: float = overpass_levels * Constants.ELEVATION_STEP

	# Only when something actually joins underneath — see `draw_lower`.
	if draw_lower:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_tri(st, faces, Vector3(-HALF_CELL, 0, -hw), Vector3(HALF_CELL, 0, -hw),
			Vector3(HALF_CELL, 0, hw), Vector3.UP, Vector3.UP, Vector3.UP)
		_add_tri(st, faces, Vector3(-HALF_CELL, 0, -hw), Vector3(HALF_CELL, 0, hw),
			Vector3(-HALF_CELL, 0, hw), Vector3.UP, Vector3.UP, Vector3.UP)
		_commit_extra(st, "OverpassLower", _road_material())

	# Piers, set outside the lower road's width so they can't be hit head-on, and
	# kept inside the cell so they don't intrude on the neighbouring tile.
	#
	# They stop just SHORT of the deck: run them to exactly deck height and their
	# top faces are coplanar with the road surface, which z-fights and flashes as
	# the camera moves. The shortfall is hidden under the deck.
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Piers collide on the WALL layer, not the tile's ROAD collision. The car body
	# no longer collides with ROAD (it floats on its wheel rays), so a pier left on
	# ROAD would be driven straight through; a real column you can hit belongs on
	# the wall layer with the fences.
	var pier_faces := PackedVector3Array()
	var pier_h: float = deck - PIER_GAP
	var pier_z: float = (hw + HALF_CELL) * 0.5
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			_add_box_solid(pst, pier_faces,
				Vector3((hw - 0.5) * sx, pier_h * 0.5, pier_z * sz),
				Vector3(0.9, pier_h, 0.9))
	_commit_extra(pst, "OverpassPiers", _tunnel_material())
	_add_wall_body("PierWalls", pier_faces)


## A solid on the WALL layer (so the car body collides with it) rather than the
## tile's own ROAD collision, which the body ignores.
func _add_wall_body(node_name: String, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Constants.WALL_BIT
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Fill under the banked curve's high side, so it reads as an embankment instead
## of a road hanging over a gap. Vanishes at both ends, where the bank is zero.
func _add_bank_skirt(frames: Array[Dictionary], faces: PackedVector3Array) -> void:
	var hw: float = road_width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(frames.size() - 1):
		var e0: Vector3 = frames[i].pos + (frames[i].lateral as Vector3) * hw
		var e1: Vector3 = frames[i + 1].pos + (frames[i + 1].lateral as Vector3) * hw
		if e0.y <= 0.02 and e1.y <= 0.02:
			continue
		var g0 := Vector3(e0.x, 0.0, e0.z)
		var g1 := Vector3(e1.x, 0.0, e1.z)
		var lat: Vector3 = frames[i].lateral
		var n := Vector3(lat.x, 0.0, lat.z).normalized()
		_add_tri(st, faces, e0, e1, g1, n, n, n)
		_add_tri(st, faces, e0, g1, g0, n, n, n)
	_commit_extra(st, "BankSkirt", _road_material())


## An axis-aligned solid box, into both the mesh and the collision.
func _add_box_solid(st: SurfaceTool, faces: PackedVector3Array, centre: Vector3, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	for axis in 3:
		for sgn in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c: Vector3 = centre + n * h[axis]
			# _add_tri re-winds against the normal, so corner order doesn't matter.
			_add_tri(st, faces, c - u - v, c + u - v, c + u + v, n, n, n)
			_add_tri(st, faces, c - u - v, c + u + v, c - u + v, n, n, n)


func _commit_extra(st: SurfaceTool, node_name: String, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _tunnel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.42, 0.46)
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _add_tri(st: SurfaceTool, faces: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	# Wind every triangle so its FRONT face agrees with the shading normal. Kinds
	# sweep their ribbon in different directions (the wide curve's arc runs the
	# opposite way to a straight's), which otherwise leaves some tiles wound
	# backwards: you then see their back face from above, the renderer flips the
	# normal to face down, and the road renders unlit/black. Godot's front face is
	# clockwise, so the right-hand cross must OPPOSE the shading normal.
	if (b - a).cross(c - a).dot(na) > 0.0:
		var tmp_v: Vector3 = b
		b = c
		c = tmp_v
		var tmp_n: Vector3 = nb
		nb = nc
		nc = tmp_n
	st.set_normal(na); st.add_vertex(a)
	st.set_normal(nb); st.add_vertex(b)
	st.set_normal(nc); st.add_vertex(c)
	faces.push_back(a); faces.push_back(b); faces.push_back(c)


## The road's cross-section at `frame`: points across the band, each with its
## surface normal. A flat road is just the two edges — which is exactly what every
## tile did before this existed. Pipes return an arc instead, which is what lets
## the same sweep loop produce a bore the car can ride around.
func _section(f: Dictionary) -> Array:
	var pos: Vector3 = f.pos
	var nrm: Vector3 = f.normal
	var lat: Vector3 = f.lateral
	var half_w: float = road_width * 0.5
	if not is_pipe_kind():
		return [
			{"pos": pos + lat * half_w, "normal": nrm},
			{"pos": pos - lat * half_w, "normal": nrm},
		]

	# `morph` blends the flat band into the bore: 0 is exactly a straight's section,
	# 1 the full pipe. The entry tiles ramp it across their length, which is what
	# lets a flat road meet a pipe. Without it the two only touch along the single
	# centreline — the pipe's section is already 3 m up by the road's edge — which
	# reads as the road being severed.
	var morph: float = f.get("morph", 1.0)
	var full: bool = kind == Kind.PIPE or kind == Kind.PIPE_ENTRY
	var sweep: float = PI if full else PI * 0.5
	var steps: int = maxi(4, pipe_segments if full else pipe_segments / 2)
	# The bore's axis sits one radius above the roadway, so the pipe's floor lands
	# exactly on the road's centreline.
	var axis: Vector3 = pos + nrm * pipe_radius

	var pts: Array[Vector3] = []
	for i in range(steps + 1):
		var u: float = float(i) / float(steps)
		var phi: float = lerpf(-sweep, sweep, u)
		# phi = 0 is the floor; +/-PI/2 the walls; +/-PI the crown.
		var arc: Vector3 = axis + (lat * sin(phi) - nrm * cos(phi)) * pipe_radius
		var flat: Vector3 = pos + lat * lerpf(-half_w, half_w, u)
		pts.append(flat.lerp(arc, morph))

	# Normals are taken from the section's own shape rather than lerped from the
	# arc's: at the crown the bore faces exactly opposite the flat road, so lerping
	# would pass through zero and the surface would go black mid-morph.
	var fwd: Vector3 = nrm.cross(lat)
	var out: Array = []
	for i in range(pts.size()):
		var across: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var n: Vector3 = across.cross(fwd)
		out.append({"pos": pts[i], "normal": nrm if n.length_squared() < 0.000001 else n.normalized()})
	return out


func is_pipe_kind() -> bool:
	return kind == Kind.PIPE or kind == Kind.HALF_PIPE \
		or kind == Kind.PIPE_ENTRY or kind == Kind.HALF_PIPE_ENTRY


## A road frame rolled by `beta` about the direction of travel, tipping the surface
## toward -`lat` so the +`lat` edge is the high one.
##
## The roadway lifts as it rolls (by half a road width times sin), which keeps the
## LOW edge on the ground rather than buried in it — so a banked piece sits on the
## terrain instead of half inside it.
# --- Painted markings -------------------------------------------------------

const MARK_WHITE := Color(0.90, 0.90, 0.88)
const MARK_RED := Color(0.82, 0.16, 0.13)
## Lift above the road, so the paint sits on top without z-fighting.
const MARK_RAISE := 0.03
## Marking geometry, in meters.
const CENTRE_WIDTH := 0.16
const CENTRE_DASH := 1.6      # dash length; same-length gap follows
const KERB_WIDTH := 0.5
const KERB_INSET := 0.32      # from the road edge to the kerb's outer side
const KERB_BLOCK := 1.0       # length of one red or white kerb block


## Paint the lane markings the reference has: a dashed white centre line and a
## red/white kerb down each edge. Built along the SAME swept frames as the road,
## so it follows curves, ramps, loops and banks for free — no per-kind code.
##
## Skipped on pipes: their cross-section is a bore, not a flat lane, so edge kerbs
## and a centreline have nowhere sensible to sit.
func _add_markings(frames: Array[Dictionary]) -> void:
	if is_pipe_kind():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w: float = road_width * 0.5
	var kerb_offset: float = half_w - KERB_INSET - KERB_WIDTH * 0.5

	# Pattern runs on arc length from the tile's entry, so dashes and kerb blocks
	# are evenly spaced regardless of how finely a kind subdivides its frames.
	var s := 0.0
	for i in range(frames.size() - 1):
		var f0: Dictionary = frames[i]
		var f1: Dictionary = frames[i + 1]
		var seg: float = (f1.pos as Vector3).distance_to(f0.pos)
		# Resample: a straight is one 8 m frame, but the dashes must repeat within
		# it, so step along at a fixed spacing rather than per frame.
		var steps: int = maxi(1, ceili(seg / 0.4))
		for k in range(steps):
			var a: Dictionary = _lerp_frame(f0, f1, float(k) / steps)
			var b: Dictionary = _lerp_frame(f0, f1, float(k + 1) / steps)
			var mid: float = s + seg * (float(k) + 0.5) / float(steps)
			if fmod(mid, CENTRE_DASH * 2.0) < CENTRE_DASH:
				_mark_strip(st, a, b, 0.0, CENTRE_WIDTH, MARK_WHITE)
			var kerb: Color = MARK_RED if int(floor(mid / KERB_BLOCK)) % 2 == 0 else MARK_WHITE
			_mark_strip(st, a, b, kerb_offset, KERB_WIDTH, kerb)
			_mark_strip(st, a, b, -kerb_offset, KERB_WIDTH, kerb)
		s += seg

	var mi := MeshInstance3D.new()
	mi.name = "Markings"
	mi.mesh = st.commit()
	mi.material_override = _marking_material()
	add_child(mi)


func _lerp_frame(f0: Dictionary, f1: Dictionary, t: float) -> Dictionary:
	return {
		"pos": (f0.pos as Vector3).lerp(f1.pos, t),
		"normal": (f0.normal as Vector3).lerp(f1.normal, t).normalized(),
		"lateral": (f0.lateral as Vector3).lerp(f1.lateral, t).normalized(),
	}


## One quad of paint from cross-section `a` to `b`, centred `offset` meters off the
## road centreline and `width` wide, laid on the surface.
func _mark_strip(st: SurfaceTool, a: Dictionary, b: Dictionary, offset: float, width: float, col: Color) -> void:
	var ac: Vector3 = a.pos + a.normal * MARK_RAISE + a.lateral * offset
	var bc: Vector3 = b.pos + b.normal * MARK_RAISE + b.lateral * offset
	var aw: Vector3 = a.lateral * (width * 0.5)
	var bw: Vector3 = b.lateral * (width * 0.5)
	_mark_tri(st, ac - aw, ac + aw, bc + bw, a.normal, col)
	_mark_tri(st, ac - aw, bc + bw, bc - bw, a.normal, col)


func _mark_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Same winding rule as the road (front face agrees with the shading normal).
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static var _mark_mat: StandardMaterial3D = null


func _marking_material() -> StandardMaterial3D:
	if _mark_mat != null:
		return _mark_mat
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_mat = mat
	return mat


static func _smoothstep(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _banked_frame(pos: Vector3, lat: Vector3, beta: float) -> Dictionary:
	var hw: float = road_width * 0.5
	return {
		"pos": pos + Vector3.UP * (hw * sin(beta)),
		"normal": Vector3.UP * cos(beta) - lat * sin(beta),
		"lateral": lat * cos(beta) + Vector3.UP * sin(beta),
	}


func _make_frames() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	match kind:
		Kind.STRAIGHT, Kind.START, Kind.TUNNEL, Kind.CROSSROADS, Kind.PIPE, Kind.HALF_PIPE:
			# All of these run straight down the tile. What differs is the section
			# (pipes) or the extra geometry (tunnel shell, crossroads arms).
			for i in range(2):
				var z: float = HALF_CELL - 2.0 * HALF_CELL * float(i)
				frames.append({"pos": Vector3(0, 0, z), "normal": Vector3.UP, "lateral": Vector3.RIGHT})
		Kind.CURVE:
			# Quarter turn joining the N (-Z) and E (+X) edges; centre at (4,-4).
			for i in range(segments + 1):
				var a: float = lerpf(PI, PI / 2.0, float(i) / float(segments))
				var x: float = HALF_CELL + HALF_CELL * cos(a)
				var z: float = -HALF_CELL + HALF_CELL * sin(a)
				frames.append({
					"pos": Vector3(x, 0, z),
					"normal": Vector3.UP,
					"lateral": Vector3(cos(a), 0, sin(a)),
				})
		Kind.PIPE_ENTRY, Kind.HALF_PIPE_ENTRY:
			# Flat at the south edge, full bore at the north — the shape that joins a
			# straight to a pipe. Rotate it 180 degrees for the exit; the sockets are
			# symmetric, so one tile serves both ends.
			for i in range(segments + 1):
				var t: float = float(i) / float(segments)
				frames.append({
					"pos": Vector3(0.0, 0.0, HALF_CELL - 2.0 * HALF_CELL * t),
					"normal": Vector3.UP,
					"lateral": Vector3.RIGHT,
					"morph": t * t * (3.0 - 2.0 * t),  # smoothstep: flat where it meets the road
				})
		Kind.OVERPASS:
			# The upper deck, running N-S. The lower road crosses under it E-W and is
			# added separately. One tile carrying both is what lets a track cross over
			# itself without the grid having to stack two tiles in a cell.
			for i in range(2):
				var z: float = HALF_CELL - 2.0 * HALF_CELL * float(i)
				frames.append({
					"pos": Vector3(0.0, overpass_levels * Constants.ELEVATION_STEP, z),
					"normal": Vector3.UP,
					"lateral": Vector3.RIGHT,
				})
		Kind.BANKED_CURVE:
			# A long 90-degree sweep across a 3x3 block (radius 2.5 cells), rolled
			# outward so speed can actually be carried through it. Banking a tight
			# one-cell corner is pointless: the car has to scrub off most of its speed
			# to make the corner at all, and the bank never comes into play.
			#
			# Same arc convention as WIDE_CURVE — S edge of the anchor cell round to
			# the E edge of the far cell, centred on the block's NE corner.
			#
			# The bank is CONSTANT the whole way round, entry included: the transition
			# to and from flat road is its own piece (BANKED_ENTRY), so banked sections
			# chain with banked straights instead of every curve paying for a run-in it
			# may not need.
			var bank_radius: float = 2.5 * Constants.CELL_SIZE
			for i in range(segments + 1):
				var t: float = float(i) / float(segments)
				var theta: float = lerpf(PI, 1.5 * PI, t)
				frames.append(_banked_frame(
					Vector3(bank_radius + bank_radius * cos(theta), 0.0,
						HALF_CELL + bank_radius * sin(theta)),
					Vector3(cos(theta), 0.0, sin(theta)),  # radial, away from the centre
					bank_angle))
		Kind.BANKED_STRAIGHT, Kind.BANKED_ENTRY, Kind.BANKED_EXIT:
			# A straight rolled about its own length. BANKED_STRAIGHT holds the bank;
			# ENTRY eases it up from flat at the S edge, EXIT eases it back down to flat
			# at the N edge, so a flat road can meet a banked one at either end.
			#
			# ENTRY and EXIT are MIRRORS, not rotations of each other. Turning the entry
			# 180 degrees does swap which end is flat — but it also swaps which side is
			# high, because the roll turns with the tile. The exit would then bank the
			# opposite way to the section it is leaving, and only join on one hand. A
			# mirror is not a rotation, so it has to be its own piece.
			#
			# Which way a piece leans IS just its rotation: a half-turn puts the high
			# side on the other hand, so the four rotations bank to every direction.
			for i in range(segments + 1):
				var t: float = float(i) / float(segments)
				var beta: float = bank_angle
				if kind == Kind.BANKED_ENTRY:
					beta = bank_angle * _smoothstep(t)
				elif kind == Kind.BANKED_EXIT:
					beta = bank_angle * _smoothstep(1.0 - t)
				frames.append(_banked_frame(
					Vector3(0.0, 0.0, HALF_CELL - 2.0 * HALF_CELL * t), Vector3.RIGHT, beta))
		Kind.RAMP:
			# Straight, constant-angle slope from S (+Z, level 0) to N (-Z,
			# +ramp_rise) — matches the terrain's linear ramp band exactly.
			var ramp_normal: Vector3 = Vector3(0.0, 2.0 * HALF_CELL, ramp_rise).normalized()
			for i in range(2):
				var t: float = float(i)
				var z: float = HALF_CELL - 2.0 * HALF_CELL * t
				var pos: Vector3 = Vector3(0.0, ramp_rise * t, z)
				var n: Vector3 = ramp_normal
				if flip_z:
					pos.z = -pos.z
					n = Vector3(n.x, n.y, -n.z)
				frames.append({"pos": pos, "normal": n, "lateral": Vector3.RIGHT})
		Kind.JUMP:
			# Rises from S (level 0) to an upward-angled lip at N for launching.
			for i in range(ramp_segments + 1):
				var t: float = float(i) / float(ramp_segments)
				var z: float = HALF_CELL - 2.0 * HALF_CELL * t
				var y: float = jump_height * pow(t, 1.6)
				var dydt: float = jump_height * 1.6 * pow(maxf(t, 0.001), 0.6)
				frames.append({
					"pos": Vector3(0.0, y, z),
					"normal": Vector3(0.0, 2.0 * HALF_CELL, dydt).normalized(),
					"lateral": Vector3.RIGHT,
				})
		Kind.LOOP:
			# A round vertical circle (in the Y/Z plane) that drifts one cell
			# sideways, so it enters in one column and exits in the NEXT column —
			# entry and exit no longer overlap. Flat lead-in (column 0, S edge) and
			# lead-out (column 1, N edge) give it a clear entrance and exit.
			# Footprint is 2x2 (see TileLibrary).
			var drift: float = Constants.CELL_SIZE  # one column east
			var z_circle: float = -HALF_CELL
			frames.append({"pos": Vector3(0, 0, HALF_CELL), "normal": Vector3.UP, "lateral": Vector3.RIGHT})
			frames.append({"pos": Vector3(0, 0, z_circle), "normal": Vector3.UP, "lateral": Vector3.RIGHT})
			for i in range(1, segments + 1):
				var t: float = float(i) / float(segments)
				var a: float = TAU * t
				# X x tangent gives the (perpendicular) surface normal.
				var n := Vector3(0.0, loop_radius * cos(a), loop_radius * sin(a)).normalized()
				frames.append({
					"pos": Vector3(drift * t, loop_radius * (1.0 - cos(a)), z_circle - loop_radius * sin(a)),
					"normal": n,
					"lateral": Vector3.RIGHT,
				})
			frames.append({"pos": Vector3(drift, 0, z_circle - 2.0 * HALF_CELL), "normal": Vector3.UP, "lateral": Vector3.RIGHT})
		Kind.WIDE_CURVE:
			# Big 90-degree arc across a 2x2 block: S edge of the anchor cell to the
			# E edge of the far cell (centre at the block's NE corner, radius 1.5 cells).
			var arc_radius: float = 1.5 * Constants.CELL_SIZE
			for i in range(segments + 1):
				var theta: float = lerpf(PI, 1.5 * PI, float(i) / float(segments))
				frames.append({
					"pos": Vector3(arc_radius + arc_radius * cos(theta), 0.0, HALF_CELL + arc_radius * sin(theta)),
					"normal": Vector3.UP,
					"lateral": Vector3(cos(theta), 0.0, sin(theta)),
				})
		Kind.CORKSCREW:
			# A barrel roll built from the loop's circle turned onto the travel axis.
			# The road spirals once around while advancing S -> N over `cell_length`
			# cells, centred on the middle column of a 3-wide footprint so it runs
			# dead straight (the road enters and exits on the same column). The roll
			# swings symmetrically into the flanking columns.
			#
			# The roll is raised onto a low ramp at each end rather than banked at
			# ground level: banking a road while its centre sits at y=0 sinks the
			# down-slope edge underground, and lifting only that edge leaves a twisted,
			# hard-to-drive lead-in. Instead the ends stay FLAT (climbing gently to
			# `corkscrew_base`), and the whole 360 roll happens up in the air where
			# every edge clears the ground. That also makes the piece taller.
			var span: float = float(cell_length) * 2.0 * HALF_CELL
			var centre_x: float = 2.0 * HALF_CELL  # middle column of the 3-wide plot
			const RAMP := 0.12   # where the 360 roll begins / ends along the length
			# The base ramps up over a much LONGER span than the roll's onset, so it is
			# still rising as the roll starts lifting the road. If the base instead
			# levelled off before the roll began, the lead-in would crest a convex bump;
			# overlapping them keeps the climb monotonic, and stretching the base ramp
			# right out makes the lift so gradual it barely reads as a rise at all.
			const BRAMP := 0.44
			# Pass 1: positions (on the raised helix) and surface normals.
			var cpos: Array[Vector3] = []
			var cnorm: Array[Vector3] = []
			for i in range(segments + 1):
				var t: float = float(i) / float(segments)
				# Roll only across the middle; the ends stay unrolled (a = 0, flat).
				# smootherstep (C2: zero 1st AND 2nd derivative at the ends) is used for
				# both the roll and the base, so not just the slope but the CURVATURE is
				# continuous through every junction — that is what takes the last of the
				# roughness out of the lead-in and lead-out.
				var u: float = clampf((t - RAMP) / (1.0 - 2.0 * RAMP), 0.0, 1.0)
				var roll: float = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
				var a: float = TAU * roll
				# Base height: climb to `corkscrew_base`, hold it under the roll, descend
				# over the lead-out — so the roll is airborne and its edges clear ground.
				var b: float = minf(clampf(t / BRAMP, 0.0, 1.0), clampf((1.0 - t) / BRAMP, 0.0, 1.0))
				var base: float = corkscrew_base * (b * b * b * (b * (b * 6.0 - 15.0) + 10.0))
				cpos.append(Vector3(
					centre_x + corkscrew_radius * sin(a),
					base + corkscrew_radius * (1.0 - cos(a)),
					HALF_CELL - span * t))
				cnorm.append(Vector3(-sin(a), cos(a), 0.0))
			# Pass 2: forward from the actual path, lateral = forward x normal.
			for i in range(segments + 1):
				var f: Vector3
				if i == 0:
					f = cpos[1] - cpos[0]
				elif i == segments:
					f = cpos[i] - cpos[i - 1]
				else:
					f = cpos[i + 1] - cpos[i - 1]
				frames.append({
					"pos": cpos[i],
					"normal": cnorm[i],
					"lateral": f.normalized().cross(cnorm[i]).normalized(),
				})
	return frames


func _add_start_marker() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(road_width, 0.06, 0.5)
	mi.mesh = box
	mi.position = Vector3(0, 0.05, HALF_CELL - 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.9, 0.9)
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	add_child(mi)


static var _road_mat: StandardMaterial3D = null
static var _stunt_mat: StandardMaterial3D = null


## Cached per kind: every tile asks for this, and a fresh material each time would
## be hundreds of copies of the same thing on a big track.
func _road_material() -> StandardMaterial3D:
	var stunt := is_stunt_kind()
	if stunt and _stunt_mat != null:
		return _stunt_mat
	if not stunt and _road_mat != null:
		return _road_mat

	var mat := StandardMaterial3D.new()
	# Slightly lighter than the flat colours these replace: the asphalt texture
	# multiplies in at 0.74..1.0, which would otherwise darken the road overall.
	mat.albedo_color = Color(0.30, 0.31, 0.36) if not stunt else Color(0.34, 0.30, 0.41)
	mat.albedo_texture = ProcTexture.asphalt()
	# Triplanar like the terrain, and for the same reason — no UVs on these meshes.
	# It also means a loop or a pipe is paved just like a straight, whatever way its
	# surface happens to face.
	mat.uv1_triplanar = true
	var s: float = 1.0 / ProcTexture.ROAD_METERS
	mat.uv1_scale = Vector3(s, s, s)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if stunt:
		_stunt_mat = mat
	else:
		_road_mat = mat
	return mat


func is_stunt_kind() -> bool:
	return kind == Kind.LOOP or kind == Kind.CORKSCREW or kind == Kind.JUMP
