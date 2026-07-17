class_name AIController
extends Node
## Simple path-following AI (SPEC.md §M4). Drives an ArcadeCar by writing its
## control fields — steering toward the next waypoint, easing the throttle in
## corners — with a rubber-band speed factor set by the race manager.

var car: ArcadeCar
var waypoints: PackedVector3Array
var target_index: int = 1

## Rubber-band multiplier on throttle (set by RaceManager: >1 when behind).
var speed_factor: float = 1.0
## Set true when the race starts.
var active: bool = false

const WAYPOINT_REACHED: float = 7.0
const STEER_GAIN: float = 2.0


func _physics_process(_delta: float) -> void:
	if not active or car == null or waypoints.is_empty():
		return

	var pos: Vector3 = car.global_position
	var target: Vector3 = waypoints[target_index]
	var to_target: Vector3 = target - pos
	to_target.y = 0.0

	if to_target.length() < WAYPOINT_REACHED:
		target_index = (target_index + 1) % waypoints.size()
		target = waypoints[target_index]
		to_target = target - pos
		to_target.y = 0.0

	if to_target.length_squared() < 0.0001:
		return

	var forward: Vector3 = -car.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var desired: Vector3 = to_target.normalized()

	# Positive signed angle (about +Y) means the target is to the left; steer
	# field is positive-for-right, so negate.
	var angle: float = forward.signed_angle_to(desired, Vector3.UP)
	car.steer = clampf(-angle * STEER_GAIN, -1.0, 1.0)
	car.throttle = clampf(1.0 - absf(angle) * 0.45, 0.35, 1.0) * speed_factor
	car.brake = 0.0
	car.handbrake = false
