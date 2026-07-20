class_name ChaseCamera
extends Camera3D
## Chase and first-person cameras (SPEC.md §M1). `camera_cycle` (C) switches.
##
## Follows a target with positional and rotational lag so the view trails the
## car a little. Kept as a plain smoothed Camera3D (rather than a SpringArm3D
## node) so the follow lag is fully under our control; collision push-in can be
## layered on later if a track ever occludes the car.

## CHASE and CLOSE trail the car, upright, following only its heading — CLOSE sits
## nearer and lower with a snappier follow, for a more intense view. COCKPIT and
## BUMPER ride the car's FULL orientation — roll included — so a loop or a pipe
## rolls the world around you, which is the whole point of a first-person view in
## a stunt game. C cycles through them in this order.
enum Mode { CHASE, CLOSE, COCKPIT, BUMPER }
const MODE_NAMES: Array[String] = ["Chase", "Close", "Cockpit", "Bumper"]

## Path to the node to follow (the car). Resolved to `target` in _ready — a
## NodePath export is used (rather than a typed Node3D export) because it
## resolves reliably from a saved scene.
@export var target_path: NodePath

## Distance behind the target, meters.
@export var distance: float = 5.5
## Height above the target, meters.
@export var height: float = 2.3
## Point above the target the camera aims at, meters.
@export var look_height: float = 0.6
## Higher = snappier follow, lower = more lag.
@export var follow_lag: float = 8.0

## The CLOSE chase: nearer, lower and quicker to react than the default chase.
@export var close_distance: float = 3.1
@export var close_height: float = 1.35
@export var close_look_height: float = 0.7
@export var close_follow_lag: float = 13.0

## Driver's eye, in the car's local space. The car's origin sits at its ride
## height, its roof about 0.5 m above that, and -Z is forward — so this is a
## little up and a little back from centre.
@export var cockpit_offset := Vector3(0.0, 0.28, 0.10)
## Front bumper, in the car's local space.
@export var bumper_offset := Vector3(0.0, 0.02, -0.95)
## Wider in first person: the view sits still relative to the car, so a normal FOV
## reads as much slower than it is.
@export var first_person_fov: float = 88.0
## Extra degrees of FOV added at top speed, eased in with pace so acceleration
## reads as a subtle widening of the view — the classic arcade "sense of speed".
@export var fov_kick: float = 10.0
## First-person follow. Very high — the view must track the car almost exactly —
## but not infinite, so single-frame suspension jitter is damped.
@export var first_person_lag: float = 30.0

var mode: Mode = Mode.CHASE
var target: Node3D
var _chase_fov: float = 75.0
var _visual: Node3D


func _ready() -> void:
	_chase_fov = fov  # cached first: it is the scene's authored FOV, target or not
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	if target == null:
		push_warning("ChaseCamera has no valid target_path; camera will not follow.")
		return
	# The car's own body, hidden while inside it (see set_mode).
	_visual = target.get_node_or_null("Visual") as Node3D


func _unhandled_input(event: InputEvent) -> void:
	if target != null and event.is_action_pressed("camera_cycle"):
		set_mode((mode + 1) % Mode.size())


func _is_chase(m: int) -> bool:
	return m == Mode.CHASE or m == Mode.CLOSE


func set_mode(m: int) -> void:
	mode = m as Mode
	var third_person: bool = _is_chase(mode)
	fov = _chase_fov if third_person else first_person_fov
	# Hide the car when the camera is inside it. Without this the near plane cuts
	# through the bodywork, and the windscreen — centimetres from the lens — tints
	# the entire view.
	if _visual != null:
		_visual.visible = third_person
	# Move this car's headlights out of the driver's view in first person. The
	# camera only ever follows the player, so this affects the player's car alone.
	if target != null and target.has_method("set_first_person_lights"):
		target.set_first_person_lights(not third_person)
	_follow(1.0)  # snap, so switching doesn't sweep the camera across the map


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_follow(delta)


func _follow(delta: float) -> void:
	if _is_chase(mode):
		_follow_chase(delta)
	else:
		_follow_first_person(delta)
	_apply_speed_fov(delta)


## Widen the FOV with speed. Eased toward a target each frame (not snapped) so the
## kick swells and settles smoothly; the base FOV is whichever the current mode
## uses, so this layers on top of the chase/first-person split in set_mode.
func _apply_speed_fov(delta: float) -> void:
	if fov_kick <= 0.0 or not (target is ArcadeCar):
		return
	var car := target as ArcadeCar
	var top: float = car.profile.max_speed if car.profile != null else 60.0
	var pace: float = clampf(car.linear_velocity.length() / maxf(top, 1.0), 0.0, 1.0)
	var base: float = _chase_fov if _is_chase(mode) else first_person_fov
	fov = lerpf(fov, base + fov_kick * pace, clampf(6.0 * delta, 0.0, 1.0))


## Ride the car's full transform, offset to the driver's eye or the bumper.
func _follow_first_person(delta: float) -> void:
	var xf: Transform3D = target.global_transform
	var offset: Vector3 = cockpit_offset if mode == Mode.COCKPIT else bumper_offset
	# The car's -Z is forward and a camera looks down its own -Z, so the car's
	# basis can be used as-is.
	var want_pos: Vector3 = xf * offset
	var want_rot: Quaternion = xf.basis.get_rotation_quaternion()
	var w: float = clampf(first_person_lag * delta, 0.0, 1.0)
	var rot: Quaternion = global_transform.basis.get_rotation_quaternion().slerp(want_rot, w)
	global_transform = Transform3D(Basis(rot), global_position.lerp(want_pos, w))


## Trail the car, upright, following only its heading — deliberately ignoring
## pitch and roll so a loop doesn't throw the view around. CLOSE uses the nearer,
## quicker set of parameters.
func _follow_chase(delta: float) -> void:
	var dist: float = close_distance if mode == Mode.CLOSE else distance
	var high: float = close_height if mode == Mode.CLOSE else height
	var look: float = close_look_height if mode == Mode.CLOSE else look_height
	var lag: float = close_follow_lag if mode == Mode.CLOSE else follow_lag

	# The car's local +Z points backward, so sitting along it puts us behind.
	var back: Vector3 = target.global_transform.basis.z
	var flat_back: Vector3 = Vector3(back.x, 0.0, back.z)
	if flat_back.length_squared() < 0.0001:
		flat_back = Vector3.BACK
	flat_back = flat_back.normalized()

	var desired: Vector3 = target.global_position + flat_back * dist + Vector3.UP * high

	var weight: float = clampf(lag * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, weight)

	look_at(target.global_position + Vector3.UP * look, Vector3.UP)
