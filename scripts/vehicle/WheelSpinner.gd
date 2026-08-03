class_name WheelSpinner
extends Node
## Spins an imported model's wheel meshes with road speed (SPEC.md §M6 polish).
##
## Only used where it reads — the monster truck, whose tyres are huge and fully
## exposed. Purely visual: nothing here touches physics.
##
## The models bake each wheel's offset into its GEOMETRY rather than its node
## transform (every wheel node sits at the same position), so rotating the node
## would swing the wheel around the car's centre like a hammer throw. Each wheel is
## therefore re-pivoted first: an axle Node3D is placed at the wheel's own centre and
## the mesh is re-parented under it, shifted back by that centre. The mesh then sits
## exactly where it did, but turning the axle spins it about itself.

## Wheel meshes are matched by name — the packs name them "... wheel front left" etc.
const WHEEL_HINT := "wheel"

var _axles: Array[Node3D] = []
var _radius: float = 0.5
var _car: ArcadeCar


## Re-pivot every wheel mesh under `model` and start spinning them from `car`.
func setup(model: Node3D, car: ArcadeCar) -> void:
	_car = car
	for mesh in _wheel_meshes(model):
		var centre: Vector3 = mesh.mesh.get_aabb().get_center()
		var parent := mesh.get_parent()
		var axle := Node3D.new()
		axle.name = "%sAxle" % mesh.name
		axle.transform = mesh.transform.translated_local(centre)
		parent.add_child(axle)
		parent.remove_child(mesh)
		axle.add_child(mesh)
		mesh.transform = Transform3D(Basis(), -centre)
		_axles.append(axle)
		# Wheel radius from the mesh's own bounds: the tyre's larger vertical/forward
		# extent, halved. Scale-independent, so it survives the model auto-fit.
		var size: Vector3 = mesh.mesh.get_aabb().size
		_radius = maxf(_radius, maxf(size.y, size.z) * 0.5)


func _wheel_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null and mi.name.to_lower().contains(WHEEL_HINT):
		out.append(mi)
	for c in n.get_children():
		out.append_array(_wheel_meshes(c))
	return out


func _process(delta: float) -> void:
	if _car == null or _axles.is_empty():
		return
	# Roll rate from forward road speed: v / r radians per second, signed so the
	# wheels turn backwards in reverse. The model's own scale cancels out, since the
	# radius was measured in the same space the wheels are drawn in.
	var forward: Vector3 = -_car.global_transform.basis.z
	var speed: float = _car.linear_velocity.dot(forward)
	var spin: float = (speed / maxf(_radius_world(), 0.05)) * delta
	for axle in _axles:
		axle.rotate_x(spin)


## The wheel radius in WORLD meters — the mesh-space radius scaled by however much
## the auto-fit shrank the model, so the roll rate matches the ground it drives on.
func _radius_world() -> float:
	if _axles.is_empty():
		return _radius
	return _radius * _axles[0].global_transform.basis.get_scale().y
