## ship_landing.gd - Manages the landed ship on planet surface
## Provides visual marker and boarding interaction
class_name ShipLanding
extends Node3D


signal board_requested()


## Ship properties
@export var interaction_distance: float = 8.0
@export var marker_height: float = 30.0

## State
var player_position: Vector3 = Vector3.ZERO
var can_board: bool = false

## Visual references
var ship_mesh: Node3D = null
var landing_lights: Array[OmniLight3D] = []
var marker_beam: MeshInstance3D = null


func _ready() -> void:
	_create_ship_visual()
	_create_marker_beam()


func _process(delta: float) -> void:
	_update_can_board()
	_animate_lights(delta)


## Create the landed ship visual
func _create_ship_visual() -> void:
	ship_mesh = Node3D.new()
	ship_mesh.name = "ShipMesh"
	add_child(ship_mesh)

	# Main hull (elongated box)
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(4, 2, 8)
	hull.mesh = hull_mesh

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.35, 0.38, 0.42)
	hull_mat.metallic = 0.6
	hull_mat.roughness = 0.4
	hull.material_override = hull_mat
	hull.position = Vector3(0, 2, 0)
	ship_mesh.add_child(hull)

	# Cockpit (front dome)
	var cockpit := MeshInstance3D.new()
	var cockpit_mesh := SphereMesh.new()
	cockpit_mesh.radius = 1.2
	cockpit_mesh.height = 2.0
	cockpit.mesh = cockpit_mesh

	var cockpit_mat := StandardMaterial3D.new()
	cockpit_mat.albedo_color = Color(0.2, 0.3, 0.4, 0.8)
	cockpit_mat.metallic = 0.8
	cockpit_mat.roughness = 0.1
	cockpit.material_override = cockpit_mat
	cockpit.position = Vector3(0, 2.5, -3)
	ship_mesh.add_child(cockpit)

	# Wings
	for side in [-1, 1]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(5, 0.3, 3)
		wing.mesh = wing_mesh

		var wing_mat := StandardMaterial3D.new()
		wing_mat.albedo_color = Color(0.32, 0.35, 0.4)
		wing_mat.metallic = 0.5
		wing.material_override = wing_mat
		wing.position = Vector3(side * 3.5, 1.5, 1)
		ship_mesh.add_child(wing)

	# Engine pods
	for side in [-1, 1]:
		var engine := MeshInstance3D.new()
		var engine_mesh := CylinderMesh.new()
		engine_mesh.top_radius = 0.8
		engine_mesh.bottom_radius = 1.0
		engine_mesh.height = 3
		engine.mesh = engine_mesh

		var engine_mat := StandardMaterial3D.new()
		engine_mat.albedo_color = Color(0.3, 0.32, 0.35)
		engine.material_override = engine_mat
		engine.position = Vector3(side * 2, 1.5, 4)
		engine.rotation.x = PI / 2
		ship_mesh.add_child(engine)

	# Landing gear
	for pos in [Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(0, 0, 3)]:
		var gear := MeshInstance3D.new()
		var gear_mesh := CylinderMesh.new()
		gear_mesh.top_radius = 0.2
		gear_mesh.bottom_radius = 0.3
		gear_mesh.height = 1.5
		gear.mesh = gear_mesh

		var gear_mat := StandardMaterial3D.new()
		gear_mat.albedo_color = Color(0.25, 0.25, 0.28)
		gear.material_override = gear_mat
		gear.position = pos + Vector3(0, 0.75, 0)
		ship_mesh.add_child(gear)

	# Landing lights
	_create_landing_lights()


## Create landing pad lights
func _create_landing_lights() -> void:
	var light_positions := [
		Vector3(-3, 0.5, -4),
		Vector3(3, 0.5, -4),
		Vector3(-3, 0.5, 5),
		Vector3(3, 0.5, 5),
	]

	for pos in light_positions:
		var light := OmniLight3D.new()
		light.light_color = Color(0.3, 0.5, 1.0)
		light.light_energy = 0.8
		light.omni_range = 6.0
		light.position = pos
		add_child(light)
		landing_lights.append(light)

		# Light marker mesh
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2
		marker.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.5, 1.0)
		mat.emission_energy_multiplier = 2.0
		marker.material_override = mat
		marker.position = pos
		add_child(marker)


## Create vertical marker beam
func _create_marker_beam() -> void:
	marker_beam = MeshInstance3D.new()
	marker_beam.name = "MarkerBeam"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = marker_height
	marker_beam.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.4, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.5, 1.0, 0.3)
	marker_beam.material_override = mat

	marker_beam.position = Vector3(0, marker_height / 2, 0)
	add_child(marker_beam)


## Update boarding state
func _update_can_board() -> void:
	var dist := player_position.distance_to(global_position)
	can_board = dist < interaction_distance


## Animate landing lights
func _animate_lights(delta: float) -> void:
	var time := Time.get_ticks_msec() * 0.001

	for i in range(landing_lights.size()):
		var light := landing_lights[i]
		var phase := i * TAU / landing_lights.size()
		light.light_energy = 0.5 + sin(time * 2.0 + phase) * 0.3


## Update player position
func update_player_position(pos: Vector3) -> void:
	player_position = pos


## Check if player can board
func get_can_board() -> bool:
	return can_board


## Get distance to ship
func get_distance_to_player() -> float:
	return player_position.distance_to(global_position)


## Try to board ship
func try_board() -> bool:
	if can_board:
		board_requested.emit()
		return true
	return false


## Set ship position on terrain
func set_landing_position(pos: Vector3, terrain_normal: Vector3 = Vector3.UP) -> void:
	global_position = pos

	# Slight rotation to match terrain (optional)
	if terrain_normal != Vector3.UP:
		var right := terrain_normal.cross(Vector3.FORWARD).normalized()
		var forward := right.cross(terrain_normal).normalized()
		global_transform.basis = Basis(right, terrain_normal, forward)
