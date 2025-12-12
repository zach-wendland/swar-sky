## galaxy_generator.gd - Generates star systems within galaxy sectors
## Each sector is a cube of space containing 50-200 star systems
## Stars are distributed using Poisson-like placement for natural clustering
class_name GalaxyGenerator
extends RefCounted


## Sector size in light years
const SECTOR_SIZE: float = 1000.0

## Star count range per sector
const MIN_STARS_PER_SECTOR: int = 50
const MAX_STARS_PER_SECTOR: int = 200

## Minimum distance between stars (in sector-local units 0-1)
const MIN_STAR_SEPARATION: float = 0.03


## Star classification with spectral types
enum StarClass {
	O,  # Blue giants - very rare, very hot
	B,  # Blue-white - rare
	A,  # White - uncommon
	F,  # Yellow-white - common
	G,  # Yellow (Sol-like) - common
	K,  # Orange - very common
	M,  # Red dwarf - extremely common
}

## Star class properties: [color, temperature_k, luminosity_mult, rarity_weight]
const STAR_CLASS_DATA: Dictionary = {
	StarClass.O: { "name": "O", "color": Color(0.6, 0.7, 1.0), "temp": 30000, "luminosity": 50.0, "weight": 1 },
	StarClass.B: { "name": "B", "color": Color(0.7, 0.8, 1.0), "temp": 20000, "luminosity": 10.0, "weight": 3 },
	StarClass.A: { "name": "A", "color": Color(0.9, 0.9, 1.0), "temp": 9000, "luminosity": 3.0, "weight": 10 },
	StarClass.F: { "name": "F", "color": Color(1.0, 1.0, 0.9), "temp": 7000, "luminosity": 1.5, "weight": 20 },
	StarClass.G: { "name": "G", "color": Color(1.0, 1.0, 0.8), "temp": 5500, "luminosity": 1.0, "weight": 25 },
	StarClass.K: { "name": "K", "color": Color(1.0, 0.85, 0.6), "temp": 4500, "luminosity": 0.5, "weight": 30 },
	StarClass.M: { "name": "M", "color": Color(1.0, 0.6, 0.4), "temp": 3000, "luminosity": 0.1, "weight": 50 },
}


## Generated star data structure
class StarData:
	var index: int                    # Index within sector
	var seed: int                     # Unique seed for this system
	var position: Vector3             # Position within sector (0-1 range)
	var galactic_position: Vector3    # Absolute galactic position
	var star_class: int               # StarClass enum
	var star_name: String             # Generated name
	var num_planets: int              # Number of planets
	var has_station: bool             # Has space station
	var faction_id: int               # Controlling faction (-1 = none)
	var danger_level: int             # 0-5 danger rating

	func get_class_data() -> Dictionary:
		return STAR_CLASS_DATA[star_class]

	func get_color() -> Color:
		return get_class_data()["color"]


## Generate all stars in a sector
static func generate_sector(sector_coords: Vector3i) -> Array[StarData]:
	var sector_seed := SeedStack.get_sector_seed(sector_coords)
	var rng := PRNG.new(sector_seed)

	# Determine star count (influenced by galactic position)
	var density_mult := _get_density_multiplier(sector_coords)
	var base_count := rng.next_int_range(MIN_STARS_PER_SECTOR, MAX_STARS_PER_SECTOR)
	var star_count := int(base_count * density_mult)
	star_count = clampi(star_count, 10, 300)

	# Generate star positions using rejection sampling for separation
	var positions: Array[Vector3] = []
	var attempts := 0
	var max_attempts := star_count * 20

	while positions.size() < star_count and attempts < max_attempts:
		var candidate := Vector3(
			rng.next_float(),
			rng.next_float(),
			rng.next_float()
		)

		# Check separation from existing stars
		var valid := true
		for existing in positions:
			if candidate.distance_to(existing) < MIN_STAR_SEPARATION:
				valid = false
				break

		if valid:
			positions.append(candidate)
		attempts += 1

	# Build star data for each position
	var stars: Array[StarData] = []
	for i in range(positions.size()):
		var star := _generate_star(sector_coords, i, positions[i], rng)
		stars.append(star)

	return stars


## Generate a single star's properties
static func _generate_star(sector_coords: Vector3i, index: int, local_pos: Vector3, rng: PRNG) -> StarData:
	var star := StarData.new()
	star.index = index
	star.seed = SeedStack.get_system_seed(sector_coords, index)
	star.position = local_pos
	star.galactic_position = Vector3(
		(sector_coords.x + local_pos.x) * SECTOR_SIZE,
		(sector_coords.y + local_pos.y) * SECTOR_SIZE,
		(sector_coords.z + local_pos.z) * SECTOR_SIZE
	)

	# Use star's own seed for its properties
	var star_rng := PRNG.new(star.seed)

	# Pick star class by weight
	var weights: Array = []
	for sc in STAR_CLASS_DATA:
		weights.append(float(STAR_CLASS_DATA[sc]["weight"]))
	star.star_class = star_rng.weighted_index(weights)

	# Generate name
	star.star_name = _generate_star_name(star_rng)

	# Planet count (influenced by star class)
	var class_data: Dictionary = STAR_CLASS_DATA[star.star_class]
	var base_planets: int = star_rng.next_int_range(0, 12)
	# Hot stars have fewer planets
	if star.star_class <= StarClass.B:
		base_planets = int(base_planets * 0.3)
	# Sol-like stars favor more planets
	elif star.star_class == StarClass.G:
		base_planets = int(base_planets * 1.3)
	star.num_planets = clampi(base_planets, 0, 15)

	# Station probability
	star.has_station = star_rng.next_bool(0.15 if star.num_planets > 0 else 0.05)

	# Faction (simplified - -1 = unclaimed)
	star.faction_id = -1
	if star_rng.next_bool(0.4):
		star.faction_id = star_rng.next_int_range(0, 5)

	# Danger level
	star.danger_level = star_rng.weighted_index([40.0, 30.0, 15.0, 10.0, 4.0, 1.0])

	return star


## Generate a procedural star name
static func _generate_star_name(rng: PRNG) -> String:
	# Prefixes
	var prefixes := ["", "", "", "New ", "Old ", "Upper ", "Lower ", "Far ", "Near "]

	# Syllables for generating names
	var starts := ["Al", "Bet", "Cor", "Dan", "Er", "Fel", "Gor", "Hel", "Ir", "Jax",
	               "Kel", "Lor", "Mur", "Nar", "Or", "Pol", "Qar", "Ry", "Sol", "Tar",
	               "Ul", "Var", "Wex", "Xar", "Yor", "Zan", "Kra", "Dra", "Tho", "Sha"]
	var middles := ["", "", "", "a", "e", "i", "o", "u", "an", "en", "on", "ar", "er", "or", "is", "us"]
	var ends := ["a", "e", "i", "o", "ia", "us", "is", "on", "an", "ar", "or", "ax", "ex", "ix", "ox",
	             "ine", "ane", "one", "ium", "ion", "ius", "eus", "aia", "eia", "oia"]

	# Greek letter designations
	var greek := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
	              "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
	              "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]

	var name_type := rng.next_int_range(0, 3)

	match name_type:
		0:  # Simple generated name: "Alderon", "Corusca"
			return rng.pick(prefixes) + rng.pick(starts) + rng.pick(middles) + rng.pick(ends)
		1:  # Greek + Name: "Alpha Centauri"
			return rng.pick(greek) + " " + rng.pick(starts) + rng.pick(ends)
		2:  # Catalog number: "KX-4827"
			var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ"
			var l1 := letters[rng.next_int_range(0, letters.length() - 1)]
			var l2 := letters[rng.next_int_range(0, letters.length() - 1)]
			var num := rng.next_int_range(1000, 9999)
			return "%s%s-%d" % [l1, l2, num]
		_:  # Fallback
			return rng.pick(starts) + rng.pick(ends)


## Get density multiplier based on galactic position
## Core regions are denser, rim is sparser
static func _get_density_multiplier(sector_coords: Vector3i) -> float:
	# Distance from galactic center (assume center is 0,0,0)
	var dist := Vector3(sector_coords).length()

	# Galactic core (within ~50 sectors) is very dense
	if dist < 50:
		return 2.0 - (dist / 50.0) * 0.5  # 2.0 to 1.5
	# Mid regions
	elif dist < 200:
		return 1.5 - ((dist - 50) / 150.0) * 0.5  # 1.5 to 1.0
	# Outer rim
	elif dist < 500:
		return 1.0 - ((dist - 200) / 300.0) * 0.5  # 1.0 to 0.5
	# Far rim
	else:
		return 0.5 - minf((dist - 500) / 500.0, 0.3) * 0.5  # 0.5 to 0.35


## Get a specific star by index (regenerates deterministically)
static func get_star(sector_coords: Vector3i, star_index: int) -> StarData:
	var stars := generate_sector(sector_coords)
	if star_index >= 0 and star_index < stars.size():
		return stars[star_index]
	return null


## Find stars within a radius of a point (for neighborhood queries)
static func find_stars_near(galactic_pos: Vector3, radius_ly: float) -> Array[StarData]:
	var results: Array[StarData] = []

	# Determine which sectors to check
	var sector_radius := ceili(radius_ly / SECTOR_SIZE) + 1
	var center_sector := Vector3i(
		int(floor(galactic_pos.x / SECTOR_SIZE)),
		int(floor(galactic_pos.y / SECTOR_SIZE)),
		int(floor(galactic_pos.z / SECTOR_SIZE))
	)

	for dx in range(-sector_radius, sector_radius + 1):
		for dy in range(-sector_radius, sector_radius + 1):
			for dz in range(-sector_radius, sector_radius + 1):
				var sector := center_sector + Vector3i(dx, dy, dz)
				var stars := generate_sector(sector)

				for star in stars:
					if star.galactic_position.distance_to(galactic_pos) <= radius_ly:
						results.append(star)

	return results
