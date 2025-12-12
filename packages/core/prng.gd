## prng.gd - Seeded pseudo-random number generator
## Implements SplitMix64 algorithm for high-quality, reproducible randomness
## CRITICAL: All methods must produce identical results for identical seeds
class_name PRNG
extends RefCounted


## SplitMix64 constants (as signed 64-bit to avoid overflow)
const SPLITMIX_A: int = -7046029254386353131   # 0x9E3779B97F4A7C15
const SPLITMIX_B: int = -4658895280553007687   # 0xBF58476D1CE4E5B9
const SPLITMIX_C: int = -7723592293110705685   # 0x94D049BB133111EB

## Internal state
var _state: int


## Create a new PRNG with the given seed
func _init(seed: int = 0) -> void:
	_state = seed


## Set the seed (reset the generator)
func set_seed(seed: int) -> void:
	_state = seed


## Get current state (for saving/restoring)
func get_state() -> int:
	return _state


## Restore state (for loading)
func restore_state(state: int) -> void:
	_state = state


## Generate next 64-bit integer (advances state)
func next_int() -> int:
	_state += SPLITMIX_A
	var z: int = _state
	z = (z ^ (z >> 30)) * SPLITMIX_B
	z = (z ^ (z >> 27)) * SPLITMIX_C
	return z ^ (z >> 31)


## Generate float in [0.0, 1.0)
func next_float() -> float:
	var n: int = next_int()
	var positive: int = n & 0x7FFFFFFFFFFFFFFF
	return float(positive) / float(0x7FFFFFFFFFFFFFFF)


## Generate float in [min_val, max_val)
func next_float_range(min_val: float, max_val: float) -> float:
	return min_val + next_float() * (max_val - min_val)


## Generate int in [min_val, max_val] (inclusive)
func next_int_range(min_val: int, max_val: int) -> int:
	var range_size: int = max_val - min_val + 1
	var n: int = next_int()
	var positive: int = n & 0x7FFFFFFFFFFFFFFF
	return min_val + (positive % range_size)


## Generate bool with given probability of true
func next_bool(probability: float = 0.5) -> bool:
	return next_float() < probability


## Pick random element from array
func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[next_int_range(0, array.size() - 1)]


## Pick N unique random elements from array
func pick_n(array: Array, count: int) -> Array:
	if count >= array.size():
		return array.duplicate()

	var result: Array = []
	var indices: Array = range(array.size())

	for i in range(count):
		var idx: int = next_int_range(0, indices.size() - 1)
		result.append(array[indices[idx]])
		indices.remove_at(idx)

	return result


## Shuffle array in place (Fisher-Yates)
func shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = next_int_range(0, i)
		var temp: Variant = array[i]
		array[i] = array[j]
		array[j] = temp


## Generate weighted random index
## weights: Array of float weights (higher = more likely)
func weighted_index(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += w

	if total <= 0.0:
		return next_int_range(0, weights.size() - 1)

	var roll: float = next_float() * total
	var cumulative: float = 0.0

	for i in range(weights.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return i

	return weights.size() - 1


## Generate 2D point in unit circle
func next_point_in_circle() -> Vector2:
	# Rejection sampling for uniform distribution
	while true:
		var x: float = next_float_range(-1.0, 1.0)
		var y: float = next_float_range(-1.0, 1.0)
		if x * x + y * y <= 1.0:
			return Vector2(x, y)
	return Vector2.ZERO  # Unreachable but required by GDScript


## Generate 3D point in unit sphere
func next_point_in_sphere() -> Vector3:
	# Rejection sampling for uniform distribution
	while true:
		var x: float = next_float_range(-1.0, 1.0)
		var y: float = next_float_range(-1.0, 1.0)
		var z: float = next_float_range(-1.0, 1.0)
		if x * x + y * y + z * z <= 1.0:
			return Vector3(x, y, z)
	return Vector3.ZERO  # Unreachable but required by GDScript


## Generate unit vector on sphere surface (uniform distribution)
func next_direction_3d() -> Vector3:
	var z: float = next_float_range(-1.0, 1.0)
	var theta: float = next_float_range(0.0, TAU)
	var r: float = sqrt(1.0 - z * z)
	return Vector3(r * cos(theta), r * sin(theta), z)


## Generate Gaussian/normal distributed value
## Uses Box-Muller transform
func next_gaussian(mean: float = 0.0, std_dev: float = 1.0) -> float:
	var u1: float = next_float()
	var u2: float = next_float()

	# Avoid log(0)
	if u1 < 1e-10:
		u1 = 1e-10

	var z: float = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	return mean + z * std_dev
