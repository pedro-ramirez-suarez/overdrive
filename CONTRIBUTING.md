# Contributing to OVERDRIVE

Bug reports, tracks, cars, tiles and code are all welcome. This file is the short
version of how the project fits together.

## Getting it running

Install [Godot 4.7](https://godotengine.org/download) (standard build — the project
uses the built-in Jolt physics and the Forward+ renderer), then **Import** this
folder by picking `project.godot`.

Open it in the **editor once and let the first import finish** before you try to
play. Assets — especially the FBX car models — are compiled on that first pass, and
launching straight from the project list skips it, which is why cars can show up
missing.

## Tests

Headless, from the project root:

```bash
godot --headless --path . tests/challenge_test.tscn
```

The other scenes in `tests/` run the same way. They cover the challenge file format
and what it refuses, the whole challenge flow as a player walks it, and the editor's
first-run walkthrough. They all put back anything they touch, so they are safe to
run against your own library.

## How the code is laid out

| Path | What lives there |
|---|---|
| `scripts/vehicle/` | The car: raycast suspension, grip, steering, cameras, profiles |
| `scripts/track/` | Tiles, the grid and its connection rules, terrain, serialization |
| `scripts/editor/` | The track editor |
| `scripts/race/` | Race loop, racing line, checkpoints, AI |
| `scripts/replay/` | Recording and playback |
| `scripts/ui/` | Menus and HUD |
| `tools/` | Godot-run generators and helper scripts, each with a README |
| `docs/decisions/` | Why things are built the way they are |

If you are changing something structural, `docs/decisions/` is worth reading first —
several of the non-obvious choices (track-relative gravity, the tile socket
contract, the racing-line walk) are written down there with their reasoning.

## Style

- **GDScript 2.0 with static typing.** Annotate variables, parameters and returns.
- **Tabs** for indentation, matching the rest of the project.
- **`##` doc comments** on classes and non-obvious functions. Say *why*, not what —
  the existing code leans heavily on this and it is the reason it stays readable.
- Match the density and voice of the file you are editing.

## Tracks

Built a good circuit? Open a PR adding the `.json` (the editor's **Export** button
writes one) — or just attach it to an issue.

A track needs to be a **closed loop with a Start/Finish tile** to be raceable. The
editor will happily let you save one that is neither, and it will look fine until
the race puts you somewhere strange.

## Assets

Anything added must be redistributable — public domain, CC0, or something
compatibly licensed with clear provenance — and recorded in
[`CREDITS.md`](CREDITS.md). Cars must be **original designs**: no real
manufacturer's badges, model names or trade dress.

## Licence

Contributions are accepted under the [MIT licence](LICENSE), the same terms as the
rest of the code.
