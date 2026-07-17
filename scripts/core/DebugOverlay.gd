class_name DebugOverlay
extends CanvasLayer
## Grounded/airborne physics debug readout (SPEC.md §M2, task 4).
##
## Shows the car's grounded state, up-axis, gravity direction, speed and road
## normal. Toggle with the backtick / tilde key (`~`).

## Path to the car to inspect. Resolved to `car` in _ready (a NodePath export
## resolves reliably from a saved scene; a typed-Node export does not).
@export var car_path: NodePath

@onready var _label: Label = $Label

var car: ArcadeCar


func _ready() -> void:
	if not car_path.is_empty():
		car = get_node_or_null(car_path) as ArcadeCar


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			visible = not visible


func _process(_delta: float) -> void:
	if not visible or car == null:
		return

	var up: Vector3 = car.global_transform.basis.y
	var speed: float = car.linear_velocity.length()
	var forward: Vector3 = -car.global_transform.basis.z
	var forward_speed: float = car.linear_velocity.dot(forward)

	_label.text = "\n".join([
		"[ ` toggles this overlay ]",
		"grounded : %s" % ("YES" if car.grounded else "no"),
		"speed    : %5.1f m/s  (fwd %5.1f)" % [speed, forward_speed],
		"up axis  : (%+.2f, %+.2f, %+.2f)" % [up.x, up.y, up.z],
		"gravity  : (%+.2f, %+.2f, %+.2f)" % [car.gravity_direction.x, car.gravity_direction.y, car.gravity_direction.z],
		"road nrml: (%+.2f, %+.2f, %+.2f)" % [car.surface_normal.x, car.surface_normal.y, car.surface_normal.z],
	])
