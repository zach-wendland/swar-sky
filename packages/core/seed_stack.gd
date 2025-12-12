## seed_stack.gd - Hierarchical seed derivation for procedural generation
## Implements the galaxy → sector → system → planet → tile → poi chain
## Autoloaded as singleton: SeedStack
extends Node


## Global seed for the entire universe
## Set once at game start, never changes during a playthrough
var global_seed: int = 0


## Layer type enumeration for seed derivation
enum Layer {
	GALAXY,
	SECTOR,
	SYSTEM,
	PLANET,
	TILE,
	POI,
	NPC,
	ITEM,
	MISSION
}


## Magic numbers for layer mixing (prevent collisions between layers)
const LAYER_SALTS: Dictionary = {
	Layer.GALAXY: 0x47414C4158,   # "GALAX"
	Layer.SECTOR: 0x53454354,     # "SECT"
	Layer.SYSTEM: 0x53595354,     # "SYST"
	Layer.PLANET: 0x504C414E,     # "PLAN"
	Layer.TILE: 0x54494C45,       # "TILE"
	Layer.POI: 0x504F4920,        # "POI "
	Layer.NPC: 0x4E504320,        # "NPC "
	Layer.ITEM: 0x4954454D,       # "ITEM"
	Layer.MISSION: 0x4D49534E,    # "MISN"
}


## Initialize with a global seed
func initialize(seed: int) -> void:
	global_seed = seed
	print("[SeedStack] Initialized with global seed: ", seed)


## Initialize with a string (hashes to int)
func initialize_from_string(seed_string: String) -> void:
	initialize(seed_string.hash())


## ============================================================================
## CORE SEED DERIVATION
## Each layer derives from its parent + local coordinates/identifiers
## ============================================================================


## Derive galaxy seed (identity - just returns global with galaxy salt)
func get_galaxy_seed() -> int:
	return Hash.hash_combine(global_seed, [LAYER_SALTS[Layer.GALAXY]])


## Derive sector seed from galaxy coordinates
## Sectors are large regions of the galaxy (e.g., 1000x1000x100 ly cubes)
func get_sector_seed(sector_coords: Vector3i) -> int:
	return Hash.hash_combine(get_galaxy_seed(), [
		LAYER_SALTS[Layer.SECTOR],
		sector_coords.x,
		sector_coords.y,
		sector_coords.z
	])


## Derive system seed from sector + local system index
## Each sector contains many star systems
func get_system_seed(sector_coords: Vector3i, system_index: int) -> int:
	var sector_seed := get_sector_seed(sector_coords)
	return Hash.hash_combine(sector_seed, [
		LAYER_SALTS[Layer.SYSTEM],
		system_index
	])


## Derive system seed from absolute galactic coordinates
## Alternative method when you have exact position
func get_system_seed_from_position(galactic_pos: Vector3) -> int:
	var sector := _position_to_sector(galactic_pos)
	var local_hash := Hash.hash_combine(get_sector_seed(sector), [
		LAYER_SALTS[Layer.SYSTEM],
		Hash._float_to_int_bits(galactic_pos.x),
		Hash._float_to_int_bits(galactic_pos.y),
		Hash._float_to_int_bits(galactic_pos.z)
	])
	return local_hash


## Derive planet seed from system + orbital index
func get_planet_seed(sector_coords: Vector3i, system_index: int, orbit_index: int) -> int:
	var system_seed := get_system_seed(sector_coords, system_index)
	return Hash.hash_combine(system_seed, [
		LAYER_SALTS[Layer.PLANET],
		orbit_index
	])


## Derive planet seed from system seed directly
func get_planet_seed_from_system(system_seed: int, orbit_index: int) -> int:
	return Hash.hash_combine(system_seed, [
		LAYER_SALTS[Layer.PLANET],
		orbit_index
	])


## Derive tile seed from planet + tile coordinates
## Tiles are chunks of planet surface (quad-tree or cube-sphere faces)
func get_tile_seed(planet_seed: int, tile_coords: Vector2i, lod: int = 0) -> int:
	return Hash.hash_combine(planet_seed, [
		LAYER_SALTS[Layer.TILE],
		tile_coords.x,
		tile_coords.y,
		lod
	])


## Derive POI seed from tile + poi index + archetype
func get_poi_seed(tile_seed: int, poi_index: int, archetype_id: int = 0) -> int:
	return Hash.hash_combine(tile_seed, [
		LAYER_SALTS[Layer.POI],
		poi_index,
		archetype_id
	])


## Derive NPC seed from context + npc index + species/role
func get_npc_seed(context_seed: int, npc_index: int, species_id: int = 0, role_id: int = 0) -> int:
	return Hash.hash_combine(context_seed, [
		LAYER_SALTS[Layer.NPC],
		npc_index,
		species_id,
		role_id
	])


## Derive item seed from container + item index + archetype
func get_item_seed(container_seed: int, item_index: int, archetype_id: int = 0) -> int:
	return Hash.hash_combine(container_seed, [
		LAYER_SALTS[Layer.ITEM],
		item_index,
		archetype_id
	])


## Derive mission seed from system + slot + template
func get_mission_seed(system_seed: int, slot_id: int, template_id: int = 0) -> int:
	return Hash.hash_combine(system_seed, [
		LAYER_SALTS[Layer.MISSION],
		slot_id,
		template_id
	])


## ============================================================================
## CONVENIENCE: Create PRNG from any seed
## ============================================================================


## Create a PRNG initialized with the given seed
func create_rng(seed: int) -> PRNG:
	return PRNG.new(seed)


## Create a PRNG for a specific sector
func create_sector_rng(sector_coords: Vector3i) -> PRNG:
	return PRNG.new(get_sector_seed(sector_coords))


## Create a PRNG for a specific system
func create_system_rng(sector_coords: Vector3i, system_index: int) -> PRNG:
	return PRNG.new(get_system_seed(sector_coords, system_index))


## Create a PRNG for a specific planet
func create_planet_rng(sector_coords: Vector3i, system_index: int, orbit_index: int) -> PRNG:
	return PRNG.new(get_planet_seed(sector_coords, system_index, orbit_index))


## Create a PRNG for a specific tile
func create_tile_rng(planet_seed: int, tile_coords: Vector2i, lod: int = 0) -> PRNG:
	return PRNG.new(get_tile_seed(planet_seed, tile_coords, lod))


## ============================================================================
## UTILITY
## ============================================================================


## Convert galactic position to sector coordinates
func _position_to_sector(pos: Vector3) -> Vector3i:
	const SECTOR_SIZE := 1000.0  # Light years per sector
	return Vector3i(
		int(floor(pos.x / SECTOR_SIZE)),
		int(floor(pos.y / SECTOR_SIZE)),
		int(floor(pos.z / SECTOR_SIZE))
	)


## Validate determinism: generate same value twice, compare
func validate_determinism(seed: int) -> bool:
	var rng1 := PRNG.new(seed)
	var rng2 := PRNG.new(seed)

	for i in range(1000):
		if rng1.next_int() != rng2.next_int():
			push_error("[SeedStack] DETERMINISM FAILURE at iteration ", i)
			return false

	return true


## Debug: Print seed chain for a location
func debug_print_chain(sector: Vector3i, system: int, planet: int, tile: Vector2i) -> void:
	print("=== Seed Chain Debug ===")
	print("Global:  ", global_seed)
	print("Galaxy:  ", get_galaxy_seed())
	print("Sector:  ", get_sector_seed(sector), " @ ", sector)
	print("System:  ", get_system_seed(sector, system), " @ idx ", system)
	print("Planet:  ", get_planet_seed(sector, system, planet), " @ orbit ", planet)
	var planet_seed := get_planet_seed(sector, system, planet)
	print("Tile:    ", get_tile_seed(planet_seed, tile), " @ ", tile)
	print("========================")
