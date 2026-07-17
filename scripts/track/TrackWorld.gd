class_name TrackWorld
extends RefCounted
## Shared world construction for the drivable/race scenes (SPEC.md §M3/§M4):
## sky+light environment, a ground plane on the road layer, and the tile
## instances for a TrackGrid. Used by both TrackPlay and RaceManager.


static func populate(parent: Node3D, grid: TrackGrid, lib: TileLibrary) -> void:
	add_environment(parent)
	if GameState.current_terrain != null:
		TerrainWorld.build(parent, GameState.current_terrain, grid)
	else:
		add_ground(parent)
	add_tiles(parent, grid, lib)
	add_props(parent, grid, GameState.current_terrain)


## Instance every prop, each sitting on the ground at its cell.
static func add_props(parent: Node3D, grid: TrackGrid, terrain: Terrain) -> void:
	if grid.props.is_empty():
		return
	var root := Node3D.new()
	root.name = "PropsRoot"
	parent.add_child(root)
	for cell in grid.props:
		var node := make_prop(cell, grid.props[cell], terrain)
		root.add_child(node)


## Build one prop, placed on the terrain with `anchor` as its plot origin. Height
## is read from the ground rather than stored, so props follow the land when it is
## sculpted.
static func make_prop(anchor: Vector2i, prop: PlacedProp, terrain: Terrain) -> PropGeo:
	var node := PropGeo.new()
	node.kind = prop.kind
	node.variant = prop.variant
	var xf := prop_transform(anchor, prop, terrain)
	node.position = xf.position
	node.rotation = xf.rotation
	node.scale = xf.scale
	return node


## Where a prop sits and how big it is: centred over its (possibly multi-cell) plot
## and scaled to fill it. Shared by the world and the editor's ghost so the preview
## matches what gets placed.
static func prop_transform(anchor: Vector2i, prop: PlacedProp, terrain: Terrain) -> Dictionary:
	var cells := TrackGrid.prop_cells(anchor, prop.kind, prop.rotation)
	var mid := Vector2.ZERO
	for c in cells:
		mid += Vector2(c.x, c.y)
	mid /= float(cells.size())

	var level: int = terrain.height_level(anchor) if terrain != null else 0
	var pos := Vector3(mid.x * Constants.CELL_SIZE, level * Constants.ELEVATION_STEP, mid.y * Constants.CELL_SIZE)

	# Multi-cell props are scaled up to fill their plot; single-cell props keep the
	# hand-authored size. Uniform, min-fit, so the shape never spills its lot.
	var scale := 1.0
	var size: Vector2i = PropGeo.cell_size(prop.kind)
	if size.x * size.y > 1:
		var plot_min: float = float(mini(size.x, size.y)) * Constants.CELL_SIZE
		var authored: Vector2 = PropGeo.footprint(prop.kind, prop.variant)
		var authored_max: float = maxf(authored.x, authored.y)
		scale = 0.85 * plot_min / maxf(authored_max, 0.1)

	return {
		"position": pos,
		"rotation": Vector3(0.0, -prop.rotation * PI / 2.0, 0.0),
		"scale": Vector3(scale, scale, scale),
	}


static func add_environment(parent: Node3D) -> void:
	# Sky, sun, fog and weather all come from the time/weather chosen on the
	# track-select screen (defaults: noon, clear).
	Atmosphere.apply(parent, GameState.race_time, GameState.race_weather)


const OFFTRACK_GROUP := "offtrack"


static func add_ground(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Constants.ROAD_BIT
	body.collision_mask = 0
	body.add_to_group(OFFTRACK_GROUP)  # wheels on this count as off the track
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2000, 2, 2000)
	col.shape = shape
	col.position = Vector3(0, -1.05, 0)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	mi.mesh = plane
	mi.position = Vector3(0, -0.05, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.24)
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(250, 250, 1)
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)


static func add_tiles(parent: Node3D, grid: TrackGrid, lib: TileLibrary) -> void:
	var root := Node3D.new()
	root.name = "TilesRoot"
	parent.add_child(root)
	for cell in grid.tiles:
		var node := lib.instantiate_placed(cell, grid.tiles[cell], grid)
		if node != null:
			root.add_child(node)
