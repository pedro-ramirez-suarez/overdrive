# Track generator

Builds an OVERDRIVE track from a real place: a lap traced out of OpenStreetMap,
laid onto the 8 m tile grid, with the ground under it sculpted from SRTM
elevation data. Seven of the bundled tracks were made with it.

It runs headless in Godot, from the project root:

```bash
godot --headless --path . --script tools/trackgen/build_track.gd -- zuzuka
```

Every track it has built is reproducible: re-running the command above writes a
file byte-identical to the one in `tracks/`, because each circuit's entry in
`CIRCUITS` carries the numbers it was built with.

## What is here

| | |
|---|---|
| `find_loop.gd` | OSM extract → one lap, as a list of points (`routes/*.json`) |
| `build_track.gd` | a lap → a finished track (`out/*.json`) |
| `map_circuit.gd` | draws an OSM extract, for finding your way around |
| `zoom_map.gd` | draws a lat/lon window of it, for reading off coordinates |
| `routes/` | the extracted laps — committed, they are the fiddly part |
| `queries/` | the Overpass queries each circuit was fetched with |
| `data/` | downloaded map and elevation data — **gitignored**, see below |
| `out/` | whatever you build — **gitignored** |

## Getting the data

Neither the map extracts nor the elevation tiles are in the repo; together they
run to hundreds of megabytes. Both are free to download.

**Map data** — one Overpass query per circuit, already written in `queries/`:

```bash
curl -s --data-urlencode "data@tools/trackgen/queries/zuzuka.q" \
  https://overpass-api.de/api/interpreter -o tools/trackgen/data/zuzuka.json
```

Do the same with `<circuit>_props.q` → `data/<circuit>_props.json` for the
buildings and woodland the scenery is placed from. Overpass rate-limits and
sometimes returns an HTML error page instead of JSON — check the file starts
with `{`, wait a few seconds, retry.

**Elevation** — 1 arc-second SRTM tiles, one degree square each, named for their
south-west corner. `build_track.gd` prints `MISSING DEM tile N50E006` if one it
needs is absent:

```bash
curl -s https://s3.amazonaws.com/elevation-tiles-prod/skadi/N50/N50E006.hgt.gz \
  | gunzip > tools/trackgen/data/N50E006.hgt
```

A circuit that straddles a degree line needs both tiles (the Eifelschleife needs
`N50E006` and `N50E007`).

## Adding a circuit

**1. Fetch and look at it.** Write a query into `queries/`, fetch it, then draw
it:

```bash
godot --headless --path . --script tools/trackgen/map_circuit.gd -- newtrack
```

`out/newtrack_map.png` shows the raceways in orange, pit lanes and kart tracks in
blue, with a lat/lon graticule. `zoom_map.gd` takes a window
(`-- newtrack 34.837 136.520 34.851 136.544`) when you need to read a coordinate
precisely.

**2. Extract the lap.** Add an entry to `CIRCUITS` in `find_loop.gd` and run it.
There are three ways to trace a lap, in order of preference:

- **`walk`** (the default) — filter out the pit lanes and side tracks, then drive
  the graph: from the start, always take the outgoing edge that bends least,
  stop when you get home. A real circuit is very nearly a simple cycle, so this
  traces it exactly. It landed within 1.5% of the published length every time.
  You give it two anchors: where to start, and a point to head towards, which
  fixes the direction round.
- **`legs`** — shortest path between anchors in order. For when junctions make
  the walk wander.
- **`traced`** — you trace the lap by hand off the map in pixel coordinates, and
  each point is snapped to the nearest real road node. Monte Carlo needed this:
  it is public street, mapped as raceway only in fragments, and shortest paths
  between distant anchors kept ducking down side streets.

Check `out/newtrack_route.png` and the printed length against the real one before
going further. A wrong lap wastes everything downstream.

**3. Build it.** Add an entry to `CIRCUITS` in `build_track.gd` and run it. Start
with `scale` and `vstep`; the rest have sensible defaults.

**4. Register it.** Copy `out/newtrack.json` into `tracks/`, add it to
`TrackSerializer.BUNDLED`, and add the place to the map-data section of
`CREDITS.md` — OpenStreetMap's licence requires the attribution to travel with
any build that ships the track.

## The settings that matter

| key | what it does |
|---|---|
| `scale` | game metres per real metre. 1.0 keeps real corner radii; the two big road courses had to shrink to 0.35–0.40 to fit |
| `vstep` | real metres per elevation level. The engine has 16 levels of 3 m, so this sets how much of the real relief survives |
| `smooth` | how far the elevation is averaged along the lap, in cells. Higher on noisy ground |
| `start_near` | `[lat, lon]` of the start/finish line |
| `lateral` | for a divided road: how far each carriageway is nudged to its own right, in cells |
| `banking` | allow 3x3 banked corners where a corner has room |
| `crossing` | `[[lat, lon], [lat, lon]]` of the bridge deck, for a lap that crosses itself |
| `tunnels` | lat/lon boxes where the road runs in a tunnel |
| `tree_reach`, `building_reach` | how far from the track scenery is placed, in cells |

## What it does to the elevation

The engine has one climbing piece: a ramp, exactly one level (3 m) per cell.
There is no shallow ramp, so a road that simply follows the ground comes out as
stairs and V-shaped kinks. Two passes tidy that up, both global constants at the
top of `build_track.gd` rather than per-circuit settings:

- **Dips are carried across** (`DIP_*`). Where the ground falls away and rises
  again within `DIP_GAP` cells, the descent is cancelled against the climb and
  the road stays level — the ground under a tile is flattened to it, so the
  embankment builds itself. Only up to `DIP_SPAN` cells, because a long dip is a
  valley and crossing one on a causeway looks sillier than driving through it,
  and only `DIP_MAX` levels deep, so a deep dip keeps its edges. Crests are left
  alone: a brow is a real feature and fun to drive.
- **Staircases are rolled into slopes** (`RAMP_*`). Ramps within `RAMP_GAP` cells
  of each other slide into one continuous run, so the road climbs once instead of
  stepping up. A merge only happens while the road stays within `RAMP_OFF_MAX`
  levels of the ground, checked per merge.

Both keep the number and direction of ramps balanced, so the lap always comes
home to the level it left at. The build prints what it did:
`slopes: 8 dips carried across, 12 steps rolled into runs`.

## Things that will bite

- **Scenery is expensive.** Every prop is a solid body with its own mesh. The
  Eifelschleife's first cut had 4,400 of them and ran at 26 fps; trimmed to what
  can be seen from the car it is 814 props and 61 fps. Keep the reaches tight.
- **Terrain has a size cap.** `TerrainWorld.MAX_SPAN` is 340 cells. Past it the
  ground simply stops while the track carries on. `build_track.gd` prints the
  span it needs — check it.
- **A crossing needs three overpass cells, not one.** Terrain corners are
  flattened to the highest tile touching them, so a deck that steps up to
  ordinary raised road in the next cell drags the ground up and fills in the
  underpass. The generator does this automatically.
- **Banked corners are handed.** Entry and exit are mirrors of each other, not
  rotations; one hand of corner takes the mirrored pair or the road ends up off
  camber. Also automatic, but worth knowing if you place them by hand.
- **Nothing may touch anything else.** The router keeps a clear cell around
  track already laid, because two unrelated stretches sharing a terrain corner
  lift the lower one's verge over its own tarmac.

The scripts live inside the game project so they can be run with `--path .`, so
they do get swept into an export unless you exclude `tools/*` in the export
preset. They are a few hundred KB of dead weight in a build, nothing more.

## Where the data comes from

- Roads and circuits: **OpenStreetMap**, © OpenStreetMap contributors, ODbL.
- Elevation: **NASA/USGS SRTM** 1 arc-second, public domain, via the AWS
  elevation-tiles-prod bucket.
