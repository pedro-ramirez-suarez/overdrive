extends Control
## Settings screen (SPEC.md §M6): audio volumes, persisted on Back.

const MAIN := "res://scenes/ui/MainMenu.tscn"


func _ready() -> void:
	var col := MenuUI.scaffold(self, "Settings", "res://assets/ui/bg_settings.png")

	col.add_child(MenuUI.label("Display", 24, MenuUI.ACCENT))
	col.add_child(_resolution_row())
	col.add_child(_fullscreen_row())

	col.add_child(MenuUI.label("Audio", 24, MenuUI.ACCENT))
	col.add_child(_slider_row("Master", "Master"))
	col.add_child(_slider_row("SFX", "SFX"))
	col.add_child(_slider_row("Music", "Music"))
	col.add_child(MenuUI.button("Back", func() -> void:
		AudioManager.save_settings()
		get_tree().change_scene_to_file(MAIN), "back"))


func _resolution_row() -> HBoxContainer:
	var row := _row("Resolution")
	var drop := OptionButton.new()
	drop.custom_minimum_size = Vector2(280, 0)
	drop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in range(DisplayManager.RESOLUTIONS.size()):
		drop.add_item(DisplayManager.resolution_name(i), i)
	drop.selected = DisplayManager.resolution_index
	drop.disabled = DisplayManager.fullscreen  # meaningless while fullscreen
	drop.item_selected.connect(func(i: int) -> void: DisplayManager.set_resolution(i))
	row.add_child(drop)
	_res_drop = drop
	drop.call_deferred("grab_focus")  # controller: a starting point for navigation
	return row


func _fullscreen_row() -> HBoxContainer:
	var row := _row("Fullscreen")
	var check := CheckBox.new()
	check.button_pressed = DisplayManager.fullscreen
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.toggled.connect(func(on: bool) -> void:
		DisplayManager.set_fullscreen(on)
		if _res_drop != null:
			_res_drop.disabled = on)
	row.add_child(check)
	return row


var _res_drop: OptionButton


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := MenuUI.label(text, 18)
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	return row


func _slider_row(text: String, bus: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := MenuUI.label(text, 18)
	label.custom_minimum_size = Vector2(90, 0)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = AudioManager.get_volume(bus)
	slider.custom_minimum_size = Vector2(280, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: AudioManager.set_volume(bus, v))
	row.add_child(label)
	row.add_child(slider)
	return row
