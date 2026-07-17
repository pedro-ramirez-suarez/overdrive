class_name Atmosphere
extends RefCounted
## Time-of-day and weather for a race (SPEC.md §M6). Builds the sky, sun and fog,
## and spawns falling rain/snow. Chosen on the track-select screen and read from
## GameState; the same call drives the live preview and the race, so what you pick
## is what you drive.
##
## Weather layers ON TOP of the time of day: it desaturates the sky, dims the sun,
## adds fog and (for rain/snow) particles, but the base palette still comes from
## the hour. So "evening + rain" is a greyed, wet sunset, not a generic storm.

enum TimeOfDay { NOON, EVENING, NIGHT }
enum Weather { CLEAR, CLOUDY, RAIN, FOG, SNOW }

const TIME_NAMES: Array[String] = ["Noon", "Evening", "Night"]
const TIME_ICONS: Array[String] = ["noon", "evening", "night"]
const WEATHER_NAMES: Array[String] = ["Clear", "Cloudy", "Rain", "Fog", "Snow"]
const WEATHER_ICONS: Array[String] = ["clear", "cloudy", "rain", "fog", "snow"]


## Replace `parent`'s environment + sun with one built for `time`/`weather`, and
## add weather particles. Call once per world; safe to call on a fresh scene.
static func apply(parent: Node3D, time: int, weather: int) -> void:
	var env := WorldEnvironment.new()
	env.environment = _environment(time, weather)
	parent.add_child(env)

	var sun := DirectionalLight3D.new()
	_configure_sun(sun, time, weather)
	parent.add_child(sun)

	if weather == Weather.RAIN or weather == Weather.SNOW:
		var rig := WeatherRig.new()
		rig.snow = weather == Weather.SNOW
		parent.add_child(rig)

	if weather == Weather.CLOUDY:
		_add_clouds(parent)


# --- Clouds -----------------------------------------------------------------

## Scatter puffy clouds high over the map for the cloudy preset. Real geometry,
## because a ProceduralSky has no cloud layer — each cloud is a few squashed
## spheres clustered together, lit by the sun so they warm at evening. A fixed
## seed keeps them from jumping around between launches.
static func _add_clouds(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.98)
	mat.roughness = 1.0
	var root := Node3D.new()
	root.name = "Clouds"
	parent.add_child(root)

	for i in range(16):
		var cloud := Node3D.new()
		cloud.position = Vector3(
			rng.randf_range(-260.0, 260.0),
			rng.randf_range(75.0, 120.0),
			rng.randf_range(-260.0, 260.0))
		root.add_child(cloud)
		var puffs: int = rng.randi_range(3, 5)
		var r: float = rng.randf_range(14.0, 26.0)
		for j in range(puffs):
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = r * rng.randf_range(0.6, 1.0)
			sph.height = sph.radius * 2.0
			mi.mesh = sph
			mi.material_override = mat
			mi.position = Vector3(
				rng.randf_range(-r, r) * 1.3, rng.randf_range(-0.2, 0.2) * r, rng.randf_range(-r, r) * 0.7)
			mi.scale = Vector3(1.0, 0.45, 1.0)  # squash flat, like a cloud
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(mi)


# --- Sky + fog --------------------------------------------------------------

static func _environment(time: int, weather: int) -> Environment:
	var sky_top: Color
	var sky_horizon: Color
	var ground: Color
	match time:
		TimeOfDay.EVENING:
			# A gentle golden hour, not a travel-poster sunset.
			sky_top = Color(0.34, 0.30, 0.46)
			sky_horizon = Color(0.86, 0.66, 0.52)
			ground = Color(0.18, 0.15, 0.16)
		TimeOfDay.NIGHT:
			sky_top = Color(0.03, 0.04, 0.10)
			sky_horizon = Color(0.10, 0.12, 0.22)
			ground = Color(0.02, 0.03, 0.05)
		_:  # NOON
			sky_top = Color(0.24, 0.45, 0.85)
			sky_horizon = Color(0.62, 0.74, 0.86)
			ground = Color(0.16, 0.16, 0.20)

	# Each weather has its OWN look, not just more fog:
	#   cloudy — flat mid-grey, clear air (no fog), softly lit
	#   rain   — dark charcoal, a little haze, downpour
	#   fog    — pale whiteout, the sky barely visible
	#   snow   — bright white overcast, a little haze, falling snow
	# `flatten` pulls the sky's top toward its horizon so an overcast day is a
	# uniform lid rather than the clear-day blue gradient.
	var overcast := Color(0.55, 0.57, 0.60)
	var grey := 0.0
	var darken := 1.0
	var flatten := 0.0
	match weather:
		Weather.CLOUDY:
			# Barely touched — cloudy is a clear sky with clouds ADDED as geometry
			# (see _add_clouds), not a grey lid.
			grey = 0.12; darken = 0.96; flatten = 0.15
		Weather.RAIN:
			overcast = Color(0.30, 0.32, 0.36); grey = 0.85; darken = 0.7; flatten = 0.9
		Weather.FOG:
			overcast = Color(0.78, 0.80, 0.82); grey = 0.92; darken = 1.0; flatten = 1.0
		Weather.SNOW:
			overcast = Color(0.85, 0.87, 0.90); grey = 0.8; darken = 0.98; flatten = 0.9
	sky_top = sky_top.lerp(overcast, grey) * darken
	sky_horizon = sky_horizon.lerp(overcast, grey) * darken
	sky_top = sky_top.lerp(sky_horizon, flatten)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_horizon
	sky_mat.ground_bottom_color = ground
	sky_mat.ground_horizon_color = sky_horizon
	sky_mat.sun_angle_max = 40.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# Glow reads as bloom on the sunset and on wet roads; muted, so it never blows out.
	env.glow_enabled = true
	env.glow_intensity = 0.6 if time == TimeOfDay.NIGHT else 0.8
	env.glow_bloom = 0.05
	# Night is kept genuinely dark so it reads as night — bright ambient made it look
	# like an overcast noon, so the headlights seemed to switch on for no reason. Just
	# enough blue ambient to see the road; the moonlight and the cars' own lights do
	# the rest.
	env.ambient_light_color = sky_horizon
	env.ambient_light_energy = 0.45 if time == TimeOfDay.NIGHT else 1.0

	_apply_fog(env, time, weather, sky_horizon)
	return env


static func _apply_fog(env: Environment, _time: int, weather: int, tint: Color) -> void:
	# Cloudy is deliberately fog-FREE — its look is the grey sky, not haze. Fog is
	# the fog preset's whole identity, so it is far denser than the drizzle a rainy
	# or snowy day carries.
	var density := 0.0
	var fog_tint := tint
	match weather:
		Weather.RAIN:
			density = 0.010; fog_tint = Color(0.34, 0.36, 0.40)
		Weather.SNOW:
			density = 0.012; fog_tint = Color(0.86, 0.88, 0.92)
		Weather.FOG:
			density = 0.10; fog_tint = Color(0.80, 0.82, 0.85)
	if density <= 0.0:
		return
	env.fog_enabled = true
	env.fog_light_color = fog_tint
	env.fog_density = density
	env.fog_sky_affect = 0.7 if weather == Weather.FOG else 0.15


# --- Sun --------------------------------------------------------------------

static func _configure_sun(sun: DirectionalLight3D, time: int, weather: int) -> void:
	var energy := 1.0
	match time:
		TimeOfDay.EVENING:
			sun.rotation = Vector3(deg_to_rad(-18), deg_to_rad(70), 0)  # low, from the side
			sun.light_color = Color(1.0, 0.84, 0.66)  # warm, not orange
			energy = 1.05
		TimeOfDay.NIGHT:
			sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)  # moonlight
			sun.light_color = Color(0.55, 0.63, 0.85)
			energy = 0.35
		_:  # NOON
			sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(40), 0)
			sun.light_color = Color(1.0, 0.97, 0.90)
			energy = 1.0

	# Overcast weather flattens the light and softens (or removes) the shadow.
	# Any overcast sky diffuses the light — no hard shadow. Cloudy keeps its shadow
	# (the sun shows between the clouds); only the truly grey skies lose it.
	var shadows := true
	match weather:
		Weather.CLOUDY: energy *= 0.9
		Weather.RAIN: energy *= 0.5; shadows = false
		Weather.FOG: energy *= 0.65; shadows = false
		Weather.SNOW: energy *= 0.85; shadows = false
	sun.light_energy = energy
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 200.0
