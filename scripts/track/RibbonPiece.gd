class_name RibbonPiece
extends StaticBody3D
## Procedurally-built stunt geometry for M2 (SPEC.md §M2, task 2).
##
## Generates a road "ribbon" — a flat strip of road width swept along a
## parametric curve — as an ArrayMesh plus a matching trimesh collision shape,
## on the `road` physics layer (set on this node in the scene). Used to hand-
## build a vertical loop and a corkscrew before the M3 tile system exists.
##
## Built at runtime in _ready (not a @tool script), so the geometry appears when
## the scene is played, not in the editor viewport. Tune via the exported
## parameters and re-run.

enum Kind {
	LOOP,       ## Full 360° vertical loop in the local Y/Z plane; car enters at the origin driving -Z.
	CORKSCREW,  ## One 360° barrel roll advancing -Z over `length`; car enters at the origin.
}

@export var kind: Kind = Kind.LOOP
## Loop radius, or corkscrew helix radius, in meters.
@export var radius: float = 7.0
## Road width in meters (8 m = one grid cell, per §2).
@export var road_width: float = 8.0
## Forward advance of the corkscrew over its full roll, in meters. Unused by LOOP.
@export var length: float = 40.0
## Number of segments around the sweep. More = smoother.
@export var segments: int = 72

const GEN_MESH := "GeneratedMesh"
const GEN_COLLISION := "GeneratedCollision"


func _ready() -> void:
	_build()


func _build() -> void:
	# Clear any previously generated children (safe re-entry).
	for child_name in [GEN_MESH, GEN_COLLISION]:
		var existing: Node = get_node_or_null(child_name)
		if existing != null:
			existing.free()

	var frames: Array[Dictionary] = _make_frames()

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collision_faces := PackedVector3Array()
	var half_width: float = road_width * 0.5

	for i in range(segments):
		var f0: Dictionary = frames[i]
		var f1: Dictionary = frames[i + 1]
		var n0: Vector3 = f0.normal
		var n1: Vector3 = f1.normal

		var left0: Vector3 = f0.pos + f0.lateral * half_width
		var right0: Vector3 = f0.pos - f0.lateral * half_width
		var left1: Vector3 = f1.pos + f1.lateral * half_width
		var right1: Vector3 = f1.pos - f1.lateral * half_width

		var v: float = float(i) / float(segments)
		var v_next: float = float(i + 1) / float(segments)

		_add_tri(surface_tool, collision_faces,
			left0, right0, right1, n0, n0, n1,
			Vector2(0.0, v), Vector2(1.0, v), Vector2(1.0, v_next))
		_add_tri(surface_tool, collision_faces,
			left0, right1, left1, n0, n1, n1,
			Vector2(0.0, v), Vector2(1.0, v_next), Vector2(0.0, v_next))

	var mesh: ArrayMesh = surface_tool.commit()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = GEN_MESH
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material()
	add_child(mesh_instance)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision_faces)
	var collision := CollisionShape3D.new()
	collision.name = GEN_COLLISION
	collision.shape = shape
	add_child(collision)


func _add_tri(st: SurfaceTool, faces: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_normal(na); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(nb); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(nc); st.set_uv(uc); st.add_vertex(c)
	faces.push_back(a); faces.push_back(b); faces.push_back(c)


## Build the per-segment frames: centerline position, surface normal (points the
## way the car's up-axis should face), and lateral (road-width) direction. All in
## this node's local space, with the entry at the local origin.
func _make_frames() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for i in range(segments + 1):
		var s: float = float(i) / float(segments)
		match kind:
			Kind.LOOP:
				var a: float = TAU * s
				frames.append({
					"pos": Vector3(0.0, radius - radius * cos(a), -radius * sin(a)),
					"normal": Vector3(0.0, cos(a), sin(a)),
					"lateral": Vector3(1.0, 0.0, 0.0),
				})
			Kind.CORKSCREW:
				var r: float = TAU * s
				frames.append({
					"pos": Vector3(radius * sin(r), radius - radius * cos(r), -length * s),
					"normal": Vector3(-sin(r), cos(r), 0.0),
					"lateral": Vector3(cos(r), sin(r), 0.0),
				})
	return frames


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.30, 0.38)
	mat.roughness = 0.75
	# Double-sided so the road reads correctly regardless of triangle winding
	# (important on the underside of a loop).
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
