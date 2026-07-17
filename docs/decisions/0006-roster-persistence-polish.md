# ADR 0006 — Roster, persistence & polish (M6)

Status: Accepted (M6)

## Context

M6 is the ship-quality layer (SPEC.md §M6): multiple cars, menus, JSON track
save/load, audio, and visual polish — tying the whole flow together.

## Decisions

### 1. Roster

Four `CarProfile` `.tres` with genuinely different feel (Kestrel 9 balanced,
Vulcan GT heavy/fast/loose, Wisp S1 light/grippy/sharp, Comet Turbo top-speed).
`CarProfile` gained `display_name`, `tagline`, and `body_color`. `GameState`
holds the roster and `selected_car`. All cars in a race use the selected profile
(fair racing); the player wears its colour, the AI take a palette. The single
`CarBody` mesh is recoloured per car (`body_color`) — we have one car model, so
identity is colour + handling, not geometry.

### 2. Menus built in code

Main / Car Select / Track Select / Settings are Control scenes whose UI is built
in `_ready` via a shared `MenuUI` helper (code-built `Theme`, buttons, stat
bars). Consistent with the editor's code-built UI: avoids fragile hand-authored
Control layouts and keeps everything headless-verifiable. Flow: Menu → Car Select
→ Track Select → Race → results → replay; the editor is reachable from the menu
and returns to it.

### 3. Track persistence — JSON

`TrackSerializer` reads/writes the spec's JSON shape (`version`, `name`, `author`,
`grid[]`, `start_cell`, `metadata`) under `user://tracks/`, and lists a library
(bundled `res://tracks/*` + user saves). Chosen over binary for tracks because
they are small, human-inspectable, and shareable — the spec's stated rationale.
(Replays stay binary; they are large transform streams.)

### 4. Audio — fully procedural

No audio assets are bundled, so `SoundBank` synthesizes engine (looped harmonic
rumble, pitch-scaled by speed), tyre screech, and impact (decaying noise) as
`AudioStreamWAV` buffers at startup. `AudioManager` (autoload) owns an SFX/Music
bus setup and persists volumes to `user://settings.cfg`. `CarAudio` per car drives
the engine/skid players; it derives speed from position delta so it also works for
replay ghost cars.

### 5. Polish

`CarFX` emits dust particles while drifting/braking/off-track. A shared UI theme
(`MenuUI`) gives the menus a coherent dark look. Cars are colour-coded in races
and replays.

## Status

All of M0–M6 acceptance criteria are met; the MVP definition of done in SPEC.md §8
is reached: launch → pick a car → build or pick a track → race AI → watch and save
a replay → save/load tracks, all through menus, with sound and a coherent style.
