class_name CarRoster
extends RefCounted
## Builds the full car roster (SPEC.md §M6): the four hand-tuned procedural cars
## plus the imported Kenney Car Kit models (CC0). The Kenney profiles are built
## in code, pointing at the imported .glb as their visual `model_scene`.

const KENNEY := "res://assets/models/kenney/%s.glb"

# Shared visual fit for every Kenney model: front faces +Z (rotate 180 to our
# -Z forward), ~2.5-2.9 m long raw so 0.78 fits our ~2 m chassis. The model's
# origin sits at the wheels, so the offset drops it by the chassis ride height
# (~0.26 m) to seat the wheels on the road.
const MODEL_SCALE := 0.78
const MODEL_Y_OFFSET := -0.265
const MODEL_YAW := PI

# [glb, display, tagline, mass, engine, max_speed, grip, steer_low, steer_high, color]
const KENNEY_DEFS := [
	["race", "Bolt R", "Open-wheel rocket, glued down", 900, 16500, 68, 0.15, 2.8, 1.3, Color(0.90, 0.92, 0.95)],
	["race-future", "Ion X", "Futuristic prototype, blistering pace", 950, 17500, 72, 0.14, 2.6, 1.2, Color(0.20, 0.80, 0.90)],
	["sedan-sports", "Marlin GT", "Sporty saloon, well balanced", 1150, 15500, 58, 0.13, 2.4, 1.1, Color(0.85, 0.15, 0.15)],
	["hatchback-sports", "Pip RS", "Pocket rocket, darty", 1000, 14000, 54, 0.15, 2.7, 1.3, Color(0.95, 0.75, 0.10)],
	["suv-luxury", "Baron LX", "Heavy cruiser, planted", 1600, 19000, 60, 0.11, 2.0, 0.9, Color(0.18, 0.18, 0.22)],
	["sedan", "Verano", "Everyday all-rounder", 1250, 15000, 56, 0.12, 2.3, 1.05, Color(0.50, 0.55, 0.62)],
	["suv", "Ridge", "Rugged and stable", 1500, 17000, 58, 0.115, 2.1, 0.95, Color(0.30, 0.45, 0.32)],
	["taxi", "City Cab", "Reliable workhorse", 1300, 15000, 55, 0.12, 2.3, 1.05, Color(0.95, 0.80, 0.12)],
	["police", "Interceptor", "Pursuit-tuned, quick", 1350, 18000, 64, 0.13, 2.4, 1.1, Color(0.12, 0.22, 0.52)],
	["van", "Hauler", "Boxy but torquey", 1500, 14500, 52, 0.11, 2.0, 0.95, Color(0.80, 0.80, 0.82)],
	["truck", "Mammoth", "Freight-train momentum", 1850, 20000, 58, 0.10, 1.9, 0.85, Color(0.60, 0.20, 0.20)],
]


const CARS := "res://assets/models/cars/%s.glb"

# The four hero cars, using the imported models under invented names.
#
# WARNING (SPEC.md §2): these .glb files are user-supplied 1:1 replicas of real
# production cars, kept here as PLACEHOLDERS to reshape into original silhouettes.
# The names below are invented, but a rename does not make the geometry original —
# the shape is the trade dress. Their licence is also unknown. Do not ship these
# meshes as-is; replace them with reworked bodies before any public release.
#
# `fit` is the target WIDTH in meters — CarBody auto-fits from the model's own
# bounds, so re-exporting at a different scale needs no change here. `yaw` turns
# the model's front onto our -Z forward: the first four models face +Z (PI), the
# later batch faces -X (-PI/2). Sizes are ~0.55x real-world, matching the fleet.
#
# Fitted on width, not length, to match the Kenney fleet's on-track bulk: these
# models are realistically proportioned while the Kenney cars are stubby, so
# equal lengths left these looking shrunken. Widths keep the real vehicles'
# relative proportions (the brute widest, the kart narrowest); length then
# follows from each model.
# [glb, display, tagline, fit, yaw, mass, engine, max, grip, steer_low, steer_high, handbrake, color]
const MODEL_DEFS := [
	["kensei", "Kensei GT", "Sleek grand-tourer, planted and quick", 1.03, PI, 1300, 18000, 66, 0.14, 2.4, 1.1, 0.25, Color(0.66, 0.70, 0.74)],
	["onito", "Onito S", "Light drift coupe, happy sideways", 0.92, PI, 1050, 15000, 56, 0.10, 2.7, 1.3, 0.15, Color(0.90, 0.92, 0.95)],
	["bruiser", "Bruiser V8", "Heavy muscle, big top end, loose tail", 1.04, PI, 1550, 21000, 65, 0.10, 2.0, 0.9, 0.30, Color(0.90, 0.42, 0.10)],
	# NOTE: "draco" (a wedge supercar) is withdrawn — the model had defects that were
	# not worth chasing. Its .glb and textures are still in assets/models/cars but
	# nothing loads them; delete them whenever. Nocturne P1 is now the fast one.
	["nocturne", "Nocturne P1", "Endurance prototype, relentless pace", 1.08, PI, 1000, 19000, 76, 0.16, 2.5, 1.15, 0.20, Color(0.10, 0.30, 0.70)],
	["scarab", "Scarab", "Off-road buggy, skips over anything", 1.05, -PI / 2.0, 1100, 16000, 52, 0.16, 2.8, 1.3, 0.25, Color(0.95, 0.55, 0.10)],
	["gnat", "Gnat", "Featherweight kart, absurd cornering", 0.78, -PI / 2.0, 400, 9000, 42, 0.18, 3.2, 1.6, 0.20, Color(0.85, 0.20, 0.45)],
	["bulwark", "Bulwark", "Armoured brute, unstoppable and slow", 1.45, -PI / 2.0, 2400, 22000, 48, 0.12, 1.8, 0.8, 0.35, Color(0.35, 0.40, 0.28)],
]


const RGSDEV := "res://assets/models/rgsdev/%s.fbx"

# Low-poly vehicle pack by Raphael Gonçalves (Rgsdev), CC0 / public domain — free
# for any use, commercial included, no credit required. Unlike MODEL_DEFS these are
# generic invented vehicle types with no real-marque geometry or badges, so they are
# safe to ship as-is (SPEC.md §2).
#
# Every model in the pack faces +Z with its wheels named front/rear, so all of them
# take yaw PI to meet our -Z forward. `fit` is the target WIDTH in meters, as with
# MODEL_DEFS; the colour mirrors each model's own baked paint so the minimap dot
# matches the car you see. Vehicles whose length far outran the chassis (bus,
# firetruck, limousine, artic) are deliberately left out of the import.
# [file, display, tagline, fit, yaw, mass, engine, max, grip, steer_low, steer_high, handbrake, color]
const RGSDEV_DEFS := [
	["sports", "Vega S", "Crisp mid-engine coupe, eager to turn", 0.95, PI, 1050, 17000, 68, 0.15, 2.6, 1.2, 0.20, Color(0.78, 0.15, 0.11)],
	["roadster", "Zephyr R", "Open-top featherweight, playful tail", 0.95, PI, 1000, 16000, 64, 0.13, 2.7, 1.25, 0.22, Color(0.00, 0.24, 0.74)],
	["muscle", "Torque 8", "Big-block bruiser, all shoulders", 1.02, PI, 1500, 20000, 66, 0.11, 2.1, 0.95, 0.30, Color(1.00, 0.99, 0.19)],
	["muscle_2", "Rampart GT", "Long-hood cruiser with a mean streak", 1.02, PI, 1450, 19500, 65, 0.115, 2.15, 1.0, 0.28, Color(0.63, 0.69, 0.78)],
	["sedan", "Corva", "Sensible saloon, surprisingly willing", 0.98, PI, 1250, 15000, 56, 0.12, 2.3, 1.05, 0.25, Color(0.63, 0.69, 0.78)],
	["hatchback", "Sprig", "Tiny, darty, impossible to upset", 0.98, PI, 1000, 13500, 53, 0.15, 2.8, 1.3, 0.22, Color(0.86, 0.56, 0.08)],
	["taxi", "Yellowtail", "Knows every shortcut in town", 0.98, PI, 1300, 14500, 54, 0.12, 2.3, 1.05, 0.25, Color(1.00, 0.81, 0.24)],
	["suv", "Summit", "Tall, heavy, planted through anything", 1.05, PI, 1550, 17000, 58, 0.115, 2.0, 0.9, 0.30, Color(0.23, 0.05, 0.10)],
	["pickup", "Buckboard", "Workhorse with a loose back end", 1.05, PI, 1450, 16500, 57, 0.12, 2.1, 0.95, 0.28, Color(0.00, 0.35, 0.15)],
	["van", "Parcel", "Boxy, slow to turn, hard to stop", 1.05, PI, 1500, 14500, 52, 0.11, 2.0, 0.95, 0.30, Color(0.00, 0.05, 0.31)],
	["ambulance", "Lifeline", "Heavy but hurried", 1.05, PI, 1600, 16000, 56, 0.115, 2.0, 0.9, 0.28, Color(1.00, 0.98, 1.00)],
	["truck", "Anvil", "Freight-train momentum, stops eventually", 1.25, PI, 1900, 20000, 55, 0.10, 1.9, 0.85, 0.35, Color(0.00, 0.35, 0.15)],
	["monster_truck", "Stomper", "Absurd tyres, shrugs off landings", 1.30, PI, 1800, 21000, 58, 0.14, 2.4, 1.1, 0.30, Color(0.02, 0.54, 0.82)],
	["police_sports", "Pursuit S", "Pursuit-spec coupe, relentless", 0.95, PI, 1100, 18500, 70, 0.15, 2.6, 1.2, 0.20, Color(0.01, 0.00, 0.00)],
	["police_muscle", "Enforcer V8", "Interceptor with a big motor", 1.02, PI, 1500, 20500, 68, 0.12, 2.2, 1.0, 0.28, Color(0.01, 0.00, 0.00)],
	["police_sedan", "Patrol", "Standard issue, quietly quick", 0.98, PI, 1350, 17500, 62, 0.13, 2.4, 1.1, 0.25, Color(0.01, 0.00, 0.00)],
	["police_suv", "Precinct", "Riot-heavy and unbothered", 1.05, PI, 1600, 18000, 60, 0.12, 2.05, 0.92, 0.30, Color(0.01, 0.00, 0.00)],
]


static func build() -> Array[CarProfile]:
	var roster: Array[CarProfile] = []
	var curve := _falloff_curve()
	for d in MODEL_DEFS:
		roster.append(_hero(d, curve))
	for d in RGSDEV_DEFS:
		roster.append(_hero(d, curve, RGSDEV))
	for d in KENNEY_DEFS:
		roster.append(_kenney(d, curve))
	return roster


## Build a width-fitted model car from a [file, display, tagline, fit, yaw, mass,
## engine, max, grip, steer_low, steer_high, handbrake, color] row. `path_fmt` is
## the asset-path format for the model, so the same row shape serves both the
## res://assets/models/cars .glb set and the Rgsdev .fbx pack.
static func _hero(d: Array, curve: Curve, path_fmt: String = CARS) -> CarProfile:
	var p := _base_profile(curve)
	p.display_name = d[1]
	p.tagline = d[2]
	p.model_scene = load(path_fmt % d[0])
	p.model_fit_width = float(d[3])
	p.model_yaw = float(d[4])
	p.mass = float(d[5])
	p.engine_force = float(d[6])
	p.max_speed = float(d[7])
	p.grip = float(d[8])
	p.steer_speed_low = float(d[9])
	p.steer_speed_high = float(d[10])
	p.handbrake_grip_mult = float(d[11])
	p.body_color = d[12]
	return p


## A CarProfile with the shared resized-car suspension + defaults applied.
static func _base_profile(curve: Curve) -> CarProfile:
	var p := CarProfile.new()
	p.engine_force_curve = curve
	p.suspension_rest = 0.21
	p.wheel_radius = 0.162
	# Stiff enough not to bottom out under the ~3x downforce a loop's centripetal
	# load imposes at speed. Softer springs let the chassis sink onto the road
	# mid-loop, so the body collider scraped and caught on the geometry (and the
	# wheels visibly clipped through). Damping tracks the stiffness to stay settled.
	p.spring_k = 110000.0
	p.damping = 8000.0
	p.brake_force = 20000.0
	p.reverse_force = 8000.0
	p.turn_responsiveness = 12.0
	p.handbrake_grip_mult = 0.25
	p.offtrack_speed_frac = 0.3
	p.offtrack_drag = 0.8
	p.gravity_blend_speed = 6.0
	p.align_gain = 6.0
	p.align_responsiveness = 8.0
	p.air_align_gain = 2.2
	p.air_align_responsiveness = 3.0
	return p


static func _kenney(d: Array, curve: Curve) -> CarProfile:
	var p := _base_profile(curve)
	p.display_name = d[1]
	p.tagline = d[2]
	p.body_color = d[9]
	p.model_scene = load(KENNEY % d[0])
	p.model_scale = MODEL_SCALE
	p.model_y_offset = MODEL_Y_OFFSET
	p.model_yaw = MODEL_YAW

	p.mass = float(d[3])
	p.engine_force = float(d[4])
	p.max_speed = float(d[5])
	p.grip = float(d[6])
	p.steer_speed_low = float(d[7])
	p.steer_speed_high = float(d[8])
	return p


static func _falloff_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.75, 0.6))
	c.add_point(Vector2(1.0, 0.0))
	return c
