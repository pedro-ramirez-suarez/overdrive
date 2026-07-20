class_name Records
extends RefCounted
## Per-track best times and the "beat your best" ghost (improvements batch).
##
## For each track we keep, under user://records/, a small JSON file with the best
## lap and best full-race times, plus a binary Replay of the run that set the best
## race time. The race scene loads that ghost and drives a translucent car with it,
## so you are always racing your previous best; the track-select screen reads the
## times to show a best time and a medal.
##
## Keyed by a slug of the track NAME (not its file path): a track keeps its record
## even if re-saved to a different filename, and bundled/imported tracks all get
## records the same way.

const DIR := "user://records"

## Reference speeds (m/s of average lap pace) that define the medal thresholds. A
## par time is the route length driven at REF_SILVER; gold is a chunk quicker,
## bronze a fair bit slower — see `medal`.
const REF_GOLD := 26.0
const REF_SILVER := 20.0
const REF_BRONZE := 14.0

enum Medal { NONE, BRONZE, SILVER, GOLD }
const MEDAL_GLYPHS: Array[String] = ["", "🥉", "🥈", "🥇"]
const MEDAL_NAMES: Array[String] = ["", "Bronze", "Silver", "Gold"]


static func _slug(track_name: String) -> String:
	var s := track_name.strip_edges().to_lower()
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	if out.replace("_", "") == "":
		out = "track"
	return out


static func _record_path(track_name: String) -> String:
	return "%s/%s.json" % [DIR, _slug(track_name)]


static func ghost_path(track_name: String) -> String:
	return "%s/%s.ghost" % [DIR, _slug(track_name)]


## { best_lap: float, best_race: float }, with -1 for a time never set. Never
## returns null, so callers can read the fields unconditionally.
static func load_record(track_name: String) -> Dictionary:
	var path := _record_path(track_name)
	var out := {"best_lap": -1.0, "best_race": -1.0}
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY:
		out["best_lap"] = float(data.get("best_lap", -1.0))
		out["best_race"] = float(data.get("best_race", -1.0))
	return out


## Fold a finished run into the stored record. Returns which times are new as
## { lap: bool, race: bool } so the results screen can announce them. When the race
## time improves, `ghost` (a single-car Replay of the run) is saved as the new
## ghost; pass null to leave any existing ghost untouched.
static func submit(track_name: String, lap_time: float, race_time: float, ghost: Replay = null) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIR)
	var rec := load_record(track_name)
	var beat := {"lap": false, "race": false}

	if lap_time > 0.0 and (rec["best_lap"] < 0.0 or lap_time < rec["best_lap"]):
		rec["best_lap"] = lap_time
		beat["lap"] = true
	if race_time > 0.0 and (rec["best_race"] < 0.0 or race_time < rec["best_race"]):
		rec["best_race"] = race_time
		beat["race"] = true
		if ghost != null:
			ghost.save_to(ghost_path(track_name))

	if beat["lap"] or beat["race"]:
		var f := FileAccess.open(_record_path(track_name), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rec, "  "))
			f.close()
	return beat


## The best-race ghost for a track, or null if none has been recorded yet.
static func load_ghost(track_name: String) -> Replay:
	return Replay.load_from(ghost_path(track_name))


# --- Medals -----------------------------------------------------------------

## Par (target) time for a route of `route_len` meters: the length driven at the
## silver reference pace. Used as the yardstick the results screen shows.
static func par_time(route_len: float) -> float:
	return route_len / REF_SILVER if REF_SILVER > 0.0 else 0.0


## Medal earned for finishing `route_len` meters in `time` seconds. Scaled by the
## route length so a long track isn't unfairly hard to medal on.
static func medal(time: float, route_len: float) -> int:
	if time <= 0.0 or route_len <= 0.0:
		return Medal.NONE
	if time <= route_len / REF_GOLD:
		return Medal.GOLD
	if time <= route_len / REF_SILVER:
		return Medal.SILVER
	if time <= route_len / REF_BRONZE:
		return Medal.BRONZE
	return Medal.NONE
