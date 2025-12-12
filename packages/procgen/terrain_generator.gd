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
static func generate_tile(config: TerrainConfig, tile_coords: Vector2i, lod: int = 0, resolution: int = 33) -> TerrainTileData:
	var tile := TerrainTileData.new()
	tile.tile_coords = tile_coords
	tile.lod = lod
	tile.seed = SeedStack.get_tile_seed(config.seed, tile_coords, lod)
	tile.resolution = resolution

	var total_points := resolution * resolution
	tile.heightmap.resize(total_points)
	tile.biome_map.resize(total_points)
	tile.normal_map.resize(total_points)

	# Tile size in world units (depends on LOD)
	var tile_size := 1000.0 * pow(2.0, lod)  # Base 1km tiles, doubling per LOD
	var step := tile_size / (resolution - 1)

	# World offset for this tile
	var world_offset := Vector2(tile_coords.x * tile_size, tile_coords.y * tile_size)

	# Generate heightmap
	for y in range(resolution):
		for x in range(resolution):
			var idx := y * resolution + x
			var world_pos := world_offset + Vector2(x * step, y * step)

			# Generate height using layered noise
			var height := _sample_terrain_height(config, world_pos)
			tile.heightmap[idx] = height

			# Calculate latitude for biome (simplified: use y position relative to planet)
			var latitude := _world_to_latitude(world_pos, config.radius_km)

			# Determine biome
			tile.biome_map[idx] = _determine_biome(config, height, latitude, world_pos)

	# Generate normals (after all heights are computed)
	for y in range(resolution):
		for x in range(resolution):
			var idx := y * resolution + x
			tile.normal_map[idx] = _calculate_normal(tile, x, y, step)

	return tile


## Sample terrain height at a world position
static func _sample_terrain_height(config: TerrainConfig, world_pos: Vector2) -> float:
	var height := 0.0

	# Sample each noise layer
	for layer in NOISE_PARAMS:
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

		var layer_value := _fbm_noise(config.seed + layer, world_pos, scale, octaves, persistence)
		height += layer_value * weight

	# Normalize to 0-1 range
	height = (height + 1.0) * 0.5
	height = clampf(height, 0.0, 1.0)

	# Apply height multiplier
	height = pow(height, 1.0 / config.height_multiplier) if config.height_multiplier != 1.0 else height

	return height


## Fractal Brownian Motion noise
static func _fbm_noise(seed: int, pos: Vector2, scale: float, octaves: int, persistence: float) -> float:
	var value := 0.0
	var amplitude := 1.0
	var frequency := scale
	var max_value := 0.0

	for i in range(octaves):
		value += _simplex_2d(seed + i * 1000, pos * frequency) * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= 2.0

	return value / max_value


## 2D simplex-like noise (deterministic)
static func _simplex_2d(seed: int, pos: Vector2) -> float:
	# Grid cell coordinates
	var i := int(floor(pos.x))
	var j := int(floor(pos.y))

	# Local position within cell
	var fx := pos.x - i
	var fy := pos.y - j

	# Smoothstep for interpolation
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)

	# Hash corners
	var n00 := _hash_to_float(seed, i, j)
	var n10 := _hash_to_float(seed, i + 1, j)
	var n01 := _hash_to_float(seed, i, j + 1)
	var n11 := _hash_to_float(seed, i + 1, j + 1)

	# Bilinear interpolation
	var nx0 := lerpf(n00, n10, u)
	var nx1 := lerpf(n01, n11, u)
	return lerpf(nx0, nx1, v)


## Hash grid position to float in [-1, 1]
static func _hash_to_float(seed: int, x: int, y: int) -> float:
	var h := Hash.hash_coords(seed, x, y)
	return Hash.to_float(h) * 2.0 - 1.0


## Convert world position to approximate latitude (-90 to 90)
static func _world_to_latitude(world_pos: Vector2, radius_km: float) -> float:
	# Simplified: assume world_pos.y maps to latitude
	# In a real sphere, this would be based on UV mapping
	var circumference := radius_km * 2.0 * PI
	var latitude := (world_pos.y / circumference) * 360.0
	latitude = fmod(latitude, 180.0)
	if latitude > 90.0:
		latitude = 180.0 - latitude
	elif latitude < -90.0:
		latitude = -180.0 - latitude
	return latitude


## Determine biome based on height, latitude, and local conditions
static func _determine_biome(config: TerrainConfig, height: float, latitude: float, world_pos: Vector2) -> int:
	var abs_lat: float = abs(latitude)

	# Temperature decreases with latitude and altitude
	var temp := config.avg_temperature
	temp -= abs_lat * 0.5  # Cooler toward poles
	temp -= maxf(0.0, height - config.sea_level) * 50.0  # Cooler at altitude

	# Moisture (simplified: use noise)
	var moisture := _simplex_2d(config.seed + 99999, world_pos * 0.003) * 0.5 + 0.5

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
	return _sample_terrain_height(config, world_pos)


## Get biome at arbitrary world position
static func get_biome_at_world(config: TerrainConfig, world_pos: Vector2) -> int:
	var height := _sample_terrain_height(config, world_pos)
	var latitude := _world_to_latitude(world_pos, config.radius_km)
	return _determine_biome(config, height, latitude, world_pos)
