## test_tile_mapping.gd - Verifies terrain tile sampling matches world coordinates
## Run: godot --headless --script packages/procgen/tests/test_tile_mapping.gd
extends SceneTree


func _init() -> void:
	print("\n========================================")
	print("TILE/WORLD MAPPING TEST SUITE")
	print("========================================\n")

	var all_passed := true

	all_passed = test_tile_samples_match_world_height() and all_passed
	all_passed = test_adjacent_tiles_match_on_seam() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL TILE/WORLD TESTS PASSED")
	else:
		print("SOME TILE/WORLD TESTS FAILED")
	print("========================================\n")

	quit(0 if all_passed else 1)


func test_tile_samples_match_world_height() -> bool:
	print("[TEST] Tile samples match world height...")

	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.create_config(
		12345,
		SystemGenerator.PlanetType.TEMPERATE
	)

	# Critical: Tile world size must control both sampling and mesh placement.
	config.tile_world_size = 500.0

	var tile_coords := Vector2i(2, -3)
	var resolution := 17
	var tile := TerrainGenerator.generate_tile(config, tile_coords, 0, resolution)

	var tile_size: float = config.tile_world_size
	var step: float = tile_size / float(resolution - 1)
	var world_offset := Vector2(tile_coords.x * tile_size, tile_coords.y * tile_size)

	# Sample a few deterministic points, including corners and midpoints.
	var sample_points := [
		Vector2i(0, 0),
		Vector2i(resolution - 1, 0),
		Vector2i(0, resolution - 1),
		Vector2i(resolution - 1, resolution - 1),
		Vector2i(resolution / 2, resolution / 2),
		Vector2i(3, 11),
	]

	for p: Vector2i in sample_points:
		var local_x: int = p.x
		var local_y: int = p.y
		var idx: int = local_y * resolution + local_x

		var world_pos := world_offset + Vector2(float(local_x) * step, float(local_y) * step)
		var expected := TerrainGenerator.get_height_at_world(config, world_pos)
		var actual := tile.heightmap[idx]

		if absf(expected - actual) > 0.0001:
			print("  FAIL: Mismatch at tile ", tile_coords, " local ", p, " world ", world_pos,
				" expected ", expected, " got ", actual)
			return false

	print("  PASS: Tile sampling matches world height")
	return true


func test_adjacent_tiles_match_on_seam() -> bool:
	print("[TEST] Adjacent tiles match on seam...")

	var config: TerrainGenerator.TerrainConfig = TerrainGenerator.create_config(
		67890,
		SystemGenerator.PlanetType.FOREST
	)
	config.tile_world_size = 500.0

	var resolution := 33
	var tile_a := TerrainGenerator.generate_tile(config, Vector2i(0, 0), 0, resolution)
	var tile_b := TerrainGenerator.generate_tile(config, Vector2i(1, 0), 0, resolution)

	var mismatches := 0
	for y in range(resolution):
		var h_a := tile_a.get_height_at(resolution - 1, y)  # right edge of A
		var h_b := tile_b.get_height_at(0, y)              # left edge of B
		if absf(h_a - h_b) > 0.0001:
			mismatches += 1

	if mismatches > 0:
		print("  FAIL: Seam mismatches: ", mismatches, " / ", resolution)
		return false

	print("  PASS: Tile seams match exactly")
	return true

