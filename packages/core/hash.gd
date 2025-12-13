## hash.gd - Deterministic hash functions for procedural generation
## Uses xxHash-inspired algorithm for fast, high-quality hashing
## CRITICAL: All functions must be pure and deterministic
class_name Hash
extends RefCounted


## xxHash-style constants (prime numbers for mixing)
const PRIME1: int = 0x9E3779B1
const PRIME2: int = 0x85EBCA77
const PRIME3: int = 0xC2B2AE3D
const PRIME4: int = 0x27D4EB2F
const PRIME5: int = 0x165667B1
const MASK_63: int = 0x7FFFFFFFFFFFFFFF


## Hash a single 64-bit integer seed with coordinates
## Returns a new deterministic seed
static func hash_coords(seed: int, x: int, y: int = 0, z: int = 0) -> int:
	var h: int = seed
	h = _mix(h, x)
	h = _mix(h, y)
	h = _mix(h, z)
	return _finalize(h)


## Hash seed with 2D coordinates (hot path helper)
static func hash_coords2(seed: int, x: int, y: int) -> int:
	var h: int = seed
	h = _mix(h, x)
	h = _mix(h, y)
	return _finalize(h)


## Hash seed with an archetype/type ID
static func hash_type(seed: int, type_id: int) -> int:
	var h: int = seed
	h = _mix(h, type_id)
	return _finalize(h)


## Hash seed with an index (for generating Nth item in a list)
static func hash_index(seed: int, index: int) -> int:
	var h: int = seed
	h = _mix(h, index)
	return _finalize(h)


## Combine multiple values into a single hash
## Use for complex seed derivation: hash_combine(parent_seed, [x, y, type_id])
static func hash_combine(seed: int, values: Array) -> int:
	var h: int = seed
	for v in values:
		if v is int:
			h = _mix(h, v)
		elif v is float:
			# Convert float to int bits for determinism
			h = _mix(h, _float_to_int_bits(v))
		elif v is String:
			h = _hash_string(h, v)
		elif v is Vector2i:
			h = _mix(h, v.x)
			h = _mix(h, v.y)
		elif v is Vector3i:
			h = _mix(h, v.x)
			h = _mix(h, v.y)
			h = _mix(h, v.z)
	return _finalize(h)


## Convert hash to normalized float [0.0, 1.0)
static func to_float(hash_value: int) -> float:
	# Use upper bits, mask to positive, divide by max
	var positive: int = hash_value & 0x7FFFFFFFFFFFFFFF
	return float(positive) / float(0x7FFFFFFFFFFFFFFF)


## Convert hash to float in range [min_val, max_val)
static func to_float_range(hash_value: int, min_val: float, max_val: float) -> float:
	return min_val + to_float(hash_value) * (max_val - min_val)


## Convert hash to int in range [min_val, max_val]
static func to_int_range(hash_value: int, min_val: int, max_val: int) -> int:
	var range_size: int = max_val - min_val + 1
	var positive: int = hash_value & 0x7FFFFFFFFFFFFFFF
	return min_val + (positive % range_size)


## Internal: Mix a value into the hash state
static func _mix(h: int, value: int) -> int:
	h &= MASK_63
	var v := value & MASK_63
	h ^= (v * PRIME2) & MASK_63
	h = ((h << 31) | (h >> 33)) & MASK_63  # Rotate left 31 (63-bit domain)
	h = (h * PRIME1) & MASK_63
	return h


## Internal: Final avalanche mixing
static func _finalize(h: int) -> int:
	h &= MASK_63
	h ^= h >> 33
	h = (h * PRIME2) & MASK_63
	h ^= h >> 29
	h = (h * PRIME3) & MASK_63
	h ^= h >> 32
	return h & MASK_63


## Internal: Convert float to int bits (IEEE 754)
static func _float_to_int_bits(f: float) -> int:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, f)
	return bytes.decode_s64(0)


## Internal: Deterministic string hash (replaces platform-dependent String.hash())
## Iterates UTF-8 bytes for consistent results across all platforms
static func _hash_string(h: int, s: String) -> int:
	var utf8 := s.to_utf8_buffer()
	for byte in utf8:
		h = _mix(h, byte)
	return h
