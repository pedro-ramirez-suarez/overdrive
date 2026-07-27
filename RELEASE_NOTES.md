# OVERDRIVE — v1.0.0

An arcade stunt-racing game **and track editor**, inspired by *Stunts / 4D Sports
Driving* (1990). Build wild circuits full of loops, corkscrews, jumps and banked
curves over sculptable terrain — then race the AI around what you made.

Made with the Godot Engine 4.7.

## Highlights

- **Modular track editor.** Snap together roads, curves, ramps, loops, a barrel-roll
  corkscrew, a spiral helix, overpasses, pipes, half-pipes, tunnels and crossroads
  on a grid, with live green/yellow/red connection feedback, undo/redo, and one-click
  Test Drive. Guardrails keep you on the helix and overpass decks.
- **Sculptable terrain.** Flat, Plains, Hills, Lakes or Mountains (with re-roll), plus
  raise / lower / level / lake tools. The track drapes over the ground.
- **Real stunt driving.** Track-relative gravity pins the car through loops and rolls;
  ramps launch you into a natural arc; banked curves let you carry speed.
- **Race weekend, your way.** Countdown start, AI opponents, laps and checkpoints,
  live position and a wrong-way warning. Choose lap count, number of opponents, time
  of day, weather — and even race the circuit **in reverse**.
- **Beat your best.** Per-track best-lap and best-time records, medals against a par
  time, and a translucent **ghost car** replaying your fastest run alongside you.
- **Replays.** Every race is recorded — scrub, slow-mo, and cycle cameras
  (chase / cockpit / trackside / helicopter), then save it.
- **28 cars** with distinct handling, a rotating car-select preview with stats, five
  camera angles (including a close "Action" cam), and a live arc speedometer.
- **Play how you like.** Full keyboard **and** Xbox / Bluetooth controller support —
  in the game *and* the editor.
- **Three tracks to start:** Sample Oval, fast, and Test Track — plus everything you
  build yourself.

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
**Godot** (MIT). See [CREDITS.md](CREDITS.md).

---

*Thanks for playing — build something ridiculous and send it around.*
