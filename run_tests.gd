## run_tests.gd - Unified test runner for all test suites
## Run: godot --headless --script run_tests.gd
## Watch mode: godot --headless --script run_tests.gd -- --watch
extends SceneTree


const TEST_SCRIPTS: Array[String] = [
	"res://packages/core/tests/test_determinism.gd",
	"res://packages/procgen/tests/test_terrain.gd",
	"res://packages/procgen/tests/test_tile_mapping.gd",
	"res://packages/procgen/tests/test_generators.gd",
	"res://packages/render/tests/test_graphics.gd",
	"res://packages/render/tests/test_artifact_gating.gd",
	"res://packages/gameplay/tests/test_mission_loop.gd",
]

var _watch_mode: bool = false
var _last_modified_times: Dictionary = {}
var _watch_paths: Array[String] = [
	"res://packages/core/",
	"res://packages/procgen/",
	"res://packages/render/",
	"res://packages/gameplay/",
]


func _init() -> void:
	# Check for --watch flag
	var args := OS.get_cmdline_user_args()
	_watch_mode = "--watch" in args or "-w" in args

	if _watch_mode:
		print("\n[WATCH MODE] Monitoring for file changes...")
		print("Press Ctrl+C to exit\n")
		_run_all_tests()
		_start_watch_loop()
	else:
		var success := _run_all_tests()
		quit(0 if success else 1)


func _run_all_tests() -> bool:
	var start_time := Time.get_ticks_msec()

	print("\n" + "=".repeat(60))
	print("SWAR-SKY TEST RUNNER")
	print("=".repeat(60))
	print("Time: ", Time.get_datetime_string_from_system())
	print("")

	var results: Array[Dictionary] = []
	var total_passed := 0
	var total_failed := 0

	for script_path in TEST_SCRIPTS:
		var result := _run_test_script(script_path)
		results.append(result)

		if result.success:
			total_passed += 1
		else:
			total_failed += 1

	# Print summary
	var elapsed := Time.get_ticks_msec() - start_time

	print("\n" + "=".repeat(60))
	print("TEST SUMMARY")
	print("=".repeat(60))

	for result in results:
		var status := "[PASS]" if result.success else "[FAIL]"
		var color := "" if result.success else " <--"
		print("  %s %s%s" % [status, result.name, color])

	print("")
	print("Total: %d passed, %d failed" % [total_passed, total_failed])
	print("Time: %.2fs" % [elapsed / 1000.0])
	print("=".repeat(60) + "\n")

	return total_failed == 0


func _run_test_script(script_path: String) -> Dictionary:
	var result := {
		"path": script_path,
		"name": script_path.get_file().replace(".gd", ""),
		"success": false,
		"error": ""
	}

	# Check if script exists
	if not ResourceLoader.exists(script_path):
		result.error = "Script not found"
		print("[SKIP] %s - not found" % result.name)
		# Don't count missing optional tests as failures
		result.success = true
		return result

	print("\n[RUN] %s" % result.name)
	print("-".repeat(40))

	# Load and validate script
	var script: GDScript = load(script_path)
	if script == null:
		result.error = "Failed to load script"
		print("  ERROR: %s" % result.error)
		return result

	# Run the test by executing it as a subprocess
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		["--headless", "--script", script_path],
		output,
		true,  # read_stderr
		false  # open_console
	)

	# Print output
	for line in output:
		var lines: PackedStringArray = line.split("\n")
		for l in lines:
			if l.strip_edges() != "":
				print("  ", l)

	result.success = (exit_code == 0)
	if not result.success:
		result.error = "Exit code: %d" % exit_code

	return result


func _start_watch_loop() -> void:
	# Initialize file modification times
	_scan_files()

	# Main watch loop
	while true:
		OS.delay_msec(1000)  # Check every second

		var changed_files := _check_for_changes()
		if changed_files.size() > 0:
			print("\n[CHANGE DETECTED]")
			for f in changed_files:
				print("  Modified: %s" % f)
			print("")

			_run_all_tests()


func _scan_files() -> void:
	_last_modified_times.clear()

	for watch_path in _watch_paths:
		_scan_directory(watch_path)


func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path)
		elif file_name.ends_with(".gd"):
			var mod_time := FileAccess.get_modified_time(full_path)
			_last_modified_times[full_path] = mod_time

		file_name = dir.get_next()

	dir.list_dir_end()


func _check_for_changes() -> Array[String]:
	var changed: Array[String] = []

	for watch_path in _watch_paths:
		_check_directory_changes(watch_path, changed)

	# Update timestamps for changed files
	for file_path in changed:
		_last_modified_times[file_path] = FileAccess.get_modified_time(file_path)

	return changed


func _check_directory_changes(path: String, changed: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_check_directory_changes(full_path, changed)
		elif file_name.ends_with(".gd"):
			var mod_time := FileAccess.get_modified_time(full_path)
			var last_time: int = _last_modified_times.get(full_path, 0)

			if mod_time != last_time:
				changed.append(full_path)
				_last_modified_times[full_path] = mod_time

		file_name = dir.get_next()

	dir.list_dir_end()
