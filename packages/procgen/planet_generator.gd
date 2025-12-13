## planet_generator.gd - Detailed planet generation for surface exploration
## Generates biomes, hazards, resources, atmosphere, and POI density
class_name PlanetGenerator
extends RefCounted


## Hazard types that can affect planets
enum Hazard {
	NONE,
	EXTREME_HEAT,
	EXTREME_COLD,
	TOXIC_ATMOSPHERE,
	RADIATION,
	ACID_RAIN,
	ELECTRICAL_STORMS,
	SEISMIC_ACTIVITY,
	HOSTILE_FAUNA,
	SENTINELS,        # Automated defense drones
	IMPERIAL_PRESENCE,
	PIRATE_ACTIVITY,
}

const HAZARD_DATA: Dictionary = {
	Hazard.NONE:             { "name": "None", "color": Color.GREEN, "severity": 0 },
	Hazard.EXTREME_HEAT:     { "name": "Extreme Heat", "color": Color.ORANGE_RED, "severity": 2 },
	Hazard.EXTREME_COLD:     { "name": "Extreme Cold", "color": Color.CYAN, "severity": 2 },
	Hazard.TOXIC_ATMOSPHERE: { "name": "Toxic Atmosphere", "color": Color.YELLOW_GREEN, "severity": 3 },
	Hazard.RADIATION:        { "name": "Radiation", "color": Color.YELLOW, "severity": 3 },
	Hazard.ACID_RAIN:        { "name": "Acid Rain", "color": Color.LIME_GREEN, "severity": 2 },
	Hazard.ELECTRICAL_STORMS:{ "name": "Electrical Storms", "color": Color.PURPLE, "severity": 2 },
	Hazard.SEISMIC_ACTIVITY: { "name": "Seismic Activity", "color": Color.BROWN, "severity": 2 },
	Hazard.HOSTILE_FAUNA:    { "name": "Hostile Fauna", "color": Color.RED, "severity": 1 },
	Hazard.SENTINELS:        { "name": "Sentinel Drones", "color": Color.STEEL_BLUE, "severity": 2 },
	Hazard.IMPERIAL_PRESENCE:{ "name": "Imperial Presence", "color": Color.GRAY, "severity": 3 },
	Hazard.PIRATE_ACTIVITY:  { "name": "Pirate Activity", "color": Color.DARK_RED, "severity": 2 },
}


## Resource types
enum ResourceType {
	COMMON_METALS,
	RARE_METALS,
	CRYSTALS,
	KYBER_CRYSTALS,   # Very rare, Force-related
	FUEL,
	ORGANICS,
	WATER,
	TECHNOLOGY,
	ARTIFACTS,
	BESKAR,           # Mandalorian iron
}

const RESOURCE_DATA: Dictionary = {
	ResourceType.COMMON_METALS: { "name": "Common Metals", "value": 1, "rarity": 0.8 },
	ResourceType.RARE_METALS:   { "name": "Rare Metals", "value": 3, "rarity": 0.4 },
	ResourceType.CRYSTALS:      { "name": "Crystals", "value": 2, "rarity": 0.5 },
	ResourceType.KYBER_CRYSTALS:{ "name": "Kyber Crystals", "value": 10, "rarity": 0.02 },
	ResourceType.FUEL:          { "name": "Fuel Deposits", "value": 2, "rarity": 0.6 },
	ResourceType.ORGANICS:      { "name": "Organic Materials", "value": 1, "rarity": 0.7 },
	ResourceType.WATER:         { "name": "Water", "value": 1, "rarity": 0.5 },
	ResourceType.TECHNOLOGY:    { "name": "Salvage Tech", "value": 4, "rarity": 0.2 },
	ResourceType.ARTIFACTS:     { "name": "Ancient Artifacts", "value": 8, "rarity": 0.05 },
	ResourceType.BESKAR:        { "name": "Beskar Deposits", "value": 15, "rarity": 0.01 },
}


## POI types that can spawn on planets
enum POIType {
	SETTLEMENT,
	RUINS,
	CRASH_SITE,
	CAVE_SYSTEM,
	IMPERIAL_BASE,
	REBEL_OUTPOST,
	JEDI_TEMPLE,
	SITH_TOMB,
	MINING_FACILITY,
	WILDLIFE_DEN,
	TRADING_POST,
	CANTINA,
	SHIPYARD,
	FACTORY,
	RESEARCH_LAB,
}


## Detailed planet data
class PlanetDetail:
	var seed: int
	var base_type: int                # SystemGenerator.PlanetType

	# Atmosphere
	var has_atmosphere: bool = true
	var atmosphere_density: float = 1.0  # 0 = none, 1 = Earth-like, 2+ = thick
	var atmosphere_composition: String = "Nitrogen-Oxygen"
	var atmosphere_color: Color = Color(0.5, 0.7, 1.0, 0.3)

	# Climate
	var avg_temperature_c: float = 15.0
	var temperature_variance: float = 30.0  # Day/night, seasonal
	var day_length_hours: float = 24.0
	var year_length_days: float = 365.0
	var axial_tilt: float = 23.0

	# Surface
	var water_coverage: float = 0.0       # 0-1
	var terrain_roughness: float = 0.5    # 0 = flat, 1 = mountainous
	var vegetation_coverage: float = 0.0  # 0-1
	var primary_color: Color = Color.GRAY
	var secondary_color: Color = Color.DARK_GRAY
	var accent_color: Color = Color.WHITE

	# Hazards and resources
	var hazards: Array[int] = []          # Hazard enum values
	var resources: Dictionary = {}         # Resource -> abundance (0-1)

	# POIs
	var poi_density: float = 0.5          # POIs per square km (normalized)
	var poi_types: Array[int] = []        # Available POI types

	# Lore/flavor
	var description: String = ""
	var discovered: bool = false
	var discovery_date: String = ""

	func get_hazard_names() -> Array[String]:
		var names: Array[String] = []
		for h in hazards:
			names.append(HAZARD_DATA[h]["name"])
		return names

	func get_total_hazard_severity() -> int:
		var total := 0
		for h in hazards:
			total += HAZARD_DATA[h]["severity"]
		return total

	func get_resource_summary() -> String:
		var parts: Array[String] = []
		# Sort keys for deterministic iteration order
		var resource_keys := resources.keys()
		resource_keys.sort()
		for r in resource_keys:
			if resources[r] > 0.5:
				parts.append(RESOURCE_DATA[r]["name"] + " (Rich)")
			elif resources[r] > 0.2:
				parts.append(RESOURCE_DATA[r]["name"])
		return ", ".join(parts) if parts.size() > 0 else "Scarce"


## Generate detailed planet data
static func generate_planet_detail(planet_seed: int, base_type: int) -> PlanetDetail:
	var detail := PlanetDetail.new()
	detail.seed = planet_seed
	detail.base_type = base_type

	var rng := PRNG.new(planet_seed)
	var type_data: Dictionary = SystemGenerator.PLANET_TYPE_DATA[base_type]

	# Base colors from type
	detail.primary_color = type_data["color"]
	detail.secondary_color = type_data["color"].darkened(0.3)
	detail.accent_color = _generate_accent_color(base_type, rng)

	# Atmosphere based on type
	detail.has_atmosphere = type_data["atmosphere"]
	if detail.has_atmosphere:
		detail.atmosphere_density = _generate_atmosphere_density(base_type, rng)
		detail.atmosphere_composition = _generate_atmosphere_composition(base_type, rng)
		detail.atmosphere_color = _generate_atmosphere_color(base_type, detail.atmosphere_composition, rng)

	# Climate
	_generate_climate(detail, base_type, rng)

	# Surface properties
	_generate_surface(detail, base_type, rng)

	# Hazards
	_generate_hazards(detail, base_type, rng)

	# Resources
	_generate_resources(detail, base_type, rng)

	# POIs
	_generate_poi_config(detail, base_type, rng)

	# Description
	detail.description = _generate_description(detail, rng)

	return detail


static func _generate_accent_color(base_type: int, rng: PRNG) -> Color:
	match base_type:
		SystemGenerator.PlanetType.VOLCANIC:
			return Color(1.0, rng.next_float_range(0.3, 0.6), 0.0)
		SystemGenerator.PlanetType.FROZEN:
			return Color(0.8, 0.9, 1.0)
		SystemGenerator.PlanetType.DESERT:
			return Color(rng.next_float_range(0.8, 1.0), rng.next_float_range(0.6, 0.8), 0.4)
		SystemGenerator.PlanetType.OCEAN:
			return Color(0.1, 0.3, rng.next_float_range(0.6, 0.9))
		SystemGenerator.PlanetType.FOREST, SystemGenerator.PlanetType.TEMPERATE:
			return Color(rng.next_float_range(0.2, 0.5), rng.next_float_range(0.5, 0.8), 0.2)
		_:
			return Color(rng.next_float(), rng.next_float(), rng.next_float())


static func _generate_atmosphere_density(base_type: int, rng: PRNG) -> float:
	match base_type:
		SystemGenerator.PlanetType.BARREN:
			return rng.next_float_range(0.0, 0.1)
		SystemGenerator.PlanetType.GAS_GIANT, SystemGenerator.PlanetType.ICE_GIANT:
			return rng.next_float_range(5.0, 100.0)
		SystemGenerator.PlanetType.TOXIC:
			return rng.next_float_range(1.5, 4.0)
		SystemGenerator.PlanetType.VOLCANIC:
			return rng.next_float_range(0.5, 2.0)
		_:
			return rng.next_float_range(0.7, 1.5)


static func _generate_atmosphere_composition(base_type: int, rng: PRNG) -> String:
	match base_type:
		SystemGenerator.PlanetType.TEMPERATE, SystemGenerator.PlanetType.FOREST:
			return rng.pick(["Nitrogen-Oxygen", "Nitrogen-Oxygen (High O2)", "Nitrogen-Oxygen-Argon"])
		SystemGenerator.PlanetType.TOXIC:
			return rng.pick(["Methane-Ammonia", "Sulfur Dioxide", "Chlorine", "Carbon Monoxide"])
		SystemGenerator.PlanetType.GAS_GIANT:
			return rng.pick(["Hydrogen-Helium", "Hydrogen-Methane", "Hydrogen-Ammonia"])
		SystemGenerator.PlanetType.VOLCANIC:
			return rng.pick(["Sulfur Dioxide", "Carbon Dioxide", "Nitrogen-Sulfur"])
		SystemGenerator.PlanetType.DESERT:
			return rng.pick(["Nitrogen-Carbon Dioxide", "Nitrogen-Oxygen (Thin)", "Carbon Dioxide"])
		SystemGenerator.PlanetType.FROZEN:
			return rng.pick(["Nitrogen", "Nitrogen-Methane", "Carbon Dioxide (Frozen)"])
		_:
			return "Nitrogen-Oxygen"


static func _generate_atmosphere_color(base_type: int, composition: String, rng: PRNG) -> Color:
	if "Methane" in composition:
		return Color(0.3, 0.5, 0.7, 0.4)
	elif "Sulfur" in composition:
		return Color(0.8, 0.7, 0.3, 0.5)
	elif "Chlorine" in composition:
		return Color(0.4, 0.7, 0.3, 0.4)
	elif "Ammonia" in composition:
		return Color(0.6, 0.5, 0.4, 0.3)
	else:
		return Color(0.5, 0.7, 1.0, 0.3)


static func _generate_climate(detail: PlanetDetail, base_type: int, rng: PRNG) -> void:
	match base_type:
		SystemGenerator.PlanetType.VOLCANIC:
			detail.avg_temperature_c = rng.next_float_range(200, 800)
			detail.temperature_variance = rng.next_float_range(50, 200)
		SystemGenerator.PlanetType.FROZEN:
			detail.avg_temperature_c = rng.next_float_range(-200, -30)
			detail.temperature_variance = rng.next_float_range(20, 60)
		SystemGenerator.PlanetType.DESERT:
			detail.avg_temperature_c = rng.next_float_range(25, 60)
			detail.temperature_variance = rng.next_float_range(40, 80)
		SystemGenerator.PlanetType.TEMPERATE, SystemGenerator.PlanetType.FOREST:
			detail.avg_temperature_c = rng.next_float_range(5, 25)
			detail.temperature_variance = rng.next_float_range(20, 40)
		SystemGenerator.PlanetType.OCEAN:
			detail.avg_temperature_c = rng.next_float_range(10, 30)
			detail.temperature_variance = rng.next_float_range(10, 25)
		SystemGenerator.PlanetType.TOXIC:
			detail.avg_temperature_c = rng.next_float_range(-50, 100)
			detail.temperature_variance = rng.next_float_range(30, 80)
		SystemGenerator.PlanetType.SWAMP:
			detail.avg_temperature_c = rng.next_float_range(20, 35)
			detail.temperature_variance = rng.next_float_range(10, 20)
		_:
			detail.avg_temperature_c = rng.next_float_range(-50, 50)
			detail.temperature_variance = rng.next_float_range(20, 50)

	detail.day_length_hours = rng.next_float_range(8, 72)
	detail.year_length_days = rng.next_float_range(100, 800)
	detail.axial_tilt = rng.next_float_range(0, 45)


static func _generate_surface(detail: PlanetDetail, base_type: int, rng: PRNG) -> void:
	match base_type:
		SystemGenerator.PlanetType.OCEAN:
			detail.water_coverage = rng.next_float_range(0.85, 0.99)
			detail.vegetation_coverage = rng.next_float_range(0.0, 0.1)
			detail.terrain_roughness = rng.next_float_range(0.1, 0.3)
		SystemGenerator.PlanetType.DESERT:
			detail.water_coverage = rng.next_float_range(0.0, 0.05)
			detail.vegetation_coverage = rng.next_float_range(0.0, 0.1)
			detail.terrain_roughness = rng.next_float_range(0.3, 0.7)
		SystemGenerator.PlanetType.FOREST:
			detail.water_coverage = rng.next_float_range(0.2, 0.5)
			detail.vegetation_coverage = rng.next_float_range(0.7, 0.95)
			detail.terrain_roughness = rng.next_float_range(0.3, 0.6)
		SystemGenerator.PlanetType.TEMPERATE:
			detail.water_coverage = rng.next_float_range(0.4, 0.7)
			detail.vegetation_coverage = rng.next_float_range(0.3, 0.7)
			detail.terrain_roughness = rng.next_float_range(0.3, 0.7)
		SystemGenerator.PlanetType.SWAMP:
			detail.water_coverage = rng.next_float_range(0.5, 0.8)
			detail.vegetation_coverage = rng.next_float_range(0.6, 0.9)
			detail.terrain_roughness = rng.next_float_range(0.1, 0.3)
		SystemGenerator.PlanetType.VOLCANIC:
			detail.water_coverage = 0.0
			detail.vegetation_coverage = 0.0
			detail.terrain_roughness = rng.next_float_range(0.6, 0.9)
		SystemGenerator.PlanetType.FROZEN:
			detail.water_coverage = rng.next_float_range(0.0, 0.3)  # Ice
			detail.vegetation_coverage = rng.next_float_range(0.0, 0.05)
			detail.terrain_roughness = rng.next_float_range(0.2, 0.6)
		_:
			detail.water_coverage = rng.next_float_range(0.0, 0.3)
			detail.vegetation_coverage = rng.next_float_range(0.0, 0.1)
			detail.terrain_roughness = rng.next_float_range(0.3, 0.7)


static func _generate_hazards(detail: PlanetDetail, base_type: int, rng: PRNG) -> void:
	# Type-specific hazards
	match base_type:
		SystemGenerator.PlanetType.VOLCANIC:
			detail.hazards.append(Hazard.EXTREME_HEAT)
			if rng.next_bool(0.5):
				detail.hazards.append(Hazard.SEISMIC_ACTIVITY)
		SystemGenerator.PlanetType.FROZEN:
			detail.hazards.append(Hazard.EXTREME_COLD)
			if rng.next_bool(0.3):
				detail.hazards.append(Hazard.ELECTRICAL_STORMS)
		SystemGenerator.PlanetType.TOXIC:
			detail.hazards.append(Hazard.TOXIC_ATMOSPHERE)
			if rng.next_bool(0.4):
				detail.hazards.append(Hazard.ACID_RAIN)
		SystemGenerator.PlanetType.DESERT:
			if rng.next_bool(0.6):
				detail.hazards.append(Hazard.EXTREME_HEAT)
			if rng.next_bool(0.3):
				detail.hazards.append(Hazard.ELECTRICAL_STORMS)

	# Random additional hazards
	if rng.next_bool(0.15):
		detail.hazards.append(Hazard.RADIATION)
	if rng.next_bool(0.2):
		detail.hazards.append(Hazard.HOSTILE_FAUNA)
	if rng.next_bool(0.1):
		detail.hazards.append(Hazard.SENTINELS)
	if rng.next_bool(0.1):
		detail.hazards.append(Hazard.IMPERIAL_PRESENCE)
	if rng.next_bool(0.15):
		detail.hazards.append(Hazard.PIRATE_ACTIVITY)


static func _generate_resources(detail: PlanetDetail, base_type: int, rng: PRNG) -> void:
	# All planets have some common metals
	detail.resources[ResourceType.COMMON_METALS] = rng.next_float_range(0.2, 0.8)

	# Type-specific resources
	match base_type:
		SystemGenerator.PlanetType.VOLCANIC:
			detail.resources[ResourceType.RARE_METALS] = rng.next_float_range(0.3, 0.8)
			detail.resources[ResourceType.CRYSTALS] = rng.next_float_range(0.2, 0.6)
		SystemGenerator.PlanetType.FROZEN:
			detail.resources[ResourceType.WATER] = rng.next_float_range(0.5, 1.0)
			detail.resources[ResourceType.FUEL] = rng.next_float_range(0.1, 0.4)
		SystemGenerator.PlanetType.FOREST, SystemGenerator.PlanetType.TEMPERATE:
			detail.resources[ResourceType.ORGANICS] = rng.next_float_range(0.4, 0.9)
			detail.resources[ResourceType.WATER] = rng.next_float_range(0.3, 0.7)
		SystemGenerator.PlanetType.OCEAN:
			detail.resources[ResourceType.WATER] = 1.0
			detail.resources[ResourceType.ORGANICS] = rng.next_float_range(0.2, 0.5)
		SystemGenerator.PlanetType.BARREN, SystemGenerator.PlanetType.ROCKY:
			detail.resources[ResourceType.RARE_METALS] = rng.next_float_range(0.1, 0.5)
			detail.resources[ResourceType.CRYSTALS] = rng.next_float_range(0.1, 0.4)

	# Rare resources (low chance)
	if rng.next_bool(0.02):
		detail.resources[ResourceType.KYBER_CRYSTALS] = rng.next_float_range(0.1, 0.4)
	if rng.next_bool(0.01):
		detail.resources[ResourceType.BESKAR] = rng.next_float_range(0.1, 0.3)
	if rng.next_bool(0.05):
		detail.resources[ResourceType.ARTIFACTS] = rng.next_float_range(0.1, 0.4)
	if rng.next_bool(0.1):
		detail.resources[ResourceType.TECHNOLOGY] = rng.next_float_range(0.1, 0.5)


static func _generate_poi_config(detail: PlanetDetail, base_type: int, rng: PRNG) -> void:
	# Base POI density by habitability
	var type_data: Dictionary = SystemGenerator.PLANET_TYPE_DATA[base_type]
	if type_data["habitable"]:
		detail.poi_density = rng.next_float_range(0.3, 0.8)
	else:
		detail.poi_density = rng.next_float_range(0.05, 0.3)

	# Available POI types
	detail.poi_types.append(POIType.CRASH_SITE)
	detail.poi_types.append(POIType.CAVE_SYSTEM)

	if type_data["habitable"]:
		detail.poi_types.append(POIType.SETTLEMENT)
		detail.poi_types.append(POIType.TRADING_POST)
		if rng.next_bool(0.5):
			detail.poi_types.append(POIType.CANTINA)

	if detail.resources.get(ResourceType.RARE_METALS, 0) > 0.3 or detail.resources.get(ResourceType.CRYSTALS, 0) > 0.3:
		detail.poi_types.append(POIType.MINING_FACILITY)

	if Hazard.IMPERIAL_PRESENCE in detail.hazards:
		detail.poi_types.append(POIType.IMPERIAL_BASE)
	else:
		if rng.next_bool(0.2):
			detail.poi_types.append(POIType.REBEL_OUTPOST)

	if detail.resources.get(ResourceType.KYBER_CRYSTALS, 0) > 0:
		if rng.next_bool(0.5):
			detail.poi_types.append(POIType.JEDI_TEMPLE)

	if detail.resources.get(ResourceType.ARTIFACTS, 0) > 0:
		if rng.next_bool(0.3):
			detail.poi_types.append(POIType.SITH_TOMB)
		detail.poi_types.append(POIType.RUINS)

	if Hazard.HOSTILE_FAUNA in detail.hazards:
		detail.poi_types.append(POIType.WILDLIFE_DEN)


static func _generate_description(detail: PlanetDetail, rng: PRNG) -> String:
	var parts: Array[String] = []

	# Climate description
	if detail.avg_temperature_c > 100:
		parts.append("A scorching world with surface temperatures exceeding %d°C." % int(detail.avg_temperature_c))
	elif detail.avg_temperature_c > 40:
		parts.append("A hot, arid world baked by its star.")
	elif detail.avg_temperature_c < -100:
		parts.append("A frozen wasteland where temperatures plunge below %d°C." % int(detail.avg_temperature_c))
	elif detail.avg_temperature_c < -20:
		parts.append("A cold world locked in perpetual winter.")
	elif detail.water_coverage > 0.8:
		parts.append("A water world with vast oceans covering the surface.")
	elif detail.vegetation_coverage > 0.6:
		parts.append("A verdant world teeming with plant life.")
	else:
		parts.append("A world of varied terrain and moderate climate.")

	# Hazard warnings
	if detail.hazards.size() > 0:
		var hazard_names := detail.get_hazard_names()
		if hazard_names.size() == 1:
			parts.append("Warning: %s detected." % hazard_names[0])
		else:
			parts.append("Warning: Multiple hazards including %s." % ", ".join(hazard_names.slice(0, 2)))

	# Resource notes
	var rich_resources: Array[String] = []
	# Sort keys for deterministic iteration order
	var resource_keys := detail.resources.keys()
	resource_keys.sort()
	for r in resource_keys:
		if detail.resources[r] > 0.6:
			rich_resources.append(RESOURCE_DATA[r]["name"])
	if rich_resources.size() > 0:
		parts.append("Rich in %s." % ", ".join(rich_resources))

	return " ".join(parts)
