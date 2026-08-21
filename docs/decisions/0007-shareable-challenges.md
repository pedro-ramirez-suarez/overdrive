# ADR 0007 — Shareable challenges

Status: Accepted

## Context

The editor is the star of this game, and nothing carried what you built in it to
anyone else. A track file could already be sent and imported, but a track alone
has no stakes — the thing worth sending is a track *and a lap on it*.

Everything needed was already here: `TrackSerializer` writes and reads tracks,
every race already extracts a single-car ghost (`Replay.extract_car(0)`) for the
"beat your best" ghost, and `RaceManager` already drives one translucently. What
was missing was a container, and the rules about which ghost wins.

See [the proposal](../proposals/challenges-and-onboarding.md) for the shape this
was specced in; this records what was actually built and why it differs.

## Decisions

### 1. One file, binary, self-contained

A challenge is a `.ovc`: a Godot binary Variant holding the track dict exactly as
`TrackSerializer.to_dict` produces it, the ghost exactly as `Replay` stores it, a
fingerprint of the track, and the metadata (author, car, times, laps, direction,
note). Binary because a ghost is a transform stream — the example lap is 1,674
frames and 76 KB; as JSON it would be several times that.

The track is embedded rather than referenced. A challenge has to work when it
arrives alone from someone you have never met, which is the whole point.

`Replay` gained `to_variant` / `from_variant` so a ghost can be embedded without
going through a temp file. No behaviour change to replays themselves.

### 2. A file from outside is hostile input

The file is read with `get_var(false)`. Godot's Variant format can encode an
object, and an object can carry a script — so objects are refused at the door.
That single flag is the whole reason a data file cannot run code here, and there
is a test that writes a scripted object into a challenge and asserts it comes
back as nothing.

Beyond that: the file is size-capped before it is read; every field is
type-checked; every number is range-checked (including a sweep for NaN and
infinity in the ghost, which would otherwise throw the car and the camera to
infinity); arrays are length-capped; and every string is stripped of control
characters and cut to length before it can reach a `Label` — a newline in an
author's name would otherwise let a stranger's file rearrange the panel it is
drawn in.

Nothing in the file is ever used as a path. Tile meshes come from the local
`TileLibrary` by id, and an id this build does not have is a reason to refuse the
file — named in the message, so the player knows what they are missing.

Every refusal returns a sentence (`Challenge.file_error`), following
`TrackSerializer.file_error`: the file someone was sent is all they have, and
"invalid file" tells them nothing about what to do next.

What is deliberately NOT done is verifying that the time was honestly driven. A
`.ovc` is a file and anyone can write one. This is a local, single-player game
passing runs between people who know each other; there is no leaderboard here to
protect, and anti-cheat machinery would cost more than it could ever be worth.

### 3. The fingerprint, and what it is for

A ghost is world-space transforms, so it means something only on the exact layout
it was recorded over: move one corner and the recorded car drives through the
scenery. `Challenge.hash_track` fingerprints the sorted grid entries plus the
terrain type, seed, edits and lakes.

Everything hashed is sorted, and nothing that merely reflects dictionary iteration
order is included — a track saved, loaded and saved again has to fingerprint the
same, or a ghost would stop matching its own track the first time it went through
the serializer. There is a test for exactly that.

A challenge whose fingerprint does not match the local track still installs, still
shows its target time, and simply does not put a ghost on the road, saying so on
the track-select screen. Silently driving a nonsense ghost would be worse.

`fits_grid` takes the terrain as an argument rather than reading
`GameState.current_terrain`: the ground is half the fingerprint, and the global is
not necessarily this track's ground. `TrackSerializer.to_dict` grew the same
optional argument, defaulting to the old behaviour.

### 4. One challenge per track, keyed by name

`user://challenges/<slug>.ovc`, using the same slug `Records` uses, so a track and
its challenge find each other by name. Importing a second challenge for a track
replaces the first. A list per track would be more faithful to how people actually
swap times, but it needs UI to choose between them and nobody has asked for it
yet.

Tracks are matched on import by **fingerprint, not name**, so importing the same
challenge twice — or a second challenge on a track already in the library — copies
nothing and adds no duplicate. A genuinely different track arriving under a name
already in use is renamed (`Crosswind Circuit (2)`) rather than merged: two tracks
sharing a name would share records, and one player's lap would silently become the
par for the other's track.

### 5. One ghost on the road, not two

With a challenge armed, its ghost replaces the personal best; a toggle on the
race-setup panel switches back. Two translucent cars through the same corner is
noise, and a challenge is meant to be a single rival to chase.

Whether a challenge belongs to the track being raced is settled once, when the
ghost is chosen. A test drive launched from the editor, or a different track
picked since, leaves a challenge armed that has nothing to do with what is being
driven — it must not put a ghost on the road, and its time must not judge the run
either. Racing the circuit in reverse skips the comparison too: it is not the same
lap.

### 6. Two doors, one importer

A challenge is an invitation; a track is a library item. Those are different
errands, so they get different entry points:

- **Challenge** on the main menu — for "someone sent me this". It accepts, then
  goes straight to picking a car and racing.
- **Import…** on track select — for "add this to my library". Someone who was
  sent a file looks there too, and before this the only door was inside the
  editor.

But both doors take **both kinds of file**. Two file pickers side by side, one
refusing `.ovc` and the other refusing `.json`, would be a trap: the player was
sent *a file*, does not necessarily know which kind it is, and a button that
rejects a perfectly good track to enforce a distinction they never made is worse
than one that simply works. The file says what it is, and whichever door it comes
through the right thing happens and the player is told what it was. The shared
logic is `ImportFlow`.

The rest of it:

- After importing a challenge, a panel says who set the time, what it is, and
  which car it was set in, with **Race it** and **Later**. Racing is one button
  away because it is the only thing anyone wants to do next.
- Accepting from the main menu sets `challenge_race_pending`, and car select
  starts the race itself rather than asking for a track the player has already
  been given. This is why the menu order did not need changing: the flag does what
  reordering car and track select would have done, without touching the
  back-navigation of four screens.
- The track's info panel names the challenge under the best-lap line.
- **S** on the results screen saves the run just driven as a challenge, and shows
  the path. The run just driven, not the personal best: it is the one the player
  has in mind at that moment, and the best is always still there to race again.
- Settings has a name field. There are no accounts here and nothing is read off
  the system — it is only what you want to be called on a file you hand a friend.

### 7. Accepting one sets up a time trial

Accepting a challenge clears the opponents, takes the challenge's lap count and
direction, and switches the ghost on. A challenge is a comparison against one
recorded lap; AI cars in the middle of it block the line, knock you off it, and
make the run you are trying to compare not comparable. The steppers on track
select are still there for anyone who wants a crowd.

The ghost also got fainter — `transparency` 0.6 to 0.82, and it stopped casting a
shadow. At 0.6 with a shadow under it, a car you were about to drive through read
as one you were about to hit.

### 8. The car is suggested, never forced

A challenge records the car it was set in, and accepting one puts that car under
the cursor on car select — but nothing is locked, and the rest of the roster is
right there.

Forcing it is tempting, because 28 cars with genuinely different handling means a
time in one is not the same measurement as a time in another. It was rejected for
three reasons. It is enforcement theatre in a feature with no enforcement: anyone
can hand-write a `.ovc`, so a car lock constrains only the honest player. It kills
the better outcome, which is beating someone's time in a worse car. And the car
name in the file is just a string — a roster change, or a challenge from a
modified build, names a car that does not exist here, so there has to be a
fallback anyway.

Instead the results screen is honest about it: beating a time in a different car
still says `★ CHALLENGE BEATEN ★`, followed by `(they drove a Marlin GT)`. That
gives the player what forcing only pretends to guarantee — enough to judge the
comparison themselves.

### 9. The example, and why the track is not bundled

`examples/crosswind_circuit.ovc` carries a track that is deliberately **not** in
the game's track list, so importing it exercises the case that matters: a
challenge for a track you have never seen. `tools/demo/make_challenge_demo.gd`
builds it — the circuit, a synthesised pace lap round the racing line, and the
file — and the challenge is honest about it: the author is "Pace Car".

The first version of that track was torn open at the start line: the start piece
was dropped on cell zero, which happened to be a corner, and it replaced the
corner with a straight. `RacePath` still walked the lap — it can leap a gap,
because that is what jump ramps are for — so nothing complained until the track
was looked at. The tool now puts the start on a cell the road runs straight
through, and checks every piece-to-piece join before it writes anything.
`check_track.gd` counts open road ends for the same reason, ignoring the ones
that are meant to be open: an overpass carries a stub of road under its deck, and
a jump ramp ends in mid-air on purpose.

## Consequences

- Two test suites under `tests/`, the first the repo has: `challenge_test`
  (format and hostile input, 46 checks) and `challenge_flow_test` (import → track
  select → race, 13 checks). Both clean up anything they install.
- `Records` still keys on the track name, so the collision question is handled by
  renaming on import rather than by re-keying records. If records ever move to a
  fingerprint key, this can be revisited.
- Challenges are deleted along with their track: a challenge without its track is
  a file nobody can race.
