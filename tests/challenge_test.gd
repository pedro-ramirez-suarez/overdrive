extends Node
## Checks on the challenge file format, and especially on what it does with a file
## it should refuse. A challenge arrives from outside, so most of these are
## hostile-input tests: an object smuggled into the payload, a tampered track, a
## ghost full of infinities, plain rubbish with the right extension.
##
## Run with:
##   godot --headless --path . tests/challenge_test.tscn
##
## Anything it writes goes under user://challenge_test and is deleted afterwards,
## including the one test that has to install into the real track library.

const TMP := "user://challenge_test"
const SAMPLE := "res://examples/crosswind_circuit.ovc"

var _passed := 0
var _failed := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var lib := TileLibrary.new()
	lib.build()
	GameState.library = lib

	var good := Challenge.load_from(SAMPLE)
	if good == null:
		print("FAILED: the example challenge does not load: ", Challenge.file_error(SAMPLE))
		_finish()
		return

	_valid_file_reads(good)
	_export_defaults()
	_round_trips(good)
	_refuses_rubbish()
	_refuses_objects()
	_refuses_tampering(good)
	_refuses_broken_ghosts(good)
	_refuses_unknown_pieces(good)
	_cleans_hostile_text(good)
	_fingerprint_survives_the_serializer(good)
	_installs_and_reuses(good)
	_finish()


# --- Tests -------------------------------------------------------------------

func _valid_file_reads(c: Challenge) -> void:
	_ok(Challenge.file_error(SAMPLE) == "", "the example challenge is accepted")
	_ok(c.author == "Pace Car", "author reads back")
	_ok(c.lap_time > 1.0, "lap time reads back")
	_ok(c.ghost != null and c.ghost.frame_count() > 100, "the ghost lap is there")
	_ok(c.track.get("name", "") == "Crosswind Circuit", "the track came with it")
	_ok(c.fits(c.track), "the challenge fits its own track")
	_track_is_a_closed_loop(c)


## The track inside the example has to be drivable, and drivable means every piece
## actually joins the next — sockets, heights and slopes agreeing. RacePath alone
## does not prove it: it can leap a gap, because that is what jump ramps are for,
## so a lap torn open at the start line still walks as "complete".
func _track_is_a_closed_loop(c: Challenge) -> void:
	var loaded := TrackSerializer.from_dict(c.track, GameState.library)
	var grid: TrackGrid = loaded["grid"]
	var cells: Array = []
	for t in c.track.get("grid", []):
		cells.append(Vector2i(int(t["cell_x"]), int(t["cell_y"])))
	var breaks := 0
	for i in range(cells.size()):
		if not grid.cells_connected(cells[i], cells[(i + 1) % cells.size()]):
			breaks += 1
	_ok(breaks == 0, "the example track joins up all the way round (%d break(s))" % breaks)
	var route: Array = RacePath.compute(grid, GameState.library)
	_ok(route.size() >= cells.size(), "and the race can walk every tile of it")


## What the save dialog offers: a filename that survives being a filename, and a
## folder the player will actually find again.
func _export_defaults() -> void:
	var name := Challenge.export_filename("Crosswind Circuit", 87.65)
	_ok(name.ends_with(".ovc"), "the offered name ends in .ovc")
	_ok(name.contains("crosswind_circuit"), "and is named for the track")
	for bad in [":", "*", "?", "\"", "<", ">", "|", "/", "\\"]:
		_ok(not name.contains(bad), "and has no %s in it" % bad)
	var dir := Challenge.export_dir()
	_ok(dir != "" and not dir.begins_with("user://"),
		"the dialog opens somewhere the player can find, not inside the game's data")


func _round_trips(c: Challenge) -> void:
	var path := "%s/round_trip.ovc" % TMP
	_ok(c.save_to(path), "a challenge saves")
	var back := Challenge.load_from(path)
	_ok(back != null, "and loads again")
	if back == null:
		return
	_ok(back.author == c.author and back.note == c.note, "text survives the trip")
	_ok(is_equal_approx(back.lap_time, c.lap_time), "the time survives the trip")
	_ok(back.track_hash == c.track_hash, "the fingerprint survives the trip")
	_ok(back.ghost.frame_count() == c.ghost.frame_count(), "the ghost survives the trip")


func _refuses_rubbish() -> void:
	_refuses("%s/missing.ovc" % TMP, "a file that isn't there")

	var empty := "%s/empty.ovc" % TMP
	FileAccess.open(empty, FileAccess.WRITE).close()
	_refuses(empty, "an empty file")

	var text := "%s/text.ovc" % TMP
	var f := FileAccess.open(text, FileAccess.WRITE)
	f.store_string("this is not a challenge, it is a note")
	f.close()
	_refuses(text, "a text file")

	# A real track file, renamed. Right game, wrong kind of file.
	var as_track := "%s/track.ovc" % TMP
	var tf := FileAccess.open(as_track, FileAccess.WRITE)
	tf.store_string(FileAccess.get_file_as_string("res://tracks/sample_oval.json"))
	tf.close()
	_refuses(as_track, "a track file with a challenge's extension")

	# Truncated halfway: the shape is right up to the point it stops.
	var whole := FileAccess.get_file_as_bytes(SAMPLE)
	var cut := "%s/truncated.ovc" % TMP
	var cf := FileAccess.open(cut, FileAccess.WRITE)
	cf.store_buffer(whole.slice(0, whole.size() / 2))
	cf.close()
	_refuses(cut, "a half-downloaded file")


## The one that matters. A Godot Variant file can encode an object, and an object
## can carry a script — so a challenge is read with objects switched OFF. A file
## that asks for one has to come back as nothing, not as a live object.
func _refuses_objects(_unused: int = 0) -> void:
	var path := "%s/objects.ovc" % TMP
	var payload := {
		"magic": Challenge.MAGIC,
		"version": 1,
		"track": {"format": TrackSerializer.SIGNATURE, "grid": [], "name": "Nasty"},
		"ghost": {},
		"track_hash": "",
		"challenge": {"author": "Nasty"},
		# An object, with a script attached, riding along inside the payload.
		"payload": _scripted_object(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(payload, true)   # true: allow objects ON THE WAY OUT, deliberately
	f.close()
	_refuses(path, "a file with an object smuggled into it")

	# And prove the refusal is the object, not the rest: reading it with objects
	# off yields nothing at all, so nothing in that file can ever run.
	var rf := FileAccess.open(path, FileAccess.READ)
	var read_back: Variant = rf.get_var(false)
	rf.close()
	_ok(typeof(read_back) != TYPE_OBJECT, "objects never come back as objects")
	if typeof(read_back) == TYPE_DICTIONARY:
		_ok(typeof((read_back as Dictionary).get("payload", null)) != TYPE_OBJECT,
			"nor do objects nested inside it")


func _scripted_object() -> Object:
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nfunc run() -> void:\n\tprint(\"ran\")\n"
	script.reload()
	var obj := RefCounted.new()
	obj.set_script(script)
	return obj


func _refuses_tampering(c: Challenge) -> void:
	var data := c.to_variant()
	var track: Dictionary = (data["track"] as Dictionary).duplicate(true)
	var grid: Array = (track["grid"] as Array).duplicate(true)
	grid[3] = (grid[3] as Dictionary).duplicate()
	grid[3]["cell_x"] = int(grid[3]["cell_x"]) + 5   # move a piece, leave the hash
	track["grid"] = grid
	data["track"] = track
	var path := "%s/tampered.ovc" % TMP
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	_refuses(path, "a challenge whose track no longer matches its fingerprint")


func _refuses_broken_ghosts(c: Challenge) -> void:
	var infinite: Callable = func(pos: PackedVector3Array) -> PackedVector3Array:
		pos[10] = Vector3(INF, 0.0, 0.0)
		return pos
	_refuses(_with_ghost(c, infinite, "infinite"), "a ghost that runs off to infinity")

	var nan_pos: Callable = func(pos: PackedVector3Array) -> PackedVector3Array:
		pos[10] = Vector3(NAN, NAN, NAN)
		return pos
	_refuses(_with_ghost(c, nan_pos, "nan"), "a ghost full of NaNs")

	var stub: Callable = func(pos: PackedVector3Array) -> PackedVector3Array:
		return pos.slice(0, 1)
	_refuses(_with_ghost(c, stub, "stub"), "a ghost with no lap in it")


## Rewrite the sample's ghost positions with `mutate` and save it under `tag`.
func _with_ghost(c: Challenge, mutate: Callable, tag: String) -> String:
	var data := c.to_variant()
	var ghost: Dictionary = (data["ghost"] as Dictionary).duplicate(true)
	var pos: PackedVector3Array = (ghost["positions"] as Array)[0]
	ghost["positions"] = [mutate.call(pos.duplicate())]
	data["ghost"] = ghost
	var path := "%s/ghost_%s.ovc" % [TMP, tag]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	return path


func _refuses_unknown_pieces(c: Challenge) -> void:
	var data := c.to_variant()
	var track: Dictionary = (data["track"] as Dictionary).duplicate(true)
	var grid: Array = (track["grid"] as Array).duplicate(true)
	grid[2] = (grid[2] as Dictionary).duplicate()
	grid[2]["def_id"] = "teleporter"
	track["grid"] = grid
	data["track"] = track
	data["track_hash"] = Challenge.hash_track(track)   # honestly re-fingerprinted
	var path := "%s/unknown_piece.ovc" % TMP
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	var why := Challenge.file_error(path)
	_ok(why.contains("doesn't have"), "a track piece this build lacks is refused by name")


## Text from a stranger's file ends up in a Label. Newlines would let one line
## become five and shove the panel around, so they never survive the door.
func _cleans_hostile_text(c: Challenge) -> void:
	var data := c.to_variant()
	var meta: Dictionary = (data["challenge"] as Dictionary).duplicate(true)
	meta["author"] = "Ana\n\n\n\nBEST DRIVER EVER"
	meta["note"] = "x".repeat(500)
	data["challenge"] = meta
	var path := "%s/hostile_text.ovc" % TMP
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	var back := Challenge.load_from(path)
	_ok(back != null, "a challenge with awkward text still loads")
	if back == null:
		return
	_ok(not back.author.contains("\n"), "newlines are stripped from the author")
	_ok(back.author.length() <= Challenge.MAX_NAME, "the author is cut to length")
	_ok(back.note.length() <= Challenge.MAX_NOTE, "the note is cut to length")


## The fingerprint has to be taken over a shape that survives being saved and
## loaded, or a ghost would stop matching its own track the first time the track
## went through the serializer.
func _fingerprint_survives_the_serializer(c: Challenge) -> void:
	var lib: TileLibrary = GameState.library
	var loaded := TrackSerializer.from_dict(c.track, lib)
	var prev: Terrain = GameState.current_terrain
	GameState.current_terrain = loaded.get("terrain", null)
	var again := TrackSerializer.to_dict(loaded["grid"], lib, String(c.track.get("name", "")), "")
	GameState.current_terrain = prev
	_ok(Challenge.hash_track(again) == c.track_hash, "a round trip through the serializer keeps the fingerprint")
	_ok(c.fits_grid(loaded["grid"], lib, String(c.track.get("name", "")), loaded.get("terrain", null)),
		"the ghost still fits the loaded track")


## Installing puts the track in the library; installing the same file again finds
## the track already there rather than making a second copy.
##
## This one writes into the player's real library, so it is careful about what it
## is allowed to remove. If the example is ALREADY installed — someone was playing
## it — the install reuses their copy, and deleting "what the test installed" would
## delete a track they own. So the test only cleans up a file it can prove it
## created, and skips the rest rather than touching anything else.
func _installs_and_reuses(_c: Challenge) -> void:
	var before := {}
	for entry in TrackSerializer.list_tracks():
		before[String(entry.get("path", ""))] = true

	var first := Challenge.install(SAMPLE)
	if first.has("error"):
		_ok(false, "installing the example challenge: " + String(first["error"]))
		return
	var track_path := String(first["track_path"])
	var track_name := String(first["track_name"])
	var ours: bool = not before.has(track_path)
	_ok(FileAccess.file_exists(track_path), "the track is in the library")
	_ok(Challenge.has_for(track_name), "the challenge is filed against it")
	if ours:
		_ok(not first.get("reused", true), "the first install adds the track")
	else:
		print("  (the example is already installed here; leaving it alone)")

	var count := TrackSerializer.list_tracks().size()
	var second := Challenge.install(SAMPLE)
	_ok(second.get("reused", false), "installing it again reuses the track")
	_ok(TrackSerializer.list_tracks().size() == count, "and adds no duplicate")

	if not ours:
		return
	# Put the library back exactly as it was found.
	Challenge.remove_for(track_name)
	TrackSerializer.delete_track(track_path)
	_ok(not FileAccess.file_exists(track_path), "the test cleaned up after itself")


# --- Harness -----------------------------------------------------------------

func _refuses(path: String, what: String) -> void:
	var why := Challenge.file_error(path)
	_ok(why != "", "refuses %s" % what)
	_ok(Challenge.load_from(path) == null, "  ...and loads nothing from %s" % what)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  ", what)


func _finish() -> void:
	_wipe(TMP)
	print("challenge: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [dir_path, file])
	DirAccess.remove_absolute(dir_path)
