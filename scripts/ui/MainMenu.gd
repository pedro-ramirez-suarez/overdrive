extends Control
## Main menu (SPEC.md §M6).

const CAR_SELECT := "res://scenes/ui/CarSelect.tscn"
const EDITOR := "res://scenes/editor/Editor.tscn"
const SETTINGS := "res://scenes/ui/Settings.tscn"


func _ready() -> void:
	theme = MenuUI.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuUI.add_background(self, "res://assets/ui/bg_menu.png")

	# A left-anchored panel of icon buttons, like the reference — not a centred list.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_horizontal = Control.GROW_DIRECTION_END
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(300, 0)
	margin.add_child(col)

	var title := MenuUI.label("OVERDRIVE", 52, MenuUI.ACCENT)
	col.add_child(title)
	col.add_child(MenuUI.label("A modular-track arcade stunt racer", 16, MenuUI.MUTED))
	col.add_child(_spacer())

	col.add_child(MenuUI.button("Play", func() -> void: get_tree().change_scene_to_file(CAR_SELECT), "play", true))
	col.add_child(MenuUI.button("Track Editor", _edit_new, "edit"))
	col.add_child(MenuUI.button("Settings", func() -> void: get_tree().change_scene_to_file(SETTINGS), "gear"))
	col.add_child(MenuUI.button("Exit", func() -> void: get_tree().quit(), "exit"))


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c


func _edit_new() -> void:
	# Fresh grid unless there's already an in-progress track.
	if GameState.current_grid.tiles.is_empty():
		GameState.current_track_name = "Untitled"
	get_tree().change_scene_to_file(EDITOR)
