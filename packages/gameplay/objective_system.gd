## objective_system.gd - Tracks player objectives and mission progress
## Manages the gameplay loop: explore -> find -> collect -> return
class_name ObjectiveSystem
extends Node


signal objective_updated(objective: Objective)
signal objective_completed(objective: Objective)
signal all_objectives_completed()
signal artifact_collected(artifact_name: String, poi_name: String)


## Objective states
enum ObjectiveState {
	INACTIVE,       # Not yet assigned
	ACTIVE,         # In progress
	COMPLETED,      # Done
}

## Objective types
enum ObjectiveType {
	EXPLORE_POI,    # Find and enter a POI
	COLLECT_ARTIFACT,   # Collect an artifact from POI
	RETURN_TO_SHIP,     # Return to landed ship
	SCAN_AREA,      # Survey a location (future)
}


## Single objective data
class Objective extends RefCounted:
	var id: int = 0
	var objective_type: ObjectiveType = ObjectiveType.EXPLORE_POI
	var state: ObjectiveState = ObjectiveState.INACTIVE
	var title: String = ""
	var description: String = ""
	var target_position: Vector3 = Vector3.ZERO
	var poi_reference: POIGenerator.POIData = null
	var progress: float = 0.0  # 0-1 for progress-based objectives

	func is_active() -> bool:
		return state == ObjectiveState.ACTIVE

	func is_completed() -> bool:
		return state == ObjectiveState.COMPLETED


## Current objectives
var objectives: Array[Objective] = []
var primary_objective: Objective = null
var collected_artifacts: Array[String] = []

## Ship reference for return objective
var ship_position: Vector3 = Vector3.ZERO
var ship_return_distance: float = 10.0

## Player position
var player_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	pass


## Generate objectives for a planet
func generate_planet_objectives(pois: Array[POIGenerator.POIData], ship_pos: Vector3) -> void:
	objectives.clear()
	collected_artifacts.clear()
	ship_position = ship_pos

	var obj_id := 0

	# Primary objective: Find artifact at a specific POI
	if pois.size() > 0:
		var target_poi := pois[0]  # First POI is primary target

		# Explore objective
		var explore := Objective.new()
		explore.id = obj_id
		obj_id += 1
		explore.objective_type = ObjectiveType.EXPLORE_POI
		explore.title = "Explore %s" % target_poi.get_type_data().get("name", "Unknown Location")
		explore.description = "Investigate the nearby point of interest"
		explore.target_position = target_poi.position
		explore.poi_reference = target_poi
		explore.state = ObjectiveState.ACTIVE
		objectives.append(explore)
		primary_objective = explore

		# Collect artifact objective (activates after explore)
		var collect := Objective.new()
		collect.id = obj_id
		obj_id += 1
		collect.objective_type = ObjectiveType.COLLECT_ARTIFACT
		collect.title = "Retrieve %s" % target_poi.artifact_name
		collect.description = "Find and collect the artifact"
		collect.target_position = target_poi.get_world_artifact_position()
		collect.poi_reference = target_poi
		collect.state = ObjectiveState.INACTIVE
		objectives.append(collect)

	# Return to ship objective (always last)
	var return_obj := Objective.new()
	return_obj.id = obj_id
	return_obj.objective_type = ObjectiveType.RETURN_TO_SHIP
	return_obj.title = "Return to Ship"
	return_obj.description = "Board your ship to leave the planet"
	return_obj.target_position = ship_pos
	return_obj.state = ObjectiveState.INACTIVE
	objectives.append(return_obj)


## Update player position
func update_player_position(pos: Vector3) -> void:
	player_position = pos
	_check_objective_progress()


## Called when player enters a POI
func on_poi_discovered(poi: POIGenerator.POIData) -> void:
	for obj in objectives:
		if obj.objective_type == ObjectiveType.EXPLORE_POI and obj.poi_reference == poi:
			if obj.state == ObjectiveState.ACTIVE:
				_complete_objective(obj)


## Called when player collects an artifact
func on_artifact_collected(poi: POIGenerator.POIData, artifact_name: String) -> void:
	collected_artifacts.append(artifact_name)
	artifact_collected.emit(artifact_name, poi.get_type_data().get("name", "Unknown"))

	for obj in objectives:
		if obj.objective_type == ObjectiveType.COLLECT_ARTIFACT and obj.poi_reference == poi:
			if obj.state == ObjectiveState.ACTIVE:
				_complete_objective(obj)


## Check if player is close enough to ship
func is_at_ship() -> bool:
	return player_position.distance_to(ship_position) < ship_return_distance


## Check objective progress
func _check_objective_progress() -> void:
	# Check return to ship objective
	for obj in objectives:
		if obj.objective_type == ObjectiveType.RETURN_TO_SHIP and obj.state == ObjectiveState.ACTIVE:
			if is_at_ship():
				_complete_objective(obj)


## Complete an objective and activate next
func _complete_objective(obj: Objective) -> void:
	obj.state = ObjectiveState.COMPLETED
	objective_completed.emit(obj)

	# Activate next objective
	_activate_next_objective()

	# Check if all done
	var all_done := true
	for o in objectives:
		if o.state != ObjectiveState.COMPLETED:
			all_done = false
			break

	if all_done:
		all_objectives_completed.emit()


## Activate the next inactive objective
func _activate_next_objective() -> void:
	for obj in objectives:
		if obj.state == ObjectiveState.INACTIVE:
			obj.state = ObjectiveState.ACTIVE
			primary_objective = obj
			objective_updated.emit(obj)
			return


## Get current active objective
func get_active_objective() -> Objective:
	for obj in objectives:
		if obj.state == ObjectiveState.ACTIVE:
			return obj
	return null


## Get objective target position for HUD marker
func get_objective_target() -> Vector3:
	var active := get_active_objective()
	if active:
		return active.target_position
	return Vector3.ZERO


## Get objective description for HUD
func get_objective_text() -> String:
	var active := get_active_objective()
	if active:
		return active.title
	return "No active objective"


## Get distance to current objective
func get_objective_distance() -> float:
	var active := get_active_objective()
	if active:
		return player_position.distance_to(active.target_position)
	return -1.0


## Check if all required objectives are completed
func can_leave_planet() -> bool:
	# Must have collected at least one artifact
	if collected_artifacts.is_empty():
		return false

	# Must be at ship
	return is_at_ship()


## Get summary of collected items
func get_collection_summary() -> String:
	if collected_artifacts.is_empty():
		return "No artifacts collected"

	return "Collected: " + ", ".join(collected_artifacts)
