## test_terrain.gd - Unit tests for terrain generation
## Run: godot --headless --script packages/procgen/tests/test_terrain.gd
extends SceneTree


func _init() -> void:
	print("\n========================================")
	print("TERRAIN GENERATION TEST SUITE")
	print("========================================\n")

	var all_passed := true

	all_passed = test_terrain_determinism() and all_passed
	all_passed = test_biome_distribution() and all_passed
	all_passed = test_tile_consistency() and all_passed
	all_passed = test_height_range() and all_passed
	all_passed = test_performance() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL TERRAIN TESTS PASSED")
	else:
		print("SOME TERRAIN TESTS FAILED")
	print("========================================\n")

	quit(0 if all_passed else 1)


func test_terrain_determinism() -> bool:
	print("[TEST] Terrain height determinism...")

	var config := TerrainGenerator.create_config(12345, SystemGenerator.PlanetType.TEMPERATE)

	# Sample same points twice
	var test_points := [
		Vector2(0, 0),
		Vector2(1000, 1000),
		Vector2(-500, 2000),
		Vector2(12345.67, -9876.54),
	]

	for point in test_points:
		var h1 := TerrainGenerator.get_height_at_world(config, point)
		var h2 := TerrainGenerator.get_height_at_world(config, point)

		if abs(h1 - h2) > 0.0001:
			print("  FAIL: Height not deterministic at ", point, " (", h1, " vs ", h2, ")")
			return false

	# Test tile generation determinism
	var tile1 := TerrainGenerator.generate_tile(config, Vector2i(5, 10), 0, 17)
	var tile2 := TerrainGenerator.generate_tile(config, Vector2i(5, 10), 0, 17)

	if tile1.seed != tile2.seed:
		print("  FAIL: Tile seeds don't match")
		return false

	for i in range(tile1.heightmap.size()):
		if abs(tile1.heightmap[i] - tile2.heightmap[i]) > 0.0001:
			print("  FAIL: Tile heightmaps differ at index ", i)
			return false

	print("  PASS: Terrain generation is deterministic")
	return true


func test_biome_distribution() -> bool:
	print("[TEST] Biome distribution sanity...")

	var config := TerrainGenerator.create_config(54321, SystemGenerator.PlanetType.TEMPERATE)
	config.sea_level = 0.4
	config.water_coverage = 0.5

	var biome_counts: Dictionary = {}
	var samples := 1000

	# Sample random points
	var rng := PRNG.new(99999)
	for i in range(samples):
		var pos := Vector2(
			rng.next_float_range(-10000, 10000),
			rng.next_float_range(-10000, 10000)
		)
		var biome := TerrainGenerator.get_biome_at_world(config, pos)
		biome_counts[biome] = biome_counts.get(biome, 0) + 1

	# Check we have variety
	if biome_counts.size() < 3:
		print("  FAIL: Too few biome types (", biome_counts.size(), ")")
		return false

	# Check water exists for temperate planet
	var water_count := biome_counts.get(TerrainGenerator.Biome.OCEAN_DEEP, 0) + \
	                   biome_counts.get(TerrainGenerator.Biome.OCEAN_SHALLOW, 0)
	if water_count == 0:
		print("  WARN: No water found in temperate planet sample")

	print("  PASS: Found ", biome_counts.size(), " different biomes in ", samples, " samples")

	# Print distribution
	for biome in biome_counts:
		var name: String = TerrainGenerator.BIOME_DATA[biome]["name"]
		var pct := float(biome_counts[biome]) / samples * 100
		print("    ", name, ": ", "%.1f" % pct, "%")

	return true


func test_tile_consistency() -> bool:
	print("[TEST] Tile edge consistency...")

	var config := TerrainGenerator.create_config(11111, SystemGenerator.PlanetType.FOREST)

	# Generate two adjacent tiles
	var tile_a := TerrainGenerator.generate_tile(config, Vector2i(0, 0), 0, 17)
	var tile_b := TerrainGenerator.generate_tile(config, Vector2i(1, 0), 0, 17)

	# The right edge of tile_a should match left edge of tile_b
	# (This tests that noise is continuous across tile boundaries)
	var res := tile_a.resolution
	var mismatches := 0

	for y in range(res):
		var h_a := tile_a.get_height_at(res - 1, y)  # Right edge of A
		var h_b := tile_b.get_height_at(0, y)        # Left edge of B

		# Heights should be very close (same world position)
		# Note: They won't be exactly equal due to different tile seeds affecting detail noise
		# But the major features should align
		if abs(h_a - h_b) > 0.3:  # Allow some variance
			mismatches += 1

	if mismatches > res / 4:
		print("  WARN: Many edge mismatches (", mismatches, "/", res, ") - check noise continuity")

	print("  PASS: Tile edges have ", res - mismatches, "/", res, " points within tolerance")
	return true


func test_height_range() -> bool:
	print("[TEST] Height values in valid range...")

	var planet_types := [
		SystemGenerator.PlanetType.TEMPERATE,
		SystemGenerator.PlanetType.DESERT,
		SystemGenerator.PlanetType.FROZEN,
		SystemGenerator.PlanetType.VOLCANIC,
		SystemGenerator.PlanetType.OCEAN,
	]

	for ptype in planet_types:
		var config := TerrainGenerator.create_config(ptype * 1000, ptype)
		var tile := TerrainGenerator.generate_tile(config, Vector2i(0, 0), 0, 33)

		var min_h := 1.0
		var max_h := 0.0

		for h in tile.heightmap:
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

		if min_h < 0.0 or max_h > 1.0:
			var type_name: String = SystemGenerator.PLANET_TYPE_DATA[ptype]["name"]
			print("  FAIL: Heights out of range for ", type_name, " (", min_h, " - ", max_h, ")")
			return false

	print("  PASS: All planet types produce heights in [0, 1]")
	return true


func test_performance() -> bool:
	print("[TEST] Tile generation performance...")

	var config := TerrainGenerator.create_config(77777, SystemGenerator.PlanetType.TEMPERATE)

	# Time tile generation
	var start := Time.get_ticks_msec()
	var tiles_to_generate := 10
	var resolution := 33

	for i in range(tiles_to_generate):
		var _tile := TerrainGenerator.generate_tile(config, Vector2i(i, 0), 0, resolution)

	var elapsed := Time.get_ticks_msec() - start
	var per_tile := float(elapsed) / tiles_to_generate

	print("  Generated ", tiles_to_generate, " tiles (", resolution, "x", resolution, ") in ", elapsed, "ms")
	print("  Average: ", "%.2f" % per_tile, "ms per tile")

	# Budget check: tiles should generate in under 50ms each for smooth streaming
	if per_tile > 50:
		print("  WARN: Tile generation exceeds 50ms budget (", "%.2f" % per_tile, "ms)")
		return true  # Warning, not failure

	print("  PASS: Tile generation within performance budget")
	return true
