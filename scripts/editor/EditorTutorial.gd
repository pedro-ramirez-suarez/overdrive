class_name EditorTutorial
extends RefCounted
## A first-run walk through the editor: six steps, each one sentence, each finished
## by doing the thing rather than by clicking Next.
##
## The editor opens on an empty grid, twenty track pieces, five terrain presets and
## five sculpting tools — and one rule that appears nowhere on screen: **a raceable
## track is a closed loop with a Start / Finish piece in it.** Until now that rule
## lived in the README and in the message you get *after* pressing Race. Step 4 is
## the whole reason this exists; the rest are the shortest path to it.
##
## It adds no systems. The connection feedback, the palette, the drape — all of it
## was already there. This points at it.
##
## ## How it watches
##
## Every step is a sentence and a predicate. `check()` runs them in order and
## advances past any that are already satisfied, so playing out of order — or doing
## two things at once — never leaves the player stuck on a step they finished five
## pieces ago. It is polled from `EditorController._update_status()`, the one place
## that already runs after every change to the track.
##
## It never takes control: no modal, no forced tool, no swallowed input, and Skip is
## on screen from the first frame.
##
## Three things cannot be read off the grid — that a piece was rotated, that a
## landscape was chosen, that a test drive was started — so the editor sets those
## as they happen. A test drive leaves the scene entirely, so the walk resumes from
## `GameState` when the editor comes back.

const SETTINGS_PATH := "user://settings.cfg"

## The step changed, or the whole thing ended: redraw the panel and the highlight.
signal changed()

var index: int = 0
var steps: Array = []
var finished: bool = false

var _grid: TrackGrid
var _lib: TileLibrary
## Set by the editor as they happen; see the note above.
var rotated: bool = false
var picked_terrain: bool = false
var drove: bool = false


func _init(grid: TrackGrid, lib: TileLibrary) -> void:
	_grid = grid
	_lib = lib
	# Coming back from a test drive the walk restarts mid-track, so what can be
	# inferred from the world is inferred rather than asked for twice.
	rotated = _count("curve") > 0
	picked_terrain = GameState.current_terrain != null and not grid.tiles.is_empty()
	steps = [
		{
			"text": "Every track starts with the finish line. Place the Start / Finish piece.",
			"highlight": "start",
			"done": func() -> bool: return _count("start") > 0,
		},
		{
			"text": "Now a Straight beside it. The join glows green where two pieces meet.",
			"highlight": "straight",
			"done": func() -> bool: return _connected_pair(),
		},
		{
			"text": "Corners: press T (B on a pad) to turn a piece before you place it.",
			"highlight": "curve",
			"done": func() -> bool: return _count("curve") > 0 and rotated,
		},
		{
			"text": "Now bring it back round to the start. A track has to be a closed loop.",
			"highlight": "",
			"done": func() -> bool: return _is_closed_loop(),
		},
		{
			"text": "Pick a landscape under TERRAIN. The track drapes over whatever you choose.",
			"highlight": "terrain",
			"done": func() -> bool: return picked_terrain,
		},
		{
			"text": "Drive it — Test Drive, up in the corner.",
			"highlight": "test",
			"done": func() -> bool: return drove,
		},
	]


## The closing line, shown once, when the editor comes back from that last drive.
const FINALE := "That is the whole idea. The rest of the palette — ramps, loops, " \
	+ "corkscrews, pipes, the helix — works exactly the same way."


func text() -> String:
	return FINALE if finished else String(steps[index]["text"])


## Which button to draw attention to: a tile id, "terrain", "test", or "" for none.
func highlight() -> String:
	return "" if finished else String(steps[index]["highlight"])


func step_number() -> int:
	return mini(index + 1, steps.size())


## Advance past every step that is now satisfied. Called after any change to the
## track, so it is cheap and safe to call as often as you like.
func check() -> void:
	if finished:
		return
	var moved := false
	while index < steps.size() and bool((steps[index]["done"] as Callable).call()):
		index += 1
		moved = true
	if index >= steps.size():
		_finish()
	elif moved:
		changed.emit()


## Give up on it, and do not offer it again.
func skip() -> void:
	finished = true
	index = steps.size()
	GameState.editor_tutorial_active = false
	mark_done()
	changed.emit()


func _finish() -> void:
	finished = true
	GameState.editor_tutorial_active = false
	# The last step is a test drive, which leaves the editor. The closing line is
	# waiting when it comes back.
	GameState.editor_tutorial_finale = true
	mark_done()
	changed.emit()


# --- Predicates --------------------------------------------------------------

func _count(def_id: String) -> int:
	var n := 0
	for cell in _grid.tiles:
		if _grid.get_anchor(cell) == cell and String(_grid.get_placed(cell).def_id) == def_id:
			n += 1
	return n


## Any two pieces that actually join — sockets, heights and slopes agreeing, which
## is exactly what the green connector on screen is saying.
func _connected_pair() -> bool:
	for cell in _grid.tiles:
		for offset in TrackGrid.OFFSETS:
			var other: Vector2i = cell + offset
			if _grid.has_tile(other) and _grid.get_anchor(other) != _grid.get_anchor(cell) \
					and _grid.cells_connected(cell, other):
				return true
	return false


## The rule the whole walk exists for: a lap the race can drive, start to start.
func _is_closed_loop() -> bool:
	var anchors := {}
	for cell in _grid.tiles:
		anchors[_grid.get_anchor(cell)] = true
	if anchors.size() < 4:
		return false
	return RacePath.compute(_grid, _lib).size() >= anchors.size()


# --- Whether to run at all ---------------------------------------------------

## For someone who has not seen it, on an empty grid — never over a track somebody
## is in the middle of building — or for a walk already under way, coming back from
## the test drive its last step asks for.
static func should_run(grid: TrackGrid) -> bool:
	if grid == null:
		return false
	if GameState.editor_tutorial_active:
		return true
	return grid.tiles.is_empty() and not was_done()


static func was_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	return bool(cfg.get_value("editor", "tutorial_done", false))


static func mark_done() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep whatever audio and display wrote
	cfg.set_value("editor", "tutorial_done", true)
	cfg.save(SETTINGS_PATH)


## Let it run again from the start — the "?" in the editor, and the row in Settings.
static func forget() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("editor", "tutorial_done", false)
	cfg.save(SETTINGS_PATH)
	GameState.editor_tutorial_active = false
	GameState.editor_tutorial_finale = false
