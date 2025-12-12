## test_determinism.gd - Unit tests for procedural generation core
## Run from editor or via command line: godot --headless --script tests/test_determinism.gd
extends SceneTree


const TEST_ITERATIONS := 10000
const SEED_SAMPLES := 100


func _init() -> void:
	print("\n========================================")
	print("SWAR-SKY DETERMINISM TEST SUITE")
	print("========================================\n")

	var all_passed := true

	all_passed = test_hash_determinism() and all_passed
	all_passed = test_hash_distribution() and all_passed
	all_passed = test_prng_determinism() and all_passed
	all_passed = test_prng_distribution() and all_passed
	all_passed = test_seed_stack_determinism() and all_passed
	all_passed = test_seed_chain_uniqueness() and all_passed
	all_passed = test_cross_layer_independence() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	print("========================================\n")

	quit(0 if all_passed else 1)


## ============================================================================
## HASH TESTS
## ============================================================================


func test_hash_determinism() -> bool:
	print("[TEST] Hash determinism...")

	for i in range(SEED_SAMPLES):
		var seed := i * 12345
		var h1 := Hash.hash_coords(seed, 100, 200, 300)
		var h2 := Hash.hash_coords(seed, 100, 200, 300)

		if h1 != h2:
			print("  FAIL: hash_coords not deterministic at seed ", seed)
			return false

		# Test hash_combine
		var c1 := Hash.hash_combine(seed, [1, 2, 3, "test"])
		var c2 := Hash.hash_combine(seed, [1, 2, 3, "test"])

		if c1 != c2:
			print("  FAIL: hash_combine not deterministic at seed ", seed)
			return false

	print("  PASS: Hash functions are deterministic")
	return true


func test_hash_distribution() -> bool:
	print("[TEST] Hash distribution quality...")

	# Test that different inputs produce different outputs
	var seen: Dictionary = {}
	var collisions := 0

	for i in range(TEST_ITERATIONS):
		var h := Hash.hash_coords(42, i, i * 2, i * 3)
		if seen.has(h):
			collisions += 1
		seen[h] = true

	var collision_rate := float(collisions) / float(TEST_ITERATIONS)
	if collision_rate > 0.001:  # Allow 0.1% collision rate
		print("  FAIL: Too many collisions: ", collisions, " (", collision_rate * 100, "%)")
		return false

	# Test float distribution is roughly uniform
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for i in range(TEST_ITERATIONS):
		var h := Hash.hash_index(12345, i)
		var f := Hash.to_float(h)
		var bucket := int(f * 10) % 10
		buckets[bucket] += 1

	var expected := TEST_ITERATIONS / 10
	var tolerance := expected * 0.15  # 15% tolerance

	for i in range(10):
		if abs(buckets[i] - expected) > tolerance:
			print("  FAIL: Non-uniform distribution in bucket ", i, ": ", buckets[i], " (expected ~", expected, ")")
			return false

	print("  PASS: Hash distribution is good (", collisions, " collisions in ", TEST_ITERATIONS, " samples)")
	return true


## ============================================================================
## PRNG TESTS
## ============================================================================


func test_prng_determinism() -> bool:
	print("[TEST] PRNG determinism...")

	for seed in range(SEED_SAMPLES):
		var rng1 := PRNG.new(seed * 54321)
		var rng2 := PRNG.new(seed * 54321)

		for i in range(100):
			if rng1.next_int() != rng2.next_int():
				print("  FAIL: PRNG not deterministic at seed ", seed, " iteration ", i)
				return false

	# Test state save/restore
	var rng := PRNG.new(99999)
	for i in range(50):
		rng.next_int()

	var saved_state := rng.get_state()
	var expected_next := rng.next_int()

	rng.restore_state(saved_state)
	var actual_next := rng.next_int()

	if expected_next != actual_next:
		print("  FAIL: State save/restore failed")
		return false

	print("  PASS: PRNG is deterministic and state-restorable")
	return true


func test_prng_distribution() -> bool:
	print("[TEST] PRNG distribution quality...")

	var rng := PRNG.new(12345)

	# Test float range
	var min_f := 1.0
	var max_f := 0.0
	for i in range(TEST_ITERATIONS):
		var f := rng.next_float()
		min_f = min(min_f, f)
		max_f = max(max_f, f)
		if f < 0.0 or f >= 1.0:
			print("  FAIL: next_float() out of range: ", f)
			return false

	if min_f > 0.01 or max_f < 0.99:
		print("  WARN: next_float() range seems narrow: [", min_f, ", ", max_f, "]")

	# Test int range
	rng.set_seed(54321)
	var counts: Dictionary = {}
	var min_val := 10
	var max_val := 20

	for i in range(TEST_ITERATIONS):
		var n := rng.next_int_range(min_val, max_val)
		if n < min_val or n > max_val:
			print("  FAIL: next_int_range() out of bounds: ", n)
			return false
		counts[n] = counts.get(n, 0) + 1

	# Check all values in range were hit
	for v in range(min_val, max_val + 1):
		if not counts.has(v):
			print("  FAIL: next_int_range() never produced ", v)
			return false

	# Test weighted_index
	rng.set_seed(11111)
	var weights := [1.0, 2.0, 3.0, 4.0]  # Should produce ~10%, 20%, 30%, 40%
	var weight_counts := [0, 0, 0, 0]

	for i in range(TEST_ITERATIONS):
		var idx := rng.weighted_index(weights)
		weight_counts[idx] += 1

	# Check roughly correct distribution (with tolerance)
	var total_weight := 10.0
	for i in range(4):
		var expected_ratio: float = weights[i] / total_weight
		var actual_ratio: float = float(weight_counts[i]) / float(TEST_ITERATIONS)
		if abs(actual_ratio - expected_ratio) > 0.05:  # 5% tolerance
			print("  WARN: weighted_index distribution off for index ", i,
				": expected ", expected_ratio, ", got ", actual_ratio)

	print("  PASS: PRNG distribution is good")
	return true


## ============================================================================
## SEED STACK TESTS
## ============================================================================


func test_seed_stack_determinism() -> bool:
	print("[TEST] Seed stack determinism...")

	# Initialize SeedStack (it's an autoload, but we test manually here)
	var stack := preload("res://packages/core/seed_stack.gd").new()
	stack.global_seed = 42424242

	# Test same inputs produce same outputs
	for i in range(SEED_SAMPLES):
		var sector := Vector3i(i, i * 2, i * 3)
		var s1 := stack.get_sector_seed(sector)
		var s2 := stack.get_sector_seed(sector)

		if s1 != s2:
			print("  FAIL: Sector seed not deterministic")
			return false

		var sys1 := stack.get_system_seed(sector, 5)
		var sys2 := stack.get_system_seed(sector, 5)

		if sys1 != sys2:
			print("  FAIL: System seed not deterministic")
			return false

		var planet1 := stack.get_planet_seed(sector, 5, 3)
		var planet2 := stack.get_planet_seed(sector, 5, 3)

		if planet1 != planet2:
			print("  FAIL: Planet seed not deterministic")
			return false

	print("  PASS: Seed stack is deterministic")
	return true


func test_seed_chain_uniqueness() -> bool:
	print("[TEST] Seed chain uniqueness...")

	var stack := preload("res://packages/core/seed_stack.gd").new()
	stack.global_seed = 99999999

	var seen_sectors: Dictionary = {}
	var seen_systems: Dictionary = {}
	var seen_planets: Dictionary = {}

	# Generate many seeds and check for collisions
	for x in range(-5, 6):
		for y in range(-5, 6):
			for z in range(-3, 4):
				var sector := Vector3i(x, y, z)
				var sector_seed := stack.get_sector_seed(sector)

				if seen_sectors.has(sector_seed):
					print("  FAIL: Sector seed collision at ", sector, " with ", seen_sectors[sector_seed])
					return false
				seen_sectors[sector_seed] = sector

				for sys_idx in range(10):
					var sys_seed := stack.get_system_seed(sector, sys_idx)

					if seen_systems.has(sys_seed):
						print("  FAIL: System seed collision")
						return false
					seen_systems[sys_seed] = [sector, sys_idx]

					for planet_idx in range(5):
						var planet_seed := stack.get_planet_seed(sector, sys_idx, planet_idx)

						if seen_planets.has(planet_seed):
							print("  FAIL: Planet seed collision")
							return false
						seen_planets[planet_seed] = [sector, sys_idx, planet_idx]

	print("  PASS: No seed collisions in ", seen_planets.size(), " planet seeds")
	return true


func test_cross_layer_independence() -> bool:
	print("[TEST] Cross-layer independence...")

	var stack := preload("res://packages/core/seed_stack.gd").new()
	stack.global_seed = 77777777

	# Different layer types at "same" coordinates should produce different seeds
	var sector := Vector3i(10, 20, 30)

	var sector_seed := stack.get_sector_seed(sector)
	var system_seed := stack.get_system_seed(sector, 0)
	var planet_seed := stack.get_planet_seed(sector, 0, 0)
	var tile_seed := stack.get_tile_seed(planet_seed, Vector2i(0, 0))
	var poi_seed := stack.get_poi_seed(tile_seed, 0)

	var all_seeds := [sector_seed, system_seed, planet_seed, tile_seed, poi_seed]
	var unique_seeds: Dictionary = {}

	for s in all_seeds:
		if unique_seeds.has(s):
			print("  FAIL: Cross-layer seed collision")
			return false
		unique_seeds[s] = true

	# Changing any parameter should change the output
	var alt_sector := stack.get_sector_seed(Vector3i(10, 20, 31))  # z+1
	if alt_sector == sector_seed:
		print("  FAIL: Adjacent sectors have same seed")
		return false

	var alt_system := stack.get_system_seed(sector, 1)  # system+1
	if alt_system == system_seed:
		print("  FAIL: Adjacent systems have same seed")
		return false

	print("  PASS: Layers are independent, adjacent values differ")
	return true
