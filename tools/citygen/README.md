# City generator

Builds **Emerald Sound**, the bundled city circuit — a 3.4 km lap around a sound,
a ship canal and a lake, inspired by Seattle.

```bash
godot --headless --path . tools/citygen/build_emerald_sound.tscn
```

It writes `tracks/emerald_sound.json` and prints what it built. The same command
writes the same bytes every time: every seed in it is fixed.

## Why this is not the map generator

[`tools/trackgen`](../trackgen/README.md) traces a lap out of OpenStreetMap and
sculpts the real ground under it. It could lay out downtown Seattle's streets —
but a real street has no loop in it, and no corkscrew, and the point of a city
track here is to drive the pieces the editor is for. So this one is laid out by
hand around the same *geography* instead: the water down the west side, a canal
cut east into a lake in the middle, hills on every side, the yards in the south —
and the stunt pieces built into the lap where the city gives them a reason.

Nothing here is a reproduction of Seattle, and the name is a near-miss on purpose.

## How it is built

A turtle walks the lap. It holds a cell, a direction and a road level, and each
piece is described by the two connectors it joins the road with — the same
sockets `TileLibrary` gives the editor:

```gdscript
_emit("helix", Vector2i.ZERO, S, 0, Vector2i(0, -2), N, 1)
```

"enter the south edge of the anchor at this level, leave the north edge of the
cell two north of it one level up." Rotation, anchor cell and base elevation fall
out of that arithmetic, so a 3x9 corkscrew is placed the same way as a straight
and nothing is counted out by hand. Corners are given as **waypoints**
(`_run_to(58)` — road until the next cell reaches x=58), so moving one corner does
not shift every piece after it.

The lap is checked as it is laid: every piece must join the one before it, none
may land on another, no road may stand in the water unless it is on a bridge, and
the last piece has to hand back to the start tile at the same level. Any of those
failing prints a `WARN` and exits non-zero.

Then: the hills are sculpted, the ground under the road is pulled to the road's
own level, the water is carved into a basin and flooded, and the districts are
built up around whatever is left.

## Things worth knowing

- **The overpass is the only piece with anything underneath it.** Its deck sits
  one level above its own base and stands on piers, so a deck with its base at
  the waterline is a bridge. `_bridge_water()` measures the span off the water
  itself, so reshaping a lake re-sizes its bridge.
- **A raised stretch is built from deck, not from straights a level up.** Terrain
  corners are pulled up to the highest tile touching them. An overpass carries its
  road above its *own* level, so the ground stays down; a straight placed a level
  up drags the corners it shares with its neighbours up with it.
- **Which is what a helix demands.** All nine cells of a helix are one tile at one
  level, and the road spirals from that level to one above it. Put ordinary raised
  road at the top of it and the corner they share is pulled up a level — and that
  same corner is the middle of the spiral, where the road has not climbed yet, so
  the ground closes over the entry and the exit. `_check_lap()` fails the build if
  anything stands a level over a helix. (`test_track` joins its two helixes with a
  run of overpass for exactly this reason.)
- **The gap a jump crosses is cut a level down.** Left alone it is whatever the
  noise put there, which can be a hump in the middle of the flight.
- **The terrain the game draws is the track's bounds plus 24 cells**
  (`TerrainWorld.MARGIN`), not whatever the terrain data covers. Water outside
  that is stored in the file and never seen — `_water_cells()` clips to it.
- **Water cannot run to the edge of that region**, or the car can see where the
  world stops. Both shores of the sound are held inside it, and hills stand along
  the north, east and south edges to close the view.
- **A hill needs as many cells of skirt as it is tall.** No two adjacent corners
  may differ by more than one level, so a peak carved down to a shoreline takes
  the whole flank with it. That is why the far bank of a narrow channel is low.
- **Scenery is expensive** — every prop is a solid body with its own mesh. This
  track is ~800, kept within 16 cells of the road, plus a dozen towers further out
  for the skyline.

## Checking it

```bash
godot --headless --path . tools/trackgen/check_track.tscn -- tracks/emerald_sound.json
godot --headless --path . tools/citygen/smoke_test.tscn -- tracks/emerald_sound.json
```

The first walks the lap the way the race does and looks for road buried in its own
ground; the route has to come out COMPLETE with no open road ends. The second
builds the whole world out of the file — terrain mesh, tiles and every prop — which
is the only check that the thing actually loads. It works on any track file.
