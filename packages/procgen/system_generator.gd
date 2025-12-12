## system_generator.gd - Generates planetary systems from a star seed
## Creates orbital structure, planet types, moons, asteroid belts, and stations
class_name SystemGenerator
extends RefCounted


## Planet type classification
enum PlanetType {
	BARREN,      # Airless rock (Mercury-like)
	VOLCANIC,    # Lava world (Mustafar)
	DESERT,      # Arid sandy world (Tatooine, Jakku)
	ROCKY,       # Earth-like terrain but harsh
	TEMPERATE,   # Earth-like, habitable
	OCEAN,       # Water world (Kamino)
	FROZEN,      # Ice world (Hoth)
	GAS_GIANT,   # Jupiter-like
	ICE_GIANT,   # Neptune-like
	TOXIC,       # Corrosive atmosphere
	FOREST,      # Dense vegetation (Endor moon, Kashyyyk)
	SWAMP,       # Wetlands (Dagobah)
	CITY,        # Ecumenopolis (Coruscant)
}

## Planet type visual/gameplay data
const PLANET_TYPE_DATA: Dictionary = {
	PlanetType.BARREN:    { "name": "Barren", "color": Color(0.5, 0.5, 0.5), "atmosphere": false, "habitable": false, "ring_chance": 0.02 },
	PlanetType.VOLCANIC:  { "name": "Volcanic", "color": Color(0.8, 0.3, 0.1), "atmosphere": true, "habitable": false, "ring_chance": 0.01 },
	PlanetType.DESERT:    { "name": "Desert", "color": Color(0.9, 0.8, 0.5), "atmosphere": true, "habitable": true, "ring_chance": 0.05 },
	PlanetType.ROCKY:     { "name": "Rocky", "color": Color(0.6, 0.5, 0.4), "atmosphere": true, "habitable": true, "ring_chance": 0.08 },
	PlanetType.TEMPERATE: { "name": "Temperate", "color": Color(0.3, 0.6, 0.3), "atmosphere": true, "habitable": true, "ring_chance": 0.03 },
	PlanetType.OCEAN:     { "name": "Ocean", "color": Color(0.2, 0.4, 0.8), "atmosphere": true, "habitable": true, "ring_chance": 0.02 },
	PlanetType.FROZEN:    { "name": "Frozen", "color": Color(0.8, 0.9, 1.0), "atmosphere": true, "habitable": true, "ring_chance": 0.1 },
	PlanetType.GAS_GIANT: { "name": "Gas Giant", "color": Color(0.8, 0.7, 0.5), "atmosphere": true, "habitable": false, "ring_chance": 0.4 },
	PlanetType.ICE_GIANT: { "name": "Ice Giant", "color": Color(0.5, 0.7, 0.9), "atmosphere": true, "habitable": false, "ring_chance": 0.3 },
	PlanetType.TOXIC:     { "name": "Toxic", "color": Color(0.6, 0.7, 0.3), "atmosphere": true, "habitable": false, "ring_chance": 0.05 },
	PlanetType.FOREST:    { "name": "Forest", "color": Color(0.2, 0.5, 0.2), "atmosphere": true, "habitable": true, "ring_chance": 0.02 },
	PlanetType.SWAMP:     { "name": "Swamp", "color": Color(0.3, 0.4, 0.3), "atmosphere": true, "habitable": true, "ring_chance": 0.01 },
	PlanetType.CITY:      { "name": "City World", "color": Color(0.6, 0.6, 0.7), "atmosphere": true, "habitable": true, "ring_chance": 0.0 },
}


## Orbital body data
class OrbitalBody:
	var orbit_index: int              # Position in orbital order
	var seed: int                     # Unique seed
	var is_planet: bool = true        # false = asteroid belt
	var planet_type: int = -1         # PlanetType enum
	var name: String
	var orbital_radius: float         # AU from star
	var orbital_period: float         # Days
	var radius_km: float              # Planet radius
	var mass_earth: float             # Mass in Earth masses
	var gravity: float                # Surface gravity (Earth = 1.0)
	var has_rings: bool = false
	var num_moons: int = 0
	var moons: Array[MoonData] = []
	var has_station: bool = false
	var population: int = 0           # 0 = uninhabited
	var tech_level: int = 0           # 0-5

	func get_type_data() -> Dictionary:
		if planet_type >= 0:
			return PLANET_TYPE_DATA[planet_type]
		return {}

	func get_color() -> Color:
		var data := get_type_data()
		return data.get("color", Color.GRAY)

	func is_habitable() -> bool:
		var data := get_type_data()
		return data.get("habitable", false)


## Moon data
class MoonData:
	var index: int
	var seed: int
	var name: String
	var radius_km: float
	var orbital_radius_km: float      # Distance from planet
	var is_habitable: bool = false


## Complete system data
class SystemData:
	var seed: int
	var star_class: int               # From GalaxyGenerator
	var star_name: String
	var bodies: Array[OrbitalBody] = []
	var asteroid_belts: Array[int] = []  # Orbit indices with belts
	var total_population: int = 0
	var has_hyperlane: bool = false   # Major trade route
	var controlling_faction: int = -1

	func get_planets() -> Array[OrbitalBody]:
		var planets: Array[OrbitalBody] = []
		for body in bodies:
			if body.is_planet:
				planets.append(body)
		return planets

	func get_habitable_planets() -> Array[OrbitalBody]:
		var hab: Array[OrbitalBody] = []
		for body in bodies:
			if body.is_planet and body.is_habitable():
				hab.append(body)
		return hab


## Generate a complete star system
static func generate_system(sector_coords: Vector3i, system_index: int, star_data: GalaxyGenerator.StarData = null) -> SystemData:
	var system := SystemData.new()
	var system_seed := SeedStack.get_system_seed(sector_coords, system_index)
	system.seed = system_seed

	# Get or regenerate star data
	if star_data == null:
		star_data = GalaxyGenerator.get_star(sector_coords, system_index)

	if star_data == null:
		push_error("Failed to get star data for system ", system_index)
		return system

	system.star_class = star_data.star_class
	system.star_name = star_data.star_name
	system.controlling_faction = star_data.faction_id

	var rng := PRNG.new(system_seed)

	# Generate orbital bodies
	var num_planets := star_data.num_planets
	var current_orbit := 0.3 + rng.next_float() * 0.2  # Start at 0.3-0.5 AU

	for i in range(num_planets):
		var body := _generate_orbital_body(system_seed, i, current_orbit, system.star_class)
		system.bodies.append(body)

		# Accumulate population
		system.total_population += body.population

		# Next orbit (exponential spacing like real systems)
		current_orbit *= 1.4 + rng.next_float() * 0.8  # 1.4x to 2.2x spacing

	# Maybe add asteroid belt
	if rng.next_bool(0.3) and num_planets >= 2:
		var belt_orbit := rng.next_int_range(1, num_planets - 1)
		system.asteroid_belts.append(belt_orbit)

	# Hyperlane probability (populous or strategic systems)
	system.has_hyperlane = rng.next_bool(0.1) or system.total_population > 1000000000

	return system


## Generate a single orbital body
static func _generate_orbital_body(system_seed: int, orbit_index: int, orbital_radius: float, star_class: int) -> OrbitalBody:
	var body := OrbitalBody.new()
	body.orbit_index = orbit_index
	body.seed = SeedStack.get_planet_seed_from_system(system_seed, orbit_index)
	body.orbital_radius = orbital_radius

	# Use body's own seed for deterministic properties
	var body_rng := PRNG.new(body.seed)

	# Determine planet type based on orbital distance and star type
	body.planet_type = _pick_planet_type(orbital_radius, star_class, body_rng)
	var type_data: Dictionary = PLANET_TYPE_DATA[body.planet_type]

	# Generate name
	body.name = _generate_planet_name(body_rng)

	# Physical properties based on type
	match body.planet_type:
		PlanetType.GAS_GIANT:
			body.radius_km = body_rng.next_float_range(40000, 140000)
			body.mass_earth = body_rng.next_float_range(50, 400)
		PlanetType.ICE_GIANT:
			body.radius_km = body_rng.next_float_range(20000, 50000)
			body.mass_earth = body_rng.next_float_range(10, 50)
		_:  # Terrestrial
			body.radius_km = body_rng.next_float_range(2000, 15000)
			body.mass_earth = body_rng.next_float_range(0.1, 3.0)

	# Surface gravity
	body.gravity = body.mass_earth / pow(body.radius_km / 6371.0, 2)
	body.gravity = clampf(body.gravity, 0.1, 3.0)

	# Orbital period (simplified Kepler)
	body.orbital_period = 365.25 * pow(orbital_radius, 1.5)

	# Rings
	body.has_rings = body_rng.next_bool(type_data["ring_chance"])

	# Moons
	if body.planet_type in [PlanetType.GAS_GIANT, PlanetType.ICE_GIANT]:
		body.num_moons = body_rng.next_int_range(2, 20)
	else:
		body.num_moons = body_rng.next_int_range(0, 4)

	# Generate moon data
	for m in range(body.num_moons):
		var moon := _generate_moon(body.seed, m, body_rng)
		body.moons.append(moon)

	# Station
	body.has_station = body_rng.next_bool(0.1 if body.is_habitable() else 0.02)

	# Population (only on habitable worlds)
	if body.is_habitable():
		var pop_roll := body_rng.next_float()
		if pop_roll < 0.3:
			body.population = 0  # Uninhabited
		elif pop_roll < 0.6:
			body.population = body_rng.next_int_range(100, 100000)  # Colony
		elif pop_roll < 0.85:
			body.population = body_rng.next_int_range(100000, 100000000)  # Settlement
		elif pop_roll < 0.95:
			body.population = body_rng.next_int_range(100000000, 5000000000)  # Populated
		else:
			body.population = body_rng.next_int_range(5000000000, 50000000000)  # Major world

		# City worlds are always heavily populated
		if body.planet_type == PlanetType.CITY:
			body.population = maxi(body.population, body_rng.next_int_range(10000000000, 100000000000))

	# Tech level correlates with population
	if body.population > 0:
		if body.population < 10000:
			body.tech_level = body_rng.next_int_range(0, 2)
		elif body.population < 10000000:
			body.tech_level = body_rng.next_int_range(1, 3)
		elif body.population < 1000000000:
			body.tech_level = body_rng.next_int_range(2, 4)
		else:
			body.tech_level = body_rng.next_int_range(3, 5)

	return body


## Pick planet type based on orbital distance and star
static func _pick_planet_type(orbital_radius: float, star_class: int, rng: PRNG) -> int:
	var star_data: Dictionary = GalaxyGenerator.STAR_CLASS_DATA[star_class]
	var luminosity: float = star_data["luminosity"]

	# Habitable zone calculation (simplified)
	var hab_inner := sqrt(luminosity) * 0.75
	var hab_outer := sqrt(luminosity) * 1.8

	# Frost line (where ice can exist)
	var frost_line := sqrt(luminosity) * 2.7

	var weights: Array = []

	# Inner system (hot)
	if orbital_radius < hab_inner * 0.5:
		weights = [
			30.0,  # BARREN
			40.0,  # VOLCANIC
			5.0,   # DESERT
			5.0,   # ROCKY
			0.0,   # TEMPERATE
			0.0,   # OCEAN
			0.0,   # FROZEN
			0.0,   # GAS_GIANT
			0.0,   # ICE_GIANT
			20.0,  # TOXIC
			0.0,   # FOREST
			0.0,   # SWAMP
			0.0,   # CITY
		]
	# Inner habitable zone
	elif orbital_radius < hab_inner:
		weights = [
			15.0,  # BARREN
			10.0,  # VOLCANIC
			30.0,  # DESERT
			15.0,  # ROCKY
			5.0,   # TEMPERATE
			0.0,   # OCEAN
			0.0,   # FROZEN
			0.0,   # GAS_GIANT
			0.0,   # ICE_GIANT
			15.0,  # TOXIC
			5.0,   # FOREST
			5.0,   # SWAMP
			0.0,   # CITY
		]
	# Goldilocks zone
	elif orbital_radius <= hab_outer:
		weights = [
			5.0,   # BARREN
			2.0,   # VOLCANIC
			15.0,  # DESERT
			15.0,  # ROCKY
			25.0,  # TEMPERATE
			15.0,  # OCEAN
			3.0,   # FROZEN
			0.0,   # GAS_GIANT
			0.0,   # ICE_GIANT
			5.0,   # TOXIC
			10.0,  # FOREST
			5.0,   # SWAMP
			0.2,   # CITY (rare)
		]
	# Outer habitable
	elif orbital_radius < frost_line:
		weights = [
			15.0,  # BARREN
			0.0,   # VOLCANIC
			10.0,  # DESERT
			15.0,  # ROCKY
			10.0,  # TEMPERATE
			10.0,  # OCEAN
			20.0,  # FROZEN
			5.0,   # GAS_GIANT
			0.0,   # ICE_GIANT
			5.0,   # TOXIC
			5.0,   # FOREST
			5.0,   # SWAMP
			0.0,   # CITY
		]
	# Outer system (cold, gas giants)
	else:
		weights = [
			10.0,  # BARREN
			0.0,   # VOLCANIC
			0.0,   # DESERT
			5.0,   # ROCKY
			0.0,   # TEMPERATE
			0.0,   # OCEAN
			25.0,  # FROZEN
			35.0,  # GAS_GIANT
			20.0,  # ICE_GIANT
			0.0,   # TOXIC
			0.0,   # FOREST
			0.0,   # SWAMP
			0.0,   # CITY
		]

	return rng.weighted_index(weights)


## Generate moon data
static func _generate_moon(planet_seed: int, moon_index: int, rng: PRNG) -> MoonData:
	var moon := MoonData.new()
	moon.index = moon_index
	moon.seed = Hash.hash_combine(planet_seed, [0x4D4F4F4E, moon_index])  # "MOON"

	var moon_rng := PRNG.new(moon.seed)

	moon.name = _generate_moon_name(moon_rng, moon_index)
	moon.radius_km = moon_rng.next_float_range(100, 3500)
	moon.orbital_radius_km = moon_rng.next_float_range(50000, 500000) * (1 + moon_index * 0.5)

	# Large moons can be habitable
	moon.is_habitable = moon.radius_km > 1500 and moon_rng.next_bool(0.2)

	return moon


## Generate planet name
static func _generate_planet_name(rng: PRNG) -> String:
	var prefixes := ["", "", "New ", "Old ", "Greater ", "Lesser "]
	var roots := ["Aldra", "Bespin", "Corel", "Dantor", "Endor", "Felucia", "Geonos",
	              "Hosnian", "Ilum", "Jedha", "Kashyy", "Lothal", "Mandal", "Naboo",
	              "Onderon", "Polis", "Quell", "Ryloth", "Sullust", "Tatoo", "Utap",
	              "Vardos", "Wobani", "Xilam", "Yavin", "Zyger", "Korriban", "Dxun",
	              "Malachor", "Tython", "Lehon", "Dromund"]
	var suffixes := ["", "", "", "a", "ia", "us", "is", "ine", "ar", "or", "an", "on", " Prime", " Major", " Minor"]

	return rng.pick(prefixes) + rng.pick(roots) + rng.pick(suffixes)


## Generate moon name (Roman numeral style or named)
static func _generate_moon_name(rng: PRNG, index: int) -> String:
	if rng.next_bool(0.7):
		# Roman numeral designation
		var numerals := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
		                 "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]
		if index < numerals.size():
			return numerals[index]
		return str(index + 1)
	else:
		# Named moon
		var names := ["Dxun", "Yavin", "Endor", "Jedha", "Nar", "Rhen", "Scarif",
		              "Concordia", "Krownest", "Pantora", "Orto", "Raada", "Skako"]
		return rng.pick(names)
