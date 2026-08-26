# Demo media

The GIF at the top of the README does more to sell this game than any amount of
prose: nobody clones a repository to find out what a game looks like. This is how
that GIF gets made.

## Record the footage

**Use the replay system.** Do not try to drive well and record at the same time.
Drive a good lap, then watch it back: `C` cycles the chase / cockpit / trackside /
helicopter cameras, `↓` gives you slow-motion, `←/→` scrub. Record the replay
instead of the live drive and you get steady, cinematic camera work you can retake
without re-driving.

Pick a capture tool:

| Tool | Get it | Notes |
|---|---|---|
| ScreenToGif | `winget install NickeManarin.ScreenToGif` | Records, trims and exports a GIF in one app. Simplest. |
| OBS Studio | `winget install OBSProject.OBSStudio` | Best quality and control; records MP4. |
| Godot Movie Maker | built in (see below) | Frame-perfect, never drops a frame. |

Godot's Movie Maker renders every frame at a fixed timestep rather than in real
time, so the result is perfectly smooth no matter what the frame rate does:

```bash
godot --path . --write-movie capture.avi
```

The catch is that fixed-step means the game no longer runs at wall-clock speed, so
driving live while it records feels sluggish. Replay playback does not care — it
is transform-driven — which is another reason to film the replay.

## Make the files

```bash
tools/media/make-demo.sh capture.mp4 --start 00:00:04 --duration 15
```

That writes `docs/media/demo.gif` and `docs/media/demo.mp4`. Then uncomment the
image line near the top of the README.

Useful options — `--speed 3` (for sped-up editor build footage), `--width`,
`--fps`, `--duration`, `--out`. Run with `--help` for the rest.

## What to aim for

- **12–20 seconds.** A loop people watch twice beats a film they abandon.
- **Under 5 MB**, ideally 2–3. The script warns if the GIF goes over.
- **640px wide, 15fps** are the defaults and a good balance.
- **Lead with the editor.** Plenty of games race; few ship an editor this deep.
  "I built this, then I drove it" is the whole pitch.

A shot list that works:

| Time | Shot |
|---|---|
| 0–4s | Editor: tiles snapping together, a loop taking shape (`--speed 3`) |
| 4–6s | Test Drive — the cut from grid to world is the hook |
| 6–12s | Driving it: the loop, the corkscrew, trackside camera |
| 12–15s | A jump or the helix, a beat of slow-motion |

## GIF in the README, MP4 everywhere else

GitHub renders an MP4 in a README, but only one uploaded through its web UI — drag
the file into an issue or the README editor and it hands you a `user-attachments`
URL to paste in. An `.mp4` committed to the repo and linked by relative path will
not play, which is why the GIF is what the README points at.

Use the MP4 for itch.io, and the GIF for forums and Reddit, where it autoplays.
