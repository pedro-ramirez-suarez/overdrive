# ADR 0001 — Custom raycast arcade car instead of VehicleBody3D

Status: Accepted (M1)

## Context

The signature feature of this game is stunt driving — loops, corkscrews,
big-air ramps — where the car must stay glued to the road even when the road is
upside down (SPEC.md §1, §5.1). That requires overriding the direction of
gravity per-frame to point *into the track surface* while grounded, and
reverting to world-down while airborne.

Godot's built-in `VehicleBody3D` bakes in world-down gravity and its own
suspension/tyre model, which fights track-relative gravity and is hard to bend
to this use case.

## Decision

Implement a custom arcade controller (`ArcadeCar.gd`) on a plain `RigidBody3D`:

- `gravity_scale = 0`; we integrate gravity ourselves as a **single overridable
  vector** (`gravity_direction`). In M1 it is world-down; M2 will aim it along
  the inverted averaged road normal while grounded.
- Four `RayCast3D` "wheels" apply spring + damping forces for suspension and
  detect grounding.
- Grip is an arcade lateral-velocity killer (fraction removed per step), not a
  tyre-slip model. The handbrake scales grip down for slides.
- Steering is a P-controller on **yaw rate about the car's own up axis**, which
  leaves pitch/roll untouched — important so the body can rotate freely through
  a loop in M2.

## Consequences

- Full control over the two hard problems in §5; M2 only needs to change
  `gravity_direction` each frame.
- We own suspension/grip tuning; all such numbers live in the `CarProfile`
  resource, not in code.
- We forgo `VehicleBody3D`'s built-in wheel visuals/steering; those become our
  responsibility later if we want spinning wheel meshes.
