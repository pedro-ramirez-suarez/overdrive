class_name CarBody
extends Node3D
## Procedural low-poly car bodies (SPEC.md §2). All silhouettes are ORIGINAL
## look-alikes — evocative proportions only, invented names, no real-marque
## geometry, badges, or trade dress. Several body styles are available; the
## profile's `body_style` picks one.
##
## Built at run time from two lofted side profiles (lower body + greenhouse) plus
## wheels, round headlights and a tail light bar. Purely visual.

## Wheel-contact height in local space (before the parent's 0.6 down-scale). The
## wheel radius is added to this to seat the tyres on the road.
const GROUND_LOCAL := -0.42

## Wheel-contact height for auto-fitted imported models, in CarBody local space
## (CarBody is unscaled on that path). Matches the chassis ride height.
const MODEL_GROUND := -0.265

## When set (e.g. a menu preview), this profile is used instead of the parent
## car's — lets CarBody render a car outside a physics chassis.
@export var preview_profile: CarProfile
@export var body_color: Color = Color(0.80, 0.10, 0.12)


func _ready() -> void:
	var profile: CarProfile = preview_profile
	if profile == null:
		var car := get_parent() as ArcadeCar
		profile = car.profile if car != null else null

	if profile != null and profile.model_scene != null:
		scale = Vector3.ONE
		var model: Node3D = profile.model_scene.instantiate()
		if profile.model_fit_width > 0.0 or profile.model_fit_length > 0.0:
			# Fit via a holder so the model keeps its own imported transform.
			var holder := Node3D.new()
			holder.name = "ModelFit"
			add_child(holder)
			holder.add_child(model)
			var by_width: bool = profile.model_fit_width > 0.0
			var target: float = profile.model_fit_width if by_width else profile.model_fit_length
			_fit_model(holder, model, target, by_width, profile.model_yaw)
			_seat_model(holder)
		else:
			model.scale = Vector3.ONE * profile.model_scale
			model.position = Vector3(0.0, profile.model_y_offset, 0.0)
			model.rotation = Vector3(0.0, profile.model_yaw, 0.0)
			add_child(model)
		return

	scale = Vector3(0.6, 0.6, 0.6)  # procedural bodies are authored at full size
	var color: Color = profile.body_color if profile != null else body_color
	var style: String = profile.body_style if profile != null else "coupe"
	_build(_style_data(style), color)


# --- Imported-model auto-fit ------------------------------------------------

## Scale/rotate/centre `holder` so `model` ends up `target` meters across — its
## width when `by_width`, else its length — centred on the chassis, with its
## lowest point (the tyres) on the road. The other dimensions follow from the
## model's own proportions.
func _fit_model(holder: Node3D, model: Node3D, target: float, by_width: bool, yaw: float) -> void:
	# Bounds from the actual VERTICES, not mesh.get_aabb(): some of these models
	# carry a stored AABB looser than their geometry, which seated them a few cm
	# high so the car floated. Vertex bounds are tight, so every car sits level.
	var raw: AABB = _vertex_bounds(model, model.transform)
	if raw.size == Vector3.ZERO:
		push_warning("CarBody: model has no meshes; cannot auto-fit.")
		return

	# Yaw first: it decides which axis ends up being the car's length vs width.
	var box: AABB = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * raw
	var span: float = box.size.x if by_width else box.size.z
	if span <= 0.001:
		push_warning("CarBody: model is degenerate; cannot auto-fit.")
		return

	# Uniform scale commutes with the yaw, so the fitted bounds are just s * box.
	var s: float = target / span
	holder.rotation = Vector3(0.0, yaw, 0.0)
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(
		-(box.position.x + box.size.x * 0.5) * s,
		MODEL_GROUND - box.position.y * s,
		-(box.position.z + box.size.z * 0.5) * s)


## Nudge the already-fitted model so its true lowest vertex rests exactly on
## MODEL_GROUND. The fit math should already do this, but a few models seat a
## couple of centimetres high, which reads as the car floating; measuring the
## real geometry in place and correcting is immune to whatever caused that.
func _seat_model(holder: Node3D) -> void:
	var inv: Transform3D = global_transform.affine_inverse()
	var lo := 1e9
	for n in _mesh_descendants(holder):
		var local: Transform3D = inv * n.global_transform
		for v in (n.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = minf(lo, (local * v).y)
	if lo < 1e8:
		holder.position.y += MODEL_GROUND - lo


func _mesh_descendants(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(mi)
	for c in n.get_children():
		out.append_array(_mesh_descendants(c))
	return out


## Tight AABB of every vertex under `n`, in the space `xf` is relative to.
func _vertex_bounds(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var started := false
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in range(mi.mesh.get_surface_count()):
			for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = xf * v
				if not started:
					box = AABB(p, Vector3.ZERO)
					started = true
				else:
					box = box.expand(p)
	for c in n.get_children():
		var child_xf: Transform3D = xf
		var c3 := c as Node3D
		if c3 != null:
			child_xf = xf * c3.transform
		var sub := _vertex_bounds(c, child_xf)
		if sub.size != Vector3.ZERO or sub.position != Vector3.ZERO:
			box = box.merge(sub) if started else sub
			started = true
	return box


func _build(d: Dictionary, color: Color) -> void:
	_add_mesh("Body", _extrude(d.body, d.body_w), _body_material(color))
	_add_mesh("Cabin", _extrude(d.cabin, d.cabin_w), _glass_material())

	var wheel_mat := _wheel_material()
	var wy: float = GROUND_LOCAL + float(d.wheel_r)
	for pos in [
			Vector3(d.wheel_x, wy, -d.wheel_z), Vector3(-d.wheel_x, wy, -d.wheel_z),
			Vector3(d.wheel_x, wy, d.wheel_z), Vector3(-d.wheel_x, wy, d.wheel_z)]:
		_add_wheel(pos, d.wheel_r, wheel_mat)

	# Lights positioned from the body extents.
	var front_z: float = 999.0
	var rear_z: float = -999.0
	var bottom_y: float = 999.0
	for p in d.body:
		front_z = minf(front_z, p.x)
		rear_z = maxf(rear_z, p.x)
		bottom_y = minf(bottom_y, p.y)

	# Dark undertray, so the belly reads as a chassis (not a bright slab) when the
	# car is inverted at the top of a loop.
	var under := StandardMaterial3D.new()
	under.albedo_color = Color(0.10, 0.10, 0.12)
	under.roughness = 0.9
	_add_box("Underbody", Vector3(float(d.body_w) * 0.94, 0.05, (rear_z - front_z) * 0.94),
		Vector3(0.0, bottom_y + 0.015, (front_z + rear_z) * 0.5), under)
	var head_mat := _emissive_material(Color(1.0, 0.97, 0.85), 2.0)
	_add_disc(Vector3(d.body_w * 0.33, 0.05, front_z + 0.1), 0.09, head_mat)
	_add_disc(Vector3(-d.body_w * 0.33, 0.05, front_z + 0.1), 0.09, head_mat)
	_add_box("TailLight", Vector3(d.body_w * 0.72, 0.08, 0.05), Vector3(0.0, 0.06, rear_z - 0.03),
		_emissive_material(Color(0.9, 0.05, 0.05), 1.2))


# --- Styles (all original silhouettes) --------------------------------------
# Profiles are Vector2(z, y): z = length (front = -Z), y = height. Bottoms sit
# near -0.34 so the body hugs the wheels.

func _style_data(style: String) -> Dictionary:
	match style:
		"gt":
			return {
				"body": [Vector2(-1.6, -0.14), Vector2(-1.15, 0.08), Vector2(-0.3, 0.12), Vector2(0.55, 0.14),
					Vector2(1.2, 0.17), Vector2(1.6, 0.13), Vector2(1.6, -0.34), Vector2(-1.6, -0.34)],
				"cabin": [Vector2(-0.35, 0.14), Vector2(0.1, 0.44), Vector2(0.75, 0.45), Vector2(1.35, 0.18)],
				"body_w": 1.6, "cabin_w": 1.08, "wheel_x": 0.72, "wheel_z": 1.12, "wheel_r": 0.28,
			}
		"drift":
			return {
				"body": [Vector2(-1.45, -0.18), Vector2(-1.05, 0.02), Vector2(-0.25, 0.08), Vector2(0.45, 0.11),
					Vector2(1.05, 0.13), Vector2(1.4, 0.08), Vector2(1.45, -0.02), Vector2(1.45, -0.34), Vector2(-1.45, -0.34)],
				"cabin": [Vector2(-0.3, 0.08), Vector2(0.1, 0.33), Vector2(0.45, 0.34), Vector2(1.2, 0.11)],
				"body_w": 1.4, "cabin_w": 0.94, "wheel_x": 0.66, "wheel_z": 1.02, "wheel_r": 0.27,
			}
		"muscle":
			return {
				"body": [Vector2(-1.65, 0.02), Vector2(-1.55, 0.12), Vector2(-0.5, 0.13), Vector2(0.3, 0.14),
					Vector2(1.35, 0.16), Vector2(1.65, 0.11), Vector2(1.65, -0.3), Vector2(-1.65, -0.3)],
				"cabin": [Vector2(-0.32, 0.14), Vector2(0.02, 0.48), Vector2(0.78, 0.49), Vector2(1.12, 0.16)],
				"body_w": 1.62, "cabin_w": 1.18, "wheel_x": 0.74, "wheel_z": 1.16, "wheel_r": 0.3,
			}
		"super":
			return {
				"body": [Vector2(-1.65, -0.22), Vector2(-1.2, -0.04), Vector2(-0.55, 0.04), Vector2(0.1, 0.1),
					Vector2(0.85, 0.15), Vector2(1.35, 0.12), Vector2(1.55, 0.0), Vector2(1.55, -0.34), Vector2(-1.65, -0.34)],
				"cabin": [Vector2(-0.55, 0.04), Vector2(-0.1, 0.28), Vector2(0.28, 0.29), Vector2(0.9, 0.14)],
				"body_w": 1.58, "cabin_w": 0.88, "wheel_x": 0.74, "wheel_z": 1.1, "wheel_r": 0.29,
			}
		_:  # "coupe"
			return {
				"body": [Vector2(-1.5, -0.16), Vector2(-1.1, 0.06), Vector2(-0.35, 0.1), Vector2(0.4, 0.12),
					Vector2(1.05, 0.14), Vector2(1.4, 0.1), Vector2(1.5, -0.06), Vector2(1.5, -0.36), Vector2(-1.5, -0.36)],
				"cabin": [Vector2(-0.4, 0.12), Vector2(0.02, 0.38), Vector2(0.42, 0.4), Vector2(1.15, 0.14)],
				"body_w": 1.45, "cabin_w": 0.98, "wheel_x": 0.66, "wheel_z": 1.05, "wheel_r": 0.27,
			}


# --- Mesh assembly ----------------------------------------------------------

func _add_mesh(node_name: String, mesh: ArrayMesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _add_wheel(pos: Vector3, radius: float, mat: Material) -> void:
	var wheel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.22
	cyl.radial_segments = 14
	wheel.mesh = cyl
	wheel.material_override = mat
	wheel.rotation = Vector3(0.0, 0.0, PI / 2.0)  # lay the cylinder along X
	wheel.position = pos
	add_child(wheel)


func _add_disc(pos: Vector3, radius: float, mat: Material) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.06
	cyl.radial_segments = 12
	disc.mesh = cyl
	disc.material_override = mat
	disc.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # face forward (-Z)
	disc.position = pos
	add_child(disc)


func _add_box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


## Extrude a closed 2D profile (Vector2(z, y)) into a solid of `width` along X.
func _extrude(profile: Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w: float = width * 0.5
	var count: int = profile.size()

	var center := Vector3.ZERO
	for p in profile:
		center += Vector3(0.0, p.y, p.x)
	center /= float(count)

	var poly := PackedVector2Array(profile)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	for i in range(0, indices.size(), 3):
		var a: Vector2 = profile[indices[i]]
		var b: Vector2 = profile[indices[i + 1]]
		var c: Vector2 = profile[indices[i + 2]]
		_tri(st, Vector3(half_w, a.y, a.x), Vector3(half_w, b.y, b.x), Vector3(half_w, c.y, c.x), center)
		_tri(st, Vector3(-half_w, a.y, a.x), Vector3(-half_w, b.y, b.x), Vector3(-half_w, c.y, c.x), center)

	for i in range(count):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[(i + 1) % count]
		var l0 := Vector3(-half_w, p0.y, p0.x)
		var r0 := Vector3(half_w, p0.y, p0.x)
		var l1 := Vector3(-half_w, p1.y, p1.x)
		var r1 := Vector3(half_w, p1.y, p1.x)
		_tri(st, l0, r0, r1, center)
		_tri(st, l0, r1, l1, center)

	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - center) < 0.0:
		normal = -normal
	st.set_normal(normal); st.add_vertex(a)
	st.set_normal(normal); st.add_vertex(b)
	st.set_normal(normal); st.add_vertex(c)


# --- Materials --------------------------------------------------------------

func _body_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.35
	mat.roughness = 0.32
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.09)
	mat.metallic = 0.2
	mat.roughness = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _wheel_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.roughness = 0.85
	return mat


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
