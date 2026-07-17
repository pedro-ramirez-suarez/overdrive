# ADR 0002 — Track-relative gravity, surface alignment, procedural stunt geometry

Status: Accepted (M2)

## Context

M2 has to prove the signature stunt physics (SPEC.md §5.1, §M2): a car that
drives normally on flat ground but stays glued through a vertical loop and
corkscrew, then falls naturally off a ramp.

## Decisions

### 1. Track-relative gravity (per §5.1)

`ArcadeCar` blends its `gravity_direction` each physics frame:

- **Grounded** → toward `-surface_normal` (the inverted averaged road normal).
  This presses the car *into* whatever surface it is on, so at the top of a loop
  "down" points up into the track and the car stays pinned.
- **Airborne** → toward world `-Y`, so jumps arc under real gravity.

The blend (`gravity_blend_speed`) avoids a snap at the ground↔air transition.

Consequence: while grounded the car is held to the road at essentially any
speed — very forgiving, matching the "don't fight the player" pillar. A car only
"falls off" if it loses wheel contact (a bump launches it) and goes airborne.

### 2. Surface-alignment assist

Track-relative gravity alone does not rotate the *chassis* to follow the road;
relying on suspension geometry to pitch the body around a loop is fragile. So we
add a proportional assist that rotates the body's up-axis toward
`surface_normal`, acting only on the pitch/roll part of angular velocity (its
rotation axis is perpendicular to `up`), leaving the yaw steering untouched.
Tunables: `align_gain`, `align_responsiveness`. This is what actually carries the
body around the loop and corkscrew. Skipped while airborne so the car tumbles
and reorients under gravity.

### 3. Stunt geometry is procedural, not hand-modelled

The loop and corkscrew are built at run time by `RibbonPiece.gd` as an
`ArrayMesh` (via `SurfaceTool`) plus a matching `ConcavePolygonShape3D`, sweeping
a road-width strip along a parametric curve. Chosen over hand-authored CSG or
`.glb` because the geometry is exact, deterministic, and fully parameterised
(radius, width, segments) — much easier to get right and to tune than modelling
a loop by hand. The tile system (M3) will supersede this with authored meshes;
`RibbonPiece` is M2 scaffolding.

Trade-off: the geometry is invisible in the editor viewport (the script is not
`@tool`) and only appears when the scene is played. Acceptable for a test
playground; revisited if we want editor previews.
