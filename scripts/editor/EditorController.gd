class_name EditorController
extends Node3D
## Minimal modular-track editor (SPEC.md §M3).
##
## Orbit/pan/zoom camera over a grid, a palette of tile definitions, place /
## delete / rotate / raise / lower at the hovered cell with live green/yellow/red
## connection feedback, and a Test Drive button that loads the built track into
## a playable scene. The world and UI are built in code in _ready.

const PLAY_SCENE := "res://scenes/race/TrackPlay.tscn"
const RACE_SCENE := "res://scenes/race/Race.tscn"
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const GRID_EXTENT := 64  # cells drawn each side of origin
## Ceiling for the Z/X camera lift — clear of the tallest possible terrain.
const CAM_MAX_HEIGHT := 400.0

## What a left-click does. TILE places the selected piece and PROP the selected
## scenery; the rest work on the terrain square under the cursor (SimCity-style).
## LEVEL flattens to an absolute target height, for slicing a hill off at a chosen
## level. LAKE floods a square.
enum Tool { TILE, RAISE, LOWER, LEVEL, LAKE, PROP, ERASE }

var _library: TileLibrary
var _grid: TrackGrid

var _tool: Tool = Tool.TILE
var _def_index: int = 0
## Selected scenery kind + shape. Clicking the same cell again cycles the shape,
## exactly as clicking a placed curve again cycles its rotation.
var _prop_kind: int = PropGeo.Kind.TREE
var _prop_variant: int = 0
## Target height for the LEVEL tool, in elevation levels.
var _level_target: int = 0
## Cells already sculpted during the current drag — each gets one application per
## stroke, so dragging back over ground you just raised doesn't raise it again.
var _drag_cells: Dictionary = {}
var _dragging: bool = false
var _rotation: int = 0
## Manual elevation offset added on top of the terrain height (raise/lower).
var _elevation: int = 0
var _hovered_cell: Vector2i = Vector2i.ZERO
var _terrain_root: Node3D
var _terrain_type: int = -1  # -1 = flat
var _terrain_dirty: bool = false
var _terrain_timer: float = 0.0

# World nodes.
var _camera_pivot: Node3D
var _camera: Camera3D
var _tiles_root: Node3D
var _props_root: Node3D
var _ghost_root: Node3D
var _ghost_instance: Node3D
var _ghost_footprint: MeshInstance3D
var _ghost_key: Array = []

# Camera state.
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.95
var _cam_distance: float = 44.0
var _pivot_pos: Vector3 = Vector3.ZERO

# UI.
var _status_label: Label
var _save_label: Label
var _save_timer: float = 0.0
var _name_edit: LineEdit
## Where the current track came from, or "" if it was never loaded/saved. Drives
## whether Import is offered.
var _loaded_path: String = ""
var _import_btn: Button
var _ui_layer: CanvasLayer
var _palette_buttons: Array[Button] = []
var _tool_buttons: Dictionary = {}     # Tool -> Button
var _terrain_buttons: Dictionary = {}  # Terrain.Type -> Button
var _prop_buttons: Dictionary = {}     # PropGeo.Kind -> Button

# Placed tile instances by cell.
var _placed_nodes: Dictionary = {}
# Placed prop instances by cell.
var _prop_nodes: Dictionary = {}

# Undo/redo: whole-track snapshots (the dict `TrackSerializer.to_dict` produces).
# Snapshotting the entire track per edit is cheap here and sidesteps having to
# invert every kind of edit — a restore just reloads and rebuilds. One snapshot is
# taken per action (or per drag stroke) BEFORE it mutates anything.
const UNDO_LIMIT := 60
var _undo_stack: Array = []
var _redo_stack: Array = []


func _ready() -> void:
	_library = GameState.library
	_grid = GameState.current_grid

	randomize()
	# A fresh track (or one saved before terrain existed) starts on the flat
	# preset, so the sculpt tools work straight away. Deliberately NOT via
	# _select_terrain: that re-drapes, which would reset every tile's elevation on
	# a loaded track. Flat is level 0 everywhere, which is exactly what a null
	# terrain already reported, so nothing moves.
	if GameState.current_terrain == null:
		var flat := Terrain.new()
		flat.setup(Terrain.Type.FLAT, 0)
		GameState.current_terrain = flat
	_terrain_type = GameState.current_terrain.type
	_build_world()
	_build_ui()
	_rebuild_terrain()
	_rebuild_all_tiles()
	_rebuild_all_props()
	_refresh_palette_highlight()
	_update_status()


# --- Terrain ----------------------------------------------------------------

func _terrain_level(cell: Vector2i) -> int:
	return GameState.current_terrain.height_level(cell) if GameState.current_terrain != null else 0


func _effective_elevation(cell: Vector2i) -> int:
	return _terrain_level(cell) + _elevation


## Switch terrain preset. Re-picking the preset you are already on does nothing —
## it would build a fresh Terrain and silently throw away any sculpting. Re-roll
## (which passes force) is how you ask for a new seed.
func _select_terrain(type_index: int, force: bool = false) -> void:
	if not force and type_index == _terrain_type and GameState.current_terrain != null:
		return
	_push_undo()
	_terrain_type = type_index
	var terrain := Terrain.new()
	terrain.setup(type_index, randi())
	GameState.current_terrain = terrain
	_redrape_track()
	_rebuild_terrain()
	_rebuild_all_tiles()
	_reseat_props()
	_refresh_palette_highlight()


## Snap every placed tile's elevation to the terrain height at its cell.
func _redrape_track() -> void:
	for cell in _grid.tiles:
		(_grid.tiles[cell] as PlacedTile).elevation_level = _terrain_level(cell)


func _rebuild_terrain() -> void:
	if _terrain_root != null:
		_terrain_root.queue_free()
	_terrain_root = Node3D.new()
	add_child(_terrain_root)
	if GameState.current_terrain != null:
		# Fill the whole editor grid (plus a little beyond for panning). No
		# collision — there's no car in the editor, so skip that cost.
		var e := GRID_EXTENT + 4
		TerrainWorld.build_region(_terrain_root, GameState.current_terrain, _grid, Vector2i(-e, -e), Vector2i(e, e), false)


# --- World & UI construction ------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/default_env.tres")
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(40), 0)
	sun.shadow_enabled = true
	add_child(sun)

	_camera_pivot = Node3D.new()
	add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera_pivot.add_child(_camera)

	_build_grid_lines()

	_tiles_root = Node3D.new()
	_tiles_root.name = "TilesRoot"
	add_child(_tiles_root)

	_props_root = Node3D.new()
	_props_root.name = "PropsRoot"
	add_child(_props_root)

	_ghost_root = Node3D.new()
	_ghost_root.name = "GhostRoot"
	add_child(_ghost_root)

	_ghost_footprint = MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(Constants.CELL_SIZE, 0.2, Constants.CELL_SIZE)
	_ghost_footprint.mesh = quad
	var fmat := StandardMaterial3D.new()
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(0, 1, 0, 0.35)
	# Draw through the world. This is a cursor: it has to be findable even when the
	# thing it marks is inside a hill (levelling a peak down to a sampled height) or
	# behind one. Standard editor-gizmo behaviour, and it also lets the level tool
	# show the slab it is about to cut away.
	fmat.no_depth_test = true
	fmat.render_priority = 1
	_ghost_footprint.material_override = fmat
	_ghost_root.add_child(_ghost_footprint)

	_update_camera_transform()


func _build_grid_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var half: float = Constants.CELL_SIZE * 0.5
	var span: float = GRID_EXTENT * Constants.CELL_SIZE
	for i in range(-GRID_EXTENT, GRID_EXTENT + 1):
		var o: float = i * Constants.CELL_SIZE + half
		st.add_vertex(Vector3(o, 0, -span))
		st.add_vertex(Vector3(o, 0, span))
		st.add_vertex(Vector3(-span, 0, o))
		st.add_vertex(Vector3(span, 0, o))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.45, 0.5, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui_layer = layer
	add_child(layer)

	# Palette panel (top-left).
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	vbox.add_child(_section("TILES"))
	var tile_grid := _icon_grid()
	vbox.add_child(tile_grid)
	for i in range(_library.ordered.size()):
		var def: TileDefinition = _library.ordered[i]
		var btn := _icon_button(String(def.id), def.display_name)
		btn.toggle_mode = true
		var idx := i
		btn.pressed.connect(func() -> void: _select_def(idx))
		tile_grid.add_child(btn)
		_palette_buttons.append(btn)

	vbox.add_child(_section("SCENERY"))
	var prop_grid := _icon_grid()
	vbox.add_child(prop_grid)
	for k in range(PropGeo.KIND_IDS.size()):
		var kind := k
		var pb := _icon_button(PropGeo.KIND_IDS[k],
			"%s — click again to cycle shape, T rotates, Del removes" % PropGeo.KIND_NAMES[k])
		pb.toggle_mode = true
		pb.pressed.connect(func() -> void: _select_prop(kind))
		prop_grid.add_child(pb)
		_prop_buttons[k] = pb

	vbox.add_child(_section("TERRAIN"))
	var terr_grid := _icon_grid()
	vbox.add_child(terr_grid)
	# Flat leads: it is the blank canvas the sculpt tools build from. (The enum
	# itself keeps FLAT last, for save compatibility.)
	for ti in [Terrain.Type.FLAT, Terrain.Type.PLAINS, Terrain.Type.HILLS,
			Terrain.Type.LAKES, Terrain.Type.MOUNTAINS]:
		var tip: String = "Flat — level ground to sculpt" if ti == Terrain.Type.FLAT else Terrain.TYPE_NAMES[ti]
		var tb := _terrain_button(Terrain.TYPE_NAMES[ti].to_lower(), tip, ti)
		terr_grid.add_child(tb)
		_terrain_buttons[ti] = tb
	var reroll := _icon_button("reroll", "Re-roll terrain (discards sculpting)")
	reroll.pressed.connect(func() -> void: _select_terrain(_terrain_type, true))
	terr_grid.add_child(reroll)

	vbox.add_child(_section("TOOLS"))
	var tool_grid := _icon_grid()
	vbox.add_child(tool_grid)
	for spec in [[Tool.ERASE, "erase", "Erase — click or drag to remove track pieces and scenery"],
			[Tool.RAISE, "raise", "Raise terrain — click or drag to lift squares one level"],
			[Tool.LOWER, "lower", "Lower terrain — click or drag to drop squares one level"],
			[Tool.LEVEL, "level", "Level terrain — flatten squares to a set height.\nRight-click a square to sample its height, PgUp/PgDn to adjust."],
			[Tool.LAKE, "lake", "Lake — flood flat squares at any height.\nNeeds a basin, so it won't go on a slope or an edge. Del removes."]]:
		var tool: Tool = spec[0]
		var tb := _icon_button(spec[1], spec[2])
		tb.toggle_mode = true
		tb.pressed.connect(func() -> void: _select_tool(tool))
		tool_grid.add_child(tb)
		_tool_buttons[tool] = tb

	# Actions (top-right), icon-only in a row. Pinned to the right edge with ZERO
	# width, so its own minimum size sizes it and it grows leftward — a fixed width
	# silently pushes buttons off-screen the moment one is added, and no window size
	# can bring them back.
	var actions := HBoxContainer.new()
	actions.anchor_left = 1.0
	actions.anchor_right = 1.0
	actions.offset_left = -12
	actions.offset_right = -12
	actions.offset_top = 12
	actions.offset_bottom = 12
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.grow_vertical = Control.GROW_DIRECTION_END
	layer.add_child(actions)

	var load_btn := _icon_button("load", "Load a track file from disk")
	load_btn.pressed.connect(_open_load_dialog)
	actions.add_child(load_btn)

	_import_btn = _icon_button("import", "Import into your track library")
	_import_btn.pressed.connect(_import_track)
	actions.add_child(_import_btn)

	var test_btn := _icon_button("test", "Test Drive")
	test_btn.pressed.connect(_start_test_drive)
	actions.add_child(test_btn)

	var race_btn := _icon_button("race", "Race")
	race_btn.pressed.connect(_start_race)
	actions.add_child(race_btn)

	var save_btn := _icon_button("save", "Save Track")
	save_btn.pressed.connect(_save_track)
	actions.add_child(save_btn)

	var menu_btn := _icon_button("menu", "Main Menu")
	menu_btn.pressed.connect(func() -> void:
		GameState.current_grid = _grid
		get_tree().change_scene_to_file(MENU_SCENE))
	actions.add_child(menu_btn)
	_refresh_import_button()

	_name_edit = LineEdit.new()
	_name_edit.text = GameState.current_track_name
	_name_edit.placeholder_text = "Track name"
	_name_edit.anchor_left = 1.0
	_name_edit.anchor_right = 1.0
	_name_edit.offset_left = -160
	_name_edit.offset_right = -12
	_name_edit.offset_top = 64
	_name_edit.offset_bottom = 92
	layer.add_child(_name_edit)

	_save_label = Label.new()
	_save_label.anchor_left = 0.5
	_save_label.anchor_right = 0.5
	_save_label.offset_left = -220
	_save_label.offset_right = 220
	_save_label.offset_top = 12
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_save_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_save_label)

	# Status (bottom-left).
	_status_label = Label.new()
	_status_label.anchor_top = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.offset_left = 12
	_status_label.offset_top = -96
	_status_label.offset_bottom = -12
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status_label)

	# Help (bottom-right).
	var help := Label.new()
	help.text = "Mouse/keys — Orbit: middle-drag or Q/E   Pan: WASD   Up/Down: Z/X   Zoom: wheel   Place: click   Delete: Del   Rotate: T   Undo: Ctrl+Z   Redo: Ctrl+Y\nController — Move: L-stick   Pan: R-stick   Orbit: LB/RB   Zoom: triggers   Place: A   Delete: X   Rotate: B   Piece: D-pad ◄►   Tool: Y   Elevation: D-pad ▲▼"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.anchor_left = 1.0
	help.anchor_right = 1.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = -520
	help.offset_top = -56
	help.offset_right = -12
	help.offset_bottom = -12
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	layer.add_child(help)


# --- Per-frame update -------------------------------------------------------

func _process(delta: float) -> void:
	_handle_controller(delta)
	_handle_pan(delta)
	# The controller drives the cell cursor directly; only fall back to the mouse
	# ray-pick when the controller isn't steering.
	if not _pad_cursor:
		_update_hovered_cell()
	# Paint while the button is held. Gated on _dragging (set only by a press that
	# reached the 3D view) so a click on a palette button never starts a stroke.
	if _dragging and _tool != Tool.TILE and _tool != Tool.PROP:
		_apply_tool_at(_hovered_cell)
	_update_ghost()
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_label.text = ""
	if _terrain_dirty:
		_terrain_timer -= delta
		if _terrain_timer <= 0.0:
			_terrain_dirty = false
			_rebuild_terrain()
			_reseat_props()


# --- Controller ------------------------------------------------------------
# Xbox-style pad: left stick moves the cell cursor, D-pad left/right cycles the
# selected piece, Y cycles the tool, A places, X deletes, B rotates, D-pad up/down
# raises/lowers, bumpers orbit, triggers zoom, right stick pans. (Face buttons and
# elevation come through the action map; the rest is read here.)

const PAD := 0  # first connected device
var _pad_cursor := false
var _pad_move_cd := 0.0
var _pad_dpad_l := false
var _pad_dpad_r := false
var _pad_y := false


func _handle_controller(delta: float) -> void:
	# Left stick steps the cursor one cell at a time, repeating while held, in the
	# camera's facing frame so "up" always moves away from the view.
	var stick := Vector2(
		Input.get_joy_axis(PAD, JOY_AXIS_LEFT_X), Input.get_joy_axis(PAD, JOY_AXIS_LEFT_Y))
	_pad_move_cd -= delta
	if stick.length() > 0.55:
		if _pad_move_cd <= 0.0:
			var world: Vector3 = Basis(Vector3.UP, _cam_yaw) * Vector3(stick.x, 0.0, stick.y)
			var d: Vector2i
			if absf(world.x) > absf(world.z):
				d = Vector2i(1 if world.x > 0.0 else -1, 0)
			else:
				d = Vector2i(0, 1 if world.z > 0.0 else -1)
			_hovered_cell += d
			_pad_cursor = true
			_pad_move_cd = 0.14
	else:
		_pad_move_cd = 0.0

	# D-pad left/right cycles the selected piece; Y cycles the tool. Edge-detected
	# so one press is one step.
	var dl := Input.is_joy_button_pressed(PAD, JOY_BUTTON_DPAD_LEFT)
	var dr := Input.is_joy_button_pressed(PAD, JOY_BUTTON_DPAD_RIGHT)
	if dr and not _pad_dpad_r:
		_cycle_selection(1)
	if dl and not _pad_dpad_l:
		_cycle_selection(-1)
	_pad_dpad_l = dl
	_pad_dpad_r = dr

	var y := Input.is_joy_button_pressed(PAD, JOY_BUTTON_Y)
	if y and not _pad_y:
		_cycle_tool()
	_pad_y = y


## Cycle the current tool's selectable variant — tile pieces and scenery kinds.
func _cycle_selection(dir: int) -> void:
	if _tool == Tool.TILE:
		_select_def(posmod(_def_index + dir, _library.ordered.size()))
	elif _tool == Tool.PROP:
		var n: int = PropGeo.KIND_IDS.size()
		_prop_kind = posmod(_prop_kind + dir, n)
		_prop_variant = 0
		_tool = Tool.PROP
		_refresh_palette_highlight()
		_update_status()


## Step through the tools with the Y button.
func _cycle_tool() -> void:
	var order := [Tool.TILE, Tool.PROP, Tool.ERASE, Tool.RAISE, Tool.LOWER, Tool.LEVEL, Tool.LAKE]
	var next: int = order[posmod(order.find(_tool) + 1, order.size())]
	if next == Tool.TILE:
		_select_def(_def_index)
	elif next == Tool.PROP:
		_select_prop(_prop_kind)
	else:
		_select_tool(next)


## Right-click / B / T: change the selected shape without drawing — rotate a tile,
## cycle a prop's shape, or sample a height for the level tool.
func _cycle_shape() -> void:
	if _tool == Tool.LEVEL:
		_level_target = _terrain_level(_hovered_cell)
	elif _tool == Tool.PROP:
		_prop_variant = (_prop_variant + 1) % PropGeo.VARIANTS
	else:
		_rotation = (_rotation + 1) % 4
	_update_status()


func _handle_pan(delta: float) -> void:
	# Q / E and the shoulder buttons orbit the camera left / right.
	var yaw_input := 0.0
	if Input.is_physical_key_pressed(KEY_Q): yaw_input += 1.0
	if Input.is_physical_key_pressed(KEY_E): yaw_input -= 1.0
	if Input.is_joy_button_pressed(PAD, JOY_BUTTON_LEFT_SHOULDER): yaw_input += 1.0
	if Input.is_joy_button_pressed(PAD, JOY_BUTTON_RIGHT_SHOULDER): yaw_input -= 1.0
	if yaw_input != 0.0:
		_cam_yaw += yaw_input * 1.6 * delta
		_update_camera_transform()

	# Triggers zoom: right trigger in, left trigger out.
	var rt := Input.get_joy_axis(PAD, JOY_AXIS_TRIGGER_RIGHT)
	var lt := Input.get_joy_axis(PAD, JOY_AXIS_TRIGGER_LEFT)
	if rt > 0.12:
		_cam_distance = clampf(_cam_distance * (1.0 - rt * delta * 1.8), 8.0, 700.0)
		_update_camera_transform()
	if lt > 0.12:
		_cam_distance = clampf(_cam_distance * (1.0 + lt * delta * 1.8), 8.0, 700.0)
		_update_camera_transform()

	# Z / X lift the camera straight up and down — in world space, not the camera's
	# frame, so it stays predictable whatever way the view is turned.
	var lift := 0.0
	if Input.is_physical_key_pressed(KEY_Z): lift += 1.0
	if Input.is_physical_key_pressed(KEY_X): lift -= 1.0
	if lift != 0.0:
		_pivot_pos.y = clampf(_pivot_pos.y + lift * _cam_distance * delta, -20.0, CAM_MAX_HEIGHT)
		_update_camera_transform()

	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): move.x += 1.0
	# Right stick pans too, proportionally.
	var rs := Vector2(
		Input.get_joy_axis(PAD, JOY_AXIS_RIGHT_X), Input.get_joy_axis(PAD, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.2:
		move += Vector3(rs.x, 0.0, rs.y)
	if move == Vector3.ZERO:
		return
	# Move in the camera's horizontal facing frame. limit_length (not normalize) so
	# the analog stick gives proportional speed while keys give full speed.
	var yaw := Basis(Vector3.UP, _cam_yaw)
	_pivot_pos += yaw * move.limit_length(1.0) * _cam_distance * delta
	_update_camera_transform()


func _update_hovered_cell() -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.00001:
		return
	# Intersect a ground plane, then re-intersect at the height of whatever cell
	# that landed on, and repeat until it settles. A single intersection at y=0
	# picks the wrong cell — badly so on tall terrain with the camera tilted,
	# since a 39 m peak is nearly five cells of parallax.
	var cell := Vector2i(2147483647, 2147483647)
	var plane_y: float = _elevation * Constants.ELEVATION_STEP
	for _i in 4:
		var t: float = (plane_y - from.y) / dir.y
		if t <= 0.0:
			return
		var hit: Vector3 = from + dir * t
		var next := Vector2i(roundi(hit.x / Constants.CELL_SIZE), roundi(hit.z / Constants.CELL_SIZE))
		if next == cell:
			break
		cell = next
		plane_y = _effective_elevation(cell) * Constants.ELEVATION_STEP
	if cell.x != 2147483647:
		_hovered_cell = cell


func _update_ghost() -> void:
	if _tool == Tool.PROP:
		_update_prop_ghost()
		return
	if _tool != Tool.TILE:
		_update_sculpt_ghost()
		return

	var def := _current_def()
	if def == null:
		return

	# Rebuild the preview mesh only when the tile type or rotation changes.
	var key := [def.id, _rotation]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost_instance != null:
			_ghost_instance.queue_free()
		_ghost_instance = def.mesh.instantiate()
		_ghost_root.add_child(_ghost_instance)

	var elev := _effective_elevation(_hovered_cell)
	var xform := TileLibrary.tile_transform(_hovered_cell, _rotation, elev)
	if _ghost_instance != null:
		_ghost_instance.transform = xform

	# Footprint indicator covers all cells the (possibly multi-cell) tile occupies.
	var cells := TrackGrid.footprint_cells(_hovered_cell, def, _rotation)
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var centre := Vector3((lo.x + hi.x) * 0.5 * Constants.CELL_SIZE, elev * Constants.ELEVATION_STEP + 0.15, (lo.y + hi.y) * 0.5 * Constants.CELL_SIZE)
	_ghost_footprint.position = centre
	_ghost_footprint.scale = Vector3(hi.x - lo.x + 1, 1.0, hi.y - lo.y + 1)

	var result := PlacementValidator.validate(_grid, _hovered_cell, def, _rotation, elev)
	var color := _status_color(result.status)
	color.a = 0.35
	(_ghost_footprint.material_override as StandardMaterial3D).albedo_color = color
	_update_status(result)


## Preview the selected scenery on the ground under the cursor, with the footprint
## square green/red for whether it can be built there.
func _update_prop_ghost() -> void:
	var key: Array = [_prop_kind, _prop_variant, _rotation]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost_instance != null:
			_ghost_instance.queue_free()
		var preview := PropGeo.new()
		preview.kind = _prop_kind as PropGeo.Kind
		preview.variant = _prop_variant
		_ghost_instance = preview
		_ghost_root.add_child(preview)

	var preview_prop := PlacedProp.make(_prop_kind, _prop_variant, _rotation)
	var xf := TrackWorld.prop_transform(_hovered_cell, preview_prop, GameState.current_terrain)
	if _ghost_instance != null:
		_ghost_instance.position = xf.position
		_ghost_instance.rotation = xf.rotation
		_ghost_instance.scale = xf.scale

	# Cover the whole plot the prop reserves, not just one cell.
	var cells := TrackGrid.prop_cells(_hovered_cell, _prop_kind, _rotation)
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var level := _terrain_level(_hovered_cell)
	_ghost_footprint.position = Vector3(
		(lo.x + hi.x) * 0.5 * Constants.CELL_SIZE,
		level * Constants.ELEVATION_STEP + 0.15,
		(lo.y + hi.y) * 0.5 * Constants.CELL_SIZE)
	_ghost_footprint.scale = Vector3(hi.x - lo.x + 1, 1.0, hi.y - lo.y + 1)
	var color: Color = Color(0.2, 0.9, 0.3) if _prop_blocker(_hovered_cell) == "" else Color(0.95, 0.25, 0.2)
	color.a = 0.35
	(_ghost_footprint.material_override as StandardMaterial3D).albedo_color = color
	_update_status()


## Sculpt cursor: drop the tile preview and mark the single square under the
## cursor, sitting on the ground at its current height.
func _update_sculpt_ghost() -> void:
	if _ghost_instance != null:
		_ghost_instance.queue_free()
		_ghost_instance = null
		_ghost_key = []

	# The marker is a COLUMN spanning the cut height and the ground, not a plate at
	# one height: with the level tool the target is usually below the hill you are
	# cutting, and a plate down there is simply buried inside it. Spanning both (and
	## drawing through terrain, see _build_world) keeps it visible whichever way the
	# cut goes, and the column reads as the slab being removed or filled in.
	var lo_lv := 0
	var hi_lv := 0
	var terrain: Terrain = GameState.current_terrain
	if terrain != null:
		lo_lv = Constants.MAX_TERRAIN_LEVEL
		for o in Terrain.CELL_CORNERS:
			var lv: int = terrain.corner_level(_hovered_cell.x + o.x, _hovered_cell.y + o.y)
			lo_lv = mini(lo_lv, lv)
			hi_lv = maxi(hi_lv, lv)
	if _tool == Tool.LEVEL:
		lo_lv = mini(lo_lv, _level_target)
		hi_lv = maxi(hi_lv, _level_target)

	# Top clears the cell's HIGHEST corner, so a sloped square can't swallow it.
	var lo: float = lo_lv * Constants.ELEVATION_STEP
	var hi: float = hi_lv * Constants.ELEVATION_STEP + 0.2
	_ghost_footprint.position = Vector3(
		_hovered_cell.x * Constants.CELL_SIZE, (lo + hi) * 0.5, _hovered_cell.y * Constants.CELL_SIZE)
	_ghost_footprint.scale = Vector3(1.0, (hi - lo) / 0.2, 1.0)  # box mesh is 0.2 tall

	var color: Color = Color(1.0, 0.82, 0.25) if _tool == Tool.LEVEL else Color(0.3, 0.8, 1.0)
	if _tool == Tool.ERASE:
		# Bright only over something removable, so it is obvious when a click bites.
		var has_something: bool = _grid.get_anchor(_hovered_cell) != TrackGrid.NONE \
			or _grid.has_prop(_hovered_cell)
		color = Color(0.95, 0.25, 0.2) if has_something else Color(0.5, 0.5, 0.55)
	elif _tool == Tool.LAKE:
		# Red where the square can't hold water, so the rule is visible before you
		# click rather than only as a rejection message afterwards.
		var blocked: bool = terrain == null or (
			not terrain.has_lake(_hovered_cell) and terrain.lake_blocker(_hovered_cell) != "")
		color = Color(0.95, 0.25, 0.2) if blocked else Color(0.15, 0.55, 0.95)
	if terrain == null:
		color = Color(0.95, 0.25, 0.2)
	color.a = 0.35
	(_ghost_footprint.material_override as StandardMaterial3D).albedo_color = color
	_update_status()


# --- Undo / redo ------------------------------------------------------------

## Capture the current track and push it as an undo point. Call BEFORE mutating.
## Clears the redo stack, since a fresh edit forks history.
func _push_undo() -> void:
	_undo_stack.append(TrackSerializer.to_dict(_grid, _library, GameState.current_track_name, "player"))
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _undo() -> void:
	if _undo_stack.is_empty():
		_flash("Nothing to undo.")
		return
	_redo_stack.append(TrackSerializer.to_dict(_grid, _library, GameState.current_track_name, "player"))
	_restore(_undo_stack.pop_back())
	_flash("Undo")


func _redo() -> void:
	if _redo_stack.is_empty():
		_flash("Nothing to redo.")
		return
	_undo_stack.append(TrackSerializer.to_dict(_grid, _library, GameState.current_track_name, "player"))
	_restore(_redo_stack.pop_back())
	_flash("Redo")


## Replace the live track with a snapshot and rebuild the world from it.
func _restore(snapshot: Dictionary) -> void:
	var result := TrackSerializer.from_dict(snapshot, _library)
	_grid = result.grid
	GameState.current_grid = _grid
	GameState.current_terrain = result.get("terrain", null)
	_terrain_type = GameState.current_terrain.type if GameState.current_terrain != null else Terrain.Type.FLAT
	_rebuild_terrain()
	_rebuild_all_tiles()
	_rebuild_all_props()
	_refresh_palette_highlight()
	_update_status()


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y before anything else. GUI-focused events (e.g.
	# typing in the name field) never reach _unhandled_input, so this is safe.
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			_redo() if event.shift_pressed else _undo()
			return
		if event.keycode == KEY_Y:
			_redo()
			return

	if event is InputEventMouseMotion:
		_pad_cursor = false  # a mouse move takes the cursor back from the controller
		if (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_cam_yaw -= event.relative.x * 0.005
			_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.005, -1.45, -0.1)
			_update_camera_transform()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_distance = clampf(_cam_distance * 0.9, 8.0, 700.0)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_distance = clampf(_cam_distance * 1.1, 8.0, 700.0)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cycle_shape()

	if event.is_action_pressed("place"):
		if _tool == Tool.TILE:
			_place_tile()
		elif _tool == Tool.PROP:
			_place_prop()
		else:
			# Start a stroke; _process paints the rest as the cursor moves. One undo
			# snapshot per stroke, taken here before the first cell is painted.
			_push_undo()
			_dragging = true
			_drag_cells.clear()
			_apply_tool_at(_hovered_cell)
	elif event.is_action_released("place"):
		_dragging = false
	elif event.is_action_pressed("delete"):
		if _tool == Tool.PROP:
			_delete_prop()
		elif _tool == Tool.LAKE:
			var terrain: Terrain = GameState.current_terrain
			if terrain != null and terrain.has_lake(_hovered_cell):
				_push_undo()
				terrain.remove_lake(_hovered_cell)
				_mark_terrain_dirty(0.05)
				_update_status()
		else:
			_delete_tile()
	elif event.is_action_pressed("rotate"):
		_cycle_shape()
	elif event.is_action_pressed("raise"):
		# PgUp/PgDn drive whichever height the active tool cares about.
		if _tool == Tool.LEVEL:
			_level_target = clampi(_level_target + 1, 0, Constants.MAX_TERRAIN_LEVEL)
		else:
			_elevation += 1
		_update_status()
	elif event.is_action_pressed("lower"):
		if _tool == Tool.LEVEL:
			_level_target = clampi(_level_target - 1, 0, Constants.MAX_TERRAIN_LEVEL)
		else:
			_elevation -= 1
		_update_status()


# --- Editing actions --------------------------------------------------------

func _place_tile() -> void:
	var def := _current_def()
	if def == null:
		return
	_push_undo()
	# Clicking a cell that already holds this tile cycles its rotation (Stunts-
	# style): repeated clicks rotate a curve through all four orientations.
	var existing: PlacedTile = _grid.get_placed(_hovered_cell)
	if existing != null and existing.def_id == def.id and _grid.get_anchor(_hovered_cell) == _hovered_cell:
		_rotation = (existing.rotation + 1) % 4
	# Free the nodes of any tiles this footprint will overwrite (incremental — no
	# full rebuild, so big maps stay responsive).
	for fc in TrackGrid.footprint_cells(_hovered_cell, def, _rotation):
		var anchor := _grid.get_anchor(fc)
		if anchor != TrackGrid.NONE and _placed_nodes.has(anchor):
			(_placed_nodes[anchor] as Node).queue_free()
			_placed_nodes.erase(anchor)
	_grid.place(_hovered_cell, def.id, _rotation, _effective_elevation(_hovered_cell))
	_spawn_tile_node(_hovered_cell)
	_refresh_adjacent_overpasses(_hovered_cell)
	_mark_terrain_dirty()
	_update_status()


## Why the selected scenery can't go at `cell`, or "" if it can. Checks the whole
## plot, so a building can't straddle the track, water or another prop.
func _prop_blocker(cell: Vector2i) -> String:
	var terrain: Terrain = GameState.current_terrain
	# Re-placing onto the same prop is allowed (it cycles its shape), so its own
	# cells don't count against it.
	var self_anchor := _grid.prop_anchor(cell)
	for c in TrackGrid.prop_cells(cell, _prop_kind, _rotation):
		if _grid.get_anchor(c) != TrackGrid.NONE:
			return "on the track"
		if terrain != null and terrain.is_water(c):
			return "in the water"
		var pa := _grid.prop_anchor(c)
		if pa != TrackGrid.NONE and pa != self_anchor:
			return "over other scenery"
	return ""


## Place the selected scenery. Clicking the same plot again cycles its shape — the
## same rule that flips a curve through its rotations on repeated clicks.
func _place_prop() -> void:
	var existing: PlacedProp = _grid.props.get(_grid.prop_anchor(_hovered_cell))
	if existing != null and existing.kind == _prop_kind:
		_prop_variant = (existing.variant + 1) % PropGeo.VARIANTS
	var blocker := _prop_blocker(_hovered_cell)
	if blocker != "":
		_flash("Can't build there: %s." % blocker)
		return
	_push_undo()
	# Free any prop nodes this plot will overwrite.
	for c in TrackGrid.prop_cells(_hovered_cell, _prop_kind, _rotation):
		var a := _grid.prop_anchor(c)
		if a != TrackGrid.NONE and _prop_nodes.has(a):
			(_prop_nodes[a] as Node).queue_free()
			_prop_nodes.erase(a)
	_grid.place_prop(_hovered_cell, PlacedProp.make(_prop_kind, _prop_variant, _rotation))
	_spawn_prop_node(_hovered_cell)
	_update_status()


func _delete_prop() -> void:
	var anchor := _grid.prop_anchor(_hovered_cell)
	if anchor == TrackGrid.NONE:
		return
	_push_undo()
	_grid.remove_prop(_hovered_cell)
	if _prop_nodes.has(anchor):
		(_prop_nodes[anchor] as Node).queue_free()
		_prop_nodes.erase(anchor)
	_update_status()


func _spawn_prop_node(cell: Vector2i) -> void:
	if _prop_nodes.has(cell):
		(_prop_nodes[cell] as Node).queue_free()
		_prop_nodes.erase(cell)
	if not _grid.props.has(cell):
		return
	var node := TrackWorld.make_prop(cell, _grid.props[cell], GameState.current_terrain)
	_props_root.add_child(node)
	_prop_nodes[cell] = node


func _rebuild_all_props() -> void:
	for child in _props_root.get_children():
		child.queue_free()
	_prop_nodes.clear()
	for cell in _grid.props:
		_spawn_prop_node(cell)


## Drop props back onto the ground after it moves. Only the height changes, so
## this beats rebuilding the meshes — sculpting re-runs it every few frames.
func _reseat_props() -> void:
	var terrain: Terrain = GameState.current_terrain
	for cell in _prop_nodes:
		var level: int = terrain.height_level(cell) if terrain != null else 0
		(_prop_nodes[cell] as Node3D).position.y = level * Constants.ELEVATION_STEP


func _delete_tile() -> void:
	var anchor := _grid.get_anchor(_hovered_cell)
	if anchor == TrackGrid.NONE:
		return
	_push_undo()
	if _placed_nodes.has(anchor):
		(_placed_nodes[anchor] as Node).queue_free()
		_placed_nodes.erase(anchor)
	_grid.remove(_hovered_cell)
	_refresh_adjacent_overpasses(_hovered_cell)
	_mark_terrain_dirty()
	_update_status()


## Apply the active sculpt tool to `cell`. Placed tiles deliberately stay where
## they are: the terrain already conforms to the track (TerrainWorld flattens
## under it), and re-draping here would wipe every manual elevation offset on the
## map.
func _apply_tool_at(cell: Vector2i) -> void:
	if _tool == Tool.ERASE:
		_erase_at(cell)
	else:
		_sculpt_at(cell)


## Remove whatever is on `cell` — scenery and track piece alike. Deleting a
## multi-cell tile from any of its cells removes the whole tile, which is what
## clicking one of its squares plainly means.
func _erase_at(cell: Vector2i) -> void:
	if _drag_cells.has(cell):
		return
	_drag_cells[cell] = true

	var prop_anchor := _grid.prop_anchor(cell)
	if prop_anchor != TrackGrid.NONE:
		_grid.remove_prop(cell)
		if _prop_nodes.has(prop_anchor):
			(_prop_nodes[prop_anchor] as Node).queue_free()
			_prop_nodes.erase(prop_anchor)

	var anchor := _grid.get_anchor(cell)
	if anchor != TrackGrid.NONE:
		if _placed_nodes.has(anchor):
			(_placed_nodes[anchor] as Node).queue_free()
			_placed_nodes.erase(anchor)
		_grid.remove(cell)
		_refresh_adjacent_overpasses(cell)
		_mark_terrain_dirty()
	_update_status()


func _sculpt_at(cell: Vector2i) -> void:
	var terrain: Terrain = GameState.current_terrain
	if terrain == null:
		_flash("Pick a terrain type first — Flat has no terrain to sculpt.")
		return
	if _drag_cells.has(cell):
		return
	_drag_cells[cell] = true
	match _tool:
		Tool.RAISE: terrain.sculpt(cell, 1)
		Tool.LOWER: terrain.sculpt(cell, -1)
		Tool.LEVEL: terrain.level_to(cell, _level_target)
		Tool.LAKE:
			if not terrain.add_lake(cell):
				_flash("Can't flood here: %s." % terrain.lake_blocker(cell))
				return
		_: return
	_mark_terrain_dirty(0.05)  # short: sculpting wants immediate feedback
	_update_status()


func _mark_terrain_dirty(delay: float = 0.25) -> void:
	if GameState.current_terrain != null:
		_terrain_dirty = true
		_terrain_timer = delay


func _spawn_tile_node(cell: Vector2i) -> void:
	if _placed_nodes.has(cell):
		(_placed_nodes[cell] as Node).queue_free()
		_placed_nodes.erase(cell)
	var placed: PlacedTile = _grid.get_placed(cell)
	if placed == null:
		return
	var node := _library.instantiate_placed(cell, placed, _grid)
	if node != null:
		_tiles_root.add_child(node)
		_placed_nodes[cell] = node


## An overpass only builds its lower road when something joins it, so placing or
## deleting a road beside one has to rebuild that overpass.
func _refresh_adjacent_overpasses(cell: Vector2i) -> void:
	for off in TrackGrid.OFFSETS:
		var anchor := _grid.get_anchor(cell + off)
		if anchor == TrackGrid.NONE or anchor == cell:
			continue
		var def := _grid.get_def(anchor)
		if def != null and def.category == TileDefinition.Category.BRIDGE:
			_spawn_tile_node(anchor)


func _rebuild_all_tiles() -> void:
	for child in _tiles_root.get_children():
		child.queue_free()
	_placed_nodes.clear()
	for cell in _grid.tiles:
		_spawn_tile_node(cell)


func _start_test_drive() -> void:
	GameState.current_grid = _grid
	GameState.return_scene = "res://scenes/editor/Editor.tscn"
	get_tree().change_scene_to_file(PLAY_SCENE)


func _start_race() -> void:
	GameState.current_grid = _grid
	GameState.return_scene = "res://scenes/editor/Editor.tscn"
	get_tree().change_scene_to_file(RACE_SCENE)


func _save_track() -> void:
	var track_name: String = _name_edit.text.strip_edges()
	if track_name == "":
		track_name = "Untitled"
	var path := TrackSerializer.default_save_path(track_name)

	# Confirm before clobbering a DIFFERENT existing track. Re-saving the track you
	# loaded is a plain save (same path) and never asks.
	if FileAccess.file_exists(path) and path != _loaded_path:
		# `hold` is captured by reference so the callbacks can free the overlay — a
		# lambda that closed over the `dlg` var directly would capture it while still
		# null (it is assigned on the same statement).
		var hold: Array[Control] = [null]
		var dlg := MenuUI.confirm_overlay(
			"A track named '%s' already exists.\nOverwrite it?" % track_name, "Overwrite",
			func() -> void:
				hold[0].queue_free()
				_do_save(track_name, path),
			func() -> void:
				hold[0].queue_free())
		hold[0] = dlg
		_ui_layer.add_child(dlg)
		dlg.show()
		return

	_do_save(track_name, path)


func _do_save(track_name: String, path: String) -> void:
	GameState.current_track_name = track_name
	if TrackSerializer.save(_grid, _library, path, track_name, "player"):
		_loaded_path = path
		_refresh_import_button()
		_flash("Saved: %s" % path)
	else:
		_flash("Save failed.")


# --- Load / import ----------------------------------------------------------

func _open_load_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# FILESYSTEM, not RESOURCES: the point is to open a track someone sent you,
	# which will not be inside the project.
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.json ; Track files"])
	dlg.title = "Load track"
	dlg.use_native_dialog = true
	DirAccess.make_dir_recursive_absolute(TrackSerializer.USER_DIR)
	dlg.current_dir = ProjectSettings.globalize_path(TrackSerializer.USER_DIR)
	dlg.file_selected.connect(_load_track_file)
	dlg.close_requested.connect(dlg.queue_free)
	dlg.file_selected.connect(func(_p: String) -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func _load_track_file(path: String) -> void:
	var result := TrackSerializer.load_track(path, _library)
	if result.is_empty():
		_flash("Could not read that track file.")
		return
	_grid = result.grid
	GameState.current_grid = _grid
	GameState.current_track_name = result.name
	GameState.current_terrain = result.get("terrain", null)
	_terrain_type = GameState.current_terrain.type if GameState.current_terrain != null else Terrain.Type.FLAT
	if GameState.current_terrain == null:
		var flat := Terrain.new()
		flat.setup(Terrain.Type.FLAT, 0)
		GameState.current_terrain = flat
	_loaded_path = path
	_name_edit.text = result.name

	_rebuild_terrain()
	_rebuild_all_tiles()
	_rebuild_all_props()
	_refresh_import_button()
	_refresh_palette_highlight()
	_update_status()
	_flash("Loaded '%s' (%d tiles)." % [result.name, _grid.tiles.size()])


## Copy the loaded file into the user's track library, so it shows up under Race.
func _import_track() -> void:
	if _loaded_path == "" or TrackSerializer.is_in_library(_loaded_path):
		return
	var dest := TrackSerializer.import_track(_loaded_path, _library)
	if dest == "":
		_flash("Import failed.")
		return
	_loaded_path = dest
	_refresh_import_button()
	_flash("Imported to your track list: %s" % dest.get_file())


## Import only means something for a track that came from outside the library —
## anything already in it is in the list by definition.
func _refresh_import_button() -> void:
	if _import_btn == null:
		return
	var importable: bool = _loaded_path != "" and not TrackSerializer.is_in_library(_loaded_path)
	_import_btn.disabled = not importable
	_import_btn.tooltip_text = "Import into your track library" if importable \
		else "Import — load an external track file first (already-saved tracks are in your list)"


func _flash(text: String) -> void:
	_save_label.text = text
	_save_timer = 4.0


# --- Palette & status -------------------------------------------------------

## Icon-only button. The label lives in the tooltip — hover to learn the tool.
func _icon_button(icon_id: String, tooltip: String) -> Button:
	var b := Button.new()
	b.icon = EditorIcons.get_icon(icon_id)
	b.tooltip_text = tooltip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(46.0, 46.0)
	return b


func _icon_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	return g


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _terrain_button(icon_id: String, tooltip: String, type_index: int) -> Button:
	var b := _icon_button(icon_id, tooltip)
	b.toggle_mode = true
	b.pressed.connect(func() -> void: _select_terrain(type_index))
	return b


func _select_def(index: int) -> void:
	_def_index = index
	_tool = Tool.TILE
	_refresh_palette_highlight()
	_update_status()


func _select_prop(kind: int) -> void:
	if _tool == Tool.PROP and _prop_kind == kind:
		# Re-picking the same scenery button cycles its shape, so the palette is
		# another way to flip through variants without placing anything.
		_prop_variant = (_prop_variant + 1) % PropGeo.VARIANTS
	else:
		_prop_variant = 0
	_prop_kind = kind
	_tool = Tool.PROP
	_refresh_palette_highlight()
	_update_status()


func _select_tool(tool: Tool) -> void:
	# Picking the level tool grabs the height under the cursor, so it starts on
	# something meaningful rather than 0 (which would flatten a mountain to sea).
	if tool == Tool.LEVEL and _tool != Tool.LEVEL:
		_level_target = _terrain_level(_hovered_cell)
	_tool = tool
	_refresh_palette_highlight()
	_update_status()


func _refresh_palette_highlight() -> void:
	for i in range(_palette_buttons.size()):
		_palette_buttons[i].button_pressed = (_tool == Tool.TILE and i == _def_index)
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).button_pressed = (_tool == t)
	for ti in _terrain_buttons:
		(_terrain_buttons[ti] as Button).button_pressed = (ti == _terrain_type)
	for pk in _prop_buttons:
		(_prop_buttons[pk] as Button).button_pressed = (_tool == Tool.PROP and pk == _prop_kind)


func _current_def() -> TileDefinition:
	if _def_index < 0 or _def_index >= _library.ordered.size():
		return null
	return _library.ordered[_def_index]


func _update_status(result: Dictionary = {}) -> void:
	if _status_label == null:
		return
	var terrain_name: String = GameState.current_terrain.type_name() if GameState.current_terrain != null else "Flat"

	if _tool == Tool.LEVEL:
		_status_label.text = "Tool: Level terrain    Target: %d (%.0f m)    Ground here: %d    Cell: (%d, %d)    Terrain: %s\nDrag to flatten    Right-click samples a height    PgUp/PgDn adjusts target" % [
			_level_target, _level_target * Constants.ELEVATION_STEP,
			_terrain_level(_hovered_cell), _hovered_cell.x, _hovered_cell.y, terrain_name]
		return

	if _tool == Tool.PROP:
		var blocked := _prop_blocker(_hovered_cell)
		_status_label.text = "Scenery: %s / %s    Facing: %s    Cell: (%d, %d)    Terrain: %s\n%s    Click again to cycle shape    Right-click cycles without placing    T rotates    Del removes" % [
			PropGeo.KIND_NAMES[_prop_kind], PropGeo.VARIANT_NAMES[_prop_kind][_prop_variant],
			["N", "E", "S", "W"][_rotation], _hovered_cell.x, _hovered_cell.y, terrain_name,
			"OK" if blocked == "" else "BLOCKED: %s" % blocked]
		return

	if _tool == Tool.ERASE:
		var anchor := _grid.get_anchor(_hovered_cell)
		var what := ""
		if anchor != TrackGrid.NONE:
			var d := _grid.get_def(anchor)
			what = d.display_name if d != null else "tile"
		var pa := _grid.prop_anchor(_hovered_cell)
		if pa != TrackGrid.NONE:
			var p: PlacedProp = _grid.props[pa]
			what += (" + " if what != "" else "") + PropGeo.KIND_NAMES[p.kind]
		_status_label.text = "Tool: Erase    %s    Cell: (%d, %d)    Terrain: %s\nClick or drag to remove track pieces and scenery" % [
			"Nothing here" if what == "" else "Remove: %s" % what,
			_hovered_cell.x, _hovered_cell.y, terrain_name]
		return

	if _tool == Tool.LAKE:
		var terrain: Terrain = GameState.current_terrain
		var state := "no terrain"
		if terrain != null:
			var blocker := terrain.lake_blocker(_hovered_cell)
			if terrain.has_lake(_hovered_cell):
				state = "already flooded (Del to remove)"
			else:
				state = "CAN FLOOD" if blocker == "" else blocker
		_status_label.text = "Tool: Lake    %s    Ground: %d    Cell: (%d, %d)    Terrain: %s\nDrag to flood    Needs a flat square with no lower ground beside it    Del removes" % [
			state, _terrain_level(_hovered_cell), _hovered_cell.x, _hovered_cell.y, terrain_name]
		return

	if _tool != Tool.TILE:
		var verb: String = "Raise" if _tool == Tool.RAISE else "Lower"
		_status_label.text = "Tool: %s terrain (click or drag)    Ground: %d    Cell: (%d, %d)    Terrain: %s" % [
			verb, _terrain_level(_hovered_cell), _hovered_cell.x, _hovered_cell.y, terrain_name]
		return

	var def := _current_def()
	var name := def.display_name if def != null else "-"
	var dirs := ["N", "E", "S", "W"]
	var status_text := ""
	if not result.is_empty():
		match result.status:
			PlacementValidator.Status.GREEN: status_text = "CONNECTED"
			PlacementValidator.Status.YELLOW: status_text = "dangling"
			PlacementValidator.Status.RED: status_text = "CONFLICT"
	_status_label.text = "Tile: %s    Facing: %s    Elev: %d (offset %+d)    Cell: (%d, %d)    Terrain: %s\n%s" % [
		name, dirs[_rotation], _effective_elevation(_hovered_cell), _elevation,
		_hovered_cell.x, _hovered_cell.y, terrain_name, status_text]


func _status_color(status: int) -> Color:
	match status:
		PlacementValidator.Status.GREEN: return Color(0.2, 0.9, 0.3)
		PlacementValidator.Status.RED: return Color(0.95, 0.25, 0.2)
		_: return Color(0.95, 0.85, 0.2)


# --- Camera -----------------------------------------------------------------

func _update_camera_transform() -> void:
	_camera_pivot.position = _pivot_pos
	_camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0)
	_camera.position = Vector3(0, 0, _cam_distance)
	_camera.rotation = Vector3.ZERO
