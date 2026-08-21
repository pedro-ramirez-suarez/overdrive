extends Control
## Main menu (SPEC.md §M6).

const CAR_SELECT := "res://scenes/ui/CarSelect.tscn"
const EDITOR := "res://scenes/editor/Editor.tscn"
const SETTINGS := "res://scenes/ui/Settings.tscn"

var _panel: Control


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

	var play := MenuUI.button("Play", func() -> void: get_tree().change_scene_to_file(CAR_SELECT), "play", true)
	col.add_child(play)
	col.add_child(MenuUI.button("Track Editor", _edit_new, "edit"))
	# A challenge is an invitation, not a library item, so it gets its own door
	# rather than hiding behind Play → Car → Track → Import.
	col.add_child(MenuUI.button("Challenge", _open_challenge, "play"))
	col.add_child(MenuUI.button("Settings", func() -> void: get_tree().change_scene_to_file(SETTINGS), "gear"))
	col.add_child(MenuUI.button("Exit", func() -> void: get_tree().quit(), "exit"))
	# Focus the primary action so the D-pad / stick has somewhere to start.
	play.call_deferred("grab_focus")


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	return c


# --- Challenges -------------------------------------------------------------

## Take in a challenge someone sent, then go straight to picking a car and racing
## it. A track file handed to the same door is imported too, and says so — the
## player had a file, not a category.
func _open_challenge() -> void:
	ImportFlow.open_dialog(self, "Open a challenge", _take_file)


func _take_file(path: String) -> void:
	var result := ImportFlow.take(path)
	if not result.get("ok", false):
		_message("Nothing imported", String(result.get("error", "")))
		return
	if String(result.get("kind", "")) != "challenge":
		# A track through this door is still a track. It is imported, and says so.
		_message("Track imported", ImportFlow.describe(result))
		return
	if _panel != null:
		_panel.queue_free()
	_panel = MenuUI.confirm_overlay(ImportFlow.describe(result), "Race it",
		func() -> void:
			_panel.hide()
			_race(result),
		func() -> void: pass, "Later", "play")
	add_child(_panel)
	_panel.show()


func _message(title: String, text: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = text
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Straight to the car, with the track already settled: Car Select sees a race
## waiting and its next button starts it rather than asking for a track.
func _race(result: Dictionary) -> void:
	if not ImportFlow.load_into_gamestate(String(result.get("track_path", ""))):
		_message("Could not open that track", "It imported, but would not load.")
		return
	ImportFlow.arm_race(GameState.active_challenge)
	GameState.challenge_race_pending = true
	GameState.return_scene = "res://scenes/ui/MainMenu.tscn"
	get_tree().change_scene_to_file(CAR_SELECT)


func _edit_new() -> void:
	# Fresh grid unless there's already an in-progress track.
	if GameState.current_grid.tiles.is_empty():
		GameState.current_track_name = "Untitled"
	get_tree().change_scene_to_file(EDITOR)
