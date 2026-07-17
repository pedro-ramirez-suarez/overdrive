class_name PlacedProp
extends Resource
## One piece of scenery on the map (SPEC.md §M3).
##
## Deliberately separate from PlacedTile: props carry no sockets and take no part
## in the connection or footprint rules — they are decoration, one per cell.
## Their height is not stored; a prop reads the terrain under it at build time, so
## it follows the ground when you sculpt.

@export var kind: PropGeo.Kind = PropGeo.Kind.TREE
## Which shape within the kind, 0..PropGeo.VARIANTS-1.
@export var variant: int = 0
## Quarter turns, matching PlacedTile.
@export var rotation: int = 0


static func make(kind: int, variant: int, rotation: int) -> PlacedProp:
	var p := PlacedProp.new()
	p.kind = kind as PropGeo.Kind
	p.variant = variant
	p.rotation = rotation
	return p
