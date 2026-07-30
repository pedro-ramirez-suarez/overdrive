class_name CarProfile
extends Resource
## Tunable handling parameters for an arcade car (SPEC.md §M1).
##
## All numbers a car's feel depends on live here so they can be authored as a
## `.tres` resource and swapped per vehicle (the M6 roster) — never as magic
## literals inside ArcadeCar.gd.

## Rebuild a car profile from a replay/ghost car-info dict. Prefers the live roster
## profile (so a still-present car keeps its correct auto-fit); rebuilds a stub if
## the recorded model still exists on disk; otherwise falls back to a plain
## procedural body in the recorded colour — so an old recording of a car whose model
## has since been removed renders a generic ghost instead of erroring on a missing
## file.
static func for_replay(info: Dictionary) -> CarProfile:
	var model_path: String = info.get("model_path", "")
	var roster_profile: CarProfile = GameState.profile_for_model(model_path)
	if roster_profile != null:
		return roster_profile
	var prof := CarProfile.new()
	if model_path != "" and ResourceLoader.exists(model_path):
		prof.model_scene = load(model_path)
		prof.model_scale = info.get("model_scale", 1.0)
		prof.model_y_offset = info.get("model_y_offset", 0.0)
		prof.model_yaw = info.get("model_yaw", 0.0)
		prof.model_fit_width = info.get("model_fit_width", 0.0)
		prof.model_fit_length = info.get("model_fit_length", 0.0)
	else:
		prof.body_color = info.get("color", Color(0.55, 0.85, 1.0))
	return prof


## Invented display name for this car. Used by the car-select screen.
@export var display_name: String = "Car"

## One-line flavour blurb for the car-select screen.
@export var tagline: String = ""

## Body colour of this car's procedural mesh (ignored for model cars).
@export var body_color: Color = Color(0.85, 0.11, 0.13)

## Which procedural silhouette CarBody builds: coupe / gt / drift / muscle / super.
@export var body_style: String = "coupe"

## When true, CarBody mounts a revolving red/blue beacon on the roof — the police cars.
@export var roof_beacon: bool = false

# --- Optional imported model (M6). If set, this scene is used as the car's
# visual instead of the procedural CarBody. ---

@export var model_scene: PackedScene
@export var model_scale: float = 1.0
@export var model_y_offset: float = 0.0
@export var model_yaw: float = 0.0

## When > 0, CarBody ignores `model_scale`/`model_y_offset` and auto-fits the
## model instead: uniformly scaled so it is this many meters long, centred on the
## chassis, wheels seated on the road. Derived from the model's own bounds, so
## re-exporting the .glb at a different scale or origin needs no re-tuning.
@export var model_fit_length: float = 0.0

## Same as `model_fit_length`, but fits to overall WIDTH and lets length follow
## from the model's own proportions. Takes precedence when > 0. Prefer this when
## matching a car against a fleet: width (not length) is what reads as size on
## track, so normalizing length instead makes realistically-proportioned cars
## look shrunken next to stubbier ones.
@export var model_fit_width: float = 0.0

## Chassis mass in kilograms. Copied onto the RigidBody3D at runtime.
@export var mass: float = 1200.0

# --- Drive ---

## Peak drive force in Newtons, at zero speed. Scaled down toward top speed by
## `engine_force_curve`.
@export var engine_force: float = 16000.0

## Normalized throttle response: x = current speed / max_speed (0..1),
## y = fraction of `engine_force` available (0..1). Should fall to ~0 at x=1 so
## the car naturally tops out.
@export var engine_force_curve: Curve

## Maximum forward speed in m/s (used only to normalize the curve; the curve is
## what actually enforces the cap).
@export var max_speed: float = 55.0

## Braking force in Newtons applied when moving forward and the brake is held.
@export var brake_force: float = 20000.0

## Force in Newtons pushing the car backward when the brake is held at a stop.
@export var reverse_force: float = 8000.0

# --- Grip & steering ---

## Fraction of lateral (sideways) velocity killed each physics step. Higher =
## grippier / less slide. 0 = ice.
@export_range(0.0, 1.0) var grip: float = 0.12

## Yaw rate (rad/s) commanded at low speed — sharp, tight turning.
@export var steer_speed_low: float = 2.4

## Yaw rate (rad/s) commanded near top speed — looser, more stable.
@export var steer_speed_high: float = 1.1

## How quickly actual yaw rate chases the commanded yaw rate (P gain, per second).
@export var turn_responsiveness: float = 12.0

## While the handbrake is held, `grip` is multiplied by this (drops rear/overall
## grip to allow slides). 0..1.
@export_range(0.0, 1.0) var handbrake_grip_mult: float = 0.25

## While the handbrake is held, the commanded yaw rate is multiplied by this, so the
## rear steps out and the nose rotates into the corner (oversteer / drift) rather than
## the car just sliding straight on.
@export var handbrake_yaw_boost: float = 2.1

## While the handbrake is held, the low-speed turn limiter is lifted to at least this
## (0..1), so yanking it in a tight corner pivots the chassis even when nearly stopped
## — the weight-transfer rotation that beats understeer.
@export_range(0.0, 1.0) var handbrake_pivot_mobility: float = 0.65

# --- Off-track penalty (SPEC.md §M4-ish) ------------------------------------

## Fraction of max_speed the car is limited to when off the track (>=50% of the
## wheels off). 0..1.
@export_range(0.0, 1.0) var offtrack_speed_frac: float = 0.3

## How hard the car is dragged back down toward the off-track speed cap when it
## enters off-track above it. Higher = quicker bleed-off.
@export var offtrack_drag: float = 0.8

# --- Suspension (raycast springs) ---

## Target ride height above the wheel contact, in meters.
@export var suspension_rest: float = 0.6

## Suspension spring stiffness (N/m).
@export var spring_k: float = 30000.0

## Suspension damping coefficient (N per m/s).
@export var damping: float = 3000.0

## Wheel radius in meters. Added to `suspension_rest` to get the natural
## ray length so the chassis floats a wheel's radius clear of the road.
@export var wheel_radius: float = 0.35

# --- Track-relative gravity & alignment (M2, SPEC.md §5.1) ------------------

## How fast the gravity "down" vector blends toward its target (grounded: into
## the road; airborne: world-down). Higher = snappier, lower = smoother.
@export var gravity_blend_speed: float = 6.0

## Proportional gain for levelling the car while airborne, so a jump lands on its
## wheels rather than its tail. Deliberately far gentler than `align_gain`: the
## car should settle over the flight, not snap flat the instant it leaves a ramp.
## 0 disables it, and the car keeps whatever attitude it took off with.
@export var air_align_gain: float = 2.2

## How fast the airborne levelling is chased (as `align_responsiveness`).
@export var air_align_responsiveness: float = 3.0

## Proportional gain for the surface-alignment assist: how strongly the chassis
## rotates to put its up-axis on the road normal. Higher = the car follows loops
## and corkscrews more insistently.
@export var align_gain: float = 6.0

## How fast the pitch/roll angular velocity chases the alignment target (0..1
## per-frame lerp weight = align_responsiveness * delta).
@export var align_responsiveness: float = 8.0
