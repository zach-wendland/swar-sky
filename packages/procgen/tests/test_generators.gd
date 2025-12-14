## test_generators.gd - Tests for all procedural generation systems
## Run: godot --headless --script packages/procgen/tests/test_generators.gd
extends SceneTree


const TEST_ITERATIONS := 100
const SEED_SAMPLES := 50


func _init() -> void:
	print("\n========================================")
	print("SWAR-SKY GENERATOR TEST SUITE")
	print("========================================\n")

	var all_passed := true

	# Galaxy Generator Tests
	all_passed = test_galaxy_sector_determinism() and all_passed
	all_passed = test_galaxy_star_distribution() and all_passed
	all_passed = test_galaxy_star_properties() and all_passed

	# System Generator Tests
	all_passed = test_system_generation_determinism() and all_passed
	all_passed = test_system_orbital_bodies() and all_passed
	all_passed = test_system_planet_types() and all_passed

	# Planet Generator Tests
	all_passed = test_planet_detail_determinism() and all_passed
	all_passed = test_planet_hazards_and_resources() and all_passed
	all_passed = test_planet_climate_consistency() and all_passed

	# POI Generator Tests
	all_passed = test_poi_generation_determinism() and all_passed
	all_passed = test_poi_placement_validity() and all_passed
	all_passed = test_poi_type_distribution() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL GENERATOR TESTS PASSED")
	else:
		print("SOME GENERATOR TESTS FAILED")
	print("========================================\n")

	quit(0 if all_passed else 1)


## ============================================================================
## GALAXY GENERATOR TESTS
## ============================================================================


func test_galaxy_sector_determinism() -> bool:
	print("[TEST] Galaxy sector determinism...")

	for i in range(SEED_SAMPLES):
		var sector := Vector3i(i - 25, (i * 3) % 50 - 25, (i * 7) % 30 - 15)

		var stars1 := GalaxyGenerator.generate_sector(sector)
		var stars2 := GalaxyGenerator.generate_sector(sector)

		if stars1.size() != stars2.size():
			print("  FAIL: Sector star count mismatch at ", sector)
			return false

		for j in range(stars1.size()):
			if stars1[j].seed != stars2[j].seed:
				print("  FAIL: Star seed mismatch at sector ", sector, " star ", j)
				return false
			if stars1[j].position != stars2[j].position:
				print("  FAIL: Star position mismatch at sector ", sector, " star ", j)
				return false
			if stars1[j].star_class != stars2[j].star_class:
				print("  FAIL: Star class mismatch at sector ", sector, " star ", j)
				return false

	print("  PASS: Galaxy sectors are deterministic")
	return true


func test_galaxy_star_distribution() -> bool:
	print("[TEST] Galaxy star distribution...")

	var total_stars := 0
	var class_counts: Dictionary = {}

	for star_class in GalaxyGenerator.STAR_CLASS_ORDER:
		class_counts[star_class] = 0

	# Sample multiple sectors
	for i in range(20):
		var sector := Vector3i(i * 5, i * 3, i * 2)
		var stars := GalaxyGenerator.generate_sector(sector)
		total_stars += stars.size()

		for star in stars:
			class_counts[star.star_class] += 1

	# Verify star count within expected range
	var avg_per_sector: float = float(total_stars) / 20.0
	if avg_per_sector < 30 or avg_per_sector > 250:
		print("  FAIL: Average stars per sector out of range: ", avg_per_sector)
		return false

	# Verify class distribution (M class should be most common)
	var m_count: int = class_counts[GalaxyGenerator.StarClass.M]
	var o_count: int = class_counts[GalaxyGenerator.StarClass.O]

	if m_count <= o_count:
		print("  FAIL: M-class stars should be more common than O-class")
		print("        M: ", m_count, " O: ", o_count)
		return false

	print("  PASS: Star distribution is reasonable (avg ", int(avg_per_sector), " per sector)")
	return true


func test_galaxy_star_properties() -> bool:
	print("[TEST] Galaxy star properties...")

	var sector := Vector3i(10, 20, 30)
	var stars := GalaxyGenerator.generate_sector(sector)

	for star in stars:
		# Verify position is within 0-1 range
		if star.position.x < 0 or star.position.x > 1:
			print("  FAIL: Star position.x out of range: ", star.position.x)
			return false
		if star.position.y < 0 or star.position.y > 1:
			print("  FAIL: Star position.y out of range: ", star.position.y)
			return false
		if star.position.z < 0 or star.position.z > 1:
			print("  FAIL: Star position.z out of range: ", star.position.z)
			return false

		# Verify star class is valid
		if star.star_class < 0 or star.star_class > GalaxyGenerator.StarClass.M:
			print("  FAIL: Invalid star class: ", star.star_class)
			return false

		# Verify star name is not empty
		if star.star_name.length() == 0:
			print("  FAIL: Star has empty name")
			return false

		# Verify planet count is reasonable
		if star.num_planets < 0 or star.num_planets > 20:
			print("  FAIL: Unreasonable planet count: ", star.num_planets)
			return false

		# Verify danger level is in range
		if star.danger_level < 0 or star.danger_level > 5:
			print("  FAIL: Danger level out of range: ", star.danger_level)
			return false

	print("  PASS: All star properties are valid")
	return true


## ============================================================================
## SYSTEM GENERATOR TESTS
## ============================================================================


func test_system_generation_determinism() -> bool:
	print("[TEST] System generation determinism...")

	var sector := Vector3i(5, 10, 15)

	for i in range(SEED_SAMPLES):
		var system1 := SystemGenerator.generate_system(sector, i)
		var system2 := SystemGenerator.generate_system(sector, i)

		if system1.seed != system2.seed:
			print("  FAIL: System seed mismatch at index ", i)
			return false

		if system1.bodies.size() != system2.bodies.size():
			print("  FAIL: Body count mismatch at index ", i)
			return false

		for j in range(system1.bodies.size()):
			if system1.bodies[j].seed != system2.bodies[j].seed:
				print("  FAIL: Body seed mismatch at system ", i, " body ", j)
				return false
			if system1.bodies[j].planet_type != system2.bodies[j].planet_type:
				print("  FAIL: Planet type mismatch at system ", i, " body ", j)
				return false

	print("  PASS: System generation is deterministic")
	return true


func test_system_orbital_bodies() -> bool:
	print("[TEST] System orbital bodies...")

	var sector := Vector3i(0, 0, 0)
	var systems_with_planets := 0
	var total_planets := 0

	for i in range(50):
		var system := SystemGenerator.generate_system(sector, i)

		if system.bodies.size() > 0:
			systems_with_planets += 1
			total_planets += system.bodies.size()

		# Verify orbital radii increase outward
		var last_radius := 0.0
		for body in system.bodies:
			if body.orbital_radius <= last_radius:
				print("  FAIL: Orbital radius not increasing: ", body.orbital_radius, " <= ", last_radius)
				return false
			last_radius = body.orbital_radius

			# Verify physical properties are reasonable
			if body.radius_km <= 0:
				print("  FAIL: Planet radius <= 0")
				return false
			if body.gravity <= 0:
				print("  FAIL: Planet gravity <= 0")
				return false
			if body.orbital_period <= 0:
				print("  FAIL: Orbital period <= 0")
				return false

	if systems_with_planets == 0:
		print("  FAIL: No systems have planets")
		return false

	var avg_planets: float = float(total_planets) / float(systems_with_planets)
	print("  PASS: Orbital bodies are valid (avg ", "%.1f" % avg_planets, " planets/system)")
	return true


func test_system_planet_types() -> bool:
	print("[TEST] System planet types...")

	var type_counts: Dictionary = {}
	for pt in range(SystemGenerator.PlanetType.CITY + 1):
		type_counts[pt] = 0

	# Sample many systems
	for sector_x in range(-2, 3):
		for sector_z in range(-2, 3):
			var sector := Vector3i(sector_x, 0, sector_z)
			for sys_idx in range(10):
				var system := SystemGenerator.generate_system(sector, sys_idx)
				for body in system.bodies:
					if body.planet_type >= 0:
						type_counts[body.planet_type] += 1

	# Verify at least some variety in planet types
	var types_with_planets := 0
	for pt in type_counts:
		if type_counts[pt] > 0:
			types_with_planets += 1

	if types_with_planets < 5:
		print("  FAIL: Not enough planet type variety: ", types_with_planets)
		return false

	# Gas giants should exist
	var gas_giants: int = type_counts[SystemGenerator.PlanetType.GAS_GIANT]
	if gas_giants == 0:
		print("  FAIL: No gas giants generated")
		return false

	print("  PASS: Planet type variety is good (", types_with_planets, " types)")
	return true


## ============================================================================
## PLANET GENERATOR TESTS
## ============================================================================


func test_planet_detail_determinism() -> bool:
	print("[TEST] Planet detail determinism...")

	for i in range(SEED_SAMPLES):
		var planet_seed := 1000000 + i * 12345
		var planet_type := i % (SystemGenerator.PlanetType.CITY + 1)

		var detail1 := PlanetGenerator.generate_planet_detail(planet_seed, planet_type)
		var detail2 := PlanetGenerator.generate_planet_detail(planet_seed, planet_type)

		if detail1.avg_temperature_c != detail2.avg_temperature_c:
			print("  FAIL: Temperature mismatch at seed ", planet_seed)
			return false

		if detail1.water_coverage != detail2.water_coverage:
			print("  FAIL: Water coverage mismatch at seed ", planet_seed)
			return false

		if detail1.hazards.size() != detail2.hazards.size():
			print("  FAIL: Hazard count mismatch at seed ", planet_seed)
			return false

		if detail1.resources.size() != detail2.resources.size():
			print("  FAIL: Resource count mismatch at seed ", planet_seed)
			return false

	print("  PASS: Planet details are deterministic")
	return true


func test_planet_hazards_and_resources() -> bool:
	print("[TEST] Planet hazards and resources...")

	# Test volcanic planet has extreme heat
	var volcanic_seed := 12345
	var volcanic := PlanetGenerator.generate_planet_detail(volcanic_seed, SystemGenerator.PlanetType.VOLCANIC)

	if PlanetGenerator.Hazard.EXTREME_HEAT not in volcanic.hazards:
		print("  FAIL: Volcanic planet missing EXTREME_HEAT hazard")
		return false

	# Test frozen planet has extreme cold
	var frozen_seed := 54321
	var frozen := PlanetGenerator.generate_planet_detail(frozen_seed, SystemGenerator.PlanetType.FROZEN)

	if PlanetGenerator.Hazard.EXTREME_COLD not in frozen.hazards:
		print("  FAIL: Frozen planet missing EXTREME_COLD hazard")
		return false

	# Test ocean planet has water resource
	var ocean_seed := 99999
	var ocean := PlanetGenerator.generate_planet_detail(ocean_seed, SystemGenerator.PlanetType.OCEAN)

	if ocean.resources.get(PlanetGenerator.ResourceType.WATER, 0) < 0.8:
		print("  FAIL: Ocean planet should have high water resource")
		return false

	print("  PASS: Hazards and resources are type-appropriate")
	return true


func test_planet_climate_consistency() -> bool:
	print("[TEST] Planet climate consistency...")

	for i in range(30):
		var seed := 100000 + i * 7777
		var planet_type := i % (SystemGenerator.PlanetType.CITY + 1)
		var detail := PlanetGenerator.generate_planet_detail(seed, planet_type)

		# Temperature should be appropriate for type
		match planet_type:
			SystemGenerator.PlanetType.VOLCANIC:
				if detail.avg_temperature_c < 100:
					print("  FAIL: Volcanic planet too cold: ", detail.avg_temperature_c)
					return false
			SystemGenerator.PlanetType.FROZEN:
				if detail.avg_temperature_c > 0:
					print("  FAIL: Frozen planet too hot: ", detail.avg_temperature_c)
					return false

		# Water coverage should be in range
		if detail.water_coverage < 0 or detail.water_coverage > 1:
			print("  FAIL: Water coverage out of range: ", detail.water_coverage)
			return false

		# Vegetation should be in range
		if detail.vegetation_coverage < 0 or detail.vegetation_coverage > 1:
			print("  FAIL: Vegetation coverage out of range: ", detail.vegetation_coverage)
			return false

		# Day length should be reasonable
		if detail.day_length_hours < 1 or detail.day_length_hours > 1000:
			print("  FAIL: Day length unreasonable: ", detail.day_length_hours)
			return false

	print("  PASS: Planet climate values are consistent")
	return true


## ============================================================================
## POI GENERATOR TESTS
## ============================================================================


func test_poi_generation_determinism() -> bool:
	print("[TEST] POI generation determinism...")

	# Create a simple terrain config for testing
	var terrain_config := TerrainGenerator.TerrainConfig.new()
	terrain_config.seed = 12345
	terrain_config.sea_level = 0.3
	terrain_config.height_multiplier = 1.0

	for i in range(SEED_SAMPLES):
		var planet_seed := 500000 + i * 11111
		var planet_type := SystemGenerator.PlanetType.TEMPERATE

		var pois1 := POIGenerator.generate_planet_pois(planet_seed, planet_type, terrain_config)
		var pois2 := POIGenerator.generate_planet_pois(planet_seed, planet_type, terrain_config)

		if pois1.size() != pois2.size():
			print("  FAIL: POI count mismatch at seed ", planet_seed)
			return false

		for j in range(pois1.size()):
			if pois1[j].seed != pois2[j].seed:
				print("  FAIL: POI seed mismatch at planet ", planet_seed, " poi ", j)
				return false
			if pois1[j].poi_type != pois2[j].poi_type:
				print("  FAIL: POI type mismatch at planet ", planet_seed, " poi ", j)
				return false
			if pois1[j].position != pois2[j].position:
				print("  FAIL: POI position mismatch at planet ", planet_seed, " poi ", j)
				return false

	print("  PASS: POI generation is deterministic")
	return true


func test_poi_placement_validity() -> bool:
	print("[TEST] POI placement validity...")

	var terrain_config := TerrainGenerator.TerrainConfig.new()
	terrain_config.seed = 54321
	terrain_config.sea_level = 0.3
	terrain_config.height_multiplier = 1.0

	for i in range(20):
		var planet_seed := 600000 + i * 5555
		var pois := POIGenerator.generate_planet_pois(planet_seed, SystemGenerator.PlanetType.TEMPERATE, terrain_config)

		for poi in pois:
			# Size should be positive and within type bounds
			var type_data := poi.get_type_data()
			var min_size: float = type_data.get("min_size", 10.0)
			var max_size: float = type_data.get("max_size", 200.0)

			if poi.size < min_size * 0.9 or poi.size > max_size * 1.1:
				print("  FAIL: POI size out of bounds: ", poi.size, " (expected ", min_size, "-", max_size, ")")
				return false

			# Rotation should be 0 to TAU
			if poi.rotation < 0 or poi.rotation > TAU + 0.01:
				print("  FAIL: POI rotation out of range: ", poi.rotation)
				return false

			# Artifact name should not be empty
			if poi.artifact_name.length() == 0:
				print("  FAIL: POI has empty artifact name")
				return false

	print("  PASS: POI placements are valid")
	return true


func test_poi_type_distribution() -> bool:
	print("[TEST] POI type distribution...")

	var terrain_config := TerrainGenerator.TerrainConfig.new()
	terrain_config.seed = 77777
	terrain_config.sea_level = 0.3
	terrain_config.height_multiplier = 1.0

	var type_counts: Dictionary = {}
	for poi_type in POIGenerator.POI_TYPE_ORDER:
		type_counts[poi_type] = 0

	# Generate many POIs across different planets
	for i in range(100):
		var planet_seed := 700000 + i * 3333
		var pois := POIGenerator.generate_planet_pois(planet_seed, SystemGenerator.PlanetType.TEMPERATE, terrain_config)

		for poi in pois:
			type_counts[poi.poi_type] += 1

	# Cave systems should be most common (weight 30)
	var cave_count: int = type_counts[POIGenerator.POIType.CAVE_SYSTEM]
	# Ancient monuments should be least common (weight 5)
	var monument_count: int = type_counts[POIGenerator.POIType.ANCIENT_MONUMENT]

	if cave_count <= monument_count:
		print("  FAIL: Cave systems should be more common than ancient monuments")
		print("        Caves: ", cave_count, " Monuments: ", monument_count)
		return false

	# Verify all types appear at least once
	var types_seen := 0
	for poi_type in type_counts:
		if type_counts[poi_type] > 0:
			types_seen += 1

	if types_seen < POIGenerator.POI_TYPE_ORDER.size():
		print("  WARN: Not all POI types generated (", types_seen, "/", POIGenerator.POI_TYPE_ORDER.size(), ")")

	print("  PASS: POI type distribution follows weights")
	return true
