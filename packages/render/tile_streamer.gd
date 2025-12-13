## tile_streamer.gd - Manages terrain tile loading/unloading around player
## Streams tiles in a grid pattern, prioritizing nearby tiles
class_name TileStreamer
extends Node3D


signal tile_loaded(coords: Vector2i)
signal tile_unloaded(coords: Vector2i)

## Configuration
@export var tile_size: float = 500.0           # World units per tile
@export var view_distance: int = 3              # Tiles to load in each direction
@export var height_scale: float = 100.0         # Vertical exaggeration
@export var tile_resolution: int = 33           # Vertices per tile edge
@export var update_interval: float = 0.5        # Seconds between update checks

## Planet data
var terrain_config: TerrainGenerator.TerrainConfig = null
var planet_seed: int = 0
var planet_type: int = 0

## State
var _loaded_tiles: Dictionary = {}  # Vector2i -> MeshInstance3D
var _player_tile: Vector2i = Vector2i.ZERO
var _update_timer: float = 0.0
var _terrain_material: Material = null
var _water_mesh: MeshInstance3D = null

## Performance tracking
var _tiles_generated_this_frame: int = 0
var _max_tiles_per_frame: int = 2


func _ready() -> void:
	_terrain_material = TerrainMesh.create_terrain_material(true)


func _process(delta: float) -> void:
	_update_timer += delta

	if _update_timer >= update_interval:
		_update_timer = 0.0
		_tiles_generated_this_frame = 0
		_update_tiles()


## Initialize with planet data
func initialize(p_seed: int, p_type: int, detail: PlanetGenerator.PlanetDetail = null, immediate_load: bool = true) -> void:
	planet_seed = p_seed
	planet_type = p_type
	terrain_config = TerrainGenerator.create_config(p_seed, p_type, detail)
	if terrain_config:
		terrain_config.tile_world_size = tile_size

	# Clear any existing tiles
	clear_all_tiles()

	# Create water plane if planet has water
	_update_water()

	# Force immediate tile load around origin
	_player_tile = Vector2i.ZERO
	if immediate_load:
		_update_tiles_immediate()


## Update player position (call from character controller)
func update_player_position(world_pos: Vector3) -> void:
	var new_tile := Vector2i(
		int(floor(world_pos.x / tile_size)),
		int(floor(world_pos.z / tile_size))
	)

	if new_tile != _player_tile:
		_player_tile = new_tile
		# Don't update immediately - let _process handle it for frame budget


## Force tile update (use sparingly)
func force_update() -> void:
	_tiles_generated_this_frame = 0
	_update_tiles_immediate()


## Deterministic comparator for Vector2i coordinates (cached to avoid allocation)
static func _compare_coords(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Compare tiles by distance from player (for load priority sorting)
func _compare_by_distance(a: Vector2i, b: Vector2i) -> bool:
	var dist_a := (a - _player_tile).length_squared()
	var dist_b := (b - _player_tile).length_squared()
	return dist_a < dist_b


## Clear all loaded tiles
func clear_all_tiles() -> void:
	# Sort keys for deterministic iteration order
	var coords_list := _loaded_tiles.keys()
	coords_list.sort_custom(_compare_coords)
	for coords in coords_list:
		var mesh: MeshInstance3D = _loaded_tiles[coords]
		if is_instance_valid(mesh):
			mesh.queue_free()
	_loaded_tiles.clear()

	if _water_mesh and is_instance_valid(_water_mesh):
		_water_mesh.queue_free()
		_water_mesh = null


## Internal: Update tiles around player
func _update_tiles() -> void:
	var needed_tiles: Dictionary = {}

	# Determine which tiles we need
	for dy in range(-view_distance, view_distance + 1):
		for dx in range(-view_distance, view_distance + 1):
			var coords := _player_tile + Vector2i(dx, dy)
			needed_tiles[coords] = true

	# Unload tiles that are too far (sort for deterministic order)
	var to_unload: Array[Vector2i] = []
	var loaded_coords := _loaded_tiles.keys()
	loaded_coords.sort_custom(_compare_coords)
	for coords in loaded_coords:
		if not needed_tiles.has(coords):
			to_unload.append(coords)

	for coords in to_unload:
		_unload_tile(coords)

	# Load tiles that are needed but not loaded (prioritize by distance)
	var to_load: Array[Vector2i] = []
	for coords in needed_tiles:
		if not _loaded_tiles.has(coords):
			to_load.append(coords)

	# Sort by distance from player
	to_load.sort_custom(_compare_by_distance)

	# Load tiles up to frame budget
	for coords in to_load:
		if _tiles_generated_this_frame >= _max_tiles_per_frame:
			break
		_load_tile(coords)


## Load all needed tiles immediately (ignores frame budget)
func _update_tiles_immediate() -> void:
	var old_max := _max_tiles_per_frame
	_max_tiles_per_frame = 100  # No limit
	_update_tiles()
	_max_tiles_per_frame = old_max


## Load a single tile
func _load_tile(coords: Vector2i) -> void:
	if terrain_config == null:
		return

	if _loaded_tiles.has(coords):
		return  # Already loaded

	# Generate tile data
	var tile_data := TerrainGenerator.generate_tile(terrain_config, coords, 0, tile_resolution)

	# Create mesh
	var mesh_instance := TerrainMesh.create_tile_mesh(tile_data, tile_size, height_scale)
	mesh_instance.material_override = _terrain_material

	# Add to scene
	add_child(mesh_instance)
	_loaded_tiles[coords] = mesh_instance

	_tiles_generated_this_frame += 1
	tile_loaded.emit(coords)


## Unload a single tile
func _unload_tile(coords: Vector2i) -> void:
	if not _loaded_tiles.has(coords):
		return

	var mesh: MeshInstance3D = _loaded_tiles[coords]
	if is_instance_valid(mesh):
		mesh.queue_free()

	_loaded_tiles.erase(coords)
	tile_unloaded.emit(coords)


## Update water plane
func _update_water() -> void:
	if _water_mesh and is_instance_valid(_water_mesh):
		_water_mesh.queue_free()
		_water_mesh = null

	if terrain_config == null:
		return

	# Only create water if planet has significant water coverage
	if terrain_config.water_coverage < 0.05:
		return

	var water_size := tile_size * (view_distance * 2 + 3)
	_water_mesh = TerrainMesh.create_water_mesh(water_size, terrain_config.sea_level, height_scale)
	add_child(_water_mesh)


## Get height at world position (for physics/placement)
func get_height_at(world_pos: Vector3) -> float:
	if terrain_config == null:
		return 0.0

	var height := TerrainGenerator.get_height_at_world(terrain_config, Vector2(world_pos.x, world_pos.z))
	return height * height_scale


## Get biome at world position
func get_biome_at(world_pos: Vector3) -> int:
	if terrain_config == null:
		return TerrainGenerator.Biome.GRASSLAND

	return TerrainGenerator.get_biome_at_world(terrain_config, Vector2(world_pos.x, world_pos.z))


## Check if a tile is loaded
func is_tile_loaded(coords: Vector2i) -> bool:
	return _loaded_tiles.has(coords)


## Get loaded tile count
func get_loaded_tile_count() -> int:
	return _loaded_tiles.size()


## Debug: Print tile stats
func print_stats() -> void:
	print("[TileStreamer] Loaded tiles: ", _loaded_tiles.size())
	print("[TileStreamer] Player tile: ", _player_tile)
	print("[TileStreamer] View distance: ", view_distance)
	if terrain_config:
		print("[TileStreamer] Sea level: ", terrain_config.sea_level)
		print("[TileStreamer] Water coverage: ", terrain_config.water_coverage)
