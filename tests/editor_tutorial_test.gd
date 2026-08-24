extends Node
## The editor's first-run walk, driven the way a player drives it: by changing the
## track and letting the steps notice.
##
## Run with:
##   godot --headless --path . tests/editor_tutorial_test.tscn
##
## It reads and restores the `tutorial_done` flag in user://settings.cfg, so a
## player's own setting survives the run.

var _passed := 0
var _failed := 0
var _was_done := false
var _lib: TileLibrary


func _ready() -> void:
	await get_tree().process_frame
	_was_done = EditorTutorial.was_done()
	_lib = GameState.library

	_walks_in_order()
	_skips_what_is_already_done()
	_out_of_order_still_advances()
	_only_starts_on_an_empty_track()
	_skip_ends_it()
	await _shows_up_in_the_editor()
	_finish()


# --- A player following along -------------------------------------------------

func _walks_in_order() -> void:
	var grid := TrackGrid.new(_lib.definitions)
	var t := EditorTutorial.new(grid, _lib)
	GameState.current_terrain = null
	_ok(t.index == 0, "starts on step 1")
	_ok(t.highlight() == "start", "and points at the Start piece")

	grid.place(Vector2i(0, 0), &"start", 1, 0)
	t.check()
	_ok(t.index == 1, "placing the start finishes step 1")
	_ok(t.highlight() == "straight", "and step 2 points at a straight")

	# A straight that does NOT join it: the step is about the join, not the piece.
	grid.place(Vector2i(4, 4), &"straight", 1, 0)
	t.check()
	_ok(t.index == 1, "a straight on its own is not a join")

	grid.place(Vector2i(1, 0), &"straight", 1, 0)
	t.check()
	_ok(t.index == 2, "one that meets the start finishes step 2")

	# A curve placed without ever rotating: the step is about learning to turn.
	grid.place(Vector2i(2, 0), &"curve", 0, 0)
	t.check()
	_ok(t.index == 2, "a curve placed without rotating does not finish step 3")
	t.rotated = true
	t.check()
	_ok(t.index == 3, "rotating and placing one does")
	_ok(t.highlight() == "", "step 4 points at no button — it is about the shape")

	# Not a loop yet.
	_ok(t.index == 3, "an unfinished lap keeps step 4 open")
	_close_the_loop(grid)
	t.check()
	_ok(t.index == 4, "closing the loop finishes step 4")
	_ok(t.highlight() == "terrain", "and step 5 points at the terrain row")

	t.picked_terrain = true
	t.check()
	_ok(t.index == 5, "picking a landscape finishes step 5")
	_ok(t.highlight() == "test", "and the last step points at Test Drive")
	_ok(not t.finished, "and it is not over until the drive")

	t.drove = true
	t.check()
	_ok(t.finished, "starting the test drive ends the walk")
	_ok(t.text() == EditorTutorial.FINALE, "and leaves the closing line")
	_ok(EditorTutorial.was_done(), "finishing it means it will not run again")
	_ok(GameState.editor_tutorial_finale, "the closing line is waiting for the editor to come back")
	_ok(not GameState.editor_tutorial_active, "and the walk is no longer running")
	GameState.editor_tutorial_finale = false


## Steps already satisfied when the walk starts are ticked off without being asked
## for — the case that matters when a test drive drops the player back in.
func _skips_what_is_already_done() -> void:
	var grid := TrackGrid.new(_lib.definitions)
	grid.place(Vector2i(0, 0), &"start", 1, 0)
	grid.place(Vector2i(1, 0), &"straight", 1, 0)
	_close_the_loop(grid)
	var t := EditorTutorial.new(grid, _lib)
	t.check()
	_ok(t.index >= 3, "a lap already built skips the first steps (on %d)" % t.step_number())
	_ok(t.index <= 4, "but does not skip the ones still undone")


## Play it backwards: the curve before the straight, the loop before anyone
## mentions corners. Nothing should get stuck.
func _out_of_order_still_advances() -> void:
	var grid := TrackGrid.new(_lib.definitions)
	var t := EditorTutorial.new(grid, _lib)
	grid.place(Vector2i(2, 0), &"curve", 0, 0)
	t.rotated = true
	t.check()
	_ok(t.index == 0, "no start piece means step 1 is still step 1")
	grid.place(Vector2i(0, 0), &"start", 1, 0)
	grid.place(Vector2i(1, 0), &"straight", 1, 0)
	_close_the_loop(grid)
	t.check()
	_ok(t.index == 4, "everything done at once jumps straight to what is left")


func _only_starts_on_an_empty_track() -> void:
	EditorTutorial.forget()
	var empty := TrackGrid.new(_lib.definitions)
	_ok(EditorTutorial.should_run(empty), "a newcomer on an empty grid gets the walk")

	var built := TrackGrid.new(_lib.definitions)
	built.place(Vector2i(0, 0), &"straight", 1, 0)
	_ok(not EditorTutorial.should_run(built),
		"someone mid-track does not get it thrown over their work")

	GameState.editor_tutorial_active = true
	_ok(EditorTutorial.should_run(built), "but a walk already under way resumes")
	GameState.editor_tutorial_active = false

	EditorTutorial.mark_done()
	_ok(not EditorTutorial.should_run(empty), "and it does not come back once seen")
	EditorTutorial.forget()
	_ok(EditorTutorial.should_run(empty), "until it is asked for again")


func _skip_ends_it() -> void:
	EditorTutorial.forget()
	var grid := TrackGrid.new(_lib.definitions)
	var t := EditorTutorial.new(grid, _lib)
	t.skip()
	_ok(t.finished, "skipping ends the walk where it stands")
	_ok(EditorTutorial.was_done(), "and it does not offer itself again")
	_ok(not GameState.editor_tutorial_active, "and nothing is left running")


## The wiring, not the state machine: the editor starts the walk, draws its panel,
## and follows along as pieces go down — because `_update_status` polls it, which
## is the one call that already runs after every change.
func _shows_up_in_the_editor() -> void:
	EditorTutorial.forget()
	GameState.current_grid = TrackGrid.new(_lib.definitions)
	GameState.current_terrain = null
	var editor: Node = load("res://scenes/editor/Editor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame

	var t: EditorTutorial = editor.get("_tutorial")
	_ok(t != null, "the editor starts the walk on an empty track")
	_ok(editor.get("_tutorial_panel") != null, "and puts its panel on screen")
	if t != null:
		var grid: TrackGrid = editor.get("_grid")
		grid.place(Vector2i(0, 0), &"start", 1, 0)
		editor.call("_update_status")
		_ok(t.index == 1, "and follows along as pieces go down")
		_ok(not editor.get("_pulsed").is_empty(), "with the button it is talking about lit up")

	# Skipping takes the panel away and leaves a normal, working editor behind —
	# and no closing line, which is for finishing.
	if t != null:
		t.skip()
		_ok(editor.get("_tutorial") == null, "skipping ends the walk")
		_ok(editor.get("_tutorial_panel") == null, "and takes the panel away")
		_ok(editor.get("_pulsed").is_empty(), "and stops lighting buttons up")
		_ok(not GameState.editor_tutorial_finale, "and does not hand out the closing line")

	editor.queue_free()
	await get_tree().process_frame


# --- Helpers ------------------------------------------------------------------

## A square of road round the origin: straights along the sides, curves at the
## four corners, which is the smallest thing the race will call a lap.
##
## The start piece goes on a side, never on a corner. A start on a corner replaces
## that corner with a straight and tears the lap open — the same way the example
## track was broken, and just as invisible from the JSON.
func _close_the_loop(grid: TrackGrid) -> void:
	for cell in grid.tiles.keys():
		grid.remove(cell)
	var w := 3
	# Corners, each rotated for the turn it makes going clockwise.
	grid.place(Vector2i(0, 0), &"curve", 1, 0)
	grid.place(Vector2i(w, 0), &"curve", 2, 0)
	grid.place(Vector2i(w, w), &"curve", 3, 0)
	grid.place(Vector2i(0, w), &"curve", 0, 0)
	# Sides. Rotation is the direction of travel: E across the top, S down the
	# right, W back along the bottom, N up the left.
	grid.place(Vector2i(1, 0), &"start", 1, 0)
	for x in range(2, w):
		grid.place(Vector2i(x, 0), &"straight", 1, 0)
	for y in range(1, w):
		grid.place(Vector2i(w, y), &"straight", 2, 0)
	for x in range(w - 1, 0, -1):
		grid.place(Vector2i(x, w), &"straight", 3, 0)
	for y in range(w - 1, 0, -1):
		grid.place(Vector2i(0, y), &"straight", 0, 0)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  ", what)


func _finish() -> void:
	# Leave the player's own setting as it was found.
	if _was_done:
		EditorTutorial.mark_done()
	else:
		EditorTutorial.forget()
	GameState.editor_tutorial_active = false
	GameState.editor_tutorial_finale = false
	print("editor tutorial: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
