class_name CarFX
extends Node3D
## Tyre dust particles (SPEC.md §M6 polish). Emits from the rear of the car while
## drifting, braking hard, or driving off-track.

var _car: ArcadeCar
var _dust: CPUParticles3D


func _ready() -> void:
	_car = get_parent() as ArcadeCar
	_dust = CPUParticles3D.new()
	_dust.amount = 20
	_dust.lifetime = 0.6
	_dust.emitting = false
	_dust.local_coords = false
	_dust.position = Vector3(0.0, 0.05, 0.55)  # behind the rear axle

	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.72, 0.66, 0.55, 0.45)
	quad.material = mat
	_dust.mesh = quad

	_dust.direction = Vector3(0.0, 1.0, 0.0)
	_dust.spread = 45.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.5
	_dust.gravity = Vector3(0.0, -1.5, 0.0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.6
	_dust.color = Color(0.72, 0.66, 0.55, 0.45)
	add_child(_dust)


func _process(_delta: float) -> void:
	if _car == null:
		return
	var active := false
	if _car.grounded:
		var lateral: float = absf(_car.linear_velocity.dot(_car.global_transform.basis.x))
		var moving: bool = _car.linear_velocity.length() > 3.0
		active = _car.handbrake or lateral > 4.0 or (not _car.on_track and moving)
	_dust.emitting = active
