class_name ReplayCamera
extends Camera3D
## Swappable replay cameras (SPEC.md §M5), cycled by input: chase, cockpit,
## fixed trackside (auto-picks the nearest camera point), and a helicopter cam.

enum Mode { CHASE, COCKPIT, TRACKSIDE, HELICOPTER }

const MODE_NAMES: Array[String] = ["Chase", "Cockpit", "Trackside", "Helicopter"]

var mode: Mode = Mode.CHASE
var target: Node3D
var trackside_points: PackedVector3Array = PackedVector3Array()


func cycle() -> void:
	mode = (mode + 1) % Mode.size()


func mode_name() -> String:
	return MODE_NAMES[mode]


func update(delta: float) -> void:
	if target == null:
		return
	match mode:
		Mode.CHASE:
			_chase(delta)
		Mode.COCKPIT:
			_cockpit()
		Mode.TRACKSIDE:
			_trackside()
		Mode.HELICOPTER:
			_helicopter(delta)


func _chase(delta: float) -> void:
	var back: Vector3 = target.global_transform.basis.z
	var flat := Vector3(back.x, 0.0, back.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.BACK
	flat = flat.normalized()
	var desired: Vector3 = target.global_position + flat * 5.5 + Vector3.UP * 2.2
	global_position = global_position.lerp(desired, clampf(8.0 * delta, 0.0, 1.0))
	_look(target.global_position + Vector3.UP * 0.6)


func _cockpit() -> void:
	var t: Transform3D = target.global_transform
	# Just behind and above the windshield, oriented with the car.
	global_transform = Transform3D(t.basis, t * Vector3(0.0, 0.5, 0.15))


func _trackside() -> void:
	if trackside_points.is_empty():
		_chase(1.0)
		return
	var best: Vector3 = trackside_points[0]
	var best_d: float = INF
	for p in trackside_points:
		var d: float = p.distance_squared_to(target.global_position)
		if d < best_d:
			best_d = d
			best = p
	global_position = best
	_look(target.global_position)


func _helicopter(delta: float) -> void:
	var desired: Vector3 = target.global_position + Vector3(0.0, 15.0, 11.0)
	global_position = global_position.lerp(desired, clampf(2.5 * delta, 0.0, 1.0))
	_look(target.global_position)


func _look(at: Vector3) -> void:
	if global_position.distance_squared_to(at) < 0.001:
		return
	look_at(at, Vector3.UP)
