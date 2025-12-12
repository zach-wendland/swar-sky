## test_artifact_gating.gd - Verifies artifacts require POI discovery before collection
## Run: godot --headless --script packages/render/tests/test_artifact_gating.gd
extends SceneTree

class DummyPOI extends RefCounted:
	var seed: int = 0
	var poi_type: int = 0
	var position: Vector3 = Vector3.ZERO
	var size: float = 10.0
	var rotation: float = 0.0

	var discovered: bool = false
	var artifact_collected: bool = false

	var artifact_name: String = ""
	var artifact_position: Vector3 = Vector3.ZERO

	func get_type_data() -> Dictionary:
		return {}

	func get_world_artifact_position() -> Vector3:
		return position + artifact_position.rotated(Vector3.UP, rotation)


func _init() -> void:
	print("\n========================================")
	print("ARTIFACT GATING TEST SUITE")
	print("========================================\n")

	var all_passed := true
	all_passed = test_artifact_requires_discovery() and all_passed
	all_passed = test_jedi_ruins_generator_compiles() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL ARTIFACT GATING TESTS PASSED")
	else:
		print("SOME ARTIFACT GATING TESTS FAILED")
	print("========================================\n")

	quit(0 if all_passed else 1)


func test_artifact_requires_discovery() -> bool:
	print("[TEST] Artifact requires POI discovery...")

	var poi := DummyPOI.new()
	poi.seed = 123
	poi.poi_type = 999
	poi.position = Vector3.ZERO
	poi.rotation = 0.0
	poi.size = 10.0 # discovery radius = size * 0.6 = 6.0
	poi.discovered = false
	poi.artifact_collected = false
	poi.artifact_name = "Test Holocron"
	poi.artifact_position = Vector3(20, 2, 0) # outside discovery radius

	var renderer_script := load("res://packages/render/poi_renderer.gd")
	var renderer: Node = renderer_script.new()
	renderer.initialize([poi])

	# Player stands on the artifact but has not discovered POI.
	var player_pos: Vector3 = poi.get_world_artifact_position()
	renderer.update_player_position(player_pos)
	renderer._process(0.016)

	if renderer.can_collect_artifact():
		print("  FAIL: Artifact was collectible before POI discovery")
		return false

	# Now mark POI discovered and re-evaluate.
	poi.discovered = true
	renderer.update_player_position(player_pos)
	renderer._process(0.016)

	if not renderer.can_collect_artifact():
		print("  FAIL: Artifact not collectible after POI discovery")
		return false

	if not renderer.try_collect_artifact():
		print("  FAIL: try_collect_artifact() returned false after discovery")
		return false

	if not poi.artifact_collected:
		print("  FAIL: POI artifact_collected flag not set")
		return false

	print("  PASS: Artifact collection is gated by discovery")
	return true


func test_jedi_ruins_generator_compiles() -> bool:
	print("[TEST] Jedi ruins generator compiles...")

	var gen = load("res://packages/procgen/poi_grammars/jedi_ruins.gd")
	if gen == null:
		print("  FAIL: Failed to load jedi_ruins.gd")
		return false

	var layout = gen.generate_ruins(123, 50.0)
	if layout == null:
		print("  FAIL: generate_ruins returned null")
		return false

	if not ("elements" in layout) or layout.elements.size() <= 0:
		print("  FAIL: generate_ruins returned empty layout")
		return false

	print("  PASS: Jedi ruins generator loads and runs")
	return true
