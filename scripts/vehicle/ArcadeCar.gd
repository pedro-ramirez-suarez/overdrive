class_name ArcadeCar
extends RigidBody3D
## Custom raycast arcade vehicle controller (SPEC.md §M1, §M2, §2, §5.1).
##
## Deliberately NOT a VehicleBody3D: we need full authority over the gravity
## direction and grip so we can pin the car to the road through loops via
## track-relative gravity (§5.1).
##
## Gravity (§5.1): while grounded, "down" blends toward the inverted averaged
## road normal, which presses the car into the surface and holds it through a
## loop or corkscrew; while airborne it blends back to world-down so jumps arc
## naturally. A surface-alignment assist rotates the chassis so its up-axis
## tracks the road normal, so the body pitches to follow the loop instead of
## relying on suspension geometry alone.
##
## Expects: gravity_scale = 0 on this body (we integrate gravity ourselves) and
## four RayCast3D children (one per wheel) whose collision_mask hits the `road`
## layer. Any number of RayCast3D children is tolerated; four is the design.

## Current "down" for gravity. Updated every frame: toward the inverted averaged
## road normal while grounded, toward world-down while airborne (§5.1). The
## scene value is just the starting orientation. Applied normalized.
@export var gravity_direction: Vector3 = Vector3.DOWN

## Handling parameters. Required — assign a CarProfile .tres in the scene.
@export var profile: CarProfile

## When true, control fields are filled from the player's Input each frame. When
## false (an AI car), an external AIController writes the control fields instead.
@export var player_controlled: bool = true

## When false, drive/steer/handbrake are held at zero (e.g. during a race
## countdown). Suspension and gravity still run so the car sits on the road.
var control_enabled: bool = true

## When false, the car ignores the reset_car input (the race manager owns
## respawning instead).
var self_reset_enabled: bool = true

## Externally-imposed top-speed multiplier (1 = none). The race manager lowers
## this toward 0.05 when the car strays far off the racing line (M6).
var external_speed_frac: float = 1.0

# --- Control inputs (0..1 throttle/brake, -1..1 steer). Set by the player-input
# read or by an AIController. ---
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var handbrake: bool = false

# --- Runtime state (readable by cameras / debug / later milestones) ---

var grounded: bool = false
## Averaged, normalized road normal under the wheels this frame (Vector3.UP when
## airborne). M2 reads this to build track-relative gravity.
var surface_normal: Vector3 = Vector3.UP
## False when >=50% of the wheels are on "offtrack"-tagged ground; drive speed is
## then capped (SPEC.md §M4).
var on_track: bool = true

var _wheel_rays: Array[RayCast3D] = []
var _last_safe_position: Vector3 = Vector3.ZERO
var _last_safe_yaw: float = 0.0


func _ready() -> void:
	assert(profile != null, "ArcadeCar requires a CarProfile assigned to `profile`.")

	# Collect wheel raycasts.
	for child in get_children():
		if child is RayCast3D:
			var ray: RayCast3D = child
			ray.enabled = true
			_wheel_rays.append(ray)
	assert(_wheel_rays.size() > 0, "ArcadeCar found no RayCast3D children to use as wheels.")

	mass = profile.mass
	gravity_scale = 0.0  # we apply gravity manually; enforce it even if the scene forgot.
	can_sleep = false

	_last_safe_position = global_position
	_last_safe_yaw = _current_yaw()

	if GameState.race_time == Atmosphere.TimeOfDay.NIGHT:
		_add_headlights()
	_add_brake_lights()

	body_entered.connect(_on_body_entered)


## A red glow at the rear that comes on while braking. No visible geometry — just
## light, so it never looks like a box stuck on the car. The car's forward is -Z,
## so the rear is +Z; a short-range red OmniLight per side lights the tail and the
## ground behind, its energy raised only when the brake is applied.
var _brake_lights: Array[OmniLight3D] = []


func _add_brake_lights() -> void:
	for side in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.08, 0.08)
		light.light_energy = 0.0  # off until braking
		light.omni_range = 1.5
		light.shadow_enabled = false
		light.position = Vector3(side * 0.34, 0.06, 0.98)
		add_child(light)
		_brake_lights.append(light)


## Glow the brake lights while the brake is pressed and the car is actually moving
## forward — brake lights don't come on while reversing under power.
func _update_brake_lights() -> void:
	if _brake_lights.is_empty():
		return
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z)
	var braking: bool = brake > 0.1 and forward_speed > 0.5
	var energy: float = 1.8 if braking else 0.0
	for light in _brake_lights:
		light.light_energy = energy


## Two forward-pointing spotlights plus glowing bulbs, added only at night. A
## SpotLight3D emits down its own -Z, which is also the car's forward, so no
## rotation is needed. Every car gets them, so the field lights the track up.
var _headlight_spots: Array[SpotLight3D] = []
var _headlight_bulbs: Array[MeshInstance3D] = []


func _add_headlights() -> void:
	# Bumper height. The car's origin sits ~0.26 m above the wheel contact, so a
	# real headlight (~0.4 m off the ground) is a little BELOW the origin, and the
	# beam is aimed slightly down so it lights the road ahead, not the sky.
	for side in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(side * 0.4, -0.08, -0.95)
		spot.rotation = Vector3(deg_to_rad(-8), 0.0, 0.0)  # tip the beam toward the road
		spot.light_color = Color(1.0, 0.96, 0.85)
		spot.light_energy = 5.0
		spot.spot_range = 30.0
		spot.spot_angle = 34.0
		spot.spot_angle_attenuation = 1.4
		spot.shadow_enabled = false  # many cars * shadows would be costly and noisy
		add_child(spot)
		_headlight_spots.append(spot)

		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		bulb.mesh = s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.97, 0.88)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.95, 0.8)
		m.emission_energy_multiplier = 4.0
		bulb.material_override = m
		bulb.position = Vector3(side * 0.4, -0.08, -0.98)
		add_child(bulb)
		_headlight_bulbs.append(bulb)


## Switch the headlights between the third-person look (visible bulbs at the
## bumper) and a first-person look. In first person the glowing bulbs sit right in
## front of the lens as two distracting spheres, so they are hidden and the beams
## are lifted above the eye line and brightened — the road still lights up, but
## there is nothing glowing in the driver's view. Called by ChaseCamera, and only
## for the player's own car, so other cars keep their visible headlights.
func set_first_person_lights(first_person: bool) -> void:
	for b in _headlight_bulbs:
		b.visible = not first_person
	for i in range(_headlight_spots.size()):
		var spot: SpotLight3D = _headlight_spots[i]
		var side: float = -1.0 if i == 0 else 1.0
		if first_person:
			spot.position = Vector3(side * 0.3, 0.45, -0.6)  # above the lens
			spot.light_energy = 8.5
		else:
			spot.position = Vector3(side * 0.4, -0.08, -0.95)
			spot.light_energy = 5.0


## Play an impact sound on a hard car-to-car collision (ignored for the
## transform-driven ghost cars in replays, which have physics disabled).
func _on_body_entered(body: Node) -> void:
	if not is_physics_processing() or not (body is ArcadeCar):
		return
	var relative_speed: float = (linear_velocity - (body as ArcadeCar).linear_velocity).length()
	if relative_speed > 6.0:
		var force: float = clampf(relative_speed / 25.0, 0.2, 1.0)
		AudioManager.play_impact(force)
		# A sharp jolt in the player's hands on a real bump; a no-op without a pad.
		if player_controlled:
			Haptics.pulse(0.4 * force, force, 0.18)


func _physics_process(delta: float) -> void:
	if profile == null:
		return

	# Captured before any force is applied this step, so a landing reads the true
	# incoming vertical speed rather than the value after the suspension pushes back.
	var incoming_vy: float = linear_velocity.y

	if player_controlled:
		if control_enabled:
			_read_player_input()
		else:
			throttle = 0.0
			brake = 0.0
			steer = 0.0
			handbrake = false

	_update_suspension()  # sets `grounded` and `surface_normal`
	_update_gravity_direction(delta)
	_apply_gravity()
	_apply_drive()
	_apply_grip()
	_apply_steering(delta)
	_apply_surface_alignment(delta)
	_update_safe_state()
	_update_brake_lights()
	if player_controlled:
		_update_rumble(delta, incoming_vy)
	if player_controlled and self_reset_enabled:
		_handle_reset()


# --- Controller rumble ------------------------------------------------------
# Player car only. Every call routes through Haptics, which no-ops without a pad.

var _was_grounded: bool = true
var _air_accum: float = 0.0
var _road_rumble_cd: float = 0.0
var _road_rumbling: bool = false


func _update_rumble(delta: float, incoming_vy: float) -> void:
	# A thump on landing, scaled by how hard the car came down and only after real
	# airtime (so rolling over crests and kerbs doesn't buzz constantly).
	if not grounded:
		_air_accum += delta
	elif not _was_grounded:
		if _air_accum > 0.25:
			var impact: float = clampf(-incoming_vy / 22.0, 0.0, 1.0)  # down is -Y
			if impact > 0.12:
				Haptics.pulse(0.25 + impact * 0.4, impact, 0.22)
		_air_accum = 0.0
	_was_grounded = grounded

	# A low, steady buzz while scrabbling over off-road ground at speed, refreshed
	# on a timer so it stays alive, and cut the moment the car is back on tarmac.
	var off_road: bool = grounded and not on_track and linear_velocity.length() > 5.0
	if off_road:
		_road_rumble_cd -= delta
		if _road_rumble_cd <= 0.0:
			Haptics.pulse(0.32, 0.0, 0.3)
			_road_rumble_cd = 0.25
		_road_rumbling = true
	elif _road_rumbling:
		Haptics.stop()
		_road_rumbling = false


func _read_player_input() -> void:
	throttle = Input.get_action_strength("accelerate")
	brake = Input.get_action_strength("brake")
	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	handbrake = Input.is_action_pressed("handbrake")


# --- Suspension: raycast springs, one per wheel -----------------------------

## The suspension is tuned around this mass; a car's spring/damping scale by its
## own mass over this, so ride height is the same for every car regardless of
## weight (see _update_suspension).
const REFERENCE_MASS := 1200.0

## Wheel contact for DRIVING (grounded, spring, steering) reaches this far past the
## natural suspension length. Beyond it the wheel has left the road — but road-stick
## can still act, out to the ray's full (longer) length.
const GROUND_MARGIN := 0.16

## Road stick: a pull toward the road that engages ONLY once a wheel has lifted off
## and the surface is still within the ray's reach. It holds the car on continuous
## surfaces — banked entries and crests — at speed, instead of launching off them,
## yet a jump ramp's road ends in a gap so past the lip the ray misses and the car
## still flies. Values are per REFERENCE_MASS, scaled by each car's mass_ratio.
const STICK_SPRING := 20000.0   # N per metre a wheel is lifted
const STICK_DAMP := 3000.0      # N per (m/s) of lift-off speed
const STICK_MAX := 12000.0      # N cap, per wheel

func _update_suspension() -> void:
	grounded = false
	var normal_sum: Vector3 = Vector3.ZERO
	var hit_count: int = 0
	var offtrack_count: int = 0
	var natural_length: float = profile.suspension_rest + profile.wheel_radius
	var ground_reach: float = natural_length + GROUND_MARGIN
	# Stiffness/damping scale with mass, so EVERY car rides at the same height.
	# Without this a heavy car (a ~1900 kg truck) compresses the fixed spring twice
	# as far as a light one and sits so low its collision box drags through terrain.
	var mass_ratio: float = mass / REFERENCE_MASS

	for ray in _wheel_rays:
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue

		var normal: Vector3 = ray.get_collision_normal()
		var ray_origin: Vector3 = ray.global_position
		var current_length: float = ray_origin.distance_to(ray.get_collision_point())
		var compression: float = natural_length - current_length  # >0 == compressed
		var offset: Vector3 = ray_origin - global_position
		var wheel_velocity: Vector3 = linear_velocity + angular_velocity.cross(offset)
		var relative_speed: float = wheel_velocity.dot(normal)  # >0 == lifting away

		# In driving contact: grounded, spring push, surface normal, off-track test.
		if current_length <= ground_reach:
			grounded = true
			hit_count += 1
			var collider: Object = ray.get_collider()
			if collider is Node and (collider as Node).is_in_group("offtrack"):
				offtrack_count += 1
			normal_sum += normal
			# Spring pushes out along the surface normal; damping opposes motion.
			var k: float = profile.spring_k * mass_ratio
			var damp: float = profile.damping * mass_ratio
			var force_mag: float = maxf(compression * k - relative_speed * damp, 0.0)
			apply_force(normal * force_mag, offset)

		# Road stick: a lifted-off wheel (compression < 0) that can still see the road
		# gets pulled back toward it — a spring on the gap plus damping on the lift-off
		# speed, capped so it plants the car without gluing it.
		if compression < 0.0:
			var pull: float = (-compression * STICK_SPRING + maxf(relative_speed, 0.0) * STICK_DAMP) * mass_ratio
			pull = minf(pull, STICK_MAX * mass_ratio)
			apply_force(-normal * pull, offset)

	if hit_count > 0:
		surface_normal = (normal_sum / float(hit_count)).normalized()
	else:
		surface_normal = Vector3.UP

	# Off the track when at least half of the wheels sit on off-track ground.
	on_track = offtrack_count < 2


# --- Gravity: track-relative while grounded, world-down while airborne ------

## Blend `gravity_direction` toward its target (§5.1). Grounded target is the
## inverted road normal (presses the car into the surface, holding it through a
## loop); airborne target is world-down. The blend avoids a snap at transitions.
func _update_gravity_direction(delta: float) -> void:
	var target: Vector3 = -surface_normal if grounded else Vector3.DOWN
	var weight: float = clampf(profile.gravity_blend_speed * delta, 0.0, 1.0)
	gravity_direction = gravity_direction.lerp(target, weight)
	if gravity_direction.length_squared() < 0.0001:
		gravity_direction = target
	gravity_direction = gravity_direction.normalized()


func _apply_gravity() -> void:
	var dir: Vector3 = gravity_direction.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.DOWN
	apply_central_force(dir * Constants.GRAVITY * mass)


# --- Drive: throttle, brake, reverse ---------------------------------------

func _apply_drive() -> void:
	if not grounded:
		return

	var forward: Vector3 = -global_transform.basis.z
	var forward_speed: float = linear_velocity.dot(forward)

	# Speed cap: the lower of the off-track penalty (wheels off the road) and any
	# externally-imposed cap (straying far off the racing line). Excess speed is
	# bled off with drag so the slowdown is gradual.
	var frac: float = profile.offtrack_speed_frac if not on_track else 1.0
	frac = minf(frac, external_speed_frac)
	var speed_cap: float = profile.max_speed * frac
	if forward_speed > speed_cap:
		apply_central_force(-forward * (forward_speed - speed_cap) * profile.offtrack_drag * mass)

	if throttle > 0.0 and forward_speed < speed_cap:
		var speed_ratio: float = clampf(absf(forward_speed) / maxf(speed_cap, 0.1), 0.0, 1.0)
		var curve_mult: float = 1.0
		if profile.engine_force_curve != null:
			curve_mult = profile.engine_force_curve.sample_baked(speed_ratio)
		apply_central_force(forward * profile.engine_force * curve_mult * throttle)

	if brake > 0.0:
		if forward_speed > 1.0:
			# Slow down.
			apply_central_force(-forward * profile.brake_force * brake)
		elif forward_speed > -profile.max_speed * 0.4:
			# Reverse (capped at 40% of top speed).
			apply_central_force(-forward * profile.reverse_force * brake)


# --- Grip: kill sideways slide (arcade) ------------------------------------

func _apply_grip() -> void:
	if not grounded:
		return

	var right: Vector3 = global_transform.basis.x
	var lateral_speed: float = linear_velocity.dot(right)

	var grip: float = profile.grip
	if handbrake:
		grip *= profile.handbrake_grip_mult

	# Remove a fraction of lateral velocity this step via an impulse.
	apply_central_impulse(-right * lateral_speed * grip * mass)


# --- Steering: yaw-rate controller about the car's own up axis --------------

func _apply_steering(delta: float) -> void:
	if not grounded:
		return

	var forward: Vector3 = -global_transform.basis.z
	var forward_speed: float = linear_velocity.dot(forward)
	var up: Vector3 = global_transform.basis.y

	var steer_input: float = steer
	var speed_ratio: float = clampf(absf(forward_speed) / profile.max_speed, 0.0, 1.0)
	var steer_speed: float = lerpf(profile.steer_speed_low, profile.steer_speed_high, speed_ratio)

	# Need some speed to turn; steer direction follows travel direction.
	var mobility: float = clampf(absf(forward_speed) / 3.0, 0.0, 1.0)
	var travel_sign: float = 1.0 if forward_speed >= -0.5 else -1.0
	# Negated: positive yaw about +up is counter-clockwise (a LEFT turn) in
	# Godot's right-handed frame, so steer_right must drive yaw negative.
	var target_yaw: float = -steer_input * steer_speed * travel_sign * mobility

	# Chase the target yaw rate but only touch the component about `up`, so pitch
	# and roll (needed for loops in M2) are untouched.
	var current_yaw: float = angular_velocity.dot(up)
	var new_yaw: float = lerpf(current_yaw, target_yaw, clampf(profile.turn_responsiveness * delta, 0.0, 1.0))
	angular_velocity += up * (new_yaw - current_yaw)


# --- Surface alignment: keep the chassis up-axis on the road normal ---------

## How long the car must be continuously airborne before it starts levelling
## itself. Short enough that a real jump is covered, long enough that momentary
## airtime is not — see _apply_surface_alignment.
const AIR_ALIGN_DELAY := 0.3

var _air_time: float = 0.0


## Rotate the body so its up-axis tracks the road while grounded, and levels out
## while airborne. The correction acts only on the pitch/roll part of angular
## velocity (its axis is perpendicular to `up`), so it never fights the yaw
## steering — and it is what carries the car around a loop or corkscrew.
##
## Airborne levelling is what makes a jump land cleanly: a car leaving a ramp
## nose-up holds that pitch for the whole arc and comes down on its tail, which
## reads as a crash. It is deliberately gentler than the grounded correction, so
## the car settles over the flight instead of snapping flat.
##
## It waits for AIR_ALIGN_DELAY of unbroken air, which matters at the top of a
## loop: there the car's up-axis points at the road and levelling would roll it
## off. Momentary unloading over a crest is left alone; only a real jump levels.
func _apply_surface_alignment(delta: float) -> void:
	var target: Vector3
	var gain: float
	var responsiveness: float
	if grounded:
		_air_time = 0.0
		target = surface_normal
		gain = profile.align_gain
		responsiveness = profile.align_responsiveness
	else:
		_air_time += delta
		if _air_time < AIR_ALIGN_DELAY or profile.air_align_gain <= 0.0:
			return
		target = Vector3.UP
		gain = profile.air_align_gain
		responsiveness = profile.air_align_responsiveness

	var up: Vector3 = global_transform.basis.y
	var angle: float = up.angle_to(target)
	var axis: Vector3 = up.cross(target)
	if axis.length() < 0.0001:
		if angle < 0.5:
			return  # already aligned; nothing to correct
		# Exactly inverted: the cross product gives no axis to turn about, so roll
		# about our own side axis rather than staying stuck upside down.
		axis = global_transform.basis.x
	var desired: Vector3 = axis.normalized() * angle * gain

	# Split off the yaw (about-up) component so steering is untouched.
	var yaw_component: Vector3 = up * angular_velocity.dot(up)
	var pitch_roll: Vector3 = angular_velocity - yaw_component
	var blended: Vector3 = pitch_roll.lerp(desired, clampf(responsiveness * delta, 0.0, 1.0))
	angular_velocity = yaw_component + blended


# --- Reset / respawn --------------------------------------------------------

## Rings searched for somewhere to reappear, in meters from the remembered spot.
## Consecutive resets from the same place start further along this list, so
## holding R walks you out of whatever you are stuck in instead of replaying it.
const RESET_RINGS := [0.0, 5.0, 9.0, 14.0, 20.0]

## Breadcrumbs are dropped this far apart, and this many are kept — so a reset
## rewinds roughly SAFE_SPACING * (SAFE_HISTORY - 1) meters.
##
## Recording the safe spot every frame (which is what this used to do) makes it
## useless: while you are upright and grounded, "the last safe place" is exactly
## where you are standing, so resetting teleports you to yourself and zeroes your
## speed. That is an instant brake, not a reset.
const SAFE_SPACING := 9.0
const SAFE_HISTORY := 3

var _reset_count: int = 0
var _reset_from: Vector3 = Vector3(1e9, 1e9, 1e9)
## Recent safe spots along the route, oldest first: [{pos: Vector3, yaw: float}].
var _safe_trail: Array[Dictionary] = []

var _pending_teleport: Transform3D = Transform3D()
var _has_teleport: bool = false


## Move the car somewhere, the way a RigidBody3D actually supports.
##
## Assigning `global_transform` from outside the physics step is not reliable: the
## physics server owns the body's transform and integrates over the top of what you
## wrote, so the car snaps back to where it was — while the zeroed velocity sticks.
## That reads as an instant brake rather than a reset, which is exactly the bug this
## exists to avoid. _integrate_forces is the one place the server takes a new
## transform, so the move is queued for there.
func _teleport_to(xf: Transform3D) -> void:
	_pending_teleport = xf
	_has_teleport = true
	# Also set it directly, so anything reading the node this frame (the camera)
	# sees the new pose immediately rather than a frame late.
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _has_teleport:
		return
	_has_teleport = false
	state.transform = _pending_teleport
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO


func _update_safe_state() -> void:
	# Remember spots where we were grounded and roughly upright...
	if not grounded or global_transform.basis.y.dot(Vector3.UP) <= 0.6:
		return
	# ...but never one in a lake. The bed is solid ground the car sits upright on,
	# so without this the drowning spot becomes the "safe" spot and resetting drops
	# you straight back into the water you were trying to leave.
	if _in_lake(global_position):
		return
	if not _safe_trail.is_empty() \
			and global_position.distance_to(_safe_trail[-1]["pos"]) < SAFE_SPACING:
		return
	_safe_trail.append({"pos": global_position, "yaw": _current_yaw()})
	if _safe_trail.size() > SAFE_HISTORY:
		_safe_trail.pop_front()


## Is `pos` under the water of a lake? Cars on the track are exempt: a road may
## bridge a lake, and it clears the surface by only inches.
func _in_lake(pos: Vector3) -> bool:
	if on_track:
		return false
	var terrain: Terrain = GameState.current_terrain
	if terrain == null:
		return false
	var cell := Vector2i(
		roundi(pos.x / Constants.CELL_SIZE), roundi(pos.z / Constants.CELL_SIZE))
	if not terrain.is_water(cell):
		return false
	return pos.y < terrain.water_surface(cell) + 0.6


func _handle_reset() -> void:
	if Input.is_action_just_pressed("reset_car") or global_position.y < -30.0:
		reset_to_safe()


## Rewind the car to the oldest breadcrumb — a stretch of road behind you, not the
## spot you are standing on — upright, at rest, facing the way you were going.
func reset_to_safe() -> void:
	if not _safe_trail.is_empty():
		var crumb: Dictionary = _safe_trail[0]
		_last_safe_position = crumb["pos"]
		_last_safe_yaw = crumb["yaw"]

	# Reset again without having reached anywhere new? Then the last spot didn't
	# work, so step further out rather than dropping in the same place twice.
	if _last_safe_position.distance_to(_reset_from) < 1.0:
		# Clamped, not unbounded: past the last ring we keep searching the widest
		# one (at a fresh angle) rather than running out of rings and giving up.
		_reset_count = mini(_reset_count + 1, RESET_RINGS.size() - 1)
	else:
		_reset_count = 0
	_reset_from = _last_safe_position

	var upright: Basis = Basis(Vector3.UP, _last_safe_yaw)
	_teleport_to(Transform3D(upright, _find_reset_spot()))
	gravity_direction = Vector3.DOWN


## Dry ground at or near the last safe spot. Steps outward in rings, skipping
## anything that is under water or has no ground beneath it at all.
func _find_reset_spot() -> Vector3:
	var base: Vector3 = _last_safe_position
	for r in range(_reset_count, RESET_RINGS.size()):
		var radius: float = RESET_RINGS[r]
		var steps: int = 1 if radius <= 0.0 else 8
		for i in steps:
			# Rotate the ring per reset so repeated tries give fresh coordinates.
			var ang: float = TAU * float(i) / float(steps) + float(_reset_count) * 0.9
			var p := base + Vector3(cos(ang), 0.0, sin(ang)) * radius
			var y: float = _ground_height(p.x, p.z, base.y)
			if is_nan(y):
				continue
			var spot := Vector3(p.x, y + 1.0, p.z)
			if _lake_at(spot):
				continue
			return spot
	return base + Vector3.UP * 1.5


## Height of the road/terrain under (x, z) near `near_y`, or NAN if nothing.
func _ground_height(x: float, z: float, near_y: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, near_y + 25.0, z), Vector3(x, near_y - 60.0, z))
	q.collision_mask = Constants.ROAD_BIT
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit.position as Vector3).y


## Like _in_lake, but for an arbitrary spot (no on_track exemption — we're asking
## whether the ground there is flooded, not where the car currently is).
func _lake_at(pos: Vector3) -> bool:
	var terrain: Terrain = GameState.current_terrain
	if terrain == null:
		return false
	var cell := Vector2i(
		roundi(pos.x / Constants.CELL_SIZE), roundi(pos.z / Constants.CELL_SIZE))
	return terrain.is_water(cell) and pos.y < terrain.water_surface(cell) + 0.6


## Place the car upright at `pos` facing horizontal `forward`, at rest. Used by
## the race manager for grid starts and checkpoint respawns.
func respawn(pos: Vector3, forward: Vector3) -> void:
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var yaw: float = atan2(-flat.x, -flat.z)
	_teleport_to(Transform3D(Basis(Vector3.UP, yaw), pos))
	gravity_direction = Vector3.DOWN
	_last_safe_position = pos
	_last_safe_yaw = yaw
	# Start the trail here: the breadcrumbs behind us describe wherever the car was
	# before it was placed, which is not somewhere a reset should rewind to.
	_safe_trail.clear()
	_safe_trail.append({"pos": pos, "yaw": yaw})
	_reset_count = 0


func _current_yaw() -> float:
	var forward: Vector3 = -global_transform.basis.z
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return _last_safe_yaw
	return atan2(-flat.x, -flat.z)
