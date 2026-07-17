# OVERDRIVE (working title)

A modern, arcade-styled homage to *Stunts / 4D Sports Driving* (1990): stylized
low-poly 3D racing with jumps, loops, and corkscrews, a modular track editor,
multi-angle replays, and a roster of look-alike cars.

See [`SPEC.md`](SPEC.md) for the full north-star spec and milestone plan.

## Requirements

- **Godot 4.4 or newer.** The project uses the built-in **Jolt** physics engine
  (`physics/3d/physics_engine = "Jolt Physics"`). On Godot 4.3 or earlier, install
  the `godot-jolt` add-on and set the engine to `JoltPhysics3D`, or temporarily
  switch back to `DEFAULT` in *Project Settings → Physics → 3D*.
- Forward+ renderer (desktop GPU). Target platforms for the MVP are Windows and Linux.

## Running

1. Open the Godot editor and **Import** this folder (select `project.godot`).
2. Let the editor finish its first-time asset import.
3. Press **F5** (Play). The main scene is `scenes/race/TestTrack.tscn`.

## Current status

**All milestones M0–M6 are in place** — the MVP is complete: scaffold, arcade
vehicle, track-relative gravity + loop, the modular tile system + editor, the
race loop, replays, and the roster / persistence / polish layer.

The main scene is the **main menu**,
[`scenes/ui/MainMenu.tscn`](scenes/ui/MainMenu.tscn) (F5):

- **Race** → pick a car (4 in the roster, distinct handling) → pick a track
  (bundled or saved) → race the AI → watch/save the replay.
- **Track Editor** → build a track, **Save Track** to the local library,
  **Test Drive** or **Race**, **Menu** to return.
- **Settings** → audio volumes (persisted to `user://settings.cfg`).

Standalone scenes still runnable with F6:
[`StuntPlayground.tscn`](scenes/race/StuntPlayground.tscn) (M2) and
[`TestTrack.tscn`](scenes/race/TestTrack.tscn) (M1).

### Racing (M4)

Build a **closed circuit** with a **Start / Finish** tile, then click **Race**.
A 3-2-1 countdown starts, then you race 3 AI opponents over 3 laps (tunable via
`GameState.race_ai_count` / `race_laps`). The HUD shows position, lap, current and
best lap time; checkpoints (auto-generated along the road) enforce lap order and
anti-shortcut; leaving the track or flipping respawns you at the last checkpoint
(or press **R**). A results screen shows final standings. Esc returns to the
editor. Flat circuits work best — AI path-following through loops is a stretch.
Cars are colour-coded (you are red).

### Replay (M5)

Every race is recorded (per-car transform snapshots each physics frame). From the
results screen press **Enter** to watch the replay. Controls: **Space**
play/pause, **←/→** scrub, **↑/↓** playback speed (0.1×–2×), **C** cycle camera
(chase / cockpit / trackside / helicopter), **R** restart, **S** save to disk
(`user://replays/`), **L** load the latest saved replay, **Esc** back to editor.

### Roster, persistence & polish (M6)

- **Roster (15 cars):** four hand-built procedural cars (Kestrel 9, Vulcan GT,
  Wisp S1, Comet Turbo) plus eleven imported [Kenney Car Kit](https://kenney.nl)
  models (CC0) — Bolt R, Ion X, Marlin GT, Pip RS, Baron LX, and more — each with
  its own handling. The car-select list scrolls; stats show top speed / accel /
  grip / weight.
- **Track persistence:** JSON under `user://tracks/`, plus a bundled Sample Oval.
  Save from the editor, load from the Track Select screen.
- **Audio:** procedurally synthesized engine (RPM-scaled), tyre screech, and
  impacts on an SFX bus with volume settings.
- **Polish:** dust particles when drifting/off-track, colour-coded cars, and a
  shared dark UI theme across the menus.

### Terrain & ramps

The editor has a **Terrain** selector (Flat / Plains / Hills / Lakes / Mountains,
with **Re-roll** for a new seed). Pick one and the track **drapes over the
terrain** — placed tiles follow the ground height (max 5 levels), and you drive on
the hills off-track. Lakes respawn you. **Elevation ramps** are now taller (3 m
per level) with a smooth profile, and there's a new **Jump Ramp** tile that
launches the car off a lip. Terrain (type + seed) is saved with the track.

### Lap rules

Laps **always count** when you cross the finish line (leave and return) — no more
missed laps from clipping a corner. Straying far from the racing line is instead
penalized softly: within ~11 m of the line is free; beyond that your top speed
scales down toward **5%** of max and a warning beep plays, but the lap still
counts. Ranking uses laps first, then in-order checkpoints, so a clean racer still
outranks a shortcutter on the same lap.

## Credits

Some car models are from the **Kenney Car Kit** (kenney.nl), licensed CC0 — see
[`assets/models/kenney/LICENSE.txt`](assets/models/kenney/LICENSE.txt).

### Editor (M3)

| Action              | Input                    |
|---------------------|--------------------------|
| Select tile         | click a palette button   |
| Orbit camera        | middle-mouse drag        |
| Pan camera          | WASD                     |
| Zoom                | mouse wheel              |
| Place tile          | left-click on the grid   |
| Delete tile         | Delete                   |
| Rotate (90°)        | T                        |
| Raise / lower level | Page Up / Page Down      |
| Test drive          | **Test Drive** button    |
| Back to editor      | Esc (from test drive)    |

The hovered cell shows a ghost preview and a coloured footprint: **green** =
connects to a neighbour, **yellow** = legal but dangling, **red** = conflict.
Validation is advisory — you can place dangling tiles. The car spawns on the
**Start / Finish** tile. Tile set: straight, curve, start/finish, ramp up/down,
loop, corkscrew.

### The car

The car is an original low-poly look-alike of a classic rear-engined flat-six
coupe (fastback roofline, round headlights, wide haunches), built procedurally in
[`scripts/vehicle/CarBody.gd`](scripts/vehicle/CarBody.gd). Per the §2 content
guardrail it uses an invented name (**"Kestrel 9"**) and no real-marque badges or
model numbers.

### Controls

| Action         | Keyboard         | Gamepad            |
|----------------|------------------|--------------------|
| Accelerate     | W / Up           | Right trigger      |
| Brake/Reverse  | S / Down         | Left trigger       |
| Steer left     | A / Left         | Left stick left    |
| Steer right    | D / Right        | Left stick right   |
| Handbrake      | Space            | A / Cross          |
| Reset car      | R                | X / Square         |
| Cycle camera   | C                | Y / Triangle       |
| Debug overlay  | `` ` `` (tilde)  | —                  |

Editor inputs (`place`, `delete`, `rotate`, `raise`, `lower`) are mapped now but
unused until the M3 track editor.

## What to expect

Drive the red car (accelerate smoothly, grippy cornering, handbrake slide,
**R** to reset upright). Then aim straight ahead and carry speed into the
**loop** — track-relative gravity pins the car to the road and takes it all the
way around and out, upright. The **corkscrew** rolls the car through a full
barrel. Off the **ramp**, gravity reverts to world-down for a natural arc and
landing. Press `` ` `` to toggle a debug readout (grounded state, up-axis,
gravity vector, road normal, speed).

The loop and corkscrew are generated procedurally at run time from
[`scripts/track/RibbonPiece.gd`](scripts/track/RibbonPiece.gd), so they appear
when you **play** the scene, not in the editor viewport. All handling numbers —
including the new `gravity_blend_speed`, `align_gain`, and `align_responsiveness`
— live in [`resources/cars/default_car.tres`](resources/cars/default_car.tres).

## Project layout

See `SPEC.md` §3. Scripts live under `scripts/`, scenes under `scenes/`, tunable
data under `resources/`. Non-obvious decisions are recorded in `docs/decisions/`.
