class_name EditorIcons
extends RefCounted
## Procedurally drawn icons for the editor's toolbar buttons (SPEC.md §M3).
##
## Each glyph is a handful of strokes laid out in a normalized 0..1 box (y points
## DOWN, matching screen space) and rasterised through a distance field, so edges
## come out antialiased and the glyph can be re-rendered at any size. Drawing them
## in code keeps the editor asset-free — there is no icon file to go missing, and
## no import step.
##
## Track-piece glyphs are drawn as the road's own path: straights and curves are
## the top view, stunt pieces the side view (which is what makes a loop read as a
## loop). Icon ids match TileDefinition ids, so the palette looks them up directly.

const SIZE := 30
const INK := Color(0.90, 0.93, 0.98)
const ACCENT := Color(1.0, 0.82, 0.25)
const DIM := Color(0.52, 0.60, 0.70)

static var _cache: Dictionary = {}


## Icon for `id`, rendered once and cached. Unknown ids get a placeholder box.
static func get_icon(id: String) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var tex := _render(_glyph(id))
	_cache[id] = tex
	return tex


# --- Glyph definitions ------------------------------------------------------

static func _glyph(id: String) -> Array:
	match id:
		"straight":
			return [_seg(0.5, 0.06, 0.5, 0.94, 0.38)]
		"start":
			return [_seg(0.5, 0.06, 0.5, 0.94, 0.38),
				_seg(0.31, 0.52, 0.69, 0.52, 0.11, ACCENT)]
		"curve":
			# Quarter turn joining the top edge to the right edge (N -> E).
			return [_arc(0.92, 0.08, 0.44, PI * 0.5, PI, 0.38)]
		"wide_curve":
			# Same corner, much larger radius — the 2x2 sweep.
			return [_arc(1.04, -0.04, 0.72, PI * 0.5, PI, 0.30)]
		"banked_curve":
			# A curve with its outer edge raised.
			return [_arc(0.92, 0.08, 0.44, PI * 0.5, PI, 0.38),
				_arc(0.92, 0.08, 0.60, PI * 0.5, PI, 0.10, ACCENT)]
		"banked_straight":
			# End-on: the road leaning, with the ground under it.
			return [_seg(0.08, 0.86, 0.92, 0.86, 0.06, DIM),
				_seg(0.14, 0.80, 0.86, 0.34, 0.16),
				_seg(0.86, 0.34, 0.86, 0.80, 0.08, ACCENT)]
		"banked_entry":
			# Flat road that rolls up into the bank.
			return [_seg(0.06, 0.86, 0.94, 0.86, 0.06, DIM),
				_seg(0.08, 0.78, 0.48, 0.78, 0.15),
				_seg(0.48, 0.78, 0.92, 0.36, 0.15, ACCENT)]
		"banked_exit":
			# The mirror: banked road rolling back down to flat.
			return [_seg(0.06, 0.86, 0.94, 0.86, 0.06, DIM),
				_seg(0.08, 0.36, 0.52, 0.78, 0.15, ACCENT),
				_seg(0.52, 0.78, 0.92, 0.78, 0.15)]
		"noon":
			# Sun: disc with rays.
			return [_arc(0.5, 0.5, 0.18, 0.0, TAU, 0.12, ACCENT),
				_seg(0.5, 0.08, 0.5, 0.2, 0.07, ACCENT), _seg(0.5, 0.8, 0.5, 0.92, 0.07, ACCENT),
				_seg(0.08, 0.5, 0.2, 0.5, 0.07, ACCENT), _seg(0.8, 0.5, 0.92, 0.5, 0.07, ACCENT),
				_seg(0.2, 0.2, 0.29, 0.29, 0.06, ACCENT), _seg(0.71, 0.71, 0.8, 0.8, 0.06, ACCENT),
				_seg(0.8, 0.2, 0.71, 0.29, 0.06, ACCENT), _seg(0.29, 0.71, 0.2, 0.8, 0.06, ACCENT)]
		"evening":
			# Half sun over a horizon.
			return [_seg(0.06, 0.68, 0.94, 0.68, 0.07, DIM),
				_arc(0.5, 0.68, 0.2, PI, TAU, 0.12, ACCENT),
				_seg(0.5, 0.28, 0.5, 0.36, 0.06, ACCENT),
				_seg(0.22, 0.42, 0.28, 0.47, 0.05, ACCENT), _seg(0.78, 0.42, 0.72, 0.47, 0.05, ACCENT)]
		"night":
			# Crescent moon: a disc with a bite taken from it.
			return [_arc(0.46, 0.5, 0.32, 0.0, TAU, 0.11, INK),
				_arc(0.62, 0.42, 0.30, 0.0, TAU, 0.14, Color(0.0, 0.0, 0.0, 0.0))]
		"clear":
			# Empty sky with a small sun — "no weather".
			return [_arc(0.66, 0.34, 0.14, 0.0, TAU, 0.1, ACCENT),
				_seg(0.66, 0.1, 0.66, 0.16, 0.05, ACCENT), _seg(0.86, 0.34, 0.92, 0.34, 0.05, ACCENT),
				_seg(0.1, 0.78, 0.9, 0.78, 0.06, DIM)]
		"cloudy":
			return [_arc(0.36, 0.52, 0.16, PI, TAU, 0.1),
				_arc(0.6, 0.46, 0.2, PI, TAU, 0.1),
				_seg(0.2, 0.66, 0.82, 0.66, 0.1)]
		"rain":
			return [_arc(0.36, 0.4, 0.15, PI, TAU, 0.09),
				_arc(0.58, 0.35, 0.18, PI, TAU, 0.09),
				_seg(0.22, 0.52, 0.76, 0.52, 0.09),
				_seg(0.3, 0.66, 0.24, 0.86, 0.07, ACCENT),
				_seg(0.5, 0.66, 0.44, 0.86, 0.07, ACCENT),
				_seg(0.7, 0.66, 0.64, 0.86, 0.07, ACCENT)]
		"fog":
			return [_seg(0.12, 0.34, 0.88, 0.34, 0.08, DIM),
				_seg(0.2, 0.5, 0.9, 0.5, 0.08),
				_seg(0.1, 0.66, 0.8, 0.66, 0.08, DIM),
				_seg(0.22, 0.82, 0.86, 0.82, 0.08)]
		"snow":
			return [_arc(0.36, 0.4, 0.15, PI, TAU, 0.09),
				_arc(0.58, 0.35, 0.18, PI, TAU, 0.09),
				_seg(0.22, 0.52, 0.76, 0.52, 0.09),
				_arc(0.3, 0.74, 0.04, 0.0, TAU, 0.06, INK),
				_arc(0.5, 0.8, 0.04, 0.0, TAU, 0.06, INK),
				_arc(0.7, 0.74, 0.04, 0.0, TAU, 0.06, INK)]
		"erase":
			# A bin.
			return [_seg(0.42, 0.12, 0.58, 0.12, 0.07),
				_seg(0.16, 0.26, 0.84, 0.26, 0.1),
				_poly([Vector2(0.26, 0.34), Vector2(0.74, 0.34), Vector2(0.68, 0.9), Vector2(0.32, 0.9)]),
				_seg(0.43, 0.44, 0.42, 0.8, 0.05, DIM),
				_seg(0.57, 0.44, 0.58, 0.8, 0.05, DIM)]
		"crossroads":
			return [_seg(0.5, 0.06, 0.5, 0.94, 0.34),
				_seg(0.06, 0.5, 0.94, 0.5, 0.34)]
		"overpass":
			# Lower road drawn first; the deck paints over it, which reads as "above".
			return [_seg(0.04, 0.62, 0.96, 0.62, 0.26, DIM),
				_seg(0.5, 0.04, 0.5, 0.96, 0.32)]
		"pipe":
			# The bore, end-on.
			return [_arc(0.5, 0.5, 0.38, 0.0, TAU, 0.09),
				_arc(0.5, 0.5, 0.22, 0.0, TAU, 0.06, DIM)]
		"pipe_entry":
			# A flat road flaring up into a bore — serves both the pipe and half-pipe.
			return [_seg(0.5, 0.96, 0.5, 0.68, 0.34),
				_arc(0.5, 0.34, 0.28, 0.0, PI, 0.10, ACCENT),
				_seg(0.22, 0.14, 0.22, 0.34, 0.10, ACCENT),
				_seg(0.78, 0.14, 0.78, 0.34, 0.10, ACCENT)]
		"half_pipe":
			return [_arc(0.5, 0.44, 0.34, 0.0, PI, 0.10),
				_seg(0.16, 0.18, 0.16, 0.44, 0.10),
				_seg(0.84, 0.18, 0.84, 0.44, 0.10)]
		"tunnel":
			# A portal mouth with the road running into it.
			return [_arc(0.5, 0.58, 0.34, PI, TAU, 0.11),
				_seg(0.16, 0.58, 0.16, 0.9, 0.11),
				_seg(0.84, 0.58, 0.84, 0.9, 0.11),
				_seg(0.5, 0.62, 0.5, 0.94, 0.24, DIM)]
		"ramp_up":
			return [_seg(0.12, 0.84, 0.9, 0.84, 0.07, DIM),
				_seg(0.12, 0.8, 0.88, 0.26, 0.15),
				_seg(0.88, 0.26, 0.88, 0.8, 0.09, DIM)]
		"ramp_down":
			return [_seg(0.12, 0.84, 0.9, 0.84, 0.07, DIM),
				_seg(0.12, 0.26, 0.88, 0.8, 0.15),
				_seg(0.12, 0.26, 0.12, 0.8, 0.09, DIM)]
		"helix":
			# Plan view: one full turn, the road running in at ground level and out
			# (accented) a level higher.
			return [_arc(0.5, 0.5, 0.26, 0.0, TAU, 0.12),
				_seg(0.24, 0.96, 0.24, 0.52, 0.12),
				_seg(0.24, 0.48, 0.24, 0.04, 0.12, ACCENT)]
		"loop":
			# Side view: the road runs in, loops, runs out.
			return [_seg(0.06, 0.88, 0.94, 0.88, 0.1),
				_arc(0.5, 0.44, 0.29, 0.0, TAU, 0.12)]
		"corkscrew":
			# Side view of a barrel roll: a coil.
			return [_arc(0.3, 0.5, 0.21, -PI * 0.75, PI * 0.75, 0.09),
				_arc(0.5, 0.5, 0.21, -PI * 0.75, PI * 0.75, 0.09),
				_arc(0.7, 0.5, 0.21, -PI * 0.75, PI * 0.75, 0.09)]
		"jump":
			# Side view: a launch lip plus the arc off it.
			return [_seg(0.08, 0.86, 0.5, 0.44, 0.15),
				_seg(0.62, 0.36, 0.66, 0.32, 0.08, ACCENT),
				_seg(0.76, 0.26, 0.82, 0.26, 0.08, ACCENT),
				_seg(0.9, 0.34, 0.94, 0.4, 0.08, ACCENT)]
		"flat":
			return [_seg(0.1, 0.56, 0.9, 0.56, 0.12)]
		"plains":
			return [_seg(0.08, 0.74, 0.92, 0.74, 0.07, DIM),
				_arc(0.32, 0.74, 0.15, PI, TAU, 0.09),
				_arc(0.66, 0.74, 0.13, PI, TAU, 0.09)]
		"hills":
			return [_seg(0.08, 0.8, 0.92, 0.8, 0.07, DIM),
				_arc(0.33, 0.8, 0.24, PI, TAU, 0.1),
				_arc(0.7, 0.8, 0.18, PI, TAU, 0.1)]
		"lakes":
			return [_arc(0.3, 0.76, 0.21, PI, TAU, 0.1),
				_seg(0.54, 0.62, 0.92, 0.62, 0.07, ACCENT),
				_seg(0.58, 0.76, 0.9, 0.76, 0.07, ACCENT),
				_seg(0.54, 0.88, 0.92, 0.88, 0.07, ACCENT)]
		"mountains":
			return [_seg(0.06, 0.82, 0.32, 0.3, 0.1),
				_seg(0.32, 0.3, 0.5, 0.6, 0.1),
				_seg(0.5, 0.6, 0.68, 0.22, 0.1),
				_seg(0.68, 0.22, 0.94, 0.82, 0.1)]
		"reroll":
			return [_arc(0.5, 0.5, 0.3, -PI * 0.85, PI * 0.55, 0.11),
				_seg(0.5, 0.12, 0.66, 0.2, 0.09),
				_seg(0.5, 0.12, 0.5, 0.28, 0.09)]
		"raise":
			return [_seg(0.14, 0.9, 0.86, 0.9, 0.09, DIM),
				_seg(0.5, 0.74, 0.5, 0.16, 0.13, ACCENT),
				_seg(0.28, 0.4, 0.5, 0.16, 0.13, ACCENT),
				_seg(0.72, 0.4, 0.5, 0.16, 0.13, ACCENT)]
		"lower":
			return [_seg(0.14, 0.9, 0.86, 0.9, 0.09, DIM),
				_seg(0.5, 0.1, 0.5, 0.68, 0.13, ACCENT),
				_seg(0.28, 0.44, 0.5, 0.68, 0.13, ACCENT),
				_seg(0.72, 0.44, 0.5, 0.68, 0.13, ACCENT)]
		"tree":
			return [_seg(0.5, 0.92, 0.5, 0.68, 0.11, Color(0.45, 0.32, 0.22)),
				_poly([Vector2(0.5, 0.08), Vector2(0.78, 0.46), Vector2(0.22, 0.46)], Color(0.35, 0.66, 0.38)),
				_poly([Vector2(0.5, 0.3), Vector2(0.86, 0.72), Vector2(0.14, 0.72)], Color(0.28, 0.58, 0.32))]
		"house":
			return [_poly([Vector2(0.5, 0.1), Vector2(0.92, 0.46), Vector2(0.08, 0.46)], Color(0.80, 0.35, 0.28)),
				_poly([Vector2(0.18, 0.46), Vector2(0.82, 0.46), Vector2(0.82, 0.9), Vector2(0.18, 0.9)]),
				_poly([Vector2(0.42, 0.62), Vector2(0.58, 0.62), Vector2(0.58, 0.9), Vector2(0.42, 0.9)], Color(0.35, 0.3, 0.32))]
		"building":
			return [_poly([Vector2(0.22, 0.08), Vector2(0.78, 0.08), Vector2(0.78, 0.92), Vector2(0.22, 0.92)]),
				_seg(0.36, 0.22, 0.36, 0.8, 0.09, Color(0.25, 0.35, 0.5)),
				_seg(0.5, 0.22, 0.5, 0.8, 0.09, Color(0.25, 0.35, 0.5)),
				_seg(0.64, 0.22, 0.64, 0.8, 0.09, Color(0.25, 0.35, 0.5))]
		"scenery":
			return [_seg(0.28, 0.9, 0.28, 0.3, 0.09, DIM),
				_seg(0.28, 0.3, 0.52, 0.3, 0.09, DIM),
				_poly([Vector2(0.44, 0.14), Vector2(0.9, 0.14), Vector2(0.9, 0.5), Vector2(0.44, 0.5)], ACCENT)]
		"lake":
			# A basin holding water — distinct from the "lakes" terrain preset.
			return [_arc(0.5, 0.34, 0.32, 0.0, PI, 0.09),
				_seg(0.22, 0.36, 0.78, 0.36, 0.09, ACCENT),
				_seg(0.34, 0.52, 0.66, 0.52, 0.07, ACCENT)]
		"level":
			# A hill (faint, the cap being removed) sliced flat into a mesa.
			return [_arc(0.5, 0.86, 0.44, PI, TAU, 0.06, DIM),
				_seg(0.08, 0.86, 0.28, 0.52, 0.1),
				_seg(0.28, 0.52, 0.72, 0.52, 0.13, ACCENT),
				_seg(0.72, 0.52, 0.92, 0.86, 0.1)]
		"test":
			return [_poly([Vector2(0.28, 0.14), Vector2(0.86, 0.5), Vector2(0.28, 0.86)])]
		"race":
			return [_seg(0.16, 0.1, 0.16, 0.92, 0.09),
				_poly([Vector2(0.24, 0.14), Vector2(0.86, 0.28), Vector2(0.24, 0.5)]),
				_poly([Vector2(0.24, 0.5), Vector2(0.86, 0.28), Vector2(0.86, 0.62)], DIM)]
		"save":
			return [_seg(0.14, 0.14, 0.86, 0.14, 0.09),
				_seg(0.14, 0.86, 0.86, 0.86, 0.09),
				_seg(0.14, 0.14, 0.14, 0.86, 0.09),
				_seg(0.86, 0.14, 0.86, 0.86, 0.09),
				_poly([Vector2(0.34, 0.14), Vector2(0.66, 0.14), Vector2(0.66, 0.4), Vector2(0.34, 0.4)], ACCENT),
				_poly([Vector2(0.3, 0.58), Vector2(0.7, 0.58), Vector2(0.7, 0.86), Vector2(0.3, 0.86)], DIM)]
		"load":
			# An open folder.
			return [_poly([Vector2(0.08, 0.3), Vector2(0.44, 0.3), Vector2(0.52, 0.42), Vector2(0.92, 0.42),
					Vector2(0.92, 0.84), Vector2(0.08, 0.84)]),
				_poly([Vector2(0.2, 0.5), Vector2(0.98, 0.5), Vector2(0.86, 0.84), Vector2(0.08, 0.84)], ACCENT)]
		"import":
			# Into the library: an arrow dropping into a tray.
			return [_seg(0.5, 0.1, 0.5, 0.52, 0.12, ACCENT),
				_seg(0.3, 0.36, 0.5, 0.56, 0.12, ACCENT),
				_seg(0.7, 0.36, 0.5, 0.56, 0.12, ACCENT),
				_seg(0.14, 0.66, 0.14, 0.88, 0.1),
				_seg(0.86, 0.66, 0.86, 0.88, 0.1),
				_seg(0.14, 0.88, 0.86, 0.88, 0.1)]
		"play":
			return [_poly([Vector2(0.28, 0.16), Vector2(0.86, 0.5), Vector2(0.28, 0.84)])]
		"plus":
			return [_seg(0.5, 0.18, 0.5, 0.82, 0.12), _seg(0.18, 0.5, 0.82, 0.5, 0.12)]
		"back":
			return [_seg(0.5, 0.22, 0.24, 0.5, 0.11), _seg(0.24, 0.5, 0.5, 0.78, 0.11),
				_seg(0.24, 0.5, 0.82, 0.5, 0.11)]
		"car":
			# Rounded body with a cabin step, two wheels.
			return [_poly([Vector2(0.1, 0.62), Vector2(0.24, 0.62), Vector2(0.34, 0.44),
					Vector2(0.66, 0.44), Vector2(0.76, 0.62), Vector2(0.9, 0.62), Vector2(0.9, 0.72),
					Vector2(0.1, 0.72)]),
				_arc(0.3, 0.74, 0.08, 0.0, TAU, 0.05, DIM),
				_arc(0.7, 0.74, 0.08, 0.0, TAU, 0.05, DIM)]
		"gear":
			var g: Array = [_arc(0.5, 0.5, 0.2, 0.0, TAU, 0.1),
				_arc(0.5, 0.5, 0.07, 0.0, TAU, 0.07, DIM)]
			for k in 8:
				var a: float = TAU * float(k) / 8.0
				g.append(_seg(0.5 + cos(a) * 0.2, 0.5 + sin(a) * 0.2,
					0.5 + cos(a) * 0.32, 0.5 + sin(a) * 0.32, 0.09))
			return g
		"exit":
			# A door with an arrow leaving it.
			return [_seg(0.24, 0.14, 0.24, 0.86, 0.09),
				_seg(0.24, 0.14, 0.5, 0.14, 0.09), _seg(0.24, 0.86, 0.5, 0.86, 0.09),
				_seg(0.5, 0.5, 0.9, 0.5, 0.09, ACCENT),
				_seg(0.72, 0.34, 0.9, 0.5, 0.09, ACCENT),
				_seg(0.72, 0.66, 0.9, 0.5, 0.09, ACCENT)]
		"edit":
			# A pencil on a diagonal.
			return [_seg(0.2, 0.8, 0.72, 0.28, 0.14),
				_poly([Vector2(0.72, 0.28), Vector2(0.86, 0.42), Vector2(0.8, 0.48), Vector2(0.66, 0.34)], ACCENT),
				_poly([Vector2(0.14, 0.86), Vector2(0.2, 0.8), Vector2(0.28, 0.88), Vector2(0.16, 0.92)], DIM)]
		"link":
			# Two interlocked rings — the "tracks" glyph.
			return [_arc(0.38, 0.5, 0.16, -PI * 0.6, PI * 0.6, 0.09),
				_arc(0.62, 0.5, 0.16, PI * 0.4, PI * 1.6, 0.09),
				_seg(0.42, 0.42, 0.58, 0.42, 0.08, ACCENT),
				_seg(0.42, 0.58, 0.58, 0.58, 0.08, ACCENT)]
		"menu":
			return [_seg(0.16, 0.28, 0.84, 0.28, 0.11),
				_seg(0.16, 0.5, 0.84, 0.5, 0.11),
				_seg(0.16, 0.72, 0.84, 0.72, 0.11)]
		_:
			return [_seg(0.2, 0.2, 0.8, 0.8, 0.1, DIM), _seg(0.8, 0.2, 0.2, 0.8, 0.1, DIM)]


# --- Stroke builders --------------------------------------------------------

static func _seg(ax: float, ay: float, bx: float, by: float, w: float, c: Color = INK) -> Dictionary:
	return {"k": "seg", "a": Vector2(ax, ay), "b": Vector2(bx, by), "w": w, "c": c}


static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, w: float, c: Color = INK) -> Dictionary:
	return {"k": "arc", "o": Vector2(cx, cy), "r": r, "a0": a0, "a1": a1, "w": w, "c": c}


static func _poly(pts: Array, c: Color = INK) -> Dictionary:
	return {"k": "poly", "pts": pts, "c": c}


# --- Rasteriser -------------------------------------------------------------

static func _render(strokes: Array) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var px := 1.0 / float(SIZE)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((x + 0.5) * px, (y + 0.5) * px)
			var col := Color(0.0, 0.0, 0.0, 0.0)
			for s in strokes:
				var cov := _coverage(s, p, px)
				if cov <= 0.0:
					continue
				var sc: Color = s["c"]
				# Paint this stroke over whatever is already there.
				col = Color(
					lerpf(col.r, sc.r, cov), lerpf(col.g, sc.g, cov),
					lerpf(col.b, sc.b, cov), maxf(col.a, cov))
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Antialiased coverage of `s` at point `p`, from its signed distance.
static func _coverage(s: Dictionary, p: Vector2, px: float) -> float:
	var d: float
	match s["k"]:
		"seg":
			d = _dist_seg(p, s["a"], s["b"]) - float(s["w"]) * 0.5
		"arc":
			d = _dist_arc(p, s["o"], float(s["r"]), float(s["a0"]), float(s["a1"])) - float(s["w"]) * 0.5
		"poly":
			d = -px if _in_poly(p, s["pts"]) else px
		_:
			return 0.0
	return clampf(0.5 - d / px, 0.0, 1.0)


static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Distance to an arc: to the circle while within the sweep, else to whichever
## endpoint is nearer.
static func _dist_arc(p: Vector2, o: Vector2, r: float, a0: float, a1: float) -> float:
	var v := p - o
	var ang := atan2(v.y, v.x)
	while ang < a0:
		ang += TAU
	if ang <= a1:
		return absf(v.length() - r)
	var e0 := o + Vector2(cos(a0), sin(a0)) * r
	var e1 := o + Vector2(cos(a1), sin(a1)) * r
	return minf(p.distance_to(e0), p.distance_to(e1))


static func _in_poly(p: Vector2, pts: Array) -> bool:
	var inside := false
	var n := pts.size()
	var j := n - 1
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if (a.y > p.y) != (b.y > p.y):
			var x_cross: float = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if p.x < x_cross:
				inside = not inside
		j = i
	return inside
