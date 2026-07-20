extends Control
## Track-select screen (SPEC.md §M6): a live 3D preview of the highlighted track
## on the left, the track list on the right. Race, edit, or delete from here.

const CAR_SELECT := "res://scenes/ui/CarSelect.tscn"
const EDITOR := "res://scenes/editor/Editor.tscn"
const RACE := "res://scenes/race/Race.tscn"

var _tracks: Array = []
var _list: ItemList
var _preview: TrackPreview
var _info: Label
var _delete_btn: Button
var _confirm: ConfirmationDialog
## Index into `_tracks` of the highlighted entry, or -1.
var _selected: int = -1


func _ready() -> void:
	theme = MenuUI.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	MenuUI.add_background(self, "res://assets/ui/bg_tracks.png", 0.3)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := MenuUI.label("Select Track", 44, MenuUI.ACCENT)
	col.add_child(title)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	split.add_child(_build_preview_pane())
	split.add_child(_build_list_pane())

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete track"
	_confirm.confirmed.connect(_do_delete)
	add_child(_confirm)

	_refresh_list()


# --- Layout -----------------------------------------------------------------

func _build_preview_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 2.0  # two thirds
	pane.add_theme_constant_override("separation", 8)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(frame)

	_preview = TrackPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_preview)

	_info = MenuUI.label("Pick a track from the list.", 16, MenuUI.MUTED)
	pane.add_child(_info)

	pane.add_child(_atmosphere_bar())
	return pane


## Time-of-day and weather pickers, as compact rows of icon toggle buttons under
## the preview. Choosing one updates GameState and rebuilds the preview, so the
## sky you see is the sky you will race in.
func _atmosphere_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)

	var time_group := ButtonGroup.new()
	var time_box := _labelled_row("Time")
	for i in range(Atmosphere.TIME_NAMES.size()):
		var idx := i
		time_box.add_child(_atmo_button(
			Atmosphere.TIME_ICONS[i], Atmosphere.TIME_NAMES[i], time_group,
			GameState.race_time == i, func() -> void: _set_time(idx)))
	bar.add_child(time_box)

	var wx_group := ButtonGroup.new()
	var wx_box := _labelled_row("Weather")
	for i in range(Atmosphere.WEATHER_NAMES.size()):
		var idx := i
		wx_box.add_child(_atmo_button(
			Atmosphere.WEATHER_ICONS[i], Atmosphere.WEATHER_NAMES[i], wx_group,
			GameState.race_weather == i, func() -> void: _set_weather(idx)))
	bar.add_child(wx_box)
	return bar


func _labelled_row(text: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := MenuUI.label(text, 13, MenuUI.MUTED)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(l)
	return box


func _atmo_button(icon_id: String, tip: String, group: ButtonGroup, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = on
	b.icon = EditorIcons.get_icon(icon_id)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(40, 40)
	b.expand_icon = true
	# The shared menu theme pads buttons 18px each side — on a 40px button that
	# leaves ~4px for the icon, which is why they render as a lone dot. These need
	# tight styleboxes so the glyph fills the button. A toggled-on toggle button
	# shows its "pressed" stylebox, so that one carries the accent highlight.
	b.add_theme_stylebox_override("normal", _tight_box(false))
	b.add_theme_stylebox_override("hover", _tight_box(false, true))
	b.add_theme_stylebox_override("focus", _tight_box(false))
	b.add_theme_stylebox_override("pressed", _tight_box(true))
	b.pressed.connect(cb)
	return b


func _tight_box(active: bool, hover: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if active:
		s.bg_color = Color(0.30, 0.16, 0.18)
	else:
		s.bg_color = Color(0.20, 0.23, 0.30) if hover else Color(0.15, 0.17, 0.22)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = MenuUI.ACCENT if active else Color(0.30, 0.33, 0.40)
	s.set_content_margin_all(5)
	return s


func _set_time(i: int) -> void:
	GameState.race_time = i as Atmosphere.TimeOfDay
	_reapply_preview()


func _set_weather(i: int) -> void:
	GameState.race_weather = i as Atmosphere.Weather
	_reapply_preview()


## Rebuild the preview so the atmosphere change shows immediately. A no-op if no
## track is selected yet.
func _reapply_preview() -> void:
	if _selected < 0 or _selected >= _tracks.size():
		return
	var terrain: Terrain = GameState.current_terrain
	_preview.show_track(GameState.current_grid, terrain, GameState.library)


func _build_list_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 1.0  # one third
	pane.add_theme_constant_override("separation", 10)

	pane.add_child(MenuUI.label("TRACKS", 20, MenuUI.MUTED))

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 18)
	_list.item_selected.connect(_on_selected)
	# Double-click a track to race it.
	_list.item_activated.connect(func(_i: int) -> void: _go(RACE))
	pane.add_child(_list)

	pane.add_child(MenuUI.button("Race", func() -> void: _go(RACE), "play", true))
	pane.add_child(MenuUI.button("Edit", func() -> void: _go(EDITOR), "edit"))
	pane.add_child(MenuUI.button("New", func() -> void: _new_track(), "plus"))

	_delete_btn = MenuUI.button("Delete", _ask_delete, "erase")
	_delete_btn.disabled = true
	pane.add_child(_delete_btn)

	pane.add_child(MenuUI.button("Back",
		func() -> void: get_tree().change_scene_to_file(CAR_SELECT), "back"))
	return pane


# --- Track list -------------------------------------------------------------

func _refresh_list(select_path: String = "") -> void:
	_tracks = TrackSerializer.list_tracks()
	_list.clear()
	for entry in _tracks:
		var suffix: String = "  (sample)" if entry.get("builtin", false) else ""
		_list.add_item(entry.name + suffix)

	if _tracks.is_empty():
		_selected = -1
		_delete_btn.disabled = true
		_preview.clear()
		_info.text = "No tracks yet — press New to build one."
		return

	var want := 0
	if select_path != "":
		for i in range(_tracks.size()):
			if _tracks[i].path == select_path:
				want = i
	_list.select(want)
	_on_selected(want)
	_list.call_deferred("grab_focus")  # controller: D-pad scrolls the track list


func _on_selected(index: int) -> void:
	if index < 0 or index >= _tracks.size():
		return
	_selected = index
	var entry: Dictionary = _tracks[index]
	var result := TrackSerializer.load_track(entry.path, GameState.library)
	if result.is_empty():
		_info.text = "Could not load '%s'." % entry.name
		_preview.clear()
		_delete_btn.disabled = true
		return

	# Selecting IS loading: Race and Edit both act on GameState.
	GameState.current_grid = result.grid
	GameState.current_track_name = result.name
	GameState.current_terrain = result.get("terrain", null)

	var terrain: Terrain = result.get("terrain", null)
	_preview.show_track(result.grid, terrain, GameState.library)

	var terrain_name: String = terrain.type_name() if terrain != null else "Flat"
	var props: int = result.grid.props.size()
	_info.text = "%s — %d tiles, %d scenery, %s%s" % [
		result.name, result.grid.tiles.size(), props, terrain_name,
		"    (built-in sample)" if entry.get("builtin", false) else ""]

	# Best lap and its medal for this track, if it has ever been raced. The medal is
	# judged on the best lap against a one-lap par, exactly as the results screen does.
	var rec: Dictionary = Records.load_record(result.name)
	var best_lap: float = rec.get("best_lap", -1.0)
	if best_lap > 0.0:
		var route_len: float = RacePath.route_length(result.grid, GameState.library)
		var medal: int = Records.medal(best_lap, route_len) if route_len > 0.0 else Records.Medal.NONE
		var glyph: String = Records.MEDAL_GLYPHS[medal]
		_info.text += "\nBest lap  %s   %s" % [LapTimer.format(best_lap), glyph]
	# Bundled tracks ship with the game; deleting one is not recoverable.
	_delete_btn.disabled = not TrackSerializer.is_in_library(entry.path)


# --- Actions ----------------------------------------------------------------

func _go(scene: String) -> void:
	if _selected < 0:
		_info.text = "Pick a track first."
		return
	# Racing from here should return here, not the editor.
	if scene == RACE:
		GameState.return_scene = "res://scenes/ui/TrackSelect.tscn"
	get_tree().change_scene_to_file(scene)


func _new_track() -> void:
	GameState.current_grid = TrackGrid.new(GameState.library.definitions)
	GameState.current_track_name = "Untitled"
	GameState.current_terrain = null
	get_tree().change_scene_to_file(EDITOR)


func _ask_delete() -> void:
	if _selected < 0 or _selected >= _tracks.size():
		return
	var entry: Dictionary = _tracks[_selected]
	if not TrackSerializer.is_in_library(entry.path):
		return
	_confirm.dialog_text = "Delete '%s' permanently?\n\nThis cannot be undone." % entry.name
	_confirm.popup_centered()


func _do_delete() -> void:
	if _selected < 0 or _selected >= _tracks.size():
		return
	var entry: Dictionary = _tracks[_selected]
	var track_name: String = entry.name
	if TrackSerializer.delete_track(entry.path):
		_refresh_list()
		_info.text = "Deleted '%s'." % track_name
	else:
		_info.text = "Could not delete '%s'." % track_name
