# ADR 0004 — Race loop (M4)

Status: Accepted (M4)

## Context

M4 turns a built track into a race (SPEC.md §M4): checkpoints, countdown, lap
timing, respawn, AI opponents, and standings.

## Decisions

### 1. Control abstraction on the car

`ArcadeCar` no longer reads `Input` inside its physics functions. It exposes
control fields (`throttle`, `brake`, `steer`, `handbrake`) plus flags
`player_controlled`, `control_enabled`, and `self_reset_enabled`. A player car
fills the fields from Input; an `AIController` writes them instead. This is the
single change that lets the same vehicle serve both the player and the AI (as the
spec intends — "AI just feeds it steering/throttle"), and lets the race manager
freeze cars during the countdown without special-casing physics.

Verified: the AI drove a seeded 8-cell circuit through all corners, so the
refactored control + steering-sign path is correct end to end.

### 2. Checkpoints from the road walk

`RacePath` derives an ordered cell path by walking road connections
(`cells_connected`) from the Start tile. `RaceManager` drops a `Checkpoint`
(Area3D) on each path cell — a tall 30 m column so it catches the car at any
elevation, including through a loop. Racers must trigger checkpoints in order
(out-of-order hits are ignored — anti-shortcut); crossing index 0 with all others
passed completes a lap. Ranking uses a monotonic `total_passed` count plus the
fractional distance to the next checkpoint.

### 3. AI: waypoint follow + rubber-band

`AIController` steers toward the next waypoint (cell centres), eases throttle in
proportion to the turn angle, and takes a `speed_factor` from the manager (1.08
when behind the player, 0.94 when ahead). Deliberately simple per the spec; racing
lines and loop-aware AI are future work. Waypoints are cell centres, so the AI
follows flat circuits well but is not expected to drive loops.

### 4. Respawn & shared world

Respawn triggers on falling below y=-8, or being inverted and slow for >2.5 s, or
the player pressing R; the car is returned upright at the last passed checkpoint
facing the next one. World construction (env, ground, tiles) moved to a shared
`TrackWorld` helper used by both `TrackPlay` (free drive) and `RaceManager`.

The editor gained a **Race** button beside **Test Drive**; both stash the grid on
`GameState` and switch scenes. Race settings live on `GameState`
(`race_laps`, `race_ai_count`).
