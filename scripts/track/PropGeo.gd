class_name PropGeo
extends StaticBody3D
## Procedural scenery (SPEC.md §M3): trees, houses and town buildings, built from
## primitives at run time so the game ships no prop models and a variant can never
## go missing. Set `kind` and `variant`, then add to the tree — _ready builds it.
##
## Sized in real-world meters against the 8 m cell, i.e. to the road and terrain
## rather than to the (deliberately under-scale) cars: a cell is one house plot.
##
## Props are solid, on the wall layer, so a town is something you can crash into.

enum Kind { TREE, HOUSE, BUILDING, SCENERY }

const KIND_IDS: Array[String] = ["tree", "house", "building", "scenery"]
const KIND_NAMES: Array[String] = ["Tree", "House", "Building", "Scenery"]
const VARIANT_NAMES: Array = [
	["Conifer", "Broadleaf", "Poplar", "Bare"],
	["Cottage", "Bungalow", "Two-storey", "L-shaped"],
	["Tower", "Mid-rise", "Wide block", "Stepped"],
	["Boulder", "Water tower", "Billboard", "Street lamp"],
]
const VARIANTS := 4

const BARK := Color(0.31, 0.23, 0.16)
const LEAF_A := Color(0.16, 0.40, 0.20)
const LEAF_B := Color(0.24, 0.48, 0.24)
const STONE := Color(0.52, 0.52, 0.55)

@export var kind: Kind = Kind.TREE
@export var variant: int = 0


func _ready() -> void:
	collision_layer = Constants.WALL_BIT
	collision_mask = 0
	match kind:
		Kind.TREE: _build_tree(variant % VARIANTS)
		Kind.HOUSE: _build_house(variant % VARIANTS)
		Kind.BUILDING: _build_building(variant % VARIANTS)
		_: _build_scenery(variant % VARIANTS)


## Plot size in CELLS a prop reserves. Buildings sit on a 2x2 block (four cells),
## houses on a 1x2 lot (two cells); trees and small scenery stay one cell. This is
## the footprint the editor blocks out and the geometry is scaled to fill.
static func cell_size(kind: int) -> Vector2i:
	match kind:
		Kind.BUILDING: return Vector2i(2, 2)
		Kind.HOUSE: return Vector2i(1, 2)
		_: return Vector2i(1, 1)


## Rough bounds a prop occupies, used for the editor's footprint hint.
static func footprint(kind: int, variant: int) -> Vector2:
	match kind:
		Kind.TREE: return Vector2(3.0, 3.0)
		Kind.HOUSE: return Vector2(6.0, 5.0)
		Kind.BUILDING: return Vector2(6.5, 6.5)
		_: return Vector2(3.0, 3.0) if variant != 2 else Vector2(4.0, 1.0)
	return Vector2(4.0, 4.0)


# --- Trees ------------------------------------------------------------------

func _build_tree(v: int) -> void:
	match v:
		0:  # Conifer: stacked cones.
			_trunk(0.35, 2.0)
			_cone(2.0, 3.0, 1.8, LEAF_A)
			_cone(1.5, 2.6, 3.6, LEAF_B)
			_cone(0.9, 2.0, 5.2, LEAF_A)
			_solid(Vector3(2.6, 7.2, 2.6), 3.6)
		1:  # Broadleaf: a round canopy.
			_trunk(0.4, 2.6)
			_sphere(2.3, 4.6, LEAF_B)
			_sphere(1.5, 6.0, LEAF_A)
			_solid(Vector3(3.4, 7.0, 3.4), 3.5)
		2:  # Poplar: tall and narrow.
			_trunk(0.3, 3.0)
			_cyl(1.1, 5.0, 5.2, LEAF_A)
			_sphere(1.1, 7.6, LEAF_B)
			_solid(Vector3(2.0, 8.4, 2.0), 4.2)
		_:  # Bare: a dead trunk with branches.
			_trunk(0.42, 4.2)
			for a in [0.0, 2.1, 4.2]:
				var arm := _box(Vector3(0.22, 2.2, 0.22), Vector3(cos(a) * 0.7, 4.4, sin(a) * 0.7), BARK)
				arm.rotation = Vector3(0.5 * sin(a), a, 0.5 * cos(a))
			_solid(Vector3(1.8, 5.6, 1.8), 2.8)


func _trunk(r: float, h: float) -> void:
	_cyl(r, h, h * 0.5, BARK)


# --- Houses -----------------------------------------------------------------

func _build_house(v: int) -> void:
	match v:
		0:  # Cottage: one storey under a gable.
			_box(Vector3(6.0, 3.0, 5.0), Vector3(0, 1.5, 0), Color(0.86, 0.83, 0.74))
			_gable(6.2, 2.0, 5.2, 4.0, Color(0.55, 0.24, 0.18))
			_box(Vector3(0.7, 1.6, 0.7), Vector3(2.0, 3.8, 1.4), Color(0.5, 0.45, 0.42))
			_windows(6.0, 5.0, 1.6, 2)
			_solid(Vector3(6.2, 5.0, 5.2), 2.5)
		1:  # Bungalow: flat roof, wide.
			_box(Vector3(6.4, 2.6, 5.4), Vector3(0, 1.3, 0), Color(0.80, 0.78, 0.72))
			_box(Vector3(6.8, 0.3, 5.8), Vector3(0, 2.75, 0), Color(0.42, 0.42, 0.45))
			_windows(6.4, 5.4, 1.5, 2)
			_solid(Vector3(6.8, 2.9, 5.8), 1.45)
		2:  # Two-storey with a chimney.
			_box(Vector3(5.4, 5.4, 5.0), Vector3(0, 2.7, 0), Color(0.84, 0.80, 0.70))
			_gable(5.6, 1.8, 5.2, 6.3, Color(0.42, 0.30, 0.26))
			_box(Vector3(0.8, 2.2, 0.8), Vector3(-1.8, 6.6, 1.2), Color(0.48, 0.42, 0.40))
			_windows(5.4, 5.0, 1.6, 2)
			_windows(5.4, 5.0, 4.0, 2)
			_solid(Vector3(5.6, 7.2, 5.2), 3.6)
		_:  # L-shaped.
			_box(Vector3(6.0, 3.2, 3.0), Vector3(0, 1.6, -1.2), Color(0.82, 0.79, 0.73))
			_box(Vector3(3.0, 3.2, 5.4), Vector3(-1.5, 1.6, 1.2), Color(0.82, 0.79, 0.73))
			_box(Vector3(6.4, 0.3, 3.4), Vector3(0, 3.35, -1.2), Color(0.5, 0.32, 0.26))
			_box(Vector3(3.4, 0.3, 5.8), Vector3(-1.5, 3.35, 1.2), Color(0.5, 0.32, 0.26))
			_windows(6.0, 3.0, 1.6, 2)
			_solid(Vector3(6.4, 3.5, 6.0), 1.75)


## A gable roof: a prism spanning `w` x `d`, `h` tall, based at `y`.
func _gable(w: float, h: float, d: float, y: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w, h, d)
	mi.mesh = prism
	mi.material_override = _mat(color, 0.9)
	mi.position = Vector3(0, y + h * 0.5, 0)
	add_child(mi)


## A band of windows on the front and back faces.
func _windows(w: float, d: float, y: float, count: int) -> void:
	var mat := _mat(Color(0.16, 0.22, 0.30), 0.25)
	mat.metallic = 0.4
	for i in range(count):
		var x: float = lerpf(-w * 0.28, w * 0.28, 0.0 if count == 1 else float(i) / float(count - 1))
		_box(Vector3(1.0, 1.1, 0.1), Vector3(x, y, d * 0.5 + 0.02), mat)
		_box(Vector3(1.0, 1.1, 0.1), Vector3(x, y, -d * 0.5 - 0.02), mat)


# --- Town buildings ---------------------------------------------------------

func _build_building(v: int) -> void:
	match v:
		0:  # Tower.
			_box(Vector3(5.0, 22.0, 5.0), Vector3(0, 11.0, 0), Color(0.62, 0.66, 0.72))
			_box(Vector3(5.4, 0.4, 5.4), Vector3(0, 22.2, 0), Color(0.40, 0.43, 0.48))
			_window_grid(5.0, 5.0, 22.0, 6)
			_solid(Vector3(5.4, 22.4, 5.4), 11.2)
		1:  # Mid-rise with a setback top.
			_box(Vector3(6.0, 12.0, 6.0), Vector3(0, 6.0, 0), Color(0.72, 0.68, 0.60))
			_box(Vector3(4.0, 3.0, 4.0), Vector3(0, 13.5, 0), Color(0.66, 0.62, 0.55))
			_window_grid(6.0, 6.0, 12.0, 4)
			_solid(Vector3(6.0, 15.0, 6.0), 7.5)
		2:  # Wide block.
			_box(Vector3(6.6, 8.0, 5.0), Vector3(0, 4.0, 0), Color(0.70, 0.56, 0.46))
			_box(Vector3(7.0, 0.4, 5.4), Vector3(0, 8.2, 0), Color(0.42, 0.40, 0.40))
			_window_grid(6.6, 5.0, 8.0, 3)
			_solid(Vector3(7.0, 8.4, 5.4), 4.2)
		_:  # Stepped / ziggurat.
			_box(Vector3(6.4, 6.0, 6.4), Vector3(0, 3.0, 0), Color(0.66, 0.64, 0.62))
			_box(Vector3(4.8, 5.0, 4.8), Vector3(0, 8.5, 0), Color(0.70, 0.68, 0.66))
			_box(Vector3(3.0, 4.0, 3.0), Vector3(0, 13.0, 0), Color(0.74, 0.72, 0.70))
			_window_grid(6.4, 6.4, 6.0, 2)
			_solid(Vector3(6.4, 15.0, 6.4), 7.5)


## Rows of windows up the front and back.
func _window_grid(w: float, d: float, h: float, rows: int) -> void:
	for i in range(rows):
		_windows(w, d, lerpf(2.0, h - 1.6, 0.0 if rows == 1 else float(i) / float(rows - 1)), 2)


# --- Scenery ----------------------------------------------------------------

func _build_scenery(v: int) -> void:
	match v:
		0:  # Boulder.
			var rock := _sphere(1.6, 1.1, STONE)
			rock.scale = Vector3(1.3, 0.8, 1.0)
			var rock2 := _sphere(0.9, 0.6, Color(0.46, 0.46, 0.48))
			rock2.position = Vector3(1.4, 0.5, 0.6)
			_solid(Vector3(4.0, 2.0, 3.0), 1.0)
		1:  # Water tower.
			for p in [Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(-1.1, 1.1), Vector2(1.1, 1.1)]:
				_box(Vector3(0.25, 5.0, 0.25), Vector3(p.x, 2.5, p.y), Color(0.45, 0.45, 0.48))
			_cyl(1.9, 3.0, 6.5, Color(0.66, 0.70, 0.72))
			_cone(1.9, 1.2, 8.4, Color(0.5, 0.28, 0.24))
			_solid(Vector3(3.8, 9.0, 3.8), 4.5)
		2:  # Billboard.
			_box(Vector3(0.3, 3.4, 0.3), Vector3(-1.2, 1.7, 0), Color(0.4, 0.4, 0.42))
			_box(Vector3(0.3, 3.4, 0.3), Vector3(1.2, 1.7, 0), Color(0.4, 0.4, 0.42))
			_box(Vector3(4.4, 2.4, 0.2), Vector3(0, 4.4, 0), Color(0.90, 0.86, 0.80))
			_box(Vector3(3.6, 1.0, 0.1), Vector3(0, 4.6, 0.16), _mat(Color(0.85, 0.25, 0.20), 0.5))
			_solid(Vector3(4.4, 5.6, 0.6), 2.8)
		_:  # Street lamp.
			_cyl(0.16, 6.0, 3.0, Color(0.38, 0.38, 0.42))
			_box(Vector3(1.4, 0.18, 0.18), Vector3(0.6, 6.0, 0), Color(0.38, 0.38, 0.42))
			var bulb := _sphere(0.32, 5.85, Color(1.0, 0.95, 0.7))
			var m := _mat(Color(1.0, 0.95, 0.7), 0.3)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.95, 0.7)
			m.emission_energy_multiplier = 2.0
			bulb.material_override = m
			bulb.position = Vector3(1.2, 5.85, 0)
			_solid(Vector3(0.5, 6.2, 0.5), 3.1)


# --- Primitives -------------------------------------------------------------

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _box(size: Vector3, pos: Vector3, color_or_mat: Variant) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = color_or_mat if color_or_mat is Material else _mat(color_or_mat, 0.85)
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(r: float, h: float, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = _mat(color, 0.9)
	mi.position = Vector3(0, y, 0)
	add_child(mi)
	return mi


func _cone(r: float, h: float, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = _mat(color, 0.9)
	mi.position = Vector3(0, y, 0)
	add_child(mi)
	return mi


func _sphere(r: float, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	mi.mesh = s
	mi.material_override = _mat(color, 0.9)
	mi.position = Vector3(0, y, 0)
	add_child(mi)
	return mi


## One box collider standing in for the whole prop — props are obstacles, not
## surfaces to drive on, so an approximate solid is enough.
func _solid(size: Vector3, y: float) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, y, 0)
	add_child(cs)
