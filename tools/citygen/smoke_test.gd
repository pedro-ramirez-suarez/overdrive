extends Node3D
## Loads a track and builds the drivable world out of it, the way the race does --
## the check the JSON cannot make: that the terrain mesh, the tiles and every prop
## actually instance without erroring, and how long it takes.
##
##   godot --headless --path . tools/citygen/smoke_test.tscn -- tracks/emerald_sound.json

func _ready() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var lib := TileLibrary.new()
	lib.build()
	var data: Dictionary = TrackSerializer.load_track(path, lib)
	if data.is_empty():
		print("FAILED to load ", path)
		get_tree().quit(1)
		return
	GameState.current_grid = data["grid"]
	GameState.current_terrain = data["terrain"]
	GameState.library = lib
	var t0 := Time.get_ticks_msec()
	TrackWorld.populate(self, data["grid"], lib)
	var built := Time.get_ticks_msec() - t0
	var nodes := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for child in n.get_children():
			stack.append(child)
	print("%s: world built in %d ms, %d nodes" % [data["name"], built, nodes])
	get_tree().quit()
