# Project Spec — "OVERDRIVE" (working title)

A modern, arcade-styled homage to *Stunts / 4D Sports Driving* (1990): stylized low-poly 3D racing with jumps, loops, and corkscrews, a full modular **track editor**, multi-angle **replays**, and a roster of look-alike cars with distinct handling.

> **How to use this document.** This is the north-star spec for the whole project. It is organized into milestones (M0–M6). Each milestone has a scope, a concrete task list, and **acceptance criteria**. Build **one milestone at a time**, in order. Do not begin a later milestone until the current one's acceptance criteria pass. When told "implement M1," read the whole doc for context but only produce the work in that milestone's section.

---

## 1. Vision & pillars

- **Feel first.** Arcade handling that is immediately fun — grippy, forgiving, fast. Closer to *Horizon Chase* than a sim. If a choice trades realism for fun, choose fun.
- **The editor is the game.** As in the original, user-built tracks are the core loop. The modular tile system and its connection rules are the architectural keystone — get them right before anything downstream.
- **Stunts, not laps.** Loops, corkscrews, ramps, and big air are first-class. The physics must keep a car planted through a vertical loop without the player fighting it.
- **Stylized, not flat.** Low-poly geometry with modern lighting (bloom, crisp shadows, vibrant skyboxes, punchy materials). Readable at speed.

## 2. Tech stack & key decisions

| Area | Decision | Rationale |
|---|---|---|
| Engine | **Godot 4.x** (GDScript 2.0) | Already the chosen engine; strong 3D + low-poly workflow. |
| Physics | **Jolt** (built into Godot 4.4+; else the `godot-jolt` add-on) | Stable rigidbody behavior for arcade vehicles. |
| Vehicle model | **Custom raycast arcade controller** on a `RigidBody3D` — *not* `VehicleBody3D` | We need full control over gravity direction and grip to do track-relative gravity through loops. `VehicleBody3D` fights this. |
| Gravity through stunts | **Track-relative gravity** (see §5) | Physically-honest gravity makes loops brittle and unfun; track-relative gravity sticks the car to the surface and is far easier to tune. |
| Track data format | **JSON** | Human-inspectable, diff-able, easy to version and share. |
| Units | Meters, 1 grid cell = **8 m × 8 m**; 1 elevation level = **2 m** | Fixed constants keep tile authoring and snapping deterministic. |
| Target platforms (MVP) | Windows + Linux desktop | Expand later. |

**Content/legal guardrail (applies to all car and branding work):** cars are *original look-alikes* — evocative silhouettes and invented names only. Do **not** replicate a real marque's exact trade dress, badges, or model names, and do not just rename a 1:1 copy. Handling profiles and names are invented. Flag anything that drifts toward a specific real brand.

## 3. Repository structure

```
res://
├── project.godot
├── SPEC.md                     # this document
├── docs/
│   └── decisions/              # short ADRs when a non-obvious choice is made
├── scenes/
│   ├── vehicle/                # Car.tscn, wheel raycasts
│   ├── track/                  # tile scenes, track root
│   ├── editor/                 # editor UI + grid
│   ├── race/                   # race HUD, countdown, results
│   └── replay/                 # replay cameras + controller
├── scripts/
│   ├── vehicle/                # ArcadeCar.gd, CarProfile.gd (Resource)
│   ├── track/                  # TileDefinition.gd, TileSocket.gd, TrackGrid.gd, TrackSerializer.gd
│   ├── editor/                 # EditorController.gd, PlacementValidator.gd
│   ├── race/                   # RaceManager.gd, Checkpoint.gd, LapTimer.gd, AIController.gd
│   ├── replay/                 # ReplayRecorder.gd, ReplayPlayer.gd, ReplayCamera.gd
│   └── core/                   # constants, autoloads, save/load
├── resources/
│   ├── cars/                   # *.tres CarProfile resources
│   └── tiles/                  # *.tres TileDefinition resources
├── assets/
│   ├── models/ (tiles, cars)   # .glb, low-poly
│   ├── materials/
│   └── sky/
└── tests/                      # GUT tests where practical
```

## 4. Coding conventions (guardrails for Claude Code)

- GDScript 2.0, **static typing everywhere** (`var speed: float = 0.0`, typed function signatures, typed arrays).
- One class per file; `class_name` on anything referenced across files.
- Tunable numbers live in **exported Resources** (`CarProfile`, `TileDefinition`), never as magic literals in logic.
- Autoloads only for genuinely global state (constants, save system). Prefer explicit references otherwise.
- Physics work goes in `_physics_process` / `_integrate_forces`; never apply forces in `_process`.
- Every milestone ends with a **playable/verifiable** state and a short note in `docs/decisions/` for any non-obvious choice.
- Keep commits scoped to one task. Small, reviewable changes.
- No networked/online features in MVP.

---

## 5. The two hard problems (read before M1)

### 5.1 Track-relative gravity

The car must feel normal on flat ground but stay glued to the road through loops and corkscrews, then fall naturally when it launches off a ramp.

Model:

- Each frame, cast rays from the four suspension points downward **relative to the car's own up-axis**.
- If the car is **grounded** (rays hit road within suspension range): the "down" for gravity and suspension is the **averaged surface normal** of the hits (inverted). Apply gravity along that axis. This is what pins the car inside a loop.
- If the car is **airborne** (no hits): gravity reverts to **world down** (`-Y`), so jumps arc naturally and the car reorients toward the ground.
- Blend the transition over a few frames to avoid a snap when leaving/landing surfaces.

This single mechanism is why we use a custom controller instead of `VehicleBody3D`. Nail it in M2 with one hand-built loop before any tile system exists.

### 5.2 Tile connection contract

Every track piece connects to neighbors through a strict socket contract. This is the keystone — the editor, validation, and serialization all depend on it. Fully specified in M3.

---

## 6. Milestones

### M0 — Scaffold & conventions

**Scope:** Empty-but-correct project so all later work has a home.

Tasks:

1. Create the Godot 4 project with the folder structure in §3.
2. Enable Jolt physics; set project up for 3D, forward+ renderer, basic environment (sky, bloom, shadows).
3. Add `core/Constants.gd` autoload with the fixed units from §2 (cell size, elevation step, layer masks for `road`, `car`, `trigger`).
4. Configure input map: `accelerate`, `brake`, `steer_left`, `steer_right`, `handbrake`, `reset_car`, `camera_cycle`, plus editor inputs (`place`, `delete`, `rotate`, `raise`, `lower`).
5. Commit a README describing how to run.

**Acceptance:** Project opens and runs to an empty lit scene with a ground plane; inputs are mapped; constants autoload is reachable.

---

### M1 — Arcade vehicle controller on a flat track

**Scope:** One car that feels great to drive on flat ground. No stunts yet.

Design — `ArcadeCar.gd` on a `RigidBody3D` chassis with 4 `RayCast3D` suspension points:

- **Suspension:** each ray applies a spring force `(-normal) * (restLength - currentLength) * springK - damping * relativeVelocity` to keep ride height.
- **Drive:** apply forward force along the chassis forward vector scaled by throttle and a speed-dependent curve from `CarProfile` (falls off near top speed). Brake/reverse on the brake input.
- **Steering:** arcade grip model — compute lateral velocity at the car, apply a counter-force scaled by a `grip` parameter to kill sideways slide; steer by rotating the target heading, sharper at low speed, looser at high speed. Add a small handbrake that temporarily drops rear grip for slides.
- **Gravity:** world `-Y` for now (track-relative comes in M2), but structure the code so the gravity direction is a single overridable vector.
- **Reset:** `reset_car` returns the car upright to the last valid position.

`CarProfile.gd` (Resource, exported): `mass`, `engine_force_curve` (Curve), `max_speed`, `grip`, `steer_speed_low`, `steer_speed_high`, `suspension_rest`, `spring_k`, `damping`, `handbrake_grip_mult`.

Also: a simple chase camera (spring-arm follow with a bit of lag) and a flat test track scene (large ground plane + a few walls/ramps to feel the physics).

**Acceptance:** With a gamepad or keyboard you can drive around a flat plane; the car accelerates smoothly, corners with satisfying grip, can slide a little on handbrake, and resets upright on command. All tunables live in a `CarProfile` `.tres`.

---

### M2 — Track-relative gravity + a working loop

**Scope:** Prove the stunt physics on hand-built geometry.

Tasks:

1. Implement §5.1 track-relative gravity in `ArcadeCar.gd`: grounded → gravity along inverted averaged surface normal; airborne → world down; blended transition.
2. Hand-build (in a scene, not via tiles yet) a **vertical loop**, a **corkscrew**, and a **ramp jump** as static meshes on the `road` layer.
3. Tune entry-speed thresholds so a normal approach carries the car through the loop without the player fighting it. Falling off at too-low speed is acceptable and expected.
4. Add a "grounded/airborne" debug overlay (current up-axis, gravity vector, grounded bool) toggled by a key.

**Acceptance:** Driving into the loop at a reasonable speed carries the car fully around and out, upright. The corkscrew reorients the car correctly. Launching off the ramp produces a natural world-gravity arc and a clean landing. No manual input tricks required.

---

### M3 — Modular tile system + minimal editor

**Scope:** The keystone. Replace hand-built geometry with a grid of snap-together tiles, and a minimal editor to place them.

**Tile connection contract** — implement exactly:

`TileSocket` (per edge of a tile: N/E/S/W after rotation):

- `has_road: bool` — is there a road opening on this edge?
- `elevation_level: int` — integer height level at this edge.
- `slope: enum { FLAT, UP, DOWN }` — pitch of the road as it meets this edge.

`TileDefinition` (Resource, exported): `id: StringName`, `display_name`, `footprint: Vector2i` (usually 1×1), `mesh: PackedScene`, `sockets: TileSocket[4]` (base, pre-rotation), `is_stunt: bool`, `category` (straight/corner/ramp/loop/corkscrew/bridge/bank/special).

**Connection rule** — two adjacent placed tiles connect validly across their shared edge **iff**, for that edge pair:

- both sockets `has_road == true`, **and**
- `elevation_level` matches, **and**
- slopes are complementary (`UP` meets `DOWN`, `FLAT` meets `FLAT`).

`TrackGrid.gd`: holds a dictionary of `Vector2i -> PlacedTile { def_id, rotation:int(0-3), elevation_level:int }`. Provides `place`, `remove`, `get_socket(cell, dir)` (applies rotation + elevation offset), and `is_connected(cellA, cellB)`.

`PlacementValidator.gd`: given a candidate placement, returns which neighbor edges connect and which conflict. Editor uses this to show green/red placement feedback. **Validation is advisory** — the player may place a non-connecting tile (dangling), it's just flagged, not blocked.

Editor (`EditorController.gd` + scene):

- Camera: pan/zoom/orbit over the grid.
- A palette of the available `TileDefinition`s.
- Place at hovered cell, `rotate` (90° steps), `raise`/`lower` elevation level, `delete`.
- Ghost preview with green (all edges connect) / yellow (dangling but legal) / red (conflict) tint.
- A "test drive" button that loads the current grid into a playable scene (spawn the car at the start tile).

Author an initial tile set as `.tres` + `.glb`: straight, curve (90°), start/finish, ramp-up, ramp-down, and port the M2 loop and corkscrew into tiles.

**Acceptance:** You can build a small closed circuit entirely from tiles in the editor, see live connection feedback, hit "test drive," and drive the resulting track — including a tiled loop — end to end.

---

### M4 — Race loop

**Scope:** Turn a track into a race.

Tasks:

1. `Checkpoint.gd` + auto-generated ordered checkpoints along the road (or authored via a checkpoint tile) for lap validation and anti-shortcut.
2. `LapTimer.gd` + `RaceManager.gd`: countdown start, lap counting, current/best/last lap times, finish + results screen.
3. Respawn: if the car leaves the road or flips unrecoverably, respawn at the last passed checkpoint, upright, facing forward.
4. `AIController.gd`: opponents that follow the checkpoint/racing-line path using the same `ArcadeCar` controller (AI just feeds it steering/throttle). Start with simple path-following + rubber-banding.
5. Position/rank tracking across player + AI.

**Acceptance:** Load a track, race N AI opponents over M laps with a countdown, checkpoints, lap times, respawn, final standings.

---

### M5 — Replay & cameras

**Scope:** The iconic multi-angle replay.

Tasks:

1. `ReplayRecorder.gd`: each physics frame, record a snapshot per car (position, rotation, maybe wheel state) into a buffer. (Prefer transform snapshots over input for determinism.)
2. `ReplayPlayer.gd`: play the buffer back, scrub, pause, slow-mo, restart.
3. `ReplayCamera.gd` with swappable modes cycled by input: chase, cockpit, fixed trackside (auto-pick nearest authored camera point), and a helicopter/tracking cam.
4. Offer "save replay" to disk (JSON or binary buffer).

**Acceptance:** After a race, replay the run, switch freely between camera modes, scrub and slow-mo, and save/reload a replay file.

---

### M6 — Roster, persistence & polish

**Scope:** Ship-quality MVP.

Tasks:

1. Multiple `CarProfile`s with genuinely different feel (grip/weight/top-speed/accel trade-offs) — original look-alike models and invented names per the §2 guardrail.
2. Car select + track select screens.
3. `TrackSerializer.gd`: save/load tracks as JSON (`{version, name, author, grid:[{cell_x,cell_y,def_id,rotation,elevation_level}], start_cell, metadata}`); local track library.
4. Audio: engine (RPM-scaled), tire, impacts, music; SFX bus.
5. Visual polish: skyboxes, materials, particle dust/skid marks, UI theme, menus.
6. Settings: audio, controls, graphics.

**Acceptance:** A player can pick a car, pick/build a track, race AI, watch and save a replay, and save/load their own tracks — all through menus, with sound and a coherent visual style.

---

## 7. Out of scope for MVP (backlog)

Online multiplayer/leaderboards; Steam Workshop-style track sharing; ghost racing; damage model; weather/day-night; mobile/console ports; advanced AI (learned racing lines). Note these as future work; don't build them now.

## 8. Definition of done (whole project MVP)

All of M0–M6 acceptance criteria pass; the game runs standalone on Windows and Linux; a first-time player can go from launch → build or pick a track → race → replay → save, without touching the editor's internals or the filesystem manually.
