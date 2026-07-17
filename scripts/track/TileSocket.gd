class_name TileSocket
extends Resource
## One edge of a tile's connection contract (SPEC.md §M3, §5.2).
##
## A TileDefinition holds four of these (base, pre-rotation) for its N/E/S/W
## edges. Two adjacent placed tiles connect across their shared edge iff both
## sockets have road, their effective elevation levels match, and their slopes
## are complementary (see TrackGrid.sockets_connect).

enum Slope {
	FLAT,  ## Road is level where it meets this edge.
	UP,    ## Road pitches up as it exits this edge.
	DOWN,  ## Road pitches down as it exits this edge.
}

## Is there a road opening on this edge?
@export var has_road: bool = false

## Integer height level at this edge, relative to the tile's placed elevation.
@export var elevation_level: int = 0

## Pitch of the road as it meets this edge.
@export var slope: Slope = Slope.FLAT
