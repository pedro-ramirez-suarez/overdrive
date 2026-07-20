class_name SkidMarks
extends MultiMeshInstance3D
## Persistent tyre marks laid on the road while the player's car drifts, hand-
## brakes or corners hard (improvements batch — "sense of speed").
##
## A MultiMesh of flat quads used as a ring buffer: each placement stamps two dark
## patches at the rear corners and advances the write head, so the oldest marks are
## overwritten once the buffer wraps. That caps the cost at a fixed instance count
## no matter how long the race runs, and needs no per-frame mesh rebuild.
##
## Added to the race root (NOT the car), so the marks stay on the tarmac where they
## were laid rather than riding along with the car.

## Quads in the ring. Two are used per placement, and placements are throttled by
## distance, so this covers a long stretch of road before it recycles.
const CAPACITY := 1200
## Minimum travel between placements, meters. Small enough to read as continuous.
const STEP := 0.35
## Rear axle position in the car's local frame, and half the track width.
const REAR_Z := 0.9
const HALF_WIDTH := 0.42
## Lateral slip (m/s) above which the tyres are considered to be scrubbing.
const SLIP_THRESHOLD := 3.5

var car: ArcadeCar

var _write: int = 0
var _last_pos: Vector3 = Vector3(1e9, 1e9, 1e9)


func _ready() -> void:
	# A PlaneMesh lies flat in the XZ plane (normal up) by default, so it hugs the
	# ground with no extra rotation.
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.34, STEP * 1.35)  # slightly longer than the step so marks overlap

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.05, 0.05, 0.06, 0.5)
	# Draw just above the road and don't write depth, so marks don't z-fight the
	# tarmac or clip each other.
	mat.no_depth_test = false
	mat.render_priority = -1
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = CAPACITY
	multimesh = mm
	# Park every instance out of sight until it is used.
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0))
	for i in range(CAPACITY):
		mm.set_instance_transform(i, hidden)


func _physics_process(_delta: float) -> void:
	if car == null or not car.grounded or not car.on_track:
		return
	var speed: float = car.linear_velocity.length()
	if speed < 4.0:
		return
	var lateral: float = absf(car.linear_velocity.dot(car.global_transform.basis.x))
	var scrubbing: bool = car.handbrake or lateral > SLIP_THRESHOLD
	if not scrubbing:
		return
	if car.global_position.distance_to(_last_pos) < STEP:
		return
	_last_pos = car.global_position
	_stamp()


## Drop a patch under each rear wheel, flattened to the road and turned to the
## car's heading so successive marks line up into a continuous streak.
func _stamp() -> void:
	var xf: Transform3D = car.global_transform
	var yaw: float = atan2(xf.basis.z.x, xf.basis.z.z)  # heading about world up
	# The mesh already lies flat (FACE_Y); just spin it to the car's heading.
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		var local := Vector3(side * HALF_WIDTH, 0.0, REAR_Z)
		var pos: Vector3 = xf * local
		pos.y += 0.06  # a hair above the tarmac
		multimesh.set_instance_transform(_write, Transform3D(basis, pos))
		_write = (_write + 1) % CAPACITY
