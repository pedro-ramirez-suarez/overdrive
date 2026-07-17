class_name TileDefinition
extends Resource
## A type of track tile (SPEC.md §M3). Defines its identity, footprint, mesh
## scene, and the four base (pre-rotation) edge sockets that drive connection
## validation. In M3 these are constructed in code by TileLibrary; they can move
## to authored .tres resources later without changing the data model.

enum Category { STRAIGHT, CORNER, RAMP, LOOP, CORKSCREW, BRIDGE, BANK, START, SPECIAL }

@export var id: StringName
@export var display_name: String
## Cells occupied. Usually 1x1 in M3.
@export var footprint: Vector2i = Vector2i.ONE
## Scene instanced into the world for this tile (a StaticBody3D on the road layer).
@export var mesh: PackedScene
## Base sockets in edge order [N, E, S, W], before the tile's placement rotation.
## Used for 1x1 tiles.
@export var sockets: Array[TileSocket] = []
## For multi-cell tiles (footprint > 1x1): road connection points, each a
## Dictionary { cell: Vector2i (base offset), dir: int (base N/E/S/W), elevation: int }.
@export var road_connectors: Array = []
@export var is_stunt: bool = false
@export var category: Category = Category.STRAIGHT
