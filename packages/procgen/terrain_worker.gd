## terrain_worker.gd - Background worker for terrain tile generation
## Moves expensive heightmap/biome computation off the main thread
## Mesh building still happens on main thread (Godot requirement)
class_name TerrainWorker
extends RefCounted


## Request for tile generation
class TileRequest:
	var coords: Vector2i
	var lod: int
	var resolution: int
	var config: TerrainGenerator.TerrainConfig
	var request_id: int

	func _init(p_coords: Vector2i, p_lod: int, p_resolution: int, p_config: TerrainGenerator.TerrainConfig, p_id: int) -> void:
		coords = p_coords
		lod = p_lod
		resolution = p_resolution
		config = p_config
		request_id = p_id


## Result from tile generation
class TileResult:
	var coords: Vector2i
	var lod: int
	var tile_data: TerrainGenerator.TerrainTileData
	var request_id: int
	var generation_time_ms: float

	func _init(p_coords: Vector2i, p_lod: int, p_data: TerrainGenerator.TerrainTileData, p_id: int, p_time: float) -> void:
		coords = p_coords
		lod = p_lod
		tile_data = p_data
		request_id = p_id
		generation_time_ms = p_time


## Thread synchronization
var _thread: Thread = null
var _mutex: Mutex = null
var _semaphore: Semaphore = null

## Queues (protected by mutex)
var _request_queue: Array[TileRequest] = []
var _result_queue: Array[TileResult] = []
var _pending_coords: Dictionary = {}  # coords -> request_id (for deduplication)

## State
var _running: bool = false
var _next_request_id: int = 0

## Thread-local scratch buffer (created per-thread)
var _thread_scratch: TerrainGenerator.TerrainScratch = null


## Start the worker thread
func start() -> void:
	if _running:
		return

	_mutex = Mutex.new()
	_semaphore = Semaphore.new()
	_running = true

	_thread = Thread.new()
	_thread.start(_worker_loop)


## Stop the worker thread gracefully
func stop() -> void:
	if not _running:
		return

	_running = false

	# Wake the thread so it can exit
	_semaphore.post()

	# Wait for thread to finish
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	_mutex = null
	_semaphore = null


## Request a tile to be generated (called from main thread)
## Returns request_id for tracking, or -1 if already pending
func request_tile(coords: Vector2i, lod: int, resolution: int, config: TerrainGenerator.TerrainConfig) -> int:
	_mutex.lock()

	# Check if already pending
	if _pending_coords.has(coords):
		_mutex.unlock()
		return -1

	var request_id := _next_request_id
	_next_request_id += 1

	var request := TileRequest.new(coords, lod, resolution, config, request_id)
	_request_queue.append(request)
	_pending_coords[coords] = request_id

	_mutex.unlock()

	# Wake worker thread
	_semaphore.post()

	return request_id


## Cancel a pending tile request (if not yet started)
func cancel_request(coords: Vector2i) -> void:
	_mutex.lock()

	# Remove from pending tracking
	_pending_coords.erase(coords)

	# Remove from request queue (if still there)
	for i in range(_request_queue.size() - 1, -1, -1):
		if _request_queue[i].coords == coords:
			_request_queue.remove_at(i)
			break

	_mutex.unlock()


## Check if a tile is pending generation
func is_pending(coords: Vector2i) -> bool:
	_mutex.lock()
	var pending := _pending_coords.has(coords)
	_mutex.unlock()
	return pending


## Get completed tiles (called from main thread)
## Returns array of TileResult, empties the result queue
func get_completed_tiles() -> Array[TileResult]:
	_mutex.lock()

	var results: Array[TileResult] = []
	results.assign(_result_queue)
	_result_queue.clear()

	_mutex.unlock()
	return results


## Get number of pending requests
func get_pending_count() -> int:
	_mutex.lock()
	var count := _request_queue.size()
	_mutex.unlock()
	return count


## Worker thread main loop
func _worker_loop() -> void:
	# Create thread-local scratch buffer
	_thread_scratch = TerrainGenerator.TerrainScratch.new()

	while _running:
		# Wait for work
		_semaphore.wait()

		if not _running:
			break

		# Get next request
		_mutex.lock()
		var request: TileRequest = null
		if _request_queue.size() > 0:
			request = _request_queue.pop_front()
		_mutex.unlock()

		if request == null:
			continue

		# Check if request was cancelled
		_mutex.lock()
		var still_pending := _pending_coords.has(request.coords)
		_mutex.unlock()

		if not still_pending:
			continue  # Request was cancelled

		# Generate tile data (the expensive part)
		var start_time := Time.get_ticks_msec()
		var tile_data := _generate_tile_with_scratch(request)
		var elapsed := Time.get_ticks_msec() - start_time

		# Create result
		var result := TileResult.new(request.coords, request.lod, tile_data, request.request_id, elapsed)

		# Add to results and remove from pending
		_mutex.lock()
		_result_queue.append(result)
		_pending_coords.erase(request.coords)
		_mutex.unlock()


## Generate tile using thread-local scratch buffer
func _generate_tile_with_scratch(request: TileRequest) -> TerrainGenerator.TerrainTileData:
	# Note: We can't easily pass the scratch buffer to generate_tile since it uses
	# a static getter. For thread safety, we temporarily set the static scratch.
	# This works because each thread has its own execution context.
	#
	# A cleaner solution would be to refactor generate_tile to accept scratch as
	# parameter, but that would require more invasive changes.
	#
	# For now, we just call generate_tile directly - it will use its own static
	# scratch buffer. Since we only have one worker thread, this is safe.
	# If we add multiple worker threads, we'd need per-thread scratch management.

	return TerrainGenerator.generate_tile(
		request.config,
		request.coords,
		request.lod,
		request.resolution,
		false  # Don't enable profiling in worker thread
	)
