class_name ImportFlow
extends RefCounted
## Taking in a file someone sent you — a track, or a challenge with a track inside
## it. Shared by the two doors that lead here: **Challenge** on the main menu, for
## an invitation to race, and **Import…** on track select, for adding to your
## library.
##
## Both doors accept both kinds of file. Someone was sent *a file*; they do not
## necessarily know which kind it is, and a button that refuses a perfectly good
## track because it wanted a challenge is a trap. The file says what it is, and
## whichever door it comes through, the right thing happens and the player is told
## what it was.


## Open the file picker over `host`. `on_file` is called with the chosen path.
static func open_dialog(host: Node, title: String, on_file: Callable) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# FILESYSTEM, not RESOURCES: the whole point is a file from outside the game,
	# which will be wherever downloads land.
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray([
		"*.%s, *.json ; Challenges and tracks" % Challenge.EXT,
		"*.%s ; Challenge files" % Challenge.EXT,
		"*.json ; Track files",
	])
	dlg.title = title
	dlg.use_native_dialog = true
	dlg.file_selected.connect(on_file)
	dlg.close_requested.connect(dlg.queue_free)
	dlg.file_selected.connect(func(_p: String) -> void: dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


## Take the file in. Returns one of:
##   { ok: false, error: String }
##   { ok: true, kind: "challenge", challenge, track_name, track_path, reused }
##   { ok: true, kind: "track", track_name, track_path }
static func take(path: String) -> Dictionary:
	if path.get_extension().to_lower() == Challenge.EXT:
		var result := Challenge.install(path)
		if result.has("error"):
			return {"ok": false, "error": String(result["error"])}
		result["ok"] = true
		result["kind"] = "challenge"
		return result

	var why := TrackSerializer.file_error(path)
	if why != "":
		return {"ok": false, "error": why}
	var dest := TrackSerializer.import_track(path, GameState.library)
	if dest == "":
		return {"ok": false, "error": "That track could not be added to your library."}
	return {"ok": true, "kind": "track", "track_path": dest,
		"track_name": _name_in(dest)}


## What to tell the player about what just came in, as the body of a panel.
static func describe(result: Dictionary) -> String:
	if String(result.get("kind", "")) != "challenge":
		return "%s is in your track list." % result.get("track_name", "That track")
	var c: Challenge = result["challenge"]
	var lines: Array[String] = []
	lines.append("%s's challenge on %s" % [
		c.author if c.author != "" else "Someone", result.get("track_name", c.track_name())])
	if c.lap_time > 0.0:
		var in_a: String = ", in a %s" % c.car if c.car != "" else ""
		lines.append("Time to beat: %s%s" % [LapTimer.format(c.lap_time), in_a])
	if c.note != "":
		lines.append("\"%s\"" % c.note)
	lines.append("Track already in your library." if result.get("reused", false)
		else "The track came with it and is now in your library.")
	return "\n\n".join(lines)


## Make `track_path` the track the game is holding, the way picking it on track
## select would, and arm whatever challenge is filed against it.
static func load_into_gamestate(track_path: String) -> bool:
	var loaded := TrackSerializer.load_track(track_path, GameState.library)
	if loaded.is_empty():
		return false
	GameState.current_grid = loaded["grid"]
	GameState.current_track_name = loaded["name"]
	GameState.current_terrain = loaded.get("terrain", null)
	GameState.active_challenge = Challenge.active_for(loaded["name"])
	return true


## Set the race up the way an accepted challenge wants it: their lap count, and
## nobody else on the track.
##
## A challenge is a time trial against one ghost. Opponents turn it into a race
## with a ghost in it — they block the line, they knock you off it, and the run
## you are trying to compare stops being comparable. The player can put them back
## from the track-select screen if they want a crowd.
static func arm_race(c: Challenge) -> void:
	if c == null:
		return
	GameState.race_ai_count = 0
	GameState.race_laps = maxi(1, c.laps)
	GameState.race_reversed = c.reversed
	GameState.race_challenge_ghost = true


static func _name_in(track_path: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(track_path))
	if typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("name"):
		return String(data["name"])
	return track_path.get_file().get_basename()
