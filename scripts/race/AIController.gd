class_name AIController
extends Node
## Simple path-following AI (SPEC.md §M4). Drives an ArcadeCar by writing its
## control fields — steering toward the next waypoint, easing the throttle in
## corners — with a rubber-band speed factor set by the race manager.

var car: ArcadeCar
var waypoints: PackedVector3Array
var target_index: int = 1

## Waypoint indices that are loop tiles (set by RaceManager). Reaching one triggers
## a straight-line "commit" so the AI drives up and over instead of cutting across.
var loop_flags: Dictionary = {}

## Rubber-band multiplier on throttle (set by RaceManager: >1 when behind).
var speed_factor: float = 1.0
## Set true when the race starts.
var active: bool = false

const WAYPOINT_REACHED: float = 7.0
const STEER_GAIN: float = 2.0

# Loop-commit state. The loop's footprint is nearly a straight line seen from
# above, so ordinary waypoint steering aims the car at the exit and it cuts across
# the base instead of going round. On reaching a loop tile we instead drive dead
# straight at full throttle — the way the player loops — until the car has climbed
# and is back on level ground (or a timeout, so a botched attempt can't lock it).
var _loop_committed: bool = false
var _loop_climbed: bool = false
var _loop_timer: float = 0.0


func _physics_process(delta: float) -> void:
	if not active or car == null or waypoints.is_empty():
		return

	if _loop_committed and _drive_loop(delta):
		return

	var pos: Vector3 = car.global_position
	var target: Vector3 = waypoints[target_index]
	var to_target: Vector3 = target - pos
	to_target.y = 0.0

	if to_target.length() < WAYPOINT_REACHED:
		# Reaching a loop tile: commit to driving straight up and over it.
		if loop_flags.get(target_index, false):
			_loop_committed = true
			_loop_climbed = false
			_loop_timer = 6.0
		target_index = (target_index + 1) % waypoints.size()
		target = waypoints[target_index]
		to_target = target - pos
		to_target.y = 0.0
		if _loop_committed and _drive_loop(delta):
			return

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


## Drive straight up and over a loop at full throttle. Returns true while the commit
## is active (the caller then skips normal steering), false once the car is back on
## level ground past the loop or the attempt times out.
func _drive_loop(delta: float) -> bool:
	_loop_timer -= delta
	var nup: float = car.surface_normal.dot(Vector3.UP)
	if car.grounded and nup < 0.6:
		_loop_climbed = true  # we're actually on the vertical part now
	var finished: bool = _loop_climbed and car.grounded and nup > 0.85
	if finished or _loop_timer <= 0.0:
		_loop_committed = false
		_loop_climbed = false
		return false
	# Full throttle, no steering — let the loop road and the car's surface alignment
	# carry it round, exactly as the player does by just holding accelerate.
	car.throttle = maxf(speed_factor, 1.0)
	car.steer = 0.0
	car.brake = 0.0
	car.handbrake = false
	return true
