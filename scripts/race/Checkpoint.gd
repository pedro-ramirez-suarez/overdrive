class_name Checkpoint
extends Area3D
## An ordered gate along the track (SPEC.md §M4). A tall column over one cell so
## it catches the car at any elevation (including through a loop). Emits `passed`
## when a car body enters.

signal passed(index: int, body: Node3D)
signal exited(index: int, body: Node3D)

var index: int = 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Constants.CAR_BIT
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(body: Node3D) -> void: exited.emit(index, body))


## Configure before adding to the tree.
func setup(p_index: int, world_pos: Vector3, cell_size: float) -> void:
	index = p_index
	position = world_pos
	var shape := BoxShape3D.new()
	shape.size = Vector3(cell_size, 30.0, cell_size)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 13.0, 0)  # spans ~ -2 .. 28 m above the cell
	add_child(cs)


func _on_body_entered(body: Node3D) -> void:
	passed.emit(index, body)
