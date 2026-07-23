extends Node
## Global game session state (SPEC.md §M3). Registered as the `GameState`
## autoload. Holds the shared tile library and the track currently being edited,
## so the editor and the test-drive play scene share one in-memory track.

var library: TileLibrary
var current_grid: TrackGrid
var current_track_name: String = "Untitled"
## Terrain the current track drapes over (null = flat ground).
var current_terrain: Terrain = null

# Car roster (M6).
var roster: Array[CarProfile] = []
var selected_car: CarProfile

# Race settings (M4).
var race_laps: int = 3
var race_ai_count: int = 3
## Race the circuit backwards (the "wrong way" round).
var race_reversed: bool = false

# Atmosphere, chosen on the track-select screen — see Atmosphere.gd.
var race_time: Atmosphere.TimeOfDay = Atmosphere.TimeOfDay.NOON
var race_weather: Atmosphere.Weather = Atmosphere.Weather.CLEAR

## Scene to return to when leaving a race or test drive — the screen it was
## launched from, so Esc goes back where you came from rather than always the
## editor. Set by whoever starts the race.
var return_scene: String = "res://scenes/ui/TrackSelect.tscn"

# Most recent recorded race, for the replay scene (M5).
var last_replay: Replay = null


func _ready() -> void:
	library = TileLibrary.new()
	library.build()
	current_grid = TrackGrid.new(library.definitions)

	roster = CarRoster.build()
	selected_car = roster[0]


## Index of the currently selected car within the roster.
func selected_car_index() -> int:
	return maxi(0, roster.find(selected_car))


## The roster profile whose model matches `path`, or null. Lets a replay reuse a
## car's full profile — including its auto-fit sizing — rather than a reconstructed
## stub, so fit-sized models (the hero cars) render at the right scale even in older
## recordings that never stored the fit fields.
func profile_for_model(path: String) -> CarProfile:
	if path == "":
		return null
	for p in roster:
		if p.model_scene != null and p.model_scene.resource_path == path:
			return p
	return null
