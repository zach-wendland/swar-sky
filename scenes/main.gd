## main.gd - Main entry point and view manager
## Handles navigation between galaxy map, system view, system space, and planet surface
extends Node


enum ViewState {
	GALAXY_MAP,
	SYSTEM_VIEW,      # 2D orbital overview
	SYSTEM_SPACE,     # 3D spaceflight
	PLANET_SURFACE,
}

var current_view: ViewState = ViewState.GALAXY_MAP
var current_sector: Vector3i = Vector3i.ZERO
var current_system_index: int = -1
var current_planet_data: Dictionary = {}  # Stores planet info for surface view
var last_ship_planet: SystemGenerator.OrbitalBody = null  # Planet we took off from

# Scene references
var galaxy_map: Node2D = null
var system_view: Node2D = null
var system_space: Node3D = null
var planet_surface: Node3D = null

# UI overlay
var view_indicator: Label = null

# Preloaded scenes
const GalaxyMapScene := preload("res://scenes/galaxy_map/galaxy_map.tscn")
const SystemViewScene := preload("res://scenes/system_view/system_view.tscn")
const SystemSpaceScene := preload("res://scenes/system_space/system_space.tscn")
const PlanetSurfaceScene := preload("res://scenes/planet_surface/planet_surface.tscn")

# View display names
const VIEW_NAMES: Dictionary = {
	ViewState.GALAXY_MAP: "Galaxy Map",
	ViewState.SYSTEM_VIEW: "System Map (2D)",
	ViewState.SYSTEM_SPACE: "System Space (3D)",
	ViewState.PLANET_SURFACE: "Planet Surface",
}


func _ready() -> void:
	# Initialize the seed stack
	SeedStack.initialize_from_string("swar-sky-alpha-001")

	# Create persistent view indicator
	_create_view_indicator()

	# Start with galaxy map
	_show_galaxy_map()


func _create_view_indicator() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ViewIndicatorLayer"
	canvas.layer = 100  # On top of everything
	add_child(canvas)

	view_indicator = Label.new()
	view_indicator.name = "ViewIndicator"
	view_indicator.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.8))
	view_indicator.add_theme_font_size_override("font_size", 12)
	view_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	view_indicator.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Position at top-right corner
	view_indicator.anchor_left = 1.0
	view_indicator.anchor_right = 1.0
	view_indicator.offset_left = -200
	view_indicator.offset_right = -10
	view_indicator.offset_top = 10
	view_indicator.offset_bottom = 30

	canvas.add_child(view_indicator)


func _update_view_indicator() -> void:
	if view_indicator:
		var view_name: String = VIEW_NAMES.get(current_view, "Unknown")
		view_indicator.text = view_name


func _show_galaxy_map() -> void:
	_clear_views()

	galaxy_map = GalaxyMapScene.instantiate()
	add_child(galaxy_map)

	# Connect signals
	galaxy_map.system_requested.connect(_on_system_requested)

	# Restore last sector if returning
	if current_sector != Vector3i.ZERO:
		galaxy_map.go_to_sector(current_sector)

	current_view = ViewState.GALAXY_MAP
	_update_view_indicator()
	print("[Main] Showing galaxy map")


func _show_system_view(sector: Vector3i, system_index: int) -> void:
	_clear_views()

	current_sector = sector
	current_system_index = system_index

	system_view = SystemViewScene.instantiate()
	add_child(system_view)

	# Connect signals
	system_view.back_to_galaxy_requested.connect(_on_back_to_galaxy)
	system_view.planet_detail_requested.connect(_on_planet_detail_requested_2d)

	# Load the system
	system_view.load_system(sector, system_index)

	current_view = ViewState.SYSTEM_VIEW
	_update_view_indicator()
	print("[Main] Showing system view for system ", system_index, " in sector ", sector)


func _show_system_space(sector: Vector3i, system_index: int, spawn_near: SystemGenerator.OrbitalBody = null) -> void:
	_clear_views()

	current_sector = sector
	current_system_index = system_index

	system_space = SystemSpaceScene.instantiate()
	add_child(system_space)

	# Connect signals
	system_space.back_to_galaxy_requested.connect(_on_back_to_galaxy)
	system_space.landing_requested.connect(_on_landing_requested_3d)

	# Load the system
	system_space.load_system(sector, system_index, spawn_near)

	current_view = ViewState.SYSTEM_SPACE
	_update_view_indicator()
	print("[Main] Entering system space for system ", system_index, " in sector ", sector)


func _show_planet_surface(planet_data: Dictionary) -> void:
	_clear_views()

	current_planet_data = planet_data

	planet_surface = PlanetSurfaceScene.instantiate()
	add_child(planet_surface)

	# Connect signals
	planet_surface.back_requested.connect(_on_back_to_space)

	# Initialize planet
	planet_surface.initialize(
		planet_data["seed"],
		planet_data["type"],
		planet_data["name"],
		planet_data.get("detail", null)
	)

	current_view = ViewState.PLANET_SURFACE
	_update_view_indicator()
	print("[Main] Landing on planet: ", planet_data["name"])


func _clear_views() -> void:
	if galaxy_map:
		galaxy_map.queue_free()
		galaxy_map = null

	if system_view:
		system_view.queue_free()
		system_view = null

	if system_space:
		system_space.queue_free()
		system_space = null

	if planet_surface:
		planet_surface.queue_free()
		planet_surface = null


func _on_system_requested(sector: Vector3i, system_index: int) -> void:
	# Go directly to 3D space flight
	_show_system_space(sector, system_index)


func _on_back_to_galaxy() -> void:
	_show_galaxy_map()

	# Re-select the system we were viewing
	if galaxy_map and current_system_index >= 0:
		galaxy_map.select_star_by_index(current_system_index)


func _on_back_to_space() -> void:
	# Return to space, spawning near the planet we were on
	_show_system_space(current_sector, current_system_index, last_ship_planet)


## Landing from 2D system view (legacy)
func _on_planet_detail_requested_2d(body: SystemGenerator.OrbitalBody, detail: PlanetGenerator.PlanetDetail) -> void:
	_attempt_landing(body, detail)


## Landing from 3D space flight
func _on_landing_requested_3d(body: SystemGenerator.OrbitalBody, detail: PlanetGenerator.PlanetDetail) -> void:
	_attempt_landing(body, detail)


## Shared landing logic
func _attempt_landing(body: SystemGenerator.OrbitalBody, detail: PlanetGenerator.PlanetDetail) -> void:
	# Check if planet is landable
	var type_data: Dictionary = SystemGenerator.PLANET_TYPE_DATA.get(body.planet_type, {})
	var is_landable: bool = type_data.get("habitable", false) or body.planet_type in [
		SystemGenerator.PlanetType.BARREN,
		SystemGenerator.PlanetType.ROCKY,
		SystemGenerator.PlanetType.DESERT,
		SystemGenerator.PlanetType.FROZEN,
		SystemGenerator.PlanetType.VOLCANIC,
	]

	if not is_landable:
		print("[Main] Cannot land on ", type_data.get("name", "this planet"), " - no solid surface")
		return

	# Store which planet we're landing on (for takeoff)
	last_ship_planet = body

	# Transition to planet surface
	_show_planet_surface({
		"seed": body.seed,
		"type": body.planet_type,
		"name": body.name,
		"detail": detail,
		"radius_km": body.radius_km,
		"gravity": body.gravity,
	})


func _input(event: InputEvent) -> void:
	# Global shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_run_quick_tests()
			KEY_F2:
				_print_debug_info()
			KEY_M:
				# Toggle between 2D/3D system view
				_toggle_system_view_mode()


## Toggle between 2D system view and 3D space flight
func _toggle_system_view_mode() -> void:
	match current_view:
		ViewState.SYSTEM_VIEW:
			_show_system_space(current_sector, current_system_index)
		ViewState.SYSTEM_SPACE:
			_show_system_view(current_sector, current_system_index)


func _run_quick_tests() -> void:
	print("\n=== Quick Determinism Test ===")

	# Test sector regeneration
	var sector := Vector3i(5, 10, 15)
	var stars1 := GalaxyGenerator.generate_sector(sector)
	var stars2 := GalaxyGenerator.generate_sector(sector)

	if stars1.size() != stars2.size():
		print("FAIL: Different star counts")
		return

	for i in range(stars1.size()):
		if stars1[i].seed != stars2[i].seed:
			print("FAIL: Star ", i, " has different seed")
			return

	print("PASS: Sector regeneration is deterministic")

	# Test system generation
	var sys1 := SystemGenerator.generate_system(sector, 0)
	var sys2 := SystemGenerator.generate_system(sector, 0)

	if sys1.bodies.size() != sys2.bodies.size():
		print("FAIL: Different planet counts")
		return

	print("PASS: System regeneration is deterministic")

	# Test terrain generation
	var terrain_config := TerrainGenerator.create_config(12345, SystemGenerator.PlanetType.TEMPERATE)
	var h1 := TerrainGenerator.get_height_at_world(terrain_config, Vector2(100, 200))
	var h2 := TerrainGenerator.get_height_at_world(terrain_config, Vector2(100, 200))

	if abs(h1 - h2) > 0.0001:
		print("FAIL: Terrain height not deterministic")
		return

	print("PASS: Terrain generation is deterministic")

	print("=== All Tests Passed ===\n")


func _print_debug_info() -> void:
	print("\n=== Debug Info ===")
	print("View: ", ViewState.keys()[current_view])
	print("Sector: ", current_sector)
	print("System: ", current_system_index)
	print("Global Seed: ", SeedStack.global_seed)

	match current_view:
		ViewState.SYSTEM_VIEW:
			if system_view and system_view.system_data:
				var sys: SystemGenerator.SystemData = system_view.system_data
				print("System: ", sys.star_name)
				print("Planets: ", sys.bodies.size())
				for body in sys.bodies:
					var type_name: String = SystemGenerator.PLANET_TYPE_DATA[body.planet_type]["name"]
					print("  - ", body.name, " (", type_name, ")")

		ViewState.SYSTEM_SPACE:
			if system_space and system_space.system_data:
				var sys: SystemGenerator.SystemData = system_space.system_data
				print("System: ", sys.star_name)
				print("Planets: ", sys.bodies.size())
				if system_space.ship:
					var ship_data: Dictionary = system_space.ship.get_ship_data()
					print("Ship speed: ", ship_data.get("speed", 0))
					print("Ship pos: ", ship_data.get("position", Vector3.ZERO))

		ViewState.PLANET_SURFACE:
			if current_planet_data:
				print("Planet: ", current_planet_data.get("name", "Unknown"))
				var type_name: String = SystemGenerator.PLANET_TYPE_DATA.get(
					current_planet_data.get("type", 0), {}
				).get("name", "Unknown")
				print("Type: ", type_name)

	print("==================\n")
