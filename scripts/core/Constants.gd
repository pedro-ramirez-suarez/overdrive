extends Node
## Global fixed constants for OVERDRIVE.
##
## Registered as the `Constants` autoload (see project.godot). Values here are
## the deterministic units the whole game depends on — see SPEC.md §2. They must
## never be redefined as magic literals elsewhere.

# --- Spatial units (SPEC.md §2) ---

## One grid cell is CELL_SIZE x CELL_SIZE meters on the ground plane.
const CELL_SIZE: float = 8.0

## One elevation "level" (one ramp) equals this many meters of vertical offset.
const ELEVATION_STEP: float = 3.0

## Maximum terrain height in levels (one level = one ramp = ELEVATION_STEP).
## Tall enough for real mountains (16 * 3 m = 48 m).
const MAX_TERRAIN_LEVEL: int = 16

# --- Physics ---

## Arcade gravity magnitude (m/s^2). Deliberately stronger than 9.8 so the car
## feels planted and responsive rather than floaty. The *direction* of gravity
## is owned per-car (world-down in M1, track-relative in M2).
const GRAVITY: float = 20.0

# --- Physics layers ---
# Layer numbers (1-indexed, as shown in the Godot inspector) and their matching
# bit-mask values. Use the *_BIT values when assigning collision_layer /
# collision_mask in code.

const LAYER_ROAD: int = 1
const LAYER_CAR: int = 2
const LAYER_TRIGGER: int = 3
const LAYER_WALL: int = 4

const ROAD_BIT: int = 1 << (LAYER_ROAD - 1)     # 1
const CAR_BIT: int = 1 << (LAYER_CAR - 1)       # 2
const TRIGGER_BIT: int = 1 << (LAYER_TRIGGER - 1) # 4
const WALL_BIT: int = 1 << (LAYER_WALL - 1)     # 8
