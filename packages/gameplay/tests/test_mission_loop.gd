## test_mission_loop.gd - Headless integration test for the MVP mission loop
## Run: godot --headless --script packages/gameplay/tests/test_mission_loop.gd
extends SceneTree


const TEST_SEED: int = 77777
const TEST_PLANET_TYPE: int = SystemGenerator.PlanetType.TEMPERATE

var _mission_completed: bool = false
var _mission_completed_artifacts: Array = []


func _init() -> void:
	print("\n========================================")
	print("MISSION LOOP TEST SUITE")
	print("========================================\n")

	call_deferred("_run")


func _run() -> void:
	var passed: bool = await _test_planet_surface_mission_loop()

	print("\n========================================")
	if passed:
		print("ALL MISSION LOOP TESTS PASSED")
	else:
		print("SOME MISSION LOOP TESTS FAILED")
	print("========================================\n")

	quit(0 if passed else 1)


func _test_planet_surface_mission_loop() -> bool:
	print("[TEST] Planet surface mission loop completes...")

	var PlanetSurfaceScene := load("res://scenes/planet_surface/planet_surface.tscn")
	if PlanetSurfaceScene == null:
		print("  FAIL: Failed to load planet_surface.tscn")
		return false

	_mission_completed = false
	_mission_completed_artifacts = []

	var surface = PlanetSurfaceScene.instantiate()
	surface.set_meta(&"web_e2e_mission", true)
	surface.set_meta(&"web_e2e_no_immediate_tiles", true)
	surface.set_meta(&"web_e2e_view_distance", 0)
	surface.set_meta(&"web_e2e_tile_resolution", 17)
	surface.set_meta(&"web_e2e_update_interval", 9999.0)
	root.add_child(surface)

	if not surface.has_signal("mission_completed"):
		print("  FAIL: PlanetSurface missing mission_completed signal")
		return false

	surface.connect("mission_completed", Callable(self, "_on_mission_completed"))

	surface.call_deferred("initialize", TEST_SEED, TEST_PLANET_TYPE, "Test Planet", null)

	# Wait for initialization (signal emitted from _setup_gameplay_systems()).
	var init_timeout_ms: int = 30_000
	var init_start_ms: int = Time.get_ticks_msec()
	while not bool(surface.has_meta(&"web_e2e_initialized")) and (Time.get_ticks_msec() - init_start_ms) < init_timeout_ms:
		await process_frame

	if not bool(surface.has_meta(&"web_e2e_initialized")):
		print("  FAIL: surface initialization timeout")
		return false

	if surface.pois == null or surface.pois.is_empty():
		print("  FAIL: No POIs generated")
		return false

	if surface.poi_renderer == null or surface.objective_system == null or surface.ship_landing == null:
		print("  FAIL: Missing systems (poi_renderer/objective_system/ship_landing)")
		return false

	var poi = surface.pois[0]
	var poi_name: String = str(poi.get_type_data().get("name", "Unknown"))

	# Sanity: POI starts undiscovered, and you can't leave before collecting an artifact.
	if bool(poi.discovered):
		print("  FAIL: POI started discovered at ", poi_name)
		return false

	var ship_pos_pre: Vector3 = surface.ship_spawn_position
	surface.character.set_character_position(ship_pos_pre + Vector3(0, 0.5, 0))
	surface.ship_landing.update_player_position(ship_pos_pre)
	surface.objective_system.update_player_position(ship_pos_pre)
	await process_frame

	if bool(surface.objective_system.can_leave_planet()):
		print("  FAIL: Allowed leaving planet before collecting artifact")
		return false

	# 1) Discover POI by entering its radius.
	var poi_pos: Vector3 = poi.position
	surface.character.set_character_position(poi_pos + Vector3(0, 0.5, 0))
	surface.poi_renderer.update_player_position(poi_pos)
	surface.poi_renderer._process(0.016)

	if not bool(poi.discovered):
		print("  FAIL: POI not discovered at ", poi_name)
		return false

	# 2) Collect artifact (now that POI is discovered).
	var artifact_pos: Vector3 = poi.get_world_artifact_position()
	surface.character.set_character_position(artifact_pos)
	surface.poi_renderer.update_player_position(artifact_pos)
	surface.poi_renderer._process(0.016)

	surface._handle_interaction()
	await process_frame

	if not bool(poi.artifact_collected):
		print("  FAIL: Artifact not collected at ", poi_name)
		return false

	if surface.objective_system.collected_artifacts.is_empty():
		print("  FAIL: ObjectiveSystem did not record artifact")
		return false

	# 3) Return to ship and board.
	var ship_pos: Vector3 = surface.ship_spawn_position
	surface.character.set_character_position(ship_pos + Vector3(0, 0.5, 0))
	surface.ship_landing.update_player_position(ship_pos)
	surface.objective_system.update_player_position(ship_pos)
	await process_frame

	if not bool(surface.ship_landing.get_can_board()):
		print("  FAIL: Cannot board ship at end of mission")
		return false

	if not bool(surface.objective_system.can_leave_planet()):
		print("  FAIL: ObjectiveSystem refuses leaving planet")
		return false

	surface._handle_interaction()

	var complete_timeout_ms: int = 10_000
	var complete_start_ms: int = Time.get_ticks_msec()
	while not _mission_completed and (Time.get_ticks_msec() - complete_start_ms) < complete_timeout_ms:
		await process_frame

	if not _mission_completed:
		print("  FAIL: Mission did not complete (timeout)")
		return false

	if _mission_completed_artifacts.is_empty():
		print("  FAIL: Mission completed with no artifacts")
		return false

	print("  PASS: Mission completed at ", poi_name, " with ", _mission_completed_artifacts)
	return true


func _on_mission_completed(artifacts: Array) -> void:
	_mission_completed = true
	_mission_completed_artifacts = artifacts
