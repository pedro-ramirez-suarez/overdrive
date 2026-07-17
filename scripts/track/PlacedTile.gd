class_name PlacedTile
extends RefCounted
## A tile instance placed on the grid (SPEC.md §M3): which definition, its 0-3
## quarter-turn rotation, and its elevation level.

var def_id: StringName
var rotation: int = 0  ## 0..3, quarter turns clockwise (viewed from above).
var elevation_level: int = 0


func _init(p_def_id: StringName = &"", p_rotation: int = 0, p_elevation_level: int = 0) -> void:
	def_id = p_def_id
	rotation = p_rotation
	elevation_level = p_elevation_level
