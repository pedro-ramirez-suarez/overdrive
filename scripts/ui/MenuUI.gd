class_name MenuUI
extends RefCounted
## Shared menu styling and widget helpers (SPEC.md §M6 polish). Builds a coherent
## dark UI theme in code and provides title/button/panel helpers so every menu
## looks the same.

const BG_TOP := Color(0.07, 0.09, 0.14)
const BG_BOTTOM := Color(0.13, 0.10, 0.16)
const ACCENT := Color(0.90, 0.24, 0.24)
const TEXT := Color(0.92, 0.94, 0.97)
const MUTED := Color(0.62, 0.66, 0.72)


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	# Dark translucent slabs with rounded corners, so the background image shows
	# through and the buttons still read — the look from the reference UI.
	var normal := _box(Color(0.08, 0.13, 0.12, 0.78), Color(1.0, 1.0, 1.0, 0.10))
	var hover := _box(Color(0.13, 0.20, 0.19, 0.88), Color(1.0, 1.0, 1.0, 0.22))
	var pressed := _box(Color(0.30, 0.13, 0.14, 0.92), ACCENT)
	for state in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(state, "Button", hover if state == "hover" else normal)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_constant("h_separation", "Button", 14)  # space between icon and label

	var panel := _box(Color(0.11, 0.13, 0.18, 0.92), Color(0.24, 0.27, 0.34))
	t.set_stylebox("panel", "PanelContainer", panel)

	t.set_color("font_color", "Label", TEXT)
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


## Cover `root` with a background image and a dark scrim, so a bright photo still
## leaves the light UI text readable. Falls back to the flat colour if the image
## is missing. Add this before any UI, so it sits behind everything.
static func add_background(root: Control, image_path: String, scrim: float = 0.2) -> void:
	var tex: Texture2D = load(image_path) if ResourceLoader.exists(image_path) else null
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(img)
	else:
		var flat := ColorRect.new()
		flat.color = BG_TOP
		flat.set_anchors_preset(Control.PRESET_FULL_RECT)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(flat)

	var veil := ColorRect.new()
	veil.color = Color(BG_TOP.r, BG_TOP.g, BG_TOP.b, scrim)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)


## Fill `root` with a background + a centred column, returning the VBoxContainer
## to add content to. Applies the shared theme. `bg_image` overrides the flat
## colour background when given.
static func scaffold(root: Control, title_text: String, bg_image: String = "") -> VBoxContainer:
	root.theme = build_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	if bg_image != "":
		add_background(root, bg_image)
	else:
		var bg := ColorRect.new()
		bg.color = BG_TOP
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(460, 0)
	center.add_child(col)

	if title_text != "":
		var title := Label.new()
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 52)
		title.add_theme_color_override("font_color", ACCENT)
		col.add_child(title)
		col.add_child(_spacer(10))

	return col


## A menu button. `icon_id` (an EditorIcons glyph) draws to the left of the label,
## left-aligned like the reference UI. `primary` gives the filled-red call-to-
## action style used for the main action on a screen.
static func button(text: String, on_pressed: Callable, icon_id: String = "", primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	if icon_id != "":
		b.icon = EditorIcons.get_icon(icon_id)
		b.add_theme_constant_override("icon_max_width", 26)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT  # icon + text hug the left edge
	if primary:
		var normal := _box(ACCENT, Color(1.0, 1.0, 1.0, 0.25))
		var hover := _box(ACCENT.lightened(0.12), Color(1.0, 1.0, 1.0, 0.4))
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("focus", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(on_pressed)
	return b


## A modal confirm overlay built from the shared theme, so it matches the menus
## rather than using Godot's default dialog. Returned hidden — call `.show()` to
## reveal it. `on_ok` runs on confirm; the overlay hides itself on cancel and runs
## `on_cancel`. Uses PROCESS_MODE_ALWAYS so its buttons work while the game is
## paused behind it.
static func confirm_overlay(message: String, ok_text: String, on_ok: Callable, on_cancel: Callable = func() -> void: pass) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = build_theme()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.hide()

	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.04, 0.06, 0.7)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	pad.add_child(col)

	var msg := label(message, 22)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(msg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var cancel := button("Cancel", func() -> void:
		root.hide()
		on_cancel.call(), "back")
	var ok := button(ok_text, on_ok, "exit", true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	row.add_child(ok)
	col.add_child(row)
	return root


## A modal menu overlay: a title over a vertical stack of buttons, built from the
## shared theme. `options` is an Array of dictionaries { text, cb, icon?, primary? }.
## Returned hidden — call `.show()`. It grabs focus on the first button whenever it
## becomes visible, so a controller can drive it. Processes while the game is
## paused behind it.
static func menu_overlay(title_text: String, options: Array) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = build_theme()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.hide()

	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.04, 0.06, 0.72)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	if title_text != "":
		var t := label(title_text, 26, ACCENT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
		col.add_child(_spacer(8))

	var first: Button = null
	for opt in options:
		var b := button(opt.text, opt.cb, opt.get("icon", ""), opt.get("primary", false))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(b)
		if first == null:
			first = b

	# Focus the first option each time it opens, so the D-pad has somewhere to go.
	if first != null:
		root.visibility_changed.connect(func() -> void:
			if root.visible:
				first.call_deferred("grab_focus"))
	return root


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A text bar like "██████░░░░" for a 0..1 value.
static func bar(v: float, width: int = 12) -> String:
	var filled: int = int(round(clampf(v, 0.0, 1.0) * width))
	return "█".repeat(filled) + "░".repeat(width - filled)


static func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
