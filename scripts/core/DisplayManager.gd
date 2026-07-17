extends Node
## Window size / fullscreen, persisted (SPEC.md §M6).
##
## The UI is laid out for BASE_SIZE and the project stretches `canvas_items` with
## an "expand" aspect, so every menu scales to whatever window it is given rather
## than being cropped by it. Changing resolution therefore only changes how sharp
## and how large things are — never whether they fit.

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "display"

## The size every screen is designed against. Godot scales from this.
const BASE_SIZE := Vector2i(1280, 720)

## Offered in the settings dropdown. Anything narrower than the base would be
## scaled down, which still fits — these are just the sensible stops.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var resolution_index: int = 0
var fullscreen: bool = false


const ICON_PATH := "res://icon.png"


func _ready() -> void:
	load_settings()
	apply()
	_apply_window_icon()


## Set the running window's taskbar/titlebar icon. config/icon covers the editor
## and exported builds, but a game run from the editor keeps Godot's own icon
## unless the window icon is set explicitly.
func _apply_window_icon() -> void:
	# Load the IMPORTED texture, not the raw file: Image.load_from_file reads the
	# source png, which is absent from an exported pack. get_image survives export.
	var tex: Texture2D = load(ICON_PATH)
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	img = img.duplicate()  # the texture's own image may be read-only
	# The source is large; a taskbar icon is tiny. Shrink so the OS isn't handed a
	# 1254px image to downscale every redraw.
	if img.get_width() > 256:
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	if DisplayServer.has_feature(DisplayServer.FEATURE_ICON):
		DisplayServer.set_icon(img)


func resolution_name(i: int) -> String:
	var r: Vector2i = RESOLUTIONS[i]
	return "%d x %d" % [r.x, r.y]


func apply() -> void:
	var win := get_window()
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
		return
	win.mode = Window.MODE_WINDOWED
	var size: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
	win.size = size
	# Re-centre: growing the window from a corner can push it off-screen, and a
	# title bar you cannot reach is not recoverable without editing the config.
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	win.position = screen.position + (screen.size - size) / 2


func set_resolution(i: int) -> void:
	resolution_index = clampi(i, 0, RESOLUTIONS.size() - 1)
	apply()
	save_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply()
	save_settings()


# --- Persistence ------------------------------------------------------------
# Shares settings.cfg with AudioManager, so each must only touch its own section.

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # keep whatever audio wrote
	cfg.set_value(SECTION, "resolution", resolution_index)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	resolution_index = clampi(
		int(cfg.get_value(SECTION, "resolution", 0)), 0, RESOLUTIONS.size() - 1)
	fullscreen = bool(cfg.get_value(SECTION, "fullscreen", false))
