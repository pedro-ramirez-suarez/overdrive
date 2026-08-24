# Proposal — Shareable challenges & editor onboarding

Status: **Both are built** — [ADR 0007](../decisions/0007-shareable-challenges.md)
and [ADR 0008](../decisions/0008-editor-onboarding.md) record what shipped and how
it differs from the spec below. Written ahead of the open-source release, when
strangers will meet this game with no context.

Two features, unrelated in code, related in purpose. The editor is the star of the
show, and right now nothing carries what you build in it to anyone else, and
nothing helps a newcomer past the empty grid. One fixes each.

They are independent — either can ship without the other. **Onboarding is the
smaller of the two** and touches only the editor; challenges add a file format and
reach into the race and the track list.

---

# 1. Shareable challenges

**Built.** [ADR 0007](../decisions/0007-shareable-challenges.md) records what was
decided, including answers to the open questions at the end of this section.

## What it is

A **challenge** is one file that carries a track, a ghost of a lap driven on it,
and the time to beat. Someone sends you `stelvia_1_47.ovc`; you open it, the track
lands in your library, and racing it puts their translucent car on the road beside
you with their time as the target.

That turns "I built a track" into "beat my time on it", which is the loop that
makes a game with an editor spread rather than just get looked at.

## Why it is cheap

Almost all of it exists already:

| piece | where it lives now |
|---|---|
| track serialization | [`TrackSerializer.to_dict` / `from_dict`](../../scripts/track/TrackSerializer.gd) |
| importing a foreign track | `TrackSerializer.import_track`, wired to the editor's Import button |
| a single-car ghost | [`Replay.extract_car(0)`](../../scripts/replay/Replay.gd), already taken at the end of every race |
| driving a ghost translucently | `RaceManager._spawn_ghost` / `_update_ghost` |
| times and medals | [`Records`](../../scripts/core/Records.gd) — best lap, best race, par, medals |

Nothing new has to be simulated. The work is a container format, a little UI, and
the rules about which ghost wins.

## File format

`.ovc` — one Godot binary Variant file, written the way `Replay.save_to` already
writes one. Binary rather than JSON because the ghost is a transform stream and
JSON would multiply its size.

```
{
  "magic": "OVRCHAL1",
  "version": 1,
  "track": { ... exactly what TrackSerializer.to_dict produces ... },
  "ghost": { ... exactly what Replay.save_to stores ... },   # one car
  "track_hash": String,     # see "The ghost only fits one track"
  "challenge": {
    "author":    String,    # who set the time
    "car":       String,    # car they drove
    "lap_time":  float,     # the target, seconds
    "race_time": float,
    "laps":      int,
    "reversed":  bool,      # the settings the time was set under
    "created":   int,       # unix seconds
    "note":      String,    # optional, one line, 140 chars
  },
}
```

The track is **embedded, not referenced**: a challenge has to work when it arrives
alone, in a chat window, from someone you have never met.

### A small refactor first

`Replay.save_to` and `TrackSerializer.save` both build their payload inline and
write it in the same breath. Split the dict out — `Replay.to_variant()` /
`Replay.from_variant()` beside the existing `save_to` / `load_from` — so a
challenge can embed a ghost without going through a temp file. No behaviour change.

## New code

- **`scripts/core/Challenge.gd`** (`class_name Challenge extends RefCounted`)
  - `static func from_run(track_dict, ghost, meta) -> Challenge`
  - `save_to(path) -> bool`, `static load_from(path) -> Challenge`
  - `static file_error(path) -> String`, mirroring `TrackSerializer.file_error`, so
    the UI can say *why* a file was refused rather than failing mutely. That
    function is the model to follow: every rejection returns a sentence a player
    can act on.
  - `static func hash_track(data: Dictionary) -> String`
- **`user://challenges/`** — one `.ovc` per file, names made unique the way
  `TrackSerializer._unique_path` does. Never overwrite: a challenge someone sent
  you is not yours to destroy.
- An index, `user://challenges/index.json`, mapping a track-name slug to the
  active challenge for it, so track-select can answer "does this track have a
  challenge?" without opening every file. The slug function is `Records._slug` —
  promote it to a shared helper rather than copying it.

## Where it shows up

**Making one.** The results screen ([`RaceManager._show_results`](../../scripts/race/RaceManager.gd))
already ends with a line of key hints — `Enter: watch replay      Esc: leave race`.
Add `S: save as challenge`, enabled whenever the player finished and a replay
exists. It writes the file and flashes the path. The run just driven is the target,
not necessarily the personal best: sending someone your best-ever lap and sending
them the one you just did are both reasonable, and the one just driven is what the
player has in mind at that moment.

**Opening one.** The editor's Load dialog already opens foreign files from the
filesystem (`FileDialog`, `ACCESS_FILESYSTEM`, filter `*.json`). Add `*.ovc` and
route it: a challenge file installs its track through the existing import path,
stores the `.ovc`, and points the player at Race rather than dropping them in the
editor. Track-select gets an **Import…** button too — that is where someone who was
sent a file will look first, and today the only door is inside the editor.

**Seeing one.** In track-select's info panel, under the existing best-lap line:

```
Best lap  1:52.30   🥈
Challenge  Ana — 1:47.05      "the tunnel is flat out, trust me"
```

**Racing one.** `_spawn_ghost` currently loads the personal best. With a challenge
active it loads the challenge ghost instead, and the pre-race panel gets a toggle
to switch back. Two ghosts at once was considered and rejected: two translucent
cars on a hairpin is noise, and the point of a challenge is a single rival.

**Beating one.** Results gains a line: `★ CHALLENGE BEATEN ★`, or
`0.42 s short of Ana's time`.

## The ghost only fits one track

A ghost is world-space transforms. Replay it over a track that has been edited — a
corner moved, the ground raised — and the car drives through scenery, or through
thin air. So the challenge stores `track_hash`: a hash over the sorted grid entries
(`cell_x`, `cell_y`, `def_id`, `rotation`, `elevation_level`) plus the terrain type,
seed, edits and lakes.

On load, if the local track's hash differs, the track still installs and still
races — but the ghost does not appear, and the player is told: *"This challenge was
set on a different version of this track, so the ghost can't be shown."* Silently
driving a nonsense ghost is worse than driving none.

## Deliberate non-goals

- **No verification.** A `.ovc` is a file; anyone can write one. This is a local,
  single-player, honour-system feature between people who know each other. Say so
  in the docs rather than pretending otherwise, and do not build anti-cheat
  machinery for a game with no leaderboard to protect.
- **No network, no accounts, no hosting.** Sharing is whatever the player already
  uses to send a file.

## Size, and one thing worth knowing

A two-minute run at 60 fps is about 7,200 frames. Positions are a
`PackedVector3Array` (12 bytes a frame); rotations are an untyped `Array` of
`Quaternion`, and Variant boxing makes that the fat half. Expect roughly 250–350 KB
per challenge, plus the track JSON. Fine for sending over a chat.

If it ever matters, the cheap fix is storing rotations as a `PackedFloat32Array`
(16 bytes a frame, no boxing) — but that changes the replay format and every saved
ghost with it, so it is not part of this. Keeping every second frame is the other
option; `Replay.sample` already interpolates, so playback would not notice.

## Test plan

- Round trip: build a challenge, save, load, every field matches.
- A challenge whose track was edited is refused *as a ghost* while still installing
  as a track, with the message above.
- Garbage in: a truncated file, a `.json` track renamed to `.ovc`, an empty file —
  each returns its own sentence from `Challenge.file_error`, none crash.
- Name collision: importing a challenge for a track name you already have makes a
  uniquely-named copy and does not touch the original.
- Headless: install a challenge for a bundled track and confirm `RaceManager` spawns
  the challenge ghost rather than the personal one.

## Open questions

1. **One challenge per track, or many?** The index above assumes one active at a
   time, replaced on import. A list per track is more faithful to how people
   actually swap times, but needs UI to pick between them.
2. **Records and imported tracks.** `Records` keys on a slug of the track *name*, so
   importing a challenge whose track is called "Untitled" shares records with your
   own "Untitled". Options: keep the name (records merge — simple, wrong), suffix
   the name on import (records separate — safe, ugly), or key records by
   `track_hash`. Worth settling before the format is fixed, since `track_hash` is in
   the file either way.
3. **Extension.** `.ovc` reads as nothing in particular. `.overdrive` is clearer and
   uglier.

---

# 2. Editor onboarding

**Built.** [ADR 0008](../decisions/0008-editor-onboarding.md) records what was
decided — including the open question at the end of this section, which went the
way of cutting the elevation step.

## What it is

A first-run guided build inside the editor: seven steps, each one sentence, each
completed by doing the thing rather than by clicking Next. It ends with the player
driving a closed loop they made, about three minutes in.

## Why

The editor opens on an empty grid, a palette of twenty track pieces, five terrain
presets and five sculpting tools, and one rule that is nowhere on screen: **a
raceable track is a closed loop containing a Start / Finish tile.** Today that rule
lives in the README and in a message you only see after driving into it —
`RaceManager` says *"This track has no drivable loop yet"* once you have already
pressed Race.

The connection feedback (green / yellow / red) is good and already built. The
tutorial adds no systems; it points at the ones there.

## The steps

Each step is a sentence, a highlight, and a predicate that watches the grid.

| # | says | done when |
|---|---|---|
| 1 | "Every track starts with the finish line. Place the **Start / Finish** piece." | a `start` tile exists |
| 2 | "Now a **Straight** next to it. The connector glows green when two pieces meet." | a `straight` tile connects to it |
| 3 | "Corners need turning — press **T** (or **B** on a pad) to rotate before you place." | a `curve` is placed after at least one rotation |
| 4 | "Keep going and bring it back round. A track has to be a **closed loop**." | `RacePath.compute` returns a route covering every tile |
| 5 | "Give it some height: **Page Up** raises the piece under the cursor." | a tile sits above level 0 |
| 6 | "Pick a landscape from **TERRAIN**. The track drapes over whatever you choose." | the terrain type changes |
| 7 | "Drive it — **Test Drive**." | the play scene is entered |

Then a closing line: *"That's the whole idea. The rest of the palette — loops,
corkscrews, pipes, the helix — works exactly the same way."*

Step 4 is the one that matters. The others are discoverable; that one is a rule.

## Mechanics

- **`scripts/editor/EditorTutorial.gd`**, a small state machine owned by
  `EditorController`. A step is a `Dictionary`: `text`, `done` (a `Callable`
  evaluated against the grid), and optionally `highlight` (a palette or tool button)
  and `hint_cell`.
- **It never takes control.** No modal, no forced tool, no blocked input. Place what
  you like, in any order; a step already satisfied when it starts is skipped.
  **Skip** is visible from the first frame, and remembered.
- **Hooking in.** `EditorController` mutates the grid in a handful of places and
  already calls `_update_status()` after each. `TrackGrid` has no signals, so rather
  than adding them, the tutorial is polled from the same place: `_update_status()`
  calls `_tutorial.check()` when a tutorial is running. One call site, no new
  plumbing, and it cannot go stale, because the status line is already the thing
  that has to be right after every change.
- **Where it draws.** The editor's `_ui_layer` `CanvasLayer` already holds
  `_status_label` (bottom-left) and `_save_label` (top-centre). The tutorial adds one
  panel bottom-centre: step number, sentence, Skip. Highlighting reuses the button
  dictionaries the editor already keeps — `_palette_buttons`, `_tool_buttons`,
  `_terrain_buttons` — with a pulsing outline. No new art.
- **Persistence.** `user://settings.cfg`, the same `ConfigFile` that `AudioManager`
  and `DisplayManager` share: `[editor] tutorial_done = true`. It runs once, on an
  empty grid only — never over a track someone is in the middle of.
- **Getting it back.** A "Replay editor tutorial" row in Settings, and a `?` button
  in the editor's action row.

## Deliberate non-goals

No cutscenes, no voice-over, no animated hand, no separate tutorial track scene. It
is a checklist that watches the grid, and it has to stay cheap enough that nobody
hesitates to change the editor for fear of breaking it.

## Test plan

- Headless: drive a scripted sequence of grid mutations through the step predicates
  and assert the tutorial advances — including out-of-order play (the curve before
  the straight) and pre-satisfied steps.
- The flag persists; the tutorial does not return on the next launch.
- Skip at any step leaves the editor in a normal, fully usable state.
- Opening the editor with tiles already on the grid starts no tutorial.

## Open question

Does step 5 (raising a piece) belong? It is the one step teaching something the
player can happily put off, and cutting it makes the whole thing six steps and about
two minutes. The alternative is to keep it and drop step 6, since a terrain preset
is one obvious button and needs no teaching.

---

# Sequencing

Onboarding first: self-contained, no format to get wrong, and the one a stranger
hits within a minute of opening the game. Challenges second, with open question 2
(how records key against imported tracks) settled before the file format is written
down anywhere a player's files depend on it.
