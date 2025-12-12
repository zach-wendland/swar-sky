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
	if _try_run_web_e2e():
		return

	# Initialize the seed stack
	SeedStack.initialize_from_string("swar-sky-alpha-001")

	# Create persistent view indicator
	_create_view_indicator()

	# Start with galaxy map
	_show_galaxy_map()

func _try_run_web_e2e() -> bool:
	if not OS.has_feature("web"):
		return false

	var enabled: bool = false
	var enabled_raw: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('e2e')")
	var mode: String = ""
	if enabled_raw != null:
		var s := str(enabled_raw)
		enabled = s != "" and s != "0" and s.to_lower() != "false"
		mode = s.to_lower()

	if not enabled:
		return false

	if mode == "mission":
		call_deferred("_run_web_e2e_mission")
		return true

	var config := TerrainGenerator.create_config(77777, SystemGenerator.PlanetType.TEMPERATE)
	var resolution := 33
	var tiles_to_generate := 3

	var start_usec := Time.get_ticks_usec()
	for i in range(tiles_to_generate):
		var _tile := TerrainGenerator.generate_tile(config, Vector2i(i, 0), 0, resolution)
	var elapsed_usec := Time.get_ticks_usec() - start_usec

	var per_tile_ms := (float(elapsed_usec) / 1000.0) / float(tiles_to_generate)

	var profiled_tile := TerrainGenerator.generate_tile(config, Vector2i(999, 0), 0, resolution, true)
	var hash_calls := 0
	if profiled_tile.profile != null:
		hash_calls = profiled_tile.profile.hash_calls

	var result := {
		"resolution": resolution,
		"tiles": tiles_to_generate,
		"elapsed_ms": float(elapsed_usec) / 1000.0,
		"per_tile_ms": per_tile_ms,
		"hash_calls": hash_calls,
	}

	var json: String = JSON.stringify(result)
	print("[E2E] RESULT ", json)

	var json_literal: String = JSON.stringify(json) # quoted JS string literal
	JavaScriptBridge.eval("window.__SWAR_E2E_RESULT__ = JSON.parse(" + json_literal + ");")
	JavaScriptBridge.eval("window.__SWAR_E2E_DONE__ = true;")

	return true


func _web_e2e_publish_result(result: Dictionary) -> void:
	var json: String = JSON.stringify(result)
	print("[E2E] RESULT ", json)

	var json_literal: String = JSON.stringify(json) # quoted JS string literal
	JavaScriptBridge.eval("window.__SWAR_E2E_RESULT__ = JSON.parse(" + json_literal + ");")
	JavaScriptBridge.eval("window.__SWAR_E2E_DONE__ = true;")


func _run_web_e2e_mission() -> void:
	var start_usec: int = Time.get_ticks_usec()

	SeedStack.initialize_from_string("swar-sky-e2e-mission-001")

	var planet_seed: int = 77777
	var planet_type: int = SystemGenerator.PlanetType.TEMPERATE
	var planet_name: String = "E2E Planet"

	planet_surface = PlanetSurfaceScene.instantiate()
	planet_surface.set_meta(&"web_e2e_mission", true)
	planet_surface.set_meta(&"web_e2e_no_immediate_tiles", true)
	planet_surface.set_meta(&"web_e2e_view_distance", 0)
	planet_surface.set_meta(&"web_e2e_tile_resolution", 17)
	planet_surface.set_meta(&"web_e2e_update_interval", 9999.0)
	add_child(planet_surface)

	var done: bool = false
	var collected: Array = []

	planet_surface.mission_completed.connect(func(artifacts: Array) -> void:
		done = true
		collected = artifacts
	)

	planet_surface.call_deferred("initialize", planet_seed, planet_type, planet_name, null)

	var error: String = ""

	var init_timeout_ms: int = 30_000
	var init_start_ms: int = Time.get_ticks_msec()
	while not bool(planet_surface.has_meta(&"web_e2e_initialized")) and (Time.get_ticks_msec() - init_start_ms) < init_timeout_ms:
		await get_tree().process_frame

	if not bool(planet_surface.has_meta(&"web_e2e_initialized")):
		error = "init_timeout"

	# Fallback: if we didn't receive the meta marker, wait a couple of frames and continue with null checks below.
	await get_tree().process_frame
	await get_tree().process_frame

	var step_discovered: bool = false
	var step_collected: bool = false
	var step_boarded: bool = false
	var poi_name: String = ""

	var objective_types := {
		"start": -1,
		"after_discover": -1,
		"after_collect": -1,
	}

	if error == "" and (planet_surface.pois == null or planet_surface.pois.is_empty()):
		error = "no_pois_generated"
	elif error == "" and planet_surface.poi_renderer == null:
		error = "poi_renderer_missing"
	elif error == "" and planet_surface.objective_system == null:
		error = "objective_system_missing"
	elif error == "" and planet_surface.ship_landing == null:
		error = "ship_landing_missing"
	elif error == "" and planet_surface.character == null:
		error = "character_missing"

	if error == "":
		var active0 = planet_surface.objective_system.get_active_objective()
		objective_types["start"] = int(active0.objective_type) if active0 != null else -1

		var expected_explore: int = int(planet_surface.objective_system.ObjectiveType.EXPLORE_POI)
		if objective_types["start"] != expected_explore:
			error = "unexpected_start_objective"

	if error == "":
		# Sanity: you cannot leave before collecting.
		var ship_pos0: Vector3 = planet_surface.ship_spawn_position
		planet_surface.ship_landing.update_player_position(ship_pos0)
		planet_surface.objective_system.update_player_position(ship_pos0)
		if bool(planet_surface.objective_system.can_leave_planet()):
			error = "left_allowed_before_collect"

	if error == "":
		var poi = planet_surface.pois[0]
		poi_name = str(poi.get_type_data().get("name", "Unknown"))

		var poi_pos: Vector3 = poi.position
		planet_surface.character.set_character_position(poi_pos + Vector3(0, 0.5, 0))

		planet_surface.poi_renderer.update_player_position(poi_pos)
		planet_surface.poi_renderer._check_poi_proximity()
		step_discovered = bool(poi.discovered)
		if not step_discovered:
			error = "poi_not_discovered"
		else:
			var active1 = planet_surface.objective_system.get_active_objective()
			objective_types["after_discover"] = int(active1.objective_type) if active1 != null else -1
			var expected_collect: int = int(planet_surface.objective_system.ObjectiveType.COLLECT_ARTIFACT)
			if objective_types["after_discover"] != expected_collect:
				error = "unexpected_collect_objective"

	if error == "":
		var poi = planet_surface.pois[0]
		var artifact_pos: Vector3 = poi.get_world_artifact_position()
		planet_surface.character.set_character_position(artifact_pos)

		planet_surface.poi_renderer.update_player_position(artifact_pos)
		planet_surface.poi_renderer._check_poi_proximity()
		var collected_ok: bool = bool(planet_surface.poi_renderer.try_collect_artifact())
		step_collected = collected_ok and bool(poi.artifact_collected)
		if not step_collected:
			error = "artifact_not_collected"
		else:
			var active2 = planet_surface.objective_system.get_active_objective()
			objective_types["after_collect"] = int(active2.objective_type) if active2 != null else -1
			var expected_return: int = int(planet_surface.objective_system.ObjectiveType.RETURN_TO_SHIP)
			if objective_types["after_collect"] != expected_return:
				error = "unexpected_return_objective"

	if error == "":
		var ship_pos: Vector3 = planet_surface.ship_spawn_position
		planet_surface.character.set_character_position(ship_pos + Vector3(0, 0.5, 0))
		planet_surface.ship_landing.update_player_position(ship_pos)
		planet_surface.objective_system.update_player_position(ship_pos)
		await get_tree().process_frame

		if not bool(planet_surface.ship_landing.get_can_board()):
			error = "cannot_board_ship"
		elif not bool(planet_surface.objective_system.can_leave_planet()):
			error = "objective_system_refused_leave"
		else:
			step_boarded = bool(planet_surface.ship_landing.try_board())
			if not step_boarded:
				error = "board_request_failed"

	if error == "":
		var timeout_ms: int = 30_000
		var start_ms: int = Time.get_ticks_msec()
		while not done and (Time.get_ticks_msec() - start_ms) < timeout_ms:
			await get_tree().process_frame

		if not done:
			error = "mission_completed_timeout"

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_web_e2e_publish_result({
		"mode": "mission",
		"success": error == "",
		"error": error,
		"elapsed_ms": elapsed_ms,
		"poi_name": poi_name,
		"steps": {
			"discovered": step_discovered,
			"collected": step_collected,
			"boarded": step_boarded,
		},
		"artifacts": collected,
		"objective_types": objective_types,
	})


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
	planet_surface.call_deferred(
		"initialize",
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
