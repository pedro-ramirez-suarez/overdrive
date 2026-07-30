extends Node3D
## Test-drive runtime for an edited track (SPEC.md §M3). Builds the current
## GameState grid into a drivable world, spawns the car at the start tile, and
## returns to the editor on Escape.

const EDITOR_SCENE := "res://scenes/editor/Editor.tscn"
const CAR_SCENE := "res://scenes/vehicle/Car.tscn"

var _car: ArcadeCar


func _ready() -> void:
	var grid: TrackGrid = GameState.current_grid
	var lib: TileLibrary = GameState.library
	TrackWorld.populate(self, grid, lib)
	_spawn_car(grid, lib)
	_add_camera()
	_add_hud()


func _spawn_car(grid: TrackGrid, lib: TileLibrary) -> void:
	var spawn_pos := Vector3(0, 1.5, 0)
	var start_cell: Vector2i = lib.find_start_cell(grid)
	if start_cell.x != 2147483647:
		spawn_pos = TileLibrary.cell_to_world(start_cell, grid.tiles[start_cell].elevation_level) + Vector3(0, 1.5, 0)
	elif not grid.tiles.is_empty():
		var any_cell: Vector2i = grid.tiles.keys()[0]
		spawn_pos = TileLibrary.cell_to_world(any_cell, grid.tiles[any_cell].elevation_level) + Vector3(0, 1.5, 0)

	_car = load(CAR_SCENE).instantiate()
	_car.name = "Car"
	if GameState.selected_car != null:
		_car.profile = GameState.selected_car
		_car.get_node("Visual").set("body_color", GameState.selected_car.body_color)
	_car.position = spawn_pos
	add_child(_car)


func _add_camera() -> void:
	var cam := Camera3D.new()
	cam.set_script(load("res://scripts/vehicle/ChaseCamera.gd"))
	cam.current = true
	cam.set("target_path", NodePath("../Car"))
	cam.position = Vector3(0, 4, 12)
	add_child(cam)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "Esc: back to editor    R: reset car    Space: handbrake    ` : debug"
	label.position = Vector2(12, 12)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)

	# Same speedometer as the race, bottom-left. The hint sits top-left, so the two
	# don't collide here.
	var speedo := Speedometer.new()
	speedo.car = _car
	speedo.anchor_top = 1.0
	speedo.anchor_bottom = 1.0
	speedo.offset_left = 16
	speedo.offset_top = -184
	speedo.offset_bottom = -16
	layer.add_child(speedo)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(EDITOR_SCENE)
