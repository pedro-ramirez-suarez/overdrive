class_name Haptics
extends RefCounted
## Controller rumble helper. Central place so the strength/duration of each kind of
## feedback (landings, impacts, off-road) is tuned in one spot and every call site
## degrades gracefully when no pad is connected.
##
## Godot drives vibration per device with two motors: `weak` (the high-frequency
## buzz) and `strong` (the low-frequency rumble). We always target the first
## connected pad — the game is single-player and its controller support assumes
## device 0.

## Master switch, so rumble can be silenced without touching call sites.
static var enabled: bool = true


## Fire a one-off vibration. No-op when disabled or when nothing is plugged in, so
## callers never have to check first.
static func pulse(weak: float, strong: float, duration: float) -> void:
	if not enabled or Input.get_connected_joypads().is_empty():
		return
	Input.start_joy_vibration(0, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Stop any vibration in progress — used when a car leaves the road-rumble state so
## the low buzz doesn't linger.
static func stop() -> void:
	if Input.get_connected_joypads().is_empty():
		return
	Input.stop_joy_vibration(0)
