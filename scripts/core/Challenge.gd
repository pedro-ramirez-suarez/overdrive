class_name Challenge
extends RefCounted
## A challenge: one self-contained file holding a track, a ghost lap driven on it,
## and the time to beat. Send it to someone and they can race your line without
## having the track — importing it installs the track and puts your ghost on the
## road beside them.
##
## The file is a Godot binary Variant (`.ovc`), the same mechanism `Replay` uses,
## because the ghost is a stream of transforms that JSON would bloat.
##
## ## Reading a file someone sent you
##
## A challenge arrives from outside, so it is treated as hostile input:
##
## - It is read with `get_var(false)`. Allowing objects would let a file name a
##   class to instantiate or a script to attach, which is the one way a data file
##   could ever run code here. It never gets that chance.
## - Nothing in the file is ever used as a path. Tile meshes come from the local
##   `TileLibrary`, looked up by id; an id that is not in the library is a reason
##   to reject the file, not something to load.
## - Every field is type-checked, every number range-checked, every array
##   length-capped, and every string stripped of control characters and cut to
##   length before it can reach a Label.
## - The file is size-capped before it is read at all.
##
## `file_error` returns a sentence explaining any refusal, so the UI can say what
## was wrong instead of failing mutely. What it deliberately does NOT do is verify
## that the time was honestly driven: a challenge is a file, anyone can write one,
## and this is a local single-player game passing runs between people who know
## each other. There is no leaderboard here to protect.

const MAGIC := "OVRCHAL1"
const VERSION := 1
const DIR := "user://challenges"
const EXT := "ovc"

# --- Limits ------------------------------------------------------------------
# Every one of these is a refusal, not a clamp: a file outside them is not a
# challenge this game made, and guessing what it meant is how you end up parsing
# something you did not intend to.
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_TILES := 20000
const MAX_PROPS := 20000
const MAX_CELL := 4096            ## grid coordinates live well inside this
const MAX_FRAMES := 216000        ## an hour at 60 fps
const MAX_TERRAIN_VALUES := 400000  ## flat [i, j, level, ...] arrays
const MAX_NOTE := 140
const MAX_NAME := 48

var track: Dictionary = {}        ## exactly what TrackSerializer.to_dict produces
var ghost: Replay = null          ## one car
var track_hash: String = ""
var author: String = ""
var car: String = ""
var lap_time: float = -1.0
var race_time: float = -1.0
var laps: int = 1
var reversed: bool = false
var created: int = 0
var note: String = ""


func track_name() -> String:
	return String(track.get("name", "Track"))


## The challenge in one line, for the track list: `Ana — 1:47.05`.
func summary() -> String:
	var who: String = author if author != "" else "Someone"
	return "%s — %s" % [who, LapTimer.format(lap_time)] if lap_time > 0.0 else who


static func from_run(track_data: Dictionary, run_ghost: Replay, meta: Dictionary) -> Challenge:
	var c := Challenge.new()
	c.track = track_data
	c.ghost = run_ghost
	c.track_hash = hash_track(track_data)
	c.author = _clean(String(meta.get("author", "")), MAX_NAME)
	c.car = _clean(String(meta.get("car", "")), MAX_NAME)
	c.lap_time = float(meta.get("lap_time", -1.0))
	c.race_time = float(meta.get("race_time", -1.0))
	c.laps = int(meta.get("laps", 1))
	c.reversed = bool(meta.get("reversed", false))
	c.created = int(meta.get("created", 0))
	c.note = _clean(String(meta.get("note", "")), MAX_NOTE)
	return c


# --- Track identity ----------------------------------------------------------

## A fingerprint of the track the ghost was driven on. A ghost is world-space
## transforms, so it only means anything on the exact layout it was recorded over:
## move one corner and the recorded car drives through the scenery. Comparing this
## against the local track is what stops a nonsense ghost being shown.
## Everything hashed is SORTED, and nothing that only reflects how a dictionary
## happened to iterate is included. A track saved, loaded and saved again has to
## fingerprint the same, or a ghost would stop matching its own track the first
## time the file went through the serializer.
static func hash_track(data: Dictionary) -> String:
	var parts: Array[String] = []
	var cells: Array = []
	for c in data.get("grid", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		cells.append("%d,%d,%s,%d,%d" % [
			int(c.get("cell_x", 0)), int(c.get("cell_y", 0)), String(c.get("def_id", "")),
			int(c.get("rotation", 0)), int(c.get("elevation_level", 0))])
	cells.sort()
	parts.append("|".join(cells))
	var t: Variant = data.get("terrain", null)
	if typeof(t) == TYPE_DICTIONARY:
		parts.append("t:%d:%d" % [int(t.get("type", 0)), int(t.get("seed", 0))])
		parts.append("e:" + _triples(t.get("edits", [])))
		parts.append("l:" + _triples(t.get("lakes", [])))
	return "\n".join(parts).sha256_text().substr(0, 32)


## A flat [i, j, level, ...] array as sorted triples, so the same sculpting
## fingerprints the same however it was stored.
static func _triples(a: Variant) -> String:
	if typeof(a) != TYPE_ARRAY:
		return ""
	var src: Array = a
	var out: Array = []
	var i := 0
	while i + 2 < src.size():
		out.append("%d/%d/%d" % [int(src[i]), int(src[i + 1]), int(src[i + 2])])
		i += 3
	out.sort()
	return ",".join(out)


## Does this challenge's ghost belong on `local_track` (a TrackSerializer dict)?
func fits(local_track: Dictionary) -> bool:
	return track_hash != "" and track_hash == hash_track(local_track)


## The same, for a track file on disk.
func fits_track_file(track_path: String) -> bool:
	return fits(_track_dict(track_path))


## The same, for the track as the game currently holds it in memory. Serialized
## through TrackSerializer so the fingerprint is taken over exactly the shape a
## saved track has — otherwise a track would stop matching itself on the way to
## disk and back. The terrain is passed in rather than read off GameState: the
## ground is half the fingerprint, and it has to be this track's ground.
func fits_grid(grid: TrackGrid, lib: TileLibrary, name: String, terrain: Terrain) -> bool:
	if grid == null or lib == null:
		return false
	return fits(TrackSerializer.to_dict(grid, lib, name, "", terrain))


# --- Persistence -------------------------------------------------------------

func to_variant() -> Dictionary:
	return {
		"magic": MAGIC,
		"version": VERSION,
		"track": track,
		"ghost": ghost.to_variant() if ghost != null else {},
		"track_hash": track_hash,
		"challenge": {
			"author": author, "car": car,
			"lap_time": lap_time, "race_time": race_time,
			"laps": laps, "reversed": reversed,
			"created": created, "note": note,
		},
	}


func save_to(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(to_variant())
	f.close()
	return true


## The challenge in `path`, or null if it is not a valid one. Ask `file_error`
## first if you want to tell the player why.
static func load_from(path: String) -> Challenge:
	var parsed := _parse(path)
	return parsed.get("challenge", null) as Challenge


## Why the file at `path` is not a challenge this game will accept, or "" if it is.
## Every refusal is a sentence a player can act on — the file they were sent is the
## only thing they have, and "invalid file" tells them nothing about what to do.
static func file_error(path: String) -> String:
	return String(_parse(path).get("error", ""))


static func _parse(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File not found."}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "That file could not be opened."}
	var size := f.get_length()
	if size == 0:
		f.close()
		return {"error": "That file is empty."}
	if size > MAX_FILE_BYTES:
		f.close()
		return {"error": "That file is far too big to be a challenge (%.1f MB)." % (size / 1048576.0)}
	# false: no objects. A challenge is numbers and strings; a file asking to build
	# an object is not one, and this is the line where that request is refused.
	var data: Variant = f.get_var(false)
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "That file isn't an OVERDRIVE challenge."}
	var d: Dictionary = data
	if String(d.get("magic", "")) != MAGIC:
		return {"error": "That file isn't an OVERDRIVE challenge (wrong signature)."}
	if int(d.get("version", 0)) > VERSION:
		return {"error": "That challenge was made by a newer version of the game."}

	var track_data: Variant = d.get("track", null)
	if typeof(track_data) != TYPE_DICTIONARY:
		return {"error": "That challenge has no track in it."}
	var track_bad := _track_error(track_data)
	if track_bad != "":
		return {"error": track_bad}

	var c := Challenge.new()
	c.track = track_data
	c.track_hash = _clean(String(d.get("track_hash", "")), 64)
	if c.track_hash != hash_track(track_data):
		return {"error": "That challenge file is damaged: its track doesn't match its own fingerprint."}

	var meta: Variant = d.get("challenge", {})
	if typeof(meta) != TYPE_DICTIONARY:
		return {"error": "That challenge file is damaged: its details are missing."}
	var m: Dictionary = meta
	c.author = _clean(String(m.get("author", "")), MAX_NAME)
	c.car = _clean(String(m.get("car", "")), MAX_NAME)
	c.lap_time = _finite(m.get("lap_time", -1.0))
	c.race_time = _finite(m.get("race_time", -1.0))
	c.laps = clampi(int(m.get("laps", 1)), 1, 99)
	c.reversed = bool(m.get("reversed", false))
	c.created = int(m.get("created", 0))
	c.note = _clean(String(m.get("note", "")), MAX_NOTE)

	var ghost_data: Variant = d.get("ghost", {})
	if typeof(ghost_data) != TYPE_DICTIONARY:
		return {"error": "That challenge file is damaged: its ghost lap is missing."}
	var g := Replay.from_variant(ghost_data)
	if g == null:
		return {"error": "That challenge file is damaged: its ghost lap is missing."}
	var ghost_bad := _ghost_error(g)
	if ghost_bad != "":
		return {"error": ghost_bad}
	c.ghost = g
	return {"challenge": c}


# --- Validation --------------------------------------------------------------

## The track half, checked hard. TrackSerializer.validation_error covers the shape
## a local file has to have; this adds what only matters for a file from outside —
## that every tile is one this build actually has, and that nothing is big enough
## or far enough out to hurt.
static func _track_error(data: Dictionary) -> String:
	var shape := TrackSerializer.validation_error(data)
	if shape != "":
		return shape
	var grid: Array = data.get("grid", [])
	if grid.is_empty():
		return "That challenge's track is empty."
	if grid.size() > MAX_TILES:
		return "That challenge's track is too big (%d tiles)." % grid.size()
	var known: Dictionary = GameState.library.definitions if GameState.library != null else {}
	for c in grid:
		var cell := Vector2i(int(c.get("cell_x", 0)), int(c.get("cell_y", 0)))
		if absi(cell.x) > MAX_CELL or absi(cell.y) > MAX_CELL:
			return "That challenge's track has tiles outside the buildable area."
		var def_id := StringName(String(c.get("def_id", "")))
		if not known.is_empty() and not known.has(def_id):
			return "That challenge uses a track piece this version doesn't have (%s)." % def_id
		var rot := int(c.get("rotation", 0))
		if rot < 0 or rot > 3:
			return "That challenge's track is damaged: a piece has an impossible rotation."
		var lvl := int(c.get("elevation_level", 0))
		if lvl < 0 or lvl > Constants.MAX_TERRAIN_LEVEL:
			return "That challenge's track is damaged: a piece sits outside the height range."

	var props: Variant = data.get("props", [])
	if typeof(props) != TYPE_ARRAY:
		return "That challenge's track is damaged: malformed scenery."
	if (props as Array).size() > MAX_PROPS:
		return "That challenge's track has too much scenery."
	for p in (props as Array):
		if typeof(p) != TYPE_DICTIONARY:
			return "That challenge's track is damaged: malformed scenery."
		var kind := int(p.get("kind", 0))
		if kind < 0 or kind >= PropGeo.KIND_IDS.size():
			return "That challenge's track is damaged: unknown scenery."
		var variant := int(p.get("variant", 0))
		if variant < 0 or variant >= (PropGeo.VARIANT_NAMES[kind] as Array).size():
			return "That challenge's track is damaged: unknown scenery."

	var terrain: Variant = data.get("terrain", null)
	if terrain != null:
		if typeof(terrain) != TYPE_DICTIONARY:
			return "That challenge's track is damaged: malformed terrain."
		var t: Dictionary = terrain
		var type_i := int(t.get("type", 0))
		if type_i < 0 or type_i >= Terrain.TYPE_NAMES.size():
			return "That challenge's track is damaged: unknown terrain type."
		for key in ["edits", "lakes"]:
			var arr: Variant = t.get(key, [])
			if typeof(arr) != TYPE_ARRAY:
				return "That challenge's track is damaged: malformed terrain."
			if (arr as Array).size() > MAX_TERRAIN_VALUES:
				return "That challenge's track has too much sculpted terrain."
			for v in (arr as Array):
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
					return "That challenge's track is damaged: malformed terrain."
	return ""


static func _ghost_error(g: Replay) -> String:
	if g.car_count() != 1:
		return "That challenge's ghost lap is malformed (it should hold one car)."
	if typeof(g.car_infos[0]) != TYPE_DICTIONARY:
		return "That challenge's ghost lap is malformed."
	if g.fps <= 0.0 or g.fps > 480.0 or not is_finite(g.fps):
		return "That challenge's ghost lap has an impossible frame rate."
	if typeof(g.positions[0]) != TYPE_PACKED_VECTOR3_ARRAY or typeof(g.rotations[0]) != TYPE_ARRAY:
		return "That challenge's ghost lap is malformed."
	var pos: PackedVector3Array = g.positions[0]
	var rot: Array = g.rotations[0]
	if pos.size() < 2:
		return "That challenge has no ghost lap recorded."
	if pos.size() > MAX_FRAMES:
		return "That challenge's ghost lap is impossibly long."
	if rot.size() != pos.size():
		return "That challenge's ghost lap is damaged (it stops halfway)."
	# One bad number would put the ghost at infinity and take the camera with it.
	for i in range(pos.size()):
		var p: Vector3 = pos[i]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return "That challenge's ghost lap is damaged (impossible positions)."
		if typeof(rot[i]) != TYPE_QUATERNION:
			return "That challenge's ghost lap is damaged (impossible rotations)."
		var q: Quaternion = rot[i]
		if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
			return "That challenge's ghost lap is damaged (impossible rotations)."
	return ""


## Strings out of a foreign file end up in Labels. Control characters (and the
## newlines that would let one line become five) are stripped, and the result is
## cut to length, so no imported text can rearrange the UI around it.
static func _clean(s: String, limit: int) -> String:
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if c.unicode_at(0) < 32 or c.unicode_at(0) == 127:
			continue
		out += c
		if out.length() >= limit:
			break
	return out.strip_edges()


static func _finite(v: Variant) -> float:
	var f := float(v)
	return f if is_finite(f) else -1.0


# --- The library of installed challenges -------------------------------------

## Challenges are kept one per track, keyed by the same slug `Records` uses, so a
## track and its challenge always find each other by name.
static func slug(track_name: String) -> String:
	var s := track_name.strip_edges().to_lower()
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return out if out.replace("_", "") != "" else "track"


static func path_for(track_name: String) -> String:
	return "%s/%s.%s" % [DIR, slug(track_name), EXT]


## The challenge installed for `track_name`, or null.
static func active_for(track_name: String) -> Challenge:
	return load_from(path_for(track_name))


static func has_for(track_name: String) -> bool:
	return FileAccess.file_exists(path_for(track_name))


## The name to offer for an exported challenge: the track and the time, so a
## folder of them stays readable and two runs never collide.
static func export_filename(track_name: String, lap: float) -> String:
	return "%s_%s.%s" % [slug(track_name),
		LapTimer.format(lap).replace(":", "m").replace(".", "s"), EXT]


## Where the save dialog should open: wherever the player last put one, falling
## back to their documents folder. A file meant to be sent to someone belongs
## somewhere they can find it, not buried in the game's own data.
static func export_dir() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var last := String(cfg.get_value("challenge", "export_dir", ""))
		if last != "" and DirAccess.dir_exists_absolute(last):
			return last
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)


static func remember_export_dir(dir: String) -> void:
	if dir.strip_edges() == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("challenge", "export_dir", dir)
	cfg.save(SETTINGS_PATH)


# --- The name a challenge goes out under -------------------------------------
# Stored in the same settings file the audio and display managers share. There is
# no account and no profile here, so this is simply what the player wants to be
# called on a file they send someone; it is never read from the system.

const SETTINGS_PATH := "user://settings.cfg"


static func saved_author() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return _clean(String(cfg.get_value("challenge", "author", "")), MAX_NAME)
	return ""


static func save_author(name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep whatever audio and display wrote
	cfg.set_value("challenge", "author", _clean(name, MAX_NAME))
	cfg.save(SETTINGS_PATH)


static func remove_for(track_name: String) -> void:
	var p := path_for(track_name)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# --- Importing ---------------------------------------------------------------

## Take in a challenge file: check it, put its track in the library if the player
## does not already have it, and file the challenge against that track.
##
## Returns { error } on refusal, or { challenge, track_name, track_path, reused }
## where `reused` means the track was already here and nothing was copied.
##
## The track is matched by fingerprint, not by name, so importing the same
## challenge twice — or a second challenge on a track you already have — adds no
## duplicate. A DIFFERENT track arriving under a name you already use is renamed
## instead of merged: two tracks sharing a name would share records, and one
## player's lap would silently become the par for the other's track.
static func install(src_path: String) -> Dictionary:
	var parsed := _parse(src_path)
	if parsed.has("error"):
		return {"error": parsed["error"]}
	var c: Challenge = parsed["challenge"]

	var existing := _local_track_with_hash(c.track_hash)
	if existing != "":
		var known_name := _name_of(existing)
		if not c.save_to(path_for(known_name)):
			return {"error": "The challenge could not be saved."}
		return {"challenge": c, "track_name": known_name, "track_path": existing, "reused": true}

	var wanted := c.track_name()
	var final_name := wanted
	for i in range(2, 100):
		if not _name_in_use(final_name):
			break
		final_name = "%s (%d)" % [wanted, i]
	var data: Dictionary = c.track.duplicate(true)
	data["name"] = final_name
	var dest := TrackSerializer.import_dict(data, GameState.library, "Imported track")
	if dest == "":
		return {"error": "That challenge's track could not be added to your library."}
	c.track = data
	c.track_hash = hash_track(data)
	if not c.save_to(path_for(final_name)):
		return {"error": "The challenge could not be saved."}
	return {"challenge": c, "track_name": final_name, "track_path": dest, "reused": false}


## Path of a track already in the library with this fingerprint, or "".
static func _local_track_with_hash(want: String) -> String:
	if want == "":
		return ""
	for entry in TrackSerializer.list_tracks():
		var d := _track_dict(String(entry.get("path", "")))
		if not d.is_empty() and hash_track(d) == want:
			return String(entry["path"])
	return ""


static func _name_in_use(name: String) -> bool:
	for entry in TrackSerializer.list_tracks():
		if String(entry.get("name", "")) == name:
			return true
	return false


static func _name_of(track_path: String) -> String:
	var d := _track_dict(track_path)
	return String(d.get("name", track_path.get_file().get_basename()))


static func _track_dict(track_path: String) -> Dictionary:
	if not FileAccess.file_exists(track_path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(track_path))
	return d if typeof(d) == TYPE_DICTIONARY else {}
