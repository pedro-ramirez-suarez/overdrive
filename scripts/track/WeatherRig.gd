class_name WeatherRig
extends Node3D
## Falling rain or snow that follows the camera, so precipitation is always around
## the player wherever they drive (SPEC.md §M6). A GPU particle box overhead emits
## downward; rain falls fast and thin, snow drifts slow and soft.

@export var snow: bool = false

var _particles: GPUParticles3D


func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 1400 if snow else 2200
	_particles.lifetime = 3.5 if snow else 1.1
	_particles.preprocess = _particles.lifetime  # start already falling, no empty sky
	_particles.local_coords = false  # trails stay in the world as the rig moves
	# Without this the emitter's default AABB is tiny and, because it moves with the
	# camera, the whole system gets frustum-culled and never draws — which is why
	# the rain and snow were invisible. A big box keeps it always rendering.
	_particles.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	_particles.draw_pass_1 = _mesh()
	_particles.process_material = _process_material()
	add_child(_particles)


func _process(_delta: float) -> void:
	# Sit near whatever camera is rendering this world — the race chase cam, or the
	# preview's own camera in its SubViewport. Rain falls fast from a high lid; snow
	# drifts slowly, so it is emitted from a tall volume centred near the camera,
	# otherwise it never falls far enough to enter the view before it expires.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position + Vector3(0.0, 6.0 if snow else 18.0, 0.0)


func _mesh() -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if snow else BaseMaterial3D.BILLBOARD_DISABLED
	if snow:
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.22)
		q.material = mat
		mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		return q
	# Rain: a bright, fairly long vertical streak — has to read against a dark road.
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 1.1, 0.035)
	box.material = mat
	mat.albedo_color = Color(0.80, 0.86, 0.98, 0.85)
	return box


func _process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 0.0
	if snow:
		# A TALL box around the camera, not a thin lid: slow flakes must already fill
		# the volume you are looking through, or they never drop into frame in time.
		m.emission_box_extents = Vector3(16.0, 12.0, 16.0)
		m.gravity = Vector3(0.0, -4.5, 0.0)
		m.initial_velocity_min = 1.5
		m.initial_velocity_max = 2.5
		# Drift sideways so flakes wander instead of dropping like plumb lines.
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 3.0
		m.turbulence_noise_scale = 1.5
		m.scale_min = 0.7
		m.scale_max = 1.6
	else:
		m.emission_box_extents = Vector3(18.0, 0.5, 18.0)
		m.gravity = Vector3(0.0, -60.0, 0.0)
		m.initial_velocity_min = 18.0
		m.initial_velocity_max = 22.0
	return m
