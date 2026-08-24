# OVERDRIVE — v1.0.0

An arcade stunt-racing game **and track editor**, inspired by *Stunts / 4D Sports
Driving* (1990). Build wild circuits full of loops, corkscrews, jumps and banked
curves over sculptable terrain — then race the AI around what you made.

Made with the Godot Engine 4.7.

## Highlights

- **Modular track editor.** Snap together roads, curves, ramps, loops, a barrel-roll
  corkscrew, a spiral helix, overpasses, pipes, half-pipes, tunnels and crossroads
  on a grid, with live green/yellow/red connection feedback, undo/redo, and one-click
  Test Drive. Guardrails keep you on the helix and overpass decks. New to it? A
  six-step walkthrough builds a loop with you the first time in — one sentence at a
  time, nothing forced, Skip always on screen.
- **Sculptable terrain.** Flat, Plains, Hills, Lakes or Mountains (with re-roll), plus
  raise / lower / level / lake tools over 96 m of vertical range — enough for a real
  mountain pass. The track drapes over the ground.
- **Real stunt driving.** Track-relative gravity pins the car through loops and rolls;
  ramps launch you into a natural arc; banked curves let you carry speed.
- **Race weekend, your way.** Countdown start, AI opponents, laps and checkpoints,
  live position and a wrong-way warning. Choose lap count, number of opponents, time
  of day, weather — and even race the circuit **in reverse**.
- **Beat your best.** Per-track best-lap and best-time records, medals against a par
  time, and a translucent **ghost car** replaying your fastest run alongside you.
- **Challenges.** Pack a track, the ghost of a lap on it and the time to beat into one
  file, send it to someone, and race their line on a track they have never seen. Press
  **S** on the results screen to make one; **Challenge** on the main menu — or **Import…**
  on the track list — to take one in.
  `examples/crosswind_circuit.ovc` is one to try — its circuit is deliberately not in
  the track list.
- **Replays.** Every race is recorded — scrub, slow-mo, and cycle cameras
  (chase / cockpit / trackside / helicopter), then save it.
- **28 cars** with distinct handling, a rotating car-select preview with stats, five
  camera angles (including a close "Action" cam), and a live arc speedometer.
- **Play how you like.** Full keyboard **and** Xbox / Bluetooth controller support —
  in the game *and* the editor.
- **Thirteen tracks to start.** Five are hand-built stunt circuits — Sample Oval, fast,
  Test Track, Serpentine Ridge and Alpine Pass. The other eight are **inspired by real
  places**, traced from map data and given the real ground under them: **Tres Marías**
  (Morelia, Michoacán), **Eifelschleife** (the Eifel forest circuit), **Spaa
  Francorchant** (the Ardennes), **Zuzuka** (the Japanese figure-of-eight, bridge and
  all), **Momako** (the Monte Carlo harbour streets, tunnel included), **Autódromo
  Hermanos Ramírez** (Mexico City), **Baytona Oval** (the Daytona tri-oval) and
  **Stelvia Pass** (the hairpins of the Stelvio — 84 m of climb, then a long run home).
  The names are near-misses on purpose: these are interpretations on a grid of 8 m
  tiles, not reproductions. Plus everything you build yourself.
- **The track generator ships with the source.** The tool that laid out those eight
  is in [`tools/trackgen/`](tools/trackgen/README.md): it traces a lap out of
  OpenStreetMap, fits it to the tile grid, and sculpts the ground from SRTM elevation.
  Every generated track rebuilds byte for byte from the committed route data, and the
  same tool will lay out somewhere new if you point it at a map extract.

## Controls

Full driving and editor control tables are in the [README](README.md). In short:
**WASD / left-stick** to drive, **click / A** to place tiles, **C** to change camera,
**Esc** to pause. To make a raceable track, build a closed loop with a Start / Finish
tile.

## Downloads

- **Windows** — download, unzip, run `OVERDRIVE.exe`.
- _(Linux and macOS builds: TODO)_

No installer, no account, no data collected — it's a single self-contained game.

## Known issues

- **Web/browser version is not recommended yet.** It boots, but browsers can't run
  the Forward+ renderer, so the 3D falls back to WebGL and the gameplay screens run
  poorly. **Play the desktop build for the intended experience.**
- **AI and the spiral pieces.** Opponents don't drive the **helix** or **corkscrew**
  well (they navigate in 2D and can't follow a climbing spiral). Great for solo runs
  and test drives; mixed results racing CPUs over those tiles.
- Minor cosmetic quirks on a few car models (slight wheel clipping).

## License & credits

Game code and original assets are **MIT** licensed ([LICENSE](LICENSE)). All car
models are public-domain (CC0) packs from **Rgsdev** and **Kenney**; the engine is
**Godot** (MIT). Road geometry for the eight real-world tracks comes from
**OpenStreetMap** (© OpenStreetMap contributors, ODbL) and ground heights from
**NASA/USGS SRTM** (public domain) — that attribution has to travel with any build
that ships them. See [CREDITS.md](CREDITS.md).

---

*Thanks for playing — build something ridiculous and send it around.*
