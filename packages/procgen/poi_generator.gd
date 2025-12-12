## poi_generator.gd - Point of Interest generation for planet surfaces
## Handles POI placement, types, and data structures
class_name POIGenerator
extends RefCounted


## POI Types
enum POIType {
	JEDI_RUINS,         # Ancient Jedi temple ruins - artifacts, holocrons
	IMPERIAL_OUTPOST,   # Abandoned Imperial checkpoint - supplies, data
	CRASHED_SHIP,       # Wreckage with salvage opportunities
	CAVE_SYSTEM,        # Natural formation with resources
	ANCIENT_MONUMENT,   # Mysterious alien structure
	REBEL_CACHE,        # Hidden supply stash
}

## POI rarity weights (higher = more common)
const POI_WEIGHTS: Dictionary = {
	POIType.JEDI_RUINS: 15,
	POIType.IMPERIAL_OUTPOST: 25,
	POIType.CRASHED_SHIP: 20,
	POIType.CAVE_SYSTEM: 30,
	POIType.ANCIENT_MONUMENT: 5,
	POIType.REBEL_CACHE: 10,
}

const POI_TYPE_ORDER: Array[POIType] = [
	POIType.JEDI_RUINS,
	POIType.IMPERIAL_OUTPOST,
	POIType.CRASHED_SHIP,
	POIType.CAVE_SYSTEM,
	POIType.ANCIENT_MONUMENT,
	POIType.REBEL_CACHE,
]

## POI type data
const POI_TYPE_DATA: Dictionary = {
	POIType.JEDI_RUINS: {
		"name": "Jedi Ruins",
		"description": "Ancient temple ruins from the Old Republic era",
		"min_size": 30.0,
		"max_size": 80.0,
		"artifact_type": "holocron",
		"color": Color(0.3, 0.5, 0.8),  # Blue
		"marker_color": Color(0.4, 0.6, 1.0),
	},
	POIType.IMPERIAL_OUTPOST: {
		"name": "Imperial Outpost",
		"description": "Abandoned Imperial military checkpoint",
		"min_size": 40.0,
		"max_size": 100.0,
		"artifact_type": "data_chip",
		"color": Color(0.5, 0.5, 0.5),  # Gray
		"marker_color": Color(0.8, 0.2, 0.2),
	},
	POIType.CRASHED_SHIP: {
		"name": "Crashed Ship",
		"description": "Wreckage of an unknown vessel",
		"min_size": 20.0,
		"max_size": 60.0,
		"artifact_type": "salvage",
		"color": Color(0.4, 0.35, 0.3),  # Brown
		"marker_color": Color(0.9, 0.6, 0.2),
	},
	POIType.CAVE_SYSTEM: {
		"name": "Cave System",
		"description": "Natural cave formation",
		"min_size": 25.0,
		"max_size": 70.0,
		"artifact_type": "crystal",
		"color": Color(0.3, 0.3, 0.35),  # Dark gray
		"marker_color": Color(0.6, 0.4, 0.8),
	},
	POIType.ANCIENT_MONUMENT: {
		"name": "Ancient Monument",
		"description": "Mysterious alien structure of unknown origin",
		"min_size": 50.0,
		"max_size": 120.0,
		"artifact_type": "relic",
		"color": Color(0.6, 0.5, 0.3),  # Gold-ish
		"marker_color": Color(1.0, 0.8, 0.3),
	},
	POIType.REBEL_CACHE: {
		"name": "Rebel Cache",
		"description": "Hidden Rebel Alliance supply stash",
		"min_size": 15.0,
		"max_size": 35.0,
		"artifact_type": "supplies",
		"color": Color(0.4, 0.5, 0.4),  # Green-gray
		"marker_color": Color(0.3, 0.8, 0.3),
	},
}

const POI_PLANET_RNG_SALT: int = 77777
const POI_SEED_SALT: int = 88888


## POI instance data
class POIData extends RefCounted:
	var seed: int = 0
	var poi_type: POIType = POIType.JEDI_RUINS
	var position: Vector3 = Vector3.ZERO
	var size: float = 50.0
	var rotation: float = 0.0

	## Discovery state
	var discovered: bool = false
	var artifact_collected: bool = false

	## Artifact info
	var artifact_name: String = ""
	var artifact_position: Vector3 = Vector3.ZERO  # Relative to POI center

	func get_type_data() -> Dictionary:
		return POI_TYPE_DATA.get(poi_type, {})

	func get_world_artifact_position() -> Vector3:
		return position + artifact_position.rotated(Vector3.UP, rotation)


## Generate POIs for a planet
static func generate_planet_pois(planet_seed: int, planet_type: int, terrain_config: TerrainGenerator.TerrainConfig) -> Array[POIData]:
	var pois: Array[POIData] = []
	var rng := PRNG.new(planet_seed + POI_PLANET_RNG_SALT)

	# Determine number of POIs based on planet type
	var base_count := _get_poi_count_for_planet(planet_type, rng)

	# Generate each POI
	for i in range(base_count):
		var poi := _generate_single_poi(planet_seed, i, terrain_config, rng)
		if poi:
			pois.append(poi)

	return pois


## Get POI count for planet type
static func _get_poi_count_for_planet(planet_type: int, rng: PRNG) -> int:
	# Different planet types have different POI densities
	match planet_type:
		SystemGenerator.PlanetType.TEMPERATE, SystemGenerator.PlanetType.FOREST:
			return rng.next_int_range(3, 6)
		SystemGenerator.PlanetType.DESERT, SystemGenerator.PlanetType.FROZEN:
			return rng.next_int_range(2, 4)
		SystemGenerator.PlanetType.VOLCANIC:
			return rng.next_int_range(1, 3)
		SystemGenerator.PlanetType.BARREN, SystemGenerator.PlanetType.ROCKY:
			return rng.next_int_range(1, 3)
		_:
			return rng.next_int_range(2, 4)


## Generate a single POI
static func _generate_single_poi(planet_seed: int, index: int, terrain_config: TerrainGenerator.TerrainConfig, rng: PRNG) -> POIData:
	var poi := POIData.new()
	poi.seed = Hash.hash_combine(planet_seed, [POI_SEED_SALT, index])

	# Choose POI type based on weights
	var poi_rng := PRNG.new(poi.seed)
	var weight_list: Array[float] = []
	for t: POIType in POI_TYPE_ORDER:
		weight_list.append(float(POI_WEIGHTS[t]))
	poi.poi_type = POI_TYPE_ORDER[poi_rng.weighted_index(weight_list)]

	var type_data := poi.get_type_data()

	# Generate position (spread across the planet surface)
	var attempts := 0
	var max_attempts := 20
	var valid_position := false

	while not valid_position and attempts < max_attempts:
		# Random position within exploration range
		var range_size := 800.0 + index * 200.0  # Spread POIs outward
		var angle := poi_rng.next_float() * TAU
		var distance := poi_rng.next_float_range(200.0, range_size)

		var x := cos(angle) * distance
		var z := sin(angle) * distance

		# Get terrain height
		var height := TerrainGenerator.get_height_at_world(terrain_config, Vector2(x, z))
		var world_height := height * 100.0  # Scale to world units

		# Check if valid placement (above water, not too steep)
		if world_height > terrain_config.sea_level * 100.0 + 5.0:
			poi.position = Vector3(x, world_height, z)
			valid_position = true

		attempts += 1

	if not valid_position:
		# Fallback: place near origin
		var height := TerrainGenerator.get_height_at_world(terrain_config, Vector2(100, 100))
		poi.position = Vector3(100, height * 100.0 + 2.0, 100)

	# Size and rotation
	poi.size = poi_rng.next_float_range(type_data.get("min_size", 30.0), type_data.get("max_size", 80.0))
	poi.rotation = poi_rng.next_float() * TAU

	# Generate artifact
	poi.artifact_name = _generate_artifact_name(poi.poi_type, poi_rng)
	poi.artifact_position = Vector3(
		poi_rng.next_float_range(-poi.size * 0.3, poi.size * 0.3),
		2.0,  # Slightly elevated
		poi_rng.next_float_range(-poi.size * 0.3, poi.size * 0.3)
	)

	return poi


## Generate artifact name based on POI type
static func _generate_artifact_name(poi_type: POIType, rng: PRNG) -> String:
	var prefixes: Array
	var suffixes: Array

	match poi_type:
		POIType.JEDI_RUINS:
			prefixes = ["Ancient", "Forgotten", "Master", "Padawan's", "Temple"]
			suffixes = ["Holocron", "Datacron", "Crystal", "Teachings", "Artifact"]
		POIType.IMPERIAL_OUTPOST:
			prefixes = ["Imperial", "Classified", "Strategic", "Officer's", "Encrypted"]
			suffixes = ["Data Chip", "Orders", "Manifest", "Codes", "Intel"]
		POIType.CRASHED_SHIP:
			prefixes = ["Captain's", "Navigation", "Emergency", "Cargo", "Flight"]
			suffixes = ["Log", "Core", "Beacon", "Manifest", "Record"]
		POIType.CAVE_SYSTEM:
			prefixes = ["Kyber", "Ilum", "Force", "Raw", "Rare"]
			suffixes = ["Crystal", "Shard", "Formation", "Deposit", "Sample"]
		POIType.ANCIENT_MONUMENT:
			prefixes = ["Mysterious", "Alien", "Unknown", "Ancient", "Primordial"]
			suffixes = ["Relic", "Artifact", "Device", "Fragment", "Key"]
		POIType.REBEL_CACHE:
			prefixes = ["Rebel", "Alliance", "Resistance", "Emergency", "Hidden"]
			suffixes = ["Supplies", "Equipment", "Weapons", "Credits", "Intel"]
		_:
			prefixes = ["Strange"]
			suffixes = ["Object"]

	return rng.pick(prefixes) + " " + rng.pick(suffixes)


## Find nearest POI to a position
static func find_nearest_poi(pois: Array[POIData], world_pos: Vector3) -> POIData:
	var nearest: POIData = null
	var nearest_dist := INF

	for poi in pois:
		var dist := world_pos.distance_to(poi.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = poi

	return nearest


## Find undiscovered POIs within range
static func find_undiscovered_in_range(pois: Array[POIData], world_pos: Vector3, range_dist: float) -> Array[POIData]:
	var result: Array[POIData] = []

	for poi in pois:
		if not poi.discovered:
			var dist := world_pos.distance_to(poi.position)
			if dist < range_dist:
				result.append(poi)

	return result


## Check if player is within POI bounds
static func is_inside_poi(poi: POIData, world_pos: Vector3) -> bool:
	var horizontal_dist := Vector2(world_pos.x - poi.position.x, world_pos.z - poi.position.z).length()
	return horizontal_dist < poi.size * 0.6
