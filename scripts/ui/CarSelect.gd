extends Control
## Car-select screen (SPEC.md §M6): a rotating 3D preview + stats on the left,
## the scrollable car list on the right.

const TRACK_SELECT := "res://scenes/ui/TrackSelect.tscn"
const MAIN := "res://scenes/ui/MainMenu.tscn"

var _index: int = 0
var _buttons: Array[Button] = []
var _name_label: Label
var _stats_label: Label
var _preview_pivot: Node3D


func _ready() -> void:
	theme = MenuUI.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_index = GameState.selected_car_index()

	MenuUI.add_background(self, "res://assets/ui/bg_cars.png", 0.3)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Select Car"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", MenuUI.TEXT)
	root.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_build_left())
	body.add_child(_build_right())

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	var back := MenuUI.button("Back", func() -> void: get_tree().change_scene_to_file(MAIN), "back")
	var next := MenuUI.button("Choose Track", func() -> void: get_tree().change_scene_to_file(TRACK_SELECT), "play", true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	nav.add_child(next)
	root.add_child(nav)

	_select(_index)
	# Focus the current car so the D-pad / stick navigates the list from the start.
	if _index >= 0 and _index < _buttons.size():
		_buttons[_index].call_deferred("grab_focus")


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Rotating 3D preview in its own isolated world.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	# A floor, not a fixed size: it expands into whatever the screen has spare, and
	# the info panel below keeps its own room. A large fixed height here is what
	# pushed the stats off the bottom of the window.
	svc.custom_minimum_size = Vector2(0, 200)
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	left.add_child(svc)

	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/default_env.tres")
	sv.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	sv.add_child(light)
	var cam := Camera3D.new()
	# Closer and lower so the car fills much more of the preview.
	cam.position = Vector3(0.0, 0.55, 2.1)
	cam.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)
	sv.add_child(cam)
	_preview_pivot = Node3D.new()
	# Lifted so the car sits in the upper part of the preview, clear of the info
	# panel that overlaps the lower portion.
	_preview_pivot.position = Vector3(0.0, 0.45, 0.0)
	sv.add_child(_preview_pivot)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_END  # keep its full height
	var pm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + side, 14)
	var info := VBoxContainer.new()
	_name_label = MenuUI.label("", 26, MenuUI.ACCENT)
	_stats_label = MenuUI.label("", 18)
	info.add_child(_name_label)
	info.add_child(_stats_label)
	pm.add_child(info)
	panel.add_child(pm)
	left.add_child(panel)
	return left


func _build_right() -> Control:
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.add_theme_constant_override("separation", 8)
	right.add_child(MenuUI.label("Cars", 20, MenuUI.MUTED))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	right.add_child(scroll)

	for i in range(GameState.roster.size()):
		var idx := i
		var b := MenuUI.button(GameState.roster[i].display_name, func() -> void: _select(idx))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(b)
		_buttons.append(b)
	return right


func _process(delta: float) -> void:
	if _preview_pivot != null:
		_preview_pivot.rotation.y += delta * 0.6


func _select(i: int) -> void:
	_index = i
	GameState.selected_car = GameState.roster[i]
	for j in range(_buttons.size()):
		_buttons[j].modulate = Color.WHITE if j == i else Color(0.68, 0.70, 0.74)
	_rebuild_preview()
	_refresh_info()


func _rebuild_preview() -> void:
	if _preview_pivot == null:
		return
	for child in _preview_pivot.get_children():
		child.queue_free()
	var body := CarBody.new()
	body.preview_profile = GameState.roster[_index]
	_preview_pivot.add_child(body)


func _refresh_info() -> void:
	var c: CarProfile = GameState.roster[_index]
	var accel: float = (c.engine_force / c.mass) / 18.0
	_name_label.text = c.display_name
	_stats_label.text = "%s\n\nTop speed  %s\nAccel      %s\nGrip       %s\nWeight     %s" % [
		c.tagline,
		MenuUI.bar(c.max_speed / 75.0),
		MenuUI.bar(accel),
		MenuUI.bar(c.grip / 0.18),
		MenuUI.bar(c.mass / 1600.0)]
