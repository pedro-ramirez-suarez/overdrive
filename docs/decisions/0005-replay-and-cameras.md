# ADR 0005 — Replay & cameras (M5)

Status: Accepted (M5)

## Context

M5 adds the iconic multi-angle replay (SPEC.md §M5): record a race, play it back
with scrub/pause/slow-mo through several cameras, and save/load to disk.

## Decisions

### 1. Record transforms, not inputs

`ReplayRecorder` captures each car's `global_transform` every physics frame into
a `Replay` (per-car `PackedVector3Array` of positions + `Array` of Quaternions).
Transform snapshots make playback deterministic and independent of physics — the
spec's stated preference — at the cost of a larger buffer than input recording.
A frame cap (~4 min) bounds memory. `RaceManager` drives capture from its
`_physics_process` while racing and stashes the finished `Replay` on `GameState`.

### 2. Playback = transform-driven ghost cars

`ReplayController` rebuilds the track (shared `TrackWorld`) and spawns the normal
`Car.tscn` per recorded car, but neutered into visual props: `set_physics_process(
false)`, `freeze = true`, `FREEZE_MODE_KINEMATIC`. Each frame it samples the
replay (lerp position, slerp rotation) and writes the ghost transforms.
`ReplayPlayer` owns the clock: play/pause, frame scrub, discrete slow-mo speeds
(0.1×–2×), restart. Cars are colour-coded via `CarBody.body_color`, recorded in
the replay so ghosts match the race.

### 3. Cameras

`ReplayCamera` cycles chase / cockpit / trackside / helicopter. Trackside points
are auto-generated from the race path (waypoints pushed outward from the track
centroid and raised), and the camera picks the nearest to the focused car each
frame — the spec's "auto-pick nearest authored camera point" without needing an
authored camera tile yet.

### 4. Persistence

`Replay.save_to`/`load_from` use Godot's binary Variant serialization
(`FileAccess.store_var`/`get_var`) under `user://replays/` — Quaternion and
`PackedVector3Array` serialize natively, so it is compact and simple (the spec
allows a binary buffer). A magic header guards the format. Round-trip verified:
save → load → sample reproduces the recorded positions exactly.
