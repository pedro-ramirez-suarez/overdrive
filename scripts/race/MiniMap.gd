class_name MiniMap
extends Control
## A small track map in the HUD corner (SPEC.md §M4): the track drawn as filled
## cells, with a dot per car. The player's dot is larger and outlined so it's easy
## to spot. Kept faint and translucent so it doesn't fight the view.

const BG := Color(0.05, 0.06, 0.09, 0.5)
const BORDER := Color(1.0, 1.0, 1.0, 0.95)
const TRACK := Color(0.56, 0.61, 0.70, 0.8)
const PAD := 8.0  # inset from the panel edge, in pixels

var _points: PackedVector3Array = PackedVector3Array()
var _racers: Array = []
var _lo := Vector2.ZERO
var _span := Vector2.ONE
var _time := 0.0  # drives the player marker's pulsing glow


func _init() -> void:
	clip_contents = true  # keep off-track cars from drawing outside the panel
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Give it the track cells (world positions) and the racers to track.
func setup(points: PackedVector3Array, racers: Array) -> void:
	_points = points
	_racers = racers
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in points:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.z)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.z)
	if points.is_empty():
		mn = Vector2.ZERO
		mx = Vector2.ONE
	var margin := Constants.CELL_SIZE
	_lo = mn - Vector2(margin, margin)
	_span = (mx - mn) + Vector2(margin * 2.0, margin * 2.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not _racers.is_empty():
		_time += delta
		queue_redraw()  # the cars move every frame


# World (x, z) -> panel pixel, fit uniformly with the track centred.
func _fit() -> Dictionary:
	var area := size - Vector2(PAD * 2.0, PAD * 2.0)
	var s := minf(area.x / maxf(_span.x, 1.0), area.y / maxf(_span.y, 1.0))
	var drawn := _span * s
	return {"origin": Vector2(PAD, PAD) + (area - drawn) * 0.5, "scale": s}


func _map(wx: float, wz: float, f: Dictionary) -> Vector2:
	return f.origin + Vector2((wx - _lo.x) * f.scale, (wz - _lo.y) * f.scale)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 2.0)

	var f := _fit()
	var cell: float = Constants.CELL_SIZE * f.scale
	var box := Vector2(cell, cell) * 0.62  # half-size, slightly overlapping neighbours
	for p in _points:
		var m := _map(p.x, p.z, f)
		draw_rect(Rect2(m - box, box * 2.0), TRACK, true)

	for r in _racers:
		var car = r.car
		if car == null:
			continue
		var m := _map(car.global_position.x, car.global_position.z, f)
		if r.is_player:
			# A pulsing halo behind the player marker — a little beacon so it reads
			# as a light and is easy to track at a glance.
			var pulse: float = 0.5 + 0.5 * sin(_time * 4.5)
			draw_circle(m, 10.0 + pulse * 4.0, Color(1.0, 0.95, 0.55, 0.12 + pulse * 0.18))
			draw_circle(m, 7.0, Color(1.0, 1.0, 1.0, 1.0))
			draw_arc(m, 7.0, 0.0, TAU, 22, Color(0.0, 0.0, 0.0, 0.7), 1.5)
		else:
			draw_circle(m, 3.5, r.color)
