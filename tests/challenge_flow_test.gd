extends Node
## The whole way through, as a player would go: import a challenge for a track
## that is not in the library, see it on the track-select screen, and start a race
## that puts the stranger's ghost on the road rather than your own best lap.
##
## Run with:
##   godot --headless --path . tests/challenge_flow_test.tscn
##
## It installs into the real track library, because that is the thing being tested.
## It removes only what it put there: if the example is already installed, that is
## someone playing it, and the test leaves their track alone.

const SAMPLE := "res://examples/crosswind_circuit.ovc"

var _passed := 0
var _failed := 0
var _track_path := ""
var _track_name := ""
## True when this test installed the example itself, and may therefore remove it.
var _ours := false


func _ready() -> void:
	await get_tree().process_frame   # let the autoloads build the tile library
	_run()


func _run() -> void:
	# This writes into the player's real library, so it keeps track of what it put
	# there. If the example is already installed — someone was playing it — the
	# install reuses their copy, every check below still means something, and the
	# cleanup at the end leaves their track exactly where it was.
	var before := {}
	for entry in TrackSerializer.list_tracks():
		before[String(entry.get("path", ""))] = true

	# 1. It arrives as a file, for a track this game may never have seen.
	var result := Challenge.install(SAMPLE)
	if result.has("error"):
		_ok(false, "install: " + String(result["error"]))
		_finish()
		return
	var c: Challenge = result["challenge"]
	_track_path = String(result["track_path"])
	_track_name = String(result["track_name"])
	_ours = not before.has(_track_path)
	_ok(_track_name.begins_with("Crosswind Circuit"), "the track keeps its name")
	if _ours:
		_ok(TrackSerializer.list_tracks().size() == before.size() + 1, "the track joins the library")
	else:
		print("  (the example is already installed here; leaving it alone)")

	# 2. Track select shows it, and picking it arms the challenge.
	var select: Control = load("res://scenes/ui/TrackSelect.tscn").instantiate()
	add_child(select)
	await get_tree().process_frame
	var index := -1
	var tracks: Array = select.get("_tracks")
	for i in range(tracks.size()):
		if String(tracks[i].get("path", "")) == _track_path:
			index = i
	_ok(index >= 0, "the imported track is in the list")
	if index >= 0:
		select.call("_on_selected", index)
		var info: Label = select.get("_info")
		_ok(info.text.contains("Challenge"), "the challenge is named on screen")
		_ok(info.text.contains("Pace Car"), "and says who set it")
		_ok(not info.text.contains("different version"), "and is not disowned by its own track")
		_ok(GameState.active_challenge != null, "the race is handed the challenge")
		var ghost_row: Control = select.get("_ghost_row")
		_ok(ghost_row != null and ghost_row.visible, "the ghost toggle appears")
	select.queue_free()
	await get_tree().process_frame

	# 3. Racing it drives the imported ghost, not the local best.
	GameState.race_laps = 1
	GameState.race_ai_count = 0
	GameState.race_reversed = false
	GameState.race_challenge_ghost = true
	GameState.active_challenge = c
	var race: Node = load("res://scenes/race/Race.tscn").instantiate()
	add_child(race)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bool(race.get("_ghost_is_challenge")), "the race picks the challenge ghost")
	var ghost_car: Node = race.get("_ghost_car")
	_ok(ghost_car != null, "the ghost car is on the track")
	var ghost_replay: Replay = race.get("_ghost_replay")
	_ok(ghost_replay != null and ghost_replay.frame_count() == c.ghost.frame_count(),
		"and it is driving the lap out of the file")
	race.queue_free()
	await get_tree().process_frame

	# 4. The main menu's own door: accept, then straight to picking a car, with the
	#    challenge's car under the cursor but nothing locked.
	GameState.challenge_race_pending = false
	GameState.selected_car = GameState.roster[0]
	var taken := ImportFlow.take(SAMPLE)
	_ok(taken.get("ok", false), "the main-menu door takes the same file")
	_ok(String(taken.get("kind", "")) == "challenge", "and knows it is a challenge")
	_ok(ImportFlow.describe(taken).contains("in a Marlin GT"), "the panel says which car it was set in")
	_ok(ImportFlow.load_into_gamestate(String(taken.get("track_path", ""))),
		"accepting loads the track")
	_ok(GameState.active_challenge != null, "and arms the challenge")

	# Accepting sets the race up as a time trial: their laps, and nobody else on
	# the track to get in the way of the comparison.
	GameState.race_ai_count = 3
	GameState.race_laps = 7
	ImportFlow.arm_race(GameState.active_challenge)
	_ok(GameState.race_ai_count == 0, "accepting clears the opponents")
	_ok(GameState.race_laps == GameState.active_challenge.laps, "and takes the challenge's lap count")
	_ok(GameState.race_challenge_ghost, "and arms the challenge ghost")

	GameState.challenge_race_pending = true
	var cars: Control = load("res://scenes/ui/CarSelect.tscn").instantiate()
	add_child(cars)
	await get_tree().process_frame
	_ok(GameState.selected_car != null and GameState.selected_car.display_name == "Marlin GT",
		"car select starts on the car the challenge was set in")
	_ok(GameState.roster.size() > 1, "and the rest of the roster is still there to pick from")
	cars.queue_free()
	await get_tree().process_frame
	GameState.challenge_race_pending = false

	# A plain track through the same door is imported, not refused.
	var track_result := ImportFlow.take("res://tracks/sample_oval.json")
	_ok(track_result.get("ok", false) and String(track_result.get("kind", "")) == "track",
		"a track file through the challenge door is imported anyway")
	if track_result.get("ok", false):
		TrackSerializer.delete_track(String(track_result["track_path"]))

	# 5. Switching the toggle off goes back to your own best (here: no ghost at all,
	#    since this track has never been raced on this machine).
	GameState.race_challenge_ghost = false
	var race2: Node = load("res://scenes/race/Race.tscn").instantiate()
	add_child(race2)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not bool(race2.get("_ghost_is_challenge")), "turning the toggle off drops the challenge ghost")
	race2.queue_free()
	await get_tree().process_frame

	_finish()


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  ", what)


func _finish() -> void:
	GameState.active_challenge = null
	GameState.race_challenge_ghost = true
	if _ours:
		Challenge.remove_for(_track_name)
		TrackSerializer.delete_track(_track_path)
		_ok(not FileAccess.file_exists(_track_path), "the test cleaned up after itself")
	print("challenge flow: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
