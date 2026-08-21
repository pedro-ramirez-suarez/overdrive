class_name Replay
extends RefCounted
## Recorded race data (SPEC.md §M5): per-car transform snapshots, one per physics
## frame. Transform snapshots (not inputs) are stored so playback is deterministic
## regardless of physics. Serialized to disk as a Godot binary Variant buffer.

const MAGIC := "OVRPLAY1"
const SAVE_DIR := "user://replays"

var fps: float = 60.0
## Per car: { "name": String, "is_player": bool, "color": Color }.
var car_infos: Array = []
## positions[car] = PackedVector3Array of origins, one per frame.
var positions: Array = []
## rotations[car] = Array of Quaternion, one per frame.
var rotations: Array = []


func init_cars(infos: Array) -> void:
	car_infos = infos
	positions = []
	rotations = []
	for i in range(infos.size()):
		positions.append(PackedVector3Array())
		rotations.append([])


func capture(index: int, xform: Transform3D) -> void:
	positions[index].append(xform.origin)
	rotations[index].append(xform.basis.get_rotation_quaternion())


func car_count() -> int:
	return car_infos.size()


func frame_count() -> int:
	return positions[0].size() if positions.size() > 0 else 0


func duration() -> float:
	return frame_count() / fps if fps > 0.0 else 0.0


## Interpolated transform for a car at fractional frame time `t`.
func sample(index: int, t: float) -> Transform3D:
	var pos: PackedVector3Array = positions[index]
	var rot: Array = rotations[index]
	var n: int = pos.size()
	if n == 0:
		return Transform3D.IDENTITY
	var tt: float = clampf(t, 0.0, float(n - 1))
	var f: int = int(floor(tt))
	var f2: int = mini(f + 1, n - 1)
	var frac: float = tt - f
	var p: Vector3 = pos[f].lerp(pos[f2], frac)
	var q: Quaternion = (rot[f] as Quaternion).slerp(rot[f2] as Quaternion, frac)
	return Transform3D(Basis(q), p)


## A new one-car Replay holding just `index`'s stream — the basis of the "beat
## your best" ghost, which only ever needs the player's own car.
func extract_car(index: int) -> Replay:
	var r := Replay.new()
	r.fps = fps
	if index < 0 or index >= car_infos.size():
		return r
	r.car_infos = [car_infos[index]]
	r.positions = [positions[index]]
	r.rotations = [rotations[index]]
	return r


# --- Persistence ------------------------------------------------------------

## The payload `save_to` writes, as a plain dictionary of built-in types. Split out
## from the file write so a replay can be carried inside another file — a challenge
## embeds a ghost this way (see Challenge.gd) without going through a temp file.
func to_variant() -> Dictionary:
	return {
		"magic": MAGIC,
		"fps": fps,
		"cars": car_infos,
		"positions": positions,
		"rotations": rotations,
	}


## Rebuild from `to_variant` output, or null if it is not that. Shape only: this is
## the trusting half, used on our own files. Anything arriving from outside goes
## through Challenge's checks first.
static func from_variant(data: Variant) -> Replay:
	if typeof(data) != TYPE_DICTIONARY or (data as Dictionary).get("magic", "") != MAGIC:
		return null
	var r := Replay.new()
	r.fps = data.get("fps", 60.0)
	r.car_infos = data.get("cars", [])
	r.positions = data.get("positions", [])
	r.rotations = data.get("rotations", [])
	return r


func save_to(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(to_variant())
	f.close()
	return true


static func load_from(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	# allow_objects stays false: a replay is numbers, and a file that asks to
	# instantiate something is not one.
	var data: Variant = f.get_var(false)
	f.close()
	return from_variant(data)


## A default timestamped save path under the replay directory.
static func default_save_path() -> String:
	return "%s/replay_%d.rpl" % [SAVE_DIR, int(Time.get_unix_time_from_system())]


## Path of the most recent saved replay, or "" if none.
static func latest_saved_path() -> String:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return ""
	var latest := ""
	for file in dir.get_files():
		if file.ends_with(".rpl") and file > latest:
			latest = file
	return "%s/%s" % [SAVE_DIR, latest] if latest != "" else ""
