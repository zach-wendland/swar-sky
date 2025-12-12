## planet_surface.gd - 3D planet surface exploration scene
## Manages terrain streaming, character, POIs, objectives, and UI
extends Node3D


signal back_requested()
signal mission_completed(collected_artifacts: Array)
signal initialized()


## Planet data
var planet_seed: int = 0
var planet_type: int = 0
var planet_name: String = ""
var planet_detail: PlanetGenerator.PlanetDetail = null

## Child references
@onready var tile_streamer: TileStreamer = $TileStreamer
@onready var character: CharacterController = $Character
@onready var environment_light: DirectionalLight3D = $Sun
@onready var hud: Control = $UI/HUD
@onready var planet_label: Label = $UI/HUD/PlanetLabel
@onready var biome_label: Label = $UI/HUD/BiomeLabel
@onready var position_label: Label = $UI/HUD/PositionLabel
@onready var back_button: Button = $UI/BackButton

## POI and gameplay systems (created dynamically)
## Note: Using Variant types to avoid parse-time dependency on autoloads
var poi_renderer = null  # POIRenderer
var objective_system = null  # ObjectiveSystem
var ship_landing = null  # ShipLanding
var exploration_hud = null  # ExplorationHUD

## POI data
var pois: Array = []  # Array of POIGenerator.POIData
var ship_spawn_position: Vector3 = Vector3.ZERO

## Environment settings by planet type
const ENVIRONMENT_PRESETS: Dictionary = {
	SystemGenerator.PlanetType.DESERT: {
		"sun_color": Color(1.0, 0.95, 0.8),
		"ambient_color": Color(0.4, 0.35, 0.3),
		"sky_color": Color(0.8, 0.7, 0.5),
		"fog_density": 0.001,
	},
	SystemGenerator.PlanetType.FROZEN: {
		"sun_color": Color(0.9, 0.95, 1.0),
		"ambient_color": Color(0.4, 0.45, 0.5),
		"sky_color": Color(0.6, 0.7, 0.8),
		"fog_density": 0.003,
	},
	SystemGenerator.PlanetType.VOLCANIC: {
		"sun_color": Color(1.0, 0.6, 0.4),
		"ambient_color": Color(0.3, 0.2, 0.15),
		"sky_color": Color(0.4, 0.2, 0.1),
		"fog_density": 0.005,
	},
	SystemGenerator.PlanetType.FOREST: {
		"sun_color": Color(1.0, 1.0, 0.9),
		"ambient_color": Color(0.3, 0.4, 0.3),
		"sky_color": Color(0.5, 0.7, 0.9),
		"fog_density": 0.002,
	},
	SystemGenerator.PlanetType.OCEAN: {
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_color": Color(0.3, 0.4, 0.5),
		"sky_color": Color(0.4, 0.6, 0.9),
		"fog_density": 0.002,
	},
	SystemGenerator.PlanetType.SWAMP: {
		"sun_color": Color(0.9, 0.9, 0.7),
		"ambient_color": Color(0.25, 0.3, 0.25),
		"sky_color": Color(0.4, 0.45, 0.4),
		"fog_density": 0.008,
	},
}


func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	# Connect character position updates
	if character:
		character.position_changed.connect(_on_character_moved)
		character.tile_streamer = tile_streamer


func _process(_delta: float) -> void:
	_update_hud()
	_update_gameplay_systems()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_try_exit()
			KEY_E:
				_handle_interaction()
			KEY_F3:
				_print_debug_info()


## Initialize planet surface
func initialize(p_seed: int, p_type: int, p_name: String, detail: PlanetGenerator.PlanetDetail = null) -> void:
	planet_seed = p_seed
	planet_type = p_type
	planet_name = p_name
	planet_detail = detail

	# Generate detail if not provided
	if planet_detail == null:
		planet_detail = PlanetGenerator.generate_planet_detail(p_seed, p_type)

	# Update planet name label
	if planet_label:
		var type_data: Dictionary = SystemGenerator.PLANET_TYPE_DATA.get(p_type, {})
		var type_name: String = type_data.get("name", "Unknown")
		planet_label.text = "%s (%s)" % [p_name, type_name]

	# Initialize terrain
	if tile_streamer:
		var e2e_mission: bool = bool(get_meta(&"web_e2e_mission", false))
		if e2e_mission:
			tile_streamer.view_distance = int(get_meta(&"web_e2e_view_distance", 0))
			tile_streamer.tile_resolution = int(get_meta(&"web_e2e_tile_resolution", 17))
			tile_streamer.update_interval = float(get_meta(&"web_e2e_update_interval", 9999.0))

		var immediate_load: bool = not bool(get_meta(&"web_e2e_no_immediate_tiles", false))
		tile_streamer.initialize(p_seed, p_type, planet_detail, immediate_load)

	# Set environment
	_setup_environment()

	# Find spawn point and place ship there
	ship_spawn_position = _find_spawn_point()

	# Position character near ship
	if character:
		character.set_character_position(ship_spawn_position + Vector3(5, 2, 5))

	# Initialize gameplay systems
	_setup_gameplay_systems()


## Setup lighting and atmosphere
func _setup_environment() -> void:
	var preset: Dictionary = ENVIRONMENT_PRESETS.get(planet_type, {
		"sun_color": Color(1.0, 1.0, 0.95),
		"ambient_color": Color(0.35, 0.4, 0.45),
		"sky_color": Color(0.5, 0.6, 0.8),
		"fog_density": 0.001,
	})

	if environment_light:
		environment_light.light_color = preset["sun_color"]
		environment_light.light_energy = 1.2


## Setup POIs, ship, objectives, and HUD
## Note: Using load() to avoid parse-time class resolution issues with autoload dependencies
func _setup_gameplay_systems() -> void:
	# Load classes dynamically to avoid autoload dependency at parse time
	var POIGeneratorClass = load("res://packages/procgen/poi_generator.gd")
	var POIRendererClass = load("res://packages/render/poi_renderer.gd")
	var ShipLandingClass = load("res://packages/gameplay/ship_landing.gd")
	var ObjectiveSystemClass = load("res://packages/gameplay/objective_system.gd")
	var ExplorationHUDClass = load("res://packages/ui/exploration_hud.gd")

	# Generate POIs
	var terrain_config = tile_streamer.terrain_config if tile_streamer else null
	if terrain_config and POIGeneratorClass:
		pois = POIGeneratorClass.generate_planet_pois(planet_seed, planet_type, terrain_config)

	# Create POI renderer
	if POIRendererClass:
		poi_renderer = POIRendererClass.new()
		poi_renderer.name = "POIRenderer"
		add_child(poi_renderer)
		poi_renderer.initialize(pois)
		# Connect POI signals
		poi_renderer.poi_entered.connect(_on_poi_entered)
		poi_renderer.artifact_collected.connect(_on_artifact_collected)

	# Create landed ship
	if ShipLandingClass:
		ship_landing = ShipLandingClass.new()
		ship_landing.name = "LandedShip"
		add_child(ship_landing)
		ship_landing.set_landing_position(ship_spawn_position)
		ship_landing.board_requested.connect(_on_board_ship)

	# Create objective system
	if ObjectiveSystemClass:
		objective_system = ObjectiveSystemClass.new()
		objective_system.name = "ObjectiveSystem"
		add_child(objective_system)
		objective_system.generate_planet_objectives(pois, ship_spawn_position)
		# Connect objective signals
		objective_system.objective_completed.connect(_on_objective_completed)
		objective_system.artifact_collected.connect(_on_objective_artifact_collected)
		objective_system.all_objectives_completed.connect(_on_all_objectives_completed)

	# Create exploration HUD
	if ExplorationHUDClass:
		exploration_hud = ExplorationHUDClass.new()
		exploration_hud.name = "ExplorationHUD"
		add_child(exploration_hud)

	# Set HUD references
	if exploration_hud:
		if character:
			exploration_hud.set_camera(character.get_camera())
		exploration_hud.set_objective_system(objective_system)
		exploration_hud.set_ship_landing(ship_landing)
		exploration_hud.set_poi_renderer(poi_renderer)

	print("[PlanetSurface] Initialized with %d POIs" % pois.size())
	initialized.emit()

	if bool(get_meta(&"web_e2e_mission", false)):
		set_meta(&"web_e2e_initialized", true)


## Find a valid spawn location (for ship landing)
func _find_spawn_point() -> Vector3:
	var rng := PRNG.new(planet_seed + 12345)
	var config := tile_streamer.terrain_config if tile_streamer else null

	# Try several random points
	for _attempt in range(20):
		var x := rng.next_float_range(-100, 100)
		var z := rng.next_float_range(-100, 100)

		var height := tile_streamer.get_height_at(Vector3(x, 0, z)) if tile_streamer else 10.0
		var biome := tile_streamer.get_biome_at(Vector3(x, 0, z)) if tile_streamer else 0

		# Check if valid spawn (above water, walkable biome)
		if config and height > config.sea_level * tile_streamer.height_scale:
			var biome_data: Dictionary = TerrainGenerator.BIOME_DATA.get(biome, {})
			if biome_data.get("walkable", true):
				return Vector3(x, height + 0.5, z)

	# Fallback: spawn at origin, elevated
	var fallback_height := tile_streamer.get_height_at(Vector3.ZERO) if tile_streamer else 10.0
	return Vector3(0, fallback_height + 0.5, 0)


## Update gameplay systems with player position
func _update_gameplay_systems() -> void:
	if not character:
		return

	var pos := character.get_world_position()
	var forward := -character.global_transform.basis.z

	if poi_renderer:
		poi_renderer.update_player_position(pos)

	if ship_landing:
		ship_landing.update_player_position(pos)

	if objective_system:
		objective_system.update_player_position(pos)

	if exploration_hud:
		exploration_hud.update_player_state(pos, forward)


## Update HUD display
func _update_hud() -> void:
	if not character:
		return

	var pos := character.get_world_position()

	# Update position label
	if position_label:
		position_label.text = "Position: %.0f, %.0f, %.0f" % [pos.x, pos.y, pos.z]

	# Update biome label
	if biome_label and tile_streamer:
		var biome := tile_streamer.get_biome_at(pos)
		var biome_data: Dictionary = TerrainGenerator.BIOME_DATA.get(biome, {"name": "Unknown"})
		biome_label.text = "Biome: %s" % biome_data["name"]


## Handle E key interaction
func _handle_interaction() -> void:
	# Try to collect artifact
	if poi_renderer and poi_renderer.can_collect_artifact():
		if poi_renderer.try_collect_artifact():
			return

	# Try to board ship
	if ship_landing and ship_landing.get_can_board():
		if objective_system and objective_system.can_leave_planet():
			ship_landing.try_board()
		else:
			print("[PlanetSurface] Collect an artifact before leaving!")


## Try to exit (ESC key)
func _try_exit() -> void:
	# For now, just emit back_requested
	# Could add confirmation dialog
	back_requested.emit()


## POI entered callback
func _on_poi_entered(poi) -> void:  # POIGenerator.POIData
	print("[PlanetSurface] Discovered: %s" % poi.get_type_data().get("name", "Unknown"))

	if objective_system:
		objective_system.on_poi_discovered(poi)


## Artifact collected callback
func _on_artifact_collected(poi, artifact_name: String) -> void:  # poi: POIGenerator.POIData
	print("[PlanetSurface] Collected: %s" % artifact_name)

	if objective_system:
		objective_system.on_artifact_collected(poi, artifact_name)

	if exploration_hud:
		exploration_hud.show_artifact_collected(artifact_name)


## Objective completed callback
func _on_objective_completed(objective) -> void:  # ObjectiveSystem.Objective
	print("[PlanetSurface] Objective completed: %s" % objective.title)


## Objective artifact collected callback (from objective system)
func _on_objective_artifact_collected(artifact_name: String, _poi_name: String) -> void:
	# Already handled in _on_artifact_collected
	pass


## All objectives completed callback
func _on_all_objectives_completed() -> void:
	print("[PlanetSurface] All objectives completed!")


## Board ship callback
func _on_board_ship() -> void:
	print("[PlanetSurface] Boarding ship...")

	# Collect artifacts summary
	var artifacts: Array = []
	if objective_system:
		artifacts = objective_system.collected_artifacts.duplicate()

	mission_completed.emit(artifacts)
	back_requested.emit()


func _on_character_moved(_pos: Vector3) -> void:
	pass


func _on_back_pressed() -> void:
	back_requested.emit()


func _print_debug_info() -> void:
	print("\n=== Planet Surface Debug ===")
	print("Planet: ", planet_name, " (seed: ", planet_seed, ")")
	print("Type: ", SystemGenerator.PLANET_TYPE_DATA.get(planet_type, {}).get("name", "Unknown"))

	if character:
		var pos := character.get_world_position()
		print("Character position: ", pos)
		print("Grounded: ", character.is_grounded())

	print("POIs: ", pois.size())
	for poi in pois:
		var type_name: String = poi.get_type_data().get("name", "Unknown")
		var status: String = "Collected" if poi.artifact_collected else ("Discovered" if poi.discovered else "Undiscovered")
		print("  - %s at %.0f, %.0f (%s)" % [type_name, poi.position.x, poi.position.z, status])

	if objective_system:
		print("Objective: ", objective_system.get_objective_text())
		print("Collected: ", objective_system.collected_artifacts)

	if tile_streamer:
		tile_streamer.print_stats()

	if planet_detail:
		print("Temperature: ", planet_detail.avg_temperature_c, "C")
		print("Hazards: ", planet_detail.get_hazard_names())

	print("============================\n")
