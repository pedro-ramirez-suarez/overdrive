class_name PoliceBeacon
extends Node3D
## A revolving red/blue roof beacon for the police cars. Purely light — no housing
## and no solid lens: each colour is a camera-facing sprite with a radial gradient
## that fades to transparent at the edges, drawn additively so it reads as a glow,
## not a ball. The two sprites sit on opposite sides of a spinner revolved around
## the vertical axis, so the colours sweep like an old rotating beacon, and a single
## OmniLight crossfades red<->blue in step so the glow thrown on the car and road
## sweeps with them. One light per beacon keeps a full field of patrol cars cheap.

const RED := Color(1.0, 0.05, 0.05)
const BLUE := Color(0.20, 0.30, 1.0)

## How fast the beacon revolves, in radians per second.
const SPIN := 9.0

## Radius the two glow sprites orbit the centre — small, so they read as one beacon.
const ORBIT := 0.075

var _spinner: Node3D
var _light: OmniLight3D
var _angle: float = 0.0


func _ready() -> void:
	var glow := _glow_texture()

	_spinner = Node3D.new()
	add_child(_spinner)

	# Red sprite on +X, blue on -X — opposite sides, so a half-turn swaps which
	# colour points at you.
	_spinner.add_child(_orb(Vector3(ORBIT, 0.0, 0.0), RED, glow))
	_spinner.add_child(_orb(Vector3(-ORBIT, 0.0, 0.0), BLUE, glow))

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 0.04, 0.0)
	_light.omni_range = 3.5
	_light.light_energy = 2.5
	_light.shadow_enabled = false
	add_child(_light)


## A soft glow sprite: a billboarded quad textured with a radial white->transparent
## gradient, tinted and drawn additively so only light shows — no solid silhouette.
func _orb(offset: Vector3, color: Color, glow: Texture2D) -> MeshInstance3D:
	var orb := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	orb.mesh = quad
	orb.position = offset
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = glow
	mat.albedo_color = color
	orb.material_override = mat
	return orb


## Radial white->transparent gradient, so a quad textured with it fades softly to
## nothing at its edges — a round glow with no hard rim.
func _glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _process(delta: float) -> void:
	_angle = fmod(_angle + SPIN * delta, TAU)
	_spinner.rotation.y = _angle
	# Crossfade the glow between the two orbs as they sweep, with a slight pulse so it
	# flickers like a real beacon rather than sitting at a flat brightness.
	var mix: float = sin(_angle) * 0.5 + 0.5
	_light.light_color = BLUE.lerp(RED, mix)
	_light.light_energy = 2.0 + 1.5 * absf(sin(_angle * 2.0))
