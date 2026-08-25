# OVERDRIVE

An arcade stunt-racing game and **track editor**, inspired by *Stunts / 4D Sports
Driving* (1990). Build wild circuits full of loops, corkscrews, jumps and banked
curves, then race the AI around them — or just take your own creations for a spin.

Made with the [Godot Engine](https://godotengine.org) 4.7.

> **The star of the show is the track editor.** Snap together roads, curves,
> ramps, loops, corkscrews, helixes, overpasses, pipes and tunnels over sculptable
> terrain, then drive what you built.

## Features

- **Modular track editor** — place and rotate tiles on a grid with live
  green/yellow/red connection feedback, undo/redo, and instant Test Drive. First
  time in, a six-step walkthrough builds a loop with you and gets you driving it.
- **Stunt pieces** — vertical loops, a barrel-roll corkscrew, a spiral helix up to
  raised decks, launch ramps, banked curves, overpasses, pipes and half-pipes,
  tunnels and crossroads. Track-relative gravity keeps the car pinned through
  loops and rolls.
- **Sculptable terrain** — Flat, Plains, Hills, Lakes or Mountains (with re-roll),
  and raise/lower/level tools over 96 m of vertical range; the track drapes over
  the ground.
- **Racing** — countdown start, AI opponents, laps and checkpoints, live position,
  best-lap/best-time records with a "beat your best" ghost car, medals, and a
  wrong-way / off-track warning. Choose lap count, opponents, time of day, weather,
  and even race the circuit in reverse.
- **Replays** — every race is recorded; scrub, slow-mo, and cycle cameras
  (chase / cockpit / trackside / helicopter), then save it.
- **28 cars** with distinct handling, a rotating car-select preview, and a live
  arc speedometer while you drive.
- **Challenges** — pack a track, a ghost lap and the time to beat into one file,
  send it to someone, and race their line on a track they have never seen.
- **Play your way** — keyboard or Xbox/Bluetooth controller, in the game *and* the
  editor.
- **Fourteen tracks to start** — six hand-built stunt circuits, plus eight
  [inspired by real places](#tracks) and laid out from map and elevation data —
  and everything you build yourself.

## Playing it

**From the Godot editor:**

1. Install [Godot 4.7](https://godotengine.org/download) (standard build; the
   project uses the built-in Jolt physics engine and the Forward+ renderer).
2. Open the editor, **Import** this folder (pick `project.godot`), and let the
   first-time asset import finish.
3. Press **F5** to play. It boots to the main menu.

From the menu: **Race** (pick a car → pick a track → set laps/opponents → go),
**Track Editor** (build, save, test drive or race), or **Settings**.

## Controls

### Driving

| Action        | Keyboard        | Controller        |
|---------------|-----------------|-------------------|
| Accelerate    | W / Up          | Right trigger     |
| Brake / rev   | S / Down        | Left trigger      |
| Steer         | A / D           | Left stick        |
| Handbrake     | Space           | A                 |
| Reset car     | R               | X                 |
| Cycle camera  | C               | Y                 |
| Pause         | Esc             | Start             |

### Editor

| Action              | Keyboard / mouse         | Controller        |
|---------------------|--------------------------|-------------------|
| Move cursor         | mouse                    | Left stick        |
| Orbit camera        | middle-drag or Q / E     | LB / RB           |
| Pan camera          | WASD                     | Right stick       |
| Camera up / down    | Z / X                    | —                 |
| Zoom                | mouse wheel              | Triggers          |
| Place               | left-click               | A                 |
| Delete              | Delete                   | X                 |
| Rotate              | T                        | B                 |
| Cycle piece / tool  | palette / —              | D-pad ◄► / Y      |
| Raise / lower       | Page Up / Page Down      | D-pad ▲▼          |
| Undo / redo         | Ctrl+Z / Ctrl+Y          | —                 |

To make a raceable track, build a **closed loop** and include a **Start / Finish**
tile.

## Tracks

Fourteen ship with the game. Six are hand-built stunt circuits — Sample Oval,
fast, Test Track, Serpentine Ridge, Alpine Pass and Emerald Sound — the kind of
thing the editor is for. **Emerald Sound** is the big one: a 3.4 km city lap
around a sound, a ship canal and a lake, taking in a barrel roll, a loop, a
spiral, a bridge, a jump and a flyover over its own start straight. It is
inspired by Seattle rather than traced from it — see
[`tools/citygen/`](tools/citygen/README.md).

**The other eight are inspired by real places.** A generator traces a lap out of
OpenStreetMap, fits it to the 8 m tile grid, and sculpts the ground under it from
SRTM elevation data, so the corners and the climbs follow the real ones. Their
names are deliberately near-misses rather than the real circuit names — these are
interpretations on a grid of 8 m tiles, not reproductions, and nothing here is
affiliated with or endorsed by any circuit, race or organiser:

| track | inspired by |
|---|---|
| Tres Marías | the boulevard loop around Ciudad Tres Marías, Morelia, Michoacán |
| Eifelschleife | the long forest circuit in the Eifel, Germany |
| Spaa Francorchant | the Ardennes road circuit near Francorchamps, Belgium |
| Zuzuka | the figure-of-eight circuit in Mie Prefecture, Japan — one stretch crosses the other on a bridge |
| Momako | the harbour street circuit in Monte Carlo, Monaco — tunnel included |
| Autódromo Hermanos Ramírez | the park circuit in Mexico City, banked |
| Baytona Oval | the banked tri-oval at Daytona Beach, Florida |
| Stelvia Pass | the hairpins at the top of the Stelvio Pass, South Tyrol — 84 m of climb, then a long run home |

The generator lives in [`tools/trackgen/`](tools/trackgen/README.md) and is part
of the repo: every one of those tracks rebuilds byte for byte from the committed
route data, and the same tool will lay out somewhere new if you point it at a map
extract. Map data is © OpenStreetMap contributors under the ODbL — see
[`CREDITS.md`](CREDITS.md), and keep the attribution with any build that ships
these tracks.

## Challenges

A **challenge** is one file holding a track, a ghost lap driven on it, and the
time to beat. Send someone a `.ovc` and they can race your line without having
the track — importing it installs the track and puts your translucent car on the
road beside them.

- **Try one:** main menu → **Challenge** → [`examples/crosswind_circuit.ovc`](examples/crosswind_circuit.ovc)
  → **Race it**. That circuit is not in the track list, so importing it is the
  real thing: a challenge arriving for a track you have never seen. (Track select
  has an **Import…** button too — both doors take either kind of file.)
- **Make one:** finish a race and press **S** on the results screen, then choose
  where to put it — it opens in your documents folder, and remembers wherever you
  last saved one. Set the name it goes out under in Settings.
- **Race one:** a track with a challenge says so in the track list, and the race
  setup panel gets a toggle to chase the challenge ghost or your own best lap. The
  car it was set in is put under your cursor on the car screen — a suggestion, not
  a rule; beat it in whatever you like and the results say which car was whose.

A challenge is checked hard on the way in — it is a file from someone else, after
all — and refused with a reason if it is damaged, tampered with, or uses a track
piece this build doesn't have. What it is not is verified: anyone can write one,
there is no leaderboard here, and it is meant to pass between people who know
each other. See [ADR 0007](docs/decisions/0007-shareable-challenges.md).

## Tests

Headless, from the project root:

```bash
godot --headless --path . tests/challenge_test.tscn
```

`challenge_test` covers the challenge file format and what it does with files it
should refuse — a smuggled object, a tampered track, a ghost full of infinities.
`challenge_flow_test` walks the whole feature the way a player would: import a
challenge for a track that isn't installed, see it on track select, and start a
race that puts the stranger's ghost on the road. `editor_tutorial_test` walks the
editor's first-run walkthrough, in order and out of it. They all put back anything
they touch.

There is also a check for generated tracks — see
[`tools/trackgen/`](tools/trackgen/README.md).

## Cars & assets

The 28-car roster is drawn from two public-domain (CC0) low-poly model packs — the
Rgsdev vehicle pack and the Kenney Car Kit — so everything here is free to
redistribute. See [`CREDITS.md`](CREDITS.md).

## License

Game code and original assets: **MIT** — see [`LICENSE`](LICENSE).
Third-party assets keep their own licenses (all CC0) — see [`CREDITS.md`](CREDITS.md).
