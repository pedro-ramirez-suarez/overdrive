class_name Racer
extends RefCounted
## State for one participant in a race (SPEC.md §M4).

var car: ArcadeCar
var display_name: String = ""
var is_player: bool = false
var color: Color = Color(0.8, 0.1, 0.12)

## Laps completed.
var lap: int = 0
## Next checkpoint expected in order (advances only on in-order passes; used for
## ranking, not for gating lap counts).
var expected_next: int = 1
## In-order checkpoints passed this lap (ranking tie-break within a lap).
var cp_this_lap: int = 0
## True once the car has left the finish line since its last lap count — a lap is
## counted when it returns, regardless of shortcuts.
var left_finish: bool = false

var last_checkpoint_pos: Vector3 = Vector3.ZERO
var last_checkpoint_forward: Vector3 = Vector3.FORWARD

var finished: bool = false
var finish_time: float = 0.0
var finish_rank: int = 0

## Time flipped-and-slow (any racer) and time crawling-while-upright (AI only).
var stuck_time: float = 0.0
var slow_time: float = 0.0

var timer: LapTimer = LapTimer.new()
