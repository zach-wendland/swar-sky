## terrain_generator.gd - Procedural terrain generation using layered noise
## Generates heightmaps, biome maps, and surface details from planet seeds
class_name TerrainGenerator
extends RefCounted


## Terrain layer types for noise composition
enum NoiseLayer {
	CONTINENTAL,    # Large-scale land/ocean shapes
	MOUNTAIN,       # Mountain ranges
	HILLS,          # Medium-scale terrain variation
	DETAIL,         # Fine detail roughness
	EROSION,        # Simulated erosion patterns
}

## Noise parameters per layer
const NOISE_PARAMS: Dictionary = {
	NoiseLayer.CONTINENTAL: { "scale": 0.001, "octaves": 4, "persistence": 0.5, "weight": 1.0 },
	NoiseLayer.MOUNTAIN:    { "scale": 0.005, "octaves": 5, "persistence": 0.6, "weight": 0.4 },
	NoiseLayer.HILLS:       { "scale": 0.02,  "octaves": 4, "persistence": 0.5, "weight": 0.15 },
	NoiseLayer.DETAIL:      { "scale": 0.1,   "octaves": 3, "persistence": 0.4, "weight": 0.05 },
	NoiseLayer.EROSION:     { "scale": 0.008, "octaves": 3, "persistence": 0.7, "weight": -0.1 },
}

const NOISE_LAYER_ORDER: Array[int] = [
	NoiseLayer.CONTINENTAL,
	NoiseLayer.MOUNTAIN,
	NoiseLayer.HILLS,
	NoiseLayer.DETAIL,
	NoiseLayer.EROSION,
]

const NOISE_LAYER_COUNT: int = NoiseLayer.EROSION + 1

class TerrainProfile:
	var total_usec: int = 0
	var height_usec: int = 0
	var biome_usec: int = 0
	var normals_usec: int = 0

	var sample_usec: int = 0
	var fbm_usec: int = 0
	var simplex_usec: int = 0
	var hash_calls: int = 0

	var layer_usec: PackedInt64Array = PackedInt64Array()
	var layer_samples: PackedInt32Array = PackedInt32Array()

	func _init() -> void:
		layer_usec.resize(NOISE_LAYER_COUNT)
		layer_samples.resize(NOISE_LAYER_COUNT)

	static func _layer_name(layer: int) -> String:
		match layer:
			NoiseLayer.CONTINENTAL:
				return "continental"
			NoiseLayer.MOUNTAIN:
				return "mountain"
			NoiseLayer.HILLS:
				return "hills"
			NoiseLayer.DETAIL:
				return "detail"
			NoiseLayer.EROSION:
				return "erosion"
		return "unknown"

	func print_report(resolution: int) -> void:
		print("  Profile (", resolution, "x", resolution, "): total=", total_usec / 1000.0, "ms",
			" heights=", height_usec / 1000.0, "ms",
			" biomes=", biome_usec / 1000.0, "ms",
			" normals=", normals_usec / 1000.0, "ms")
		print("    noise: sample=", sample_usec / 1000.0, "ms fbm=", fbm_usec / 1000.0, "ms simplex=", simplex_usec / 1000.0, "ms hash_calls=", hash_calls)
		for layer in NOISE_LAYER_ORDER:
			print("    layer ", _layer_name(layer), ": ", layer_usec[layer] / 1000.0, "ms (samples=", layer_samples[layer], ")")


## Biome classification
enum Biome {
	OCEAN_DEEP,
	OCEAN_SHALLOW,
	BEACH,
	DESERT,
	GRASSLAND,
	FOREST,
	JUNGLE,
	TUNDRA,
	SNOW,
	MOUNTAIN,
	VOLCANIC,
	SWAMP,
	FROZEN_OCEAN,
}

## Biome visual properties
const BIOME_DATA: Dictionary = {
	Biome.OCEAN_DEEP:    { "name": "Deep Ocean", "color": Color(0.05, 0.1, 0.3), "walkable": false },
	Biome.OCEAN_SHALLOW: { "name": "Shallow Ocean", "color": Color(0.1, 0.3, 0.5), "walkable": false },
	Biome.BEACH:         { "name": "Beach", "color": Color(0.9, 0.85, 0.6), "walkable": true },
	Biome.DESERT:        { "name": "Desert", "color": Color(0.9, 0.8, 0.5), "walkable": true },
	Biome.GRASSLAND:     { "name": "Grassland", "color": Color(0.4, 0.6, 0.3), "walkable": true },
	Biome.FOREST:        { "name": "Forest", "color": Color(0.2, 0.4, 0.2), "walkable": true },
	Biome.JUNGLE:        { "name": "Jungle", "color": Color(0.1, 0.35, 0.15), "walkable": true },
	Biome.TUNDRA:        { "name": "Tundra", "color": Color(0.6, 0.65, 0.5), "walkable": true },
	Biome.SNOW:          { "name": "Snow", "color": Color(0.95, 0.95, 1.0), "walkable": true },
	Biome.MOUNTAIN:      { "name": "Mountain", "color": Color(0.5, 0.45, 0.4), "walkable": true },
	Biome.VOLCANIC:      { "name": "Volcanic", "color": Color(0.3, 0.2, 0.2), "walkable": true },
	Biome.SWAMP:         { "name": "Swamp", "color": Color(0.3, 0.35, 0.25), "walkable": true },
	Biome.FROZEN_OCEAN:  { "name": "Frozen Ocean", "color": Color(0.7, 0.8, 0.9), "walkable": true },
}


## Terrain configuration for a planet
class TerrainConfig:
	var seed: int
	var planet_type: int
	var radius_km: float = 6000.0
	var tile_world_size: float = 1000.0  # World units per tile at LOD 0
	var sea_level: float = 0.4           # Height threshold for water
	var mountain_threshold: float = 0.75  # Height for mountains
	var avg_temperature: float = 15.0     # Celsius
	var water_coverage: float = 0.5
	var terrain_roughness: float = 0.5
	var has_polar_caps: bool = true

	# Noise modifiers based on planet type
	var continental_scale: float = 1.0
	var height_multiplier: float = 1.0
	var erosion_strength: float = 1.0


## Generated tile data (named TerrainTileData to avoid conflict with Godot's TileData)
class TerrainTileData:
	var tile_coords: Vector2i
	var lod: int
	var seed: int
	var heightmap: PackedFloat32Array      # Grid of height values 0-1
	var biome_map: PackedInt32Array        # Grid of Biome enum values
	var normal_map: PackedVector3Array     # Surface normals
	var resolution: int                    # Grid size (e.g., 33 for 32 quads)
	var profile: TerrainProfile = null

	func get_height_at(local_x: int, local_y: int) -> float:
		var idx := local_y * resolution + local_x
		if idx >= 0 and idx < heightmap.size():
			return heightmap[idx]
		return 0.0

	func get_biome_at(local_x: int, local_y: int) -> int:
		var idx := local_y * resolution + local_x
		if idx >= 0 and idx < biome_map.size():
			return biome_map[idx]
		return Biome.GRASSLAND


## Create terrain config from planet data
static func create_config(planet_seed: int, planet_type: int, detail: PlanetGenerator.PlanetDetail = null) -> TerrainConfig:
	var config := TerrainConfig.new()
	config.seed = planet_seed
	config.planet_type = planet_type

	var rng := PRNG.new(planet_seed)

	# Get type data
	var type_data: Dictionary = SystemGenerator.PLANET_TYPE_DATA.get(planet_type, {})

	# Set parameters based on planet type
	match planet_type:
		SystemGenerator.PlanetType.OCEAN:
			config.sea_level = rng.next_float_range(0.6, 0.85)
			config.water_coverage = rng.next_float_range(0.85, 0.98)
			config.terrain_roughness = rng.next_float_range(0.2, 0.4)
			config.height_multiplier = 0.5

		SystemGenerator.PlanetType.DESERT:
			config.sea_level = rng.next_float_range(0.0, 0.1)
			config.water_coverage = rng.next_float_range(0.0, 0.05)
			config.terrain_roughness = rng.next_float_range(0.4, 0.7)
			config.avg_temperature = rng.next_float_range(30, 50)
			config.has_polar_caps = rng.next_bool(0.3)
			config.continental_scale = 2.0

		SystemGenerator.PlanetType.FROZEN:
			config.sea_level = rng.next_float_range(0.3, 0.5)
			config.water_coverage = rng.next_float_range(0.2, 0.5)
			config.terrain_roughness = rng.next_float_range(0.3, 0.6)
			config.avg_temperature = rng.next_float_range(-80, -20)
			config.has_polar_caps = true

		SystemGenerator.PlanetType.VOLCANIC:
			config.sea_level = 0.0
			config.water_coverage = 0.0
			config.terrain_roughness = rng.next_float_range(0.6, 0.9)
			config.avg_temperature = rng.next_float_range(100, 400)
			config.has_polar_caps = false
			config.height_multiplier = 1.5
			config.erosion_strength = 0.3

		SystemGenerator.PlanetType.FOREST:
			config.sea_level = rng.next_float_range(0.3, 0.45)
			config.water_coverage = rng.next_float_range(0.3, 0.5)
			config.terrain_roughness = rng.next_float_range(0.4, 0.6)
			config.avg_temperature = rng.next_float_range(15, 28)

		SystemGenerator.PlanetType.TEMPERATE:
			config.sea_level = rng.next_float_range(0.35, 0.5)
			config.water_coverage = rng.next_float_range(0.4, 0.7)
			config.terrain_roughness = rng.next_float_range(0.4, 0.6)
			config.avg_temperature = rng.next_float_range(10, 22)

		SystemGenerator.PlanetType.SWAMP:
			config.sea_level = rng.next_float_range(0.45, 0.6)
			config.water_coverage = rng.next_float_range(0.5, 0.75)
			config.terrain_roughness = rng.next_float_range(0.2, 0.4)
			config.avg_temperature = rng.next_float_range(20, 35)
			config.height_multiplier = 0.4

		SystemGenerator.PlanetType.BARREN, SystemGenerator.PlanetType.ROCKY:
			config.sea_level = 0.0
			config.water_coverage = 0.0
			config.terrain_roughness = rng.next_float_range(0.5, 0.8)
			config.has_polar_caps = false
			config.erosion_strength = 0.2

		_:
			# Default temperate-ish
			config.sea_level = rng.next_float_range(0.3, 0.5)
			config.water_coverage = rng.next_float_range(0.3, 0.6)
			config.terrain_roughness = rng.next_float_range(0.4, 0.6)

	# Override with detail if provided
	if detail:
		config.avg_temperature = detail.avg_temperature_c
		config.water_coverage = detail.water_coverage
		config.terrain_roughness = detail.terrain_roughness

	return config


## Generate a terrain tile
static func generate_tile(config: TerrainConfig, tile_coords: Vector2i, lod: int = 0, resolution: int = 33, enable_profile: bool = false) -> TerrainTileData:
	var tile := TerrainTileData.new()
	tile.tile_coords = tile_coords
	tile.lod = lod
	tile.seed = Hash.hash_combine(config.seed, [
		0x54494C45, # "TILE"
		tile_coords.x,
		tile_coords.y,
		lod
	])
	tile.resolution = resolution

	var total_points := resolution * resolution
	tile.heightmap.resize(total_points)
	tile.biome_map.resize(total_points)
	tile.normal_map.resize(total_points)

	# Tile size in world units (depends on LOD)
	var base_tile_size := config.tile_world_size
	if base_tile_size <= 0.0:
		base_tile_size = 1000.0
	var tile_size := base_tile_size * pow(2.0, lod)
	var step := tile_size / (resolution - 1)

	var profile: TerrainProfile = null
	var total_start_usec := 0
	if enable_profile:
		profile = TerrainProfile.new()
		total_start_usec = Time.get_ticks_usec()

	# World offset for this tile (floats to avoid Vector2 churn)
	var world_offset_x := float(tile_coords.x) * tile_size
	var world_offset_y := float(tile_coords.y) * tile_size

	# Generate heightmap
	for y in range(resolution):
		var world_y := world_offset_y + float(y) * step
		for x in range(resolution):
			var idx := y * resolution + x
			var world_x := world_offset_x + float(x) * step

			var height_start_usec := 0
			if profile != null:
				height_start_usec = Time.get_ticks_usec()
			var height := _sample_terrain_height_xy(config, world_x, world_y, profile)
			if profile != null:
				profile.height_usec += Time.get_ticks_usec() - height_start_usec
			tile.heightmap[idx] = height

			# Calculate latitude for biome (simplified: use y position relative to planet)
			var latitude := _world_to_latitude_y(world_y, config.radius_km)

			# Determine biome
			var biome_start_usec := 0
			if profile != null:
				biome_start_usec = Time.get_ticks_usec()
			tile.biome_map[idx] = _determine_biome_xy(config, height, latitude, world_x, world_y, profile)
			if profile != null:
				profile.biome_usec += Time.get_ticks_usec() - biome_start_usec

	# Generate normals (after all heights are computed)
	var normals_start_usec := 0
	if profile != null:
		normals_start_usec = Time.get_ticks_usec()
	for y in range(resolution):
		for x in range(resolution):
			var idx := y * resolution + x
			tile.normal_map[idx] = _calculate_normal(tile, x, y, step)
	if profile != null:
		profile.normals_usec = Time.get_ticks_usec() - normals_start_usec
		profile.total_usec = Time.get_ticks_usec() - total_start_usec
		tile.profile = profile

	return tile


## Sample terrain height at a world position
static func _sample_terrain_height(config: TerrainConfig, world_pos: Vector2) -> float:
	return _sample_terrain_height_xy(config, world_pos.x, world_pos.y, null)

static func _sample_terrain_height_xy(config: TerrainConfig, world_x: float, world_y: float, profile: TerrainProfile) -> float:
	var height := 0.0

	var start_usec := 0
	if profile != null:
		start_usec = Time.get_ticks_usec()

	# Sample each noise layer
	for layer: int in NOISE_LAYER_ORDER:
		var params: Dictionary = NOISE_PARAMS[layer]
		var scale: float = params["scale"] * config.continental_scale
		var octaves: int = params["octaves"]
		var persistence: float = params["persistence"]
		var weight: float = params["weight"]

		# Apply roughness modifier
		if layer in [NoiseLayer.HILLS, NoiseLayer.DETAIL]:
			weight *= config.terrain_roughness * 2.0

		if layer == NoiseLayer.EROSION:
			weight *= config.erosion_strength

		var layer_start_usec := 0
		if profile != null:
			layer_start_usec = Time.get_ticks_usec()
		var layer_value := _fbm_noise_xy(config.seed + layer, world_x, world_y, scale, octaves, persistence, profile)
		if profile != null:
			profile.layer_usec[layer] += Time.get_ticks_usec() - layer_start_usec
			profile.layer_samples[layer] += 1
		height += layer_value * weight

	# Normalize to 0-1 range
	height = (height + 1.0) * 0.5
	height = clampf(height, 0.0, 1.0)

	# Apply height multiplier
	height = pow(height, 1.0 / config.height_multiplier) if config.height_multiplier != 1.0 else height

	if profile != null:
		profile.sample_usec += Time.get_ticks_usec() - start_usec

	return height


## Fractal Brownian Motion noise
static func _fbm_noise(seed: int, pos: Vector2, scale: float, octaves: int, persistence: float) -> float:
	return _fbm_noise_xy(seed, pos.x, pos.y, scale, octaves, persistence, null)

static func _fbm_noise_xy(seed: int, x: float, y: float, scale: float, octaves: int, persistence: float, profile: TerrainProfile) -> float:
	var value := 0.0
	var amplitude := 1.0
	var frequency := scale
	var max_value := 0.0

	var start_usec := 0
	if profile != null:
		start_usec = Time.get_ticks_usec()

	for i in range(octaves):
		var s := _simplex_2d_xy(seed + i * 1000, x * frequency, y * frequency, profile)
		value += s * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= 2.0

	if profile != null:
		profile.fbm_usec += Time.get_ticks_usec() - start_usec

	return value / max_value


## 2D simplex-like noise (deterministic)
static func _simplex_2d(seed: int, pos: Vector2) -> float:
	return _simplex_2d_xy(seed, pos.x, pos.y, null)

static func _simplex_2d_xy(seed: int, x: float, y: float, profile: TerrainProfile) -> float:
	var start_usec := 0
	if profile != null:
		start_usec = Time.get_ticks_usec()

	# Grid cell coordinates
	var i := int(floor(x))
	var j := int(floor(y))

	# Local position within cell
	var fx := x - i
	var fy := y - j

	# Smoothstep for interpolation
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)

	# Hash corners
	var n00 := _hash_to_float(seed, i, j, profile)
	var n10 := _hash_to_float(seed, i + 1, j, profile)
	var n01 := _hash_to_float(seed, i, j + 1, profile)
	var n11 := _hash_to_float(seed, i + 1, j + 1, profile)

	# Bilinear interpolation
	var nx0 := lerpf(n00, n10, u)
	var nx1 := lerpf(n01, n11, u)
	var out := lerpf(nx0, nx1, v)
	if profile != null:
		profile.simplex_usec += Time.get_ticks_usec() - start_usec
	return out


## Hash grid position to float in [-1, 1]
static func _hash_to_float(seed: int, x: int, y: int, profile: TerrainProfile) -> float:
	if profile != null:
		profile.hash_calls += 1
	var h := Hash.hash_coords2(seed, x, y)
	return Hash.to_float(h) * 2.0 - 1.0


## Convert world position to approximate latitude (-90 to 90)
static func _world_to_latitude(world_pos: Vector2, radius_km: float) -> float:
	return _world_to_latitude_y(world_pos.y, radius_km)

static func _world_to_latitude_y(world_y: float, radius_km: float) -> float:
	# Simplified: assume world_pos.y maps to latitude
	# In a real sphere, this would be based on UV mapping
	var circumference := radius_km * 2.0 * PI
	var latitude := (world_y / circumference) * 360.0
	latitude = fmod(latitude, 180.0)
	if latitude > 90.0:
		latitude = 180.0 - latitude
	elif latitude < -90.0:
		latitude = -180.0 - latitude
	return latitude


## Determine biome based on height, latitude, and local conditions
static func _determine_biome(config: TerrainConfig, height: float, latitude: float, world_pos: Vector2) -> int:
	return _determine_biome_xy(config, height, latitude, world_pos.x, world_pos.y, null)

static func _determine_biome_xy(config: TerrainConfig, height: float, latitude: float, world_x: float, world_y: float, profile: TerrainProfile) -> int:
	var abs_lat: float = abs(latitude)

	# Temperature decreases with latitude and altitude
	var temp := config.avg_temperature
	temp -= abs_lat * 0.5  # Cooler toward poles
	temp -= maxf(0.0, height - config.sea_level) * 50.0  # Cooler at altitude

	# Moisture (simplified: use noise)
	var moisture := _simplex_2d_xy(config.seed + 99999, world_x * 0.003, world_y * 0.003, profile) * 0.5 + 0.5

	# Water bodies
	if height < config.sea_level:
		if temp < -10:
			return Biome.FROZEN_OCEAN
		elif height < config.sea_level - 0.1:
			return Biome.OCEAN_DEEP
		else:
			return Biome.OCEAN_SHALLOW

	# Beach (just above water)
	if height < config.sea_level + 0.03 and config.water_coverage > 0.1:
		return Biome.BEACH

	# Mountain (high altitude)
	if height > config.mountain_threshold:
		if temp < -5:
			return Biome.SNOW
		return Biome.MOUNTAIN

	# Volcanic planets
	if config.planet_type == SystemGenerator.PlanetType.VOLCANIC:
		return Biome.VOLCANIC

	# Temperature-based biomes
	if temp < -20:
		return Biome.SNOW
	elif temp < 0:
		return Biome.TUNDRA
	elif temp > 35:
		if moisture < 0.3:
			return Biome.DESERT
		else:
			return Biome.JUNGLE
	else:
		# Temperate zones - moisture determines biome
		if moisture < 0.25:
			return Biome.DESERT
		elif moisture < 0.4:
			return Biome.GRASSLAND
		elif moisture < 0.6:
			return Biome.FOREST
		elif moisture < 0.8:
			return Biome.JUNGLE
		else:
			return Biome.SWAMP


## Calculate surface normal from heightmap
static func _calculate_normal(tile: TerrainTileData, x: int, y: int, step: float) -> Vector3:
	var res := tile.resolution

	# Get neighboring heights (clamped to edges)
	var h_l := tile.get_height_at(maxi(0, x - 1), y)
	var h_r := tile.get_height_at(mini(res - 1, x + 1), y)
	var h_d := tile.get_height_at(x, maxi(0, y - 1))
	var h_u := tile.get_height_at(x, mini(res - 1, y + 1))

	# Height scale for normal calculation
	var height_scale := step * 0.5

	# Calculate normal from height differences
	var normal := Vector3(
		(h_l - h_r) * height_scale,
		2.0 * step,
		(h_d - h_u) * height_scale
	).normalized()

	return normal


## Get height at arbitrary world position (interpolated)
static func get_height_at_world(config: TerrainConfig, world_pos: Vector2) -> float:
	return _sample_terrain_height_xy(config, world_pos.x, world_pos.y, null)


## Get biome at arbitrary world position
static func get_biome_at_world(config: TerrainConfig, world_pos: Vector2) -> int:
	var height := _sample_terrain_height_xy(config, world_pos.x, world_pos.y, null)
	var latitude := _world_to_latitude_y(world_pos.y, config.radius_km)
	return _determine_biome_xy(config, height, latitude, world_pos.x, world_pos.y, null)
