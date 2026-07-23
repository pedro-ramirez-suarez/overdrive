class_name Speedometer
extends Control
## Arc speedometer for the race HUD. Reads the player car's speed each frame and
## draws a 270-degree dial with tick marks, a sweeping needle and a digital km/h
## readout. Fully code-drawn so it needs no art.

## The car to read speed from. Set by the race manager once the player spawns.
var car: ArcadeCar

## Full-scale of the dial in km/h, rounded up from the car's top speed in _ready.
var max_kmh: float = 220.0

const START := deg_to_rad(135.0)   # needle rest, lower-left
const SWEEP := deg_to_rad(270.0)   # clockwise round to lower-right
const RADIUS := 74.0
const TICKS := 8

var _kmh: float = 0.0
var _font: Font
var _scaled: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(168.0, 168.0)
	size = custom_minimum_size
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if car == null:
		return
	if not _scaled and car.profile != null:
		# Round the dial up to a tidy full scale a little above the car's top speed.
		max_kmh = ceilf(car.profile.max_speed * 3.6 * 1.12 / 20.0) * 20.0
		_scaled = true
	var target: float = car.linear_velocity.length() * 3.6  # m/s -> km/h
	# Ease the needle so it sweeps rather than jitters.
	_kmh = lerpf(_kmh, target, clampf(delta * 8.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var ratio: float = clampf(_kmh / max_kmh, 0.0, 1.0)

	# Dial face.
	draw_circle(c, RADIUS + 14.0, Color(0.05, 0.06, 0.09, 0.74))
	draw_arc(c, RADIUS + 14.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.10), 2.0, true)

	# Track arc, then the lit arc up to the current speed, coloured by how fast.
	draw_arc(c, RADIUS, START, START + SWEEP, 72, Color(0.24, 0.27, 0.33), 6.0, true)
	draw_arc(c, RADIUS, START, START + SWEEP * ratio, 72, _speed_color(ratio), 6.0, true)

	# Tick marks around the dial.
	for i in range(TICKS + 1):
		var f: float = float(i) / float(TICKS)
		var dir: Vector2 = Vector2(cos(START + SWEEP * f), sin(START + SWEEP * f))
		var long: bool = (i % 2 == 0)
		draw_line(c + dir * (RADIUS - (11.0 if long else 6.0)), c + dir * (RADIUS - 1.0),
			Color(0.78, 0.82, 0.88, 0.9 if long else 0.6), 2.0 if long else 1.0)

	# Needle + hub.
	var nd: Vector2 = Vector2(cos(START + SWEEP * ratio), sin(START + SWEEP * ratio))
	draw_line(c - nd * 10.0, c + nd * (RADIUS - 14.0), Color(0.95, 0.27, 0.22), 3.0, true)
	draw_circle(c, 6.0, Color(0.90, 0.92, 0.95))

	# Digital readout: big number, small unit beneath.
	var num: String = "%d" % int(round(_kmh))
	var num_w: float = _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(_font, c + Vector2(-num_w * 0.5, 30.0), num,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	var unit_w: float = _font.get_string_size("KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(_font, c + Vector2(-unit_w * 0.5, 46.0), "KM/H",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.66, 0.70, 0.76))


## Green through the low range, amber in the middle, red near the top.
func _speed_color(r: float) -> Color:
	if r < 0.5:
		return Color(0.30, 0.85, 0.35).lerp(Color(0.95, 0.80, 0.20), r * 2.0)
	return Color(0.95, 0.80, 0.20).lerp(Color(0.95, 0.25, 0.20), (r - 0.5) * 2.0)
