# ADR 0008 — Editor onboarding

Status: Accepted

## Context

The editor is the star of this game, and it opens on an empty grid, twenty track
pieces, five terrain presets and five sculpting tools — with one rule that appears
nowhere on screen: **a raceable track is a closed loop with a Start / Finish piece
in it.** That rule lived in the README and in the message `RaceManager` shows
*after* you press Race and find there is nothing to drive.

For an open-source release this is the first thing a stranger meets. The
connection feedback, the palette and the drape are all good already; what was
missing was anything pointing at them.

See [the proposal](../proposals/challenges-and-onboarding.md) for the shape this
was specced in.

## Decisions

### 1. Six steps, each finished by doing the thing

Place a Start piece; join a Straight to it; rotate and place a Curve; close the
loop; pick a landscape; drive it. No Next button anywhere — each step is a
sentence and a predicate, and the predicate is satisfied by building, not by
acknowledging.

Step 4 is the whole reason the walk exists. The others are the shortest path to
it: they are discoverable on their own, that one is a rule.

### 2. The elevation step was cut

The spec had seven steps, with "Page Up raises the height you build at" between
the loop and the landscape. It is gone, and the closing line mentions ramps
instead.

Two reasons. Raising the build height and placing an ordinary piece *breaks* the
loop the player has just been taught to close — the road steps up with nothing to
climb on, which is the opposite of the lesson. Teaching it properly means ramp up,
run, ramp down, which is a second lesson in the middle of the first. And it is the
one step teaching something a player can happily put off; cutting it takes the
walk to about two minutes, which is the difference between finishing it and
abandoning it.

### 3. It never takes control

No modal, no forced tool, no swallowed input, no separate tutorial scene. Place
what you like, in any order. `check()` advances past every step that is already
satisfied, so playing out of order — or doing two things at once — never strands
the player on something they finished five pieces ago. **Skip** is on screen from
the first frame.

### 4. Polled from the status line

`TrackGrid` has no signals, and this did not seem worth adding one for.
`EditorController._update_status()` already runs after every change to the track,
so the walk is polled from there: one call site, no new plumbing, and it cannot go
stale, because the status line is already the thing that has to be right after
every edit.

Three facts cannot be read off the grid — that a piece was *rotated*, that a
landscape was *chosen*, that a test drive was *started* — so the editor sets those
as they happen.

### 5. It survives the test drive

The last step asks the player to leave the editor entirely. `GameState` keeps two
flags: `editor_tutorial_active` resumes the walk when the editor comes back, and
`editor_tutorial_finale` is the closing line waiting to be shown once. Coming back
mid-walk, whatever can be inferred from the world is inferred rather than asked
for twice.

Finishing earns the closing line. Skipping does not — it just goes away.

### 6. Where it draws

One panel, bottom-centre, in the `CanvasLayer` the editor already has: step number,
one sentence, Skip. The button the sentence is talking about breathes, using
`modulate` — free, because the palette shows what is *selected* with
`button_pressed`, not with tint. No new art: the "?" that replays the walk is
another procedurally drawn glyph in `EditorIcons`.

### 7. Getting it back

A `?` in the editor's action row, and a row in Settings. Both clear the
`[editor] tutorial_done` flag in `user://settings.cfg` — the same file the audio
and display managers share. The walk itself only ever starts on an **empty** grid,
so pressing `?` over a half-built track says so rather than throwing a
half-finished checklist over someone's work.

## Consequences

- `tests/editor_tutorial_test.gd` — 40 checks: the steps in order, out of order,
  pre-satisfied, skipping, the persistence flag, and the editor wiring itself. It
  restores the player's own `tutorial_done` setting on the way out.
- The walk is a checklist that watches the grid and nothing more, which is the
  point: nobody should hesitate to change the editor for fear of breaking it.
