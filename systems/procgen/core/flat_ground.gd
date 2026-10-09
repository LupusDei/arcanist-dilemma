class_name FlatGround
extends RefCounted
## Stand-in for Terrain when a generator runs on flat ground (tests, the lab).
## Any ground passed to a generator needs these three methods.

var height := 0.0


func height_at(_x: float, _z: float) -> float:
	return height


func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func is_water(_x: float, _z: float) -> bool:
	return false
