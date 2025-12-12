## poi_renderer.gd - Renders POIs as 3D structures on planet surface
## Creates meshes from POI grammar layouts
class_name POIRenderer
extends Node3D


signal poi_entered(poi: POIGenerator.POIData)
signal poi_exited(poi: POIGenerator.POIData)
signal artifact_collected(poi: POIGenerator.POIData, artifact_name: String)


## Rendering settings
@export var render_distance: float = 500.0
@export var detail_distance: float = 150.0

## POI data
var pois: Array[POIGenerator.POIData] = []
var poi_nodes: Dictionary = {}  # POI -> Node3D
var artifact_nodes: Dictionary = {}  # POI -> artifact mesh

## Player tracking
var player_position: Vector3 = Vector3.ZERO
var current_poi: POIGenerator.POIData = null

## Artifact interaction
var nearby_artifact: POIGenerator.POIData = null
var artifact_collect_distance: float = 3.0


func _process(_delta: float) -> void:
	_update_poi_visibility()
	_check_poi_proximity()
	_animate_artifacts(_delta)


## Initialize with POI data
func initialize(poi_list: Array[POIGenerator.POIData]) -> void:
	pois = poi_list

	# Pre-generate all POI structures
	for poi in pois:
		_create_poi_structure(poi)


## Create 3D structure for a POI
func _create_poi_structure(poi: POIGenerator.POIData) -> void:
	var poi_root := Node3D.new()
	poi_root.name = "POI_%d" % poi.seed
	poi_root.position = poi.position
	poi_root.rotation.y = poi.rotation
	add_child(poi_root)

	poi_nodes[poi] = poi_root

	# Generate structure based on POI type
	match poi.poi_type:
		POIGenerator.POIType.JEDI_RUINS:
			_build_jedi_ruins(poi, poi_root)
		POIGenerator.POIType.IMPERIAL_OUTPOST:
			_build_imperial_outpost(poi, poi_root)
		POIGenerator.POIType.CRASHED_SHIP:
			_build_crashed_ship(poi, poi_root)
		_:
			_build_generic_poi(poi, poi_root)

	# Create artifact (collectible)
	_create_artifact(poi, poi_root)

	# Create discovery trigger area (visual indicator when far)
	_create_poi_marker(poi, poi_root)


## Build Jedi Ruins structure
func _build_jedi_ruins(poi: POIGenerator.POIData, root: Node3D) -> void:
	var layout := JediRuinsGenerator.generate_ruins(poi.seed, poi.size)

	for element in layout.elements:
		var mesh := _create_element_mesh(element)
		if mesh:
			mesh.position = element.local_position
			mesh.rotation.y = element.rotation
			mesh.scale = element.scale
			root.add_child(mesh)


## Build Imperial Outpost
func _build_imperial_outpost(poi: POIGenerator.POIData, root: Node3D) -> void:
	var rng := PRNG.new(poi.seed)
	var size := poi.size

	# Main building (bunker style)
	var bunker := _create_box_mesh(Vector3(size * 0.4, 4, size * 0.3), Color(0.4, 0.4, 0.45))
	bunker.position = Vector3.ZERO
	root.add_child(bunker)

	# Watchtower
	var tower := _create_cylinder_mesh(1.5, 8, Color(0.45, 0.45, 0.5))
	tower.position = Vector3(size * 0.3, 0, size * 0.2)
	root.add_child(tower)

	# Barrier walls
	for i in range(4):
		var angle := i * TAU / 4 + rng.next_float() * 0.3
		var dist := size * 0.4
		var wall := _create_box_mesh(Vector3(8, 2.5, 0.5), Color(0.35, 0.35, 0.4))
		wall.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		wall.rotation.y = angle
		root.add_child(wall)

	# Crates/containers
	for _i in range(rng.next_int_range(3, 6)):
		var crate := _create_box_mesh(Vector3(1.5, 1, 1), Color(0.3, 0.35, 0.3))
		crate.position = Vector3(
			rng.next_float_range(-size * 0.2, size * 0.2),
			0.5,
			rng.next_float_range(-size * 0.2, size * 0.2)
		)
		crate.rotation.y = rng.next_float() * TAU
		root.add_child(crate)


## Build Crashed Ship
func _build_crashed_ship(poi: POIGenerator.POIData, root: Node3D) -> void:
	var rng := PRNG.new(poi.seed)
	var size := poi.size

	# Main hull (tilted)
	var hull := _create_box_mesh(Vector3(size * 0.5, 4, size * 0.2), Color(0.35, 0.3, 0.28))
	hull.position = Vector3(0, 2, 0)
	hull.rotation.x = rng.next_float_range(0.2, 0.5)
	hull.rotation.z = rng.next_float_range(-0.3, 0.3)
	root.add_child(hull)

	# Wing debris
	for side in [-1, 1]:
		var wing := _create_box_mesh(Vector3(size * 0.3, 0.5, size * 0.15), Color(0.32, 0.28, 0.25))
		wing.position = Vector3(side * size * 0.25, 0.5, rng.next_float_range(-5, 5))
		wing.rotation.y = rng.next_float_range(-0.5, 0.5)
		wing.rotation.z = side * rng.next_float_range(0.1, 0.4)
		root.add_child(wing)

	# Scattered debris
	for _i in range(rng.next_int_range(5, 10)):
		var debris := _create_box_mesh(
			Vector3(rng.next_float_range(0.5, 2), rng.next_float_range(0.3, 1), rng.next_float_range(0.5, 2)),
			Color(0.3, 0.28, 0.25)
		)
		debris.position = Vector3(
			rng.next_float_range(-size * 0.4, size * 0.4),
			rng.next_float_range(0, 0.5),
			rng.next_float_range(-size * 0.4, size * 0.4)
		)
		debris.rotation = Vector3(rng.next_float(), rng.next_float(), rng.next_float())
		root.add_child(debris)


## Build generic POI (placeholder)
func _build_generic_poi(poi: POIGenerator.POIData, root: Node3D) -> void:
	var type_data := poi.get_type_data()
	var color: Color = type_data.get("color", Color.GRAY)

	# Simple marker structure
	var base := _create_cylinder_mesh(poi.size * 0.3, 0.5, color.darkened(0.2))
	base.position = Vector3(0, 0.25, 0)
	root.add_child(base)

	# Central pillar
	var pillar := _create_cylinder_mesh(1.5, 5, color)
	pillar.position = Vector3(0, 2.5, 0)
	root.add_child(pillar)


## Create artifact collectible
func _create_artifact(poi: POIGenerator.POIData, root: Node3D) -> void:
	var artifact := Node3D.new()
	artifact.name = "Artifact"
	artifact.position = poi.artifact_position

	# Glowing sphere
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.5, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color(0.2, 0.4, 0.8)
	mesh.material_override = mat

	artifact.add_child(mesh)

	# Point light for glow
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.6, 1.0)
	light.light_energy = 1.5
	light.omni_range = 8.0
	artifact.add_child(light)

	root.add_child(artifact)
	artifact_nodes[poi] = artifact


## Create distant POI marker
func _create_poi_marker(poi: POIGenerator.POIData, root: Node3D) -> void:
	var marker := Node3D.new()
	marker.name = "DistantMarker"

	# Vertical beam
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.3
	cylinder.height = 50
	beam.mesh = cylinder

	var type_data := poi.get_type_data()
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = type_data.get("marker_color", Color.WHITE)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.3)
	beam.material_override = mat

	beam.position = Vector3(0, 25, 0)
	marker.add_child(beam)

	root.add_child(marker)


## Create mesh helpers
func _create_element_mesh(element: JediRuinsGenerator.StructureElement) -> MeshInstance3D:
	var data := element.get_data()
	var mesh_type: String = data.get("mesh", "box")
	var size: Vector3 = data.get("size", Vector3.ONE)
	var color: Color = data.get("color", Color.GRAY)

	if element.damaged:
		color = color.darkened(0.15)
		size *= Vector3(1.0, 0.7, 1.0)  # Broken pillars shorter

	var mesh_instance: MeshInstance3D

	match mesh_type:
		"box", "arch", "alcove", "steps", "collapsed":
			mesh_instance = _create_box_mesh(size, color)
		"cylinder", "pedestal":
			mesh_instance = _create_cylinder_mesh(size.x, size.y, color)
		"statue":
			mesh_instance = _create_statue_mesh(size, color)
		"rubble":
			mesh_instance = _create_rubble_mesh(size, color)
		_:
			mesh_instance = _create_box_mesh(size, color)

	# Add emission for pedestals
	if data.get("emissive", false):
		var mat: StandardMaterial3D = mesh_instance.material_override
		if mat:
			mat.emission_enabled = true
			mat.emission = color.lightened(0.3)
			mat.emission_energy_multiplier = 0.5

	return mesh_instance


func _create_box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat

	mesh_instance.position.y = size.y / 2.0
	return mesh_instance


func _create_cylinder_mesh(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh_instance.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat

	mesh_instance.position.y = height / 2.0
	return mesh_instance


func _create_statue_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	# Simple humanoid shape using capsule
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = size.x * 0.4
	capsule.height = size.y
	mesh_instance.mesh = capsule

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat

	mesh_instance.position.y = size.y / 2.0
	return mesh_instance


func _create_rubble_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	# Irregular shape using box with variation
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size * Vector3(1.0, 0.5, 0.8)
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat

	mesh_instance.position.y = size.y * 0.25
	return mesh_instance


## Update POI visibility based on distance
func _update_poi_visibility() -> void:
	for poi in pois:
		var node: Node3D = poi_nodes.get(poi)
		if not node:
			continue

		var dist := player_position.distance_to(poi.position)
		node.visible = dist < render_distance

		# Hide artifact if collected
		var artifact: Node3D = artifact_nodes.get(poi)
		if artifact:
			artifact.visible = not poi.artifact_collected and dist < detail_distance


## Check proximity to POIs and artifacts
func _check_poi_proximity() -> void:
	var was_inside := current_poi

	# Check POI boundaries
	current_poi = null
	for poi in pois:
		if POIGenerator.is_inside_poi(poi, player_position):
			current_poi = poi
			if not poi.discovered:
				poi.discovered = true
				poi_entered.emit(poi)
			break

	if was_inside and not current_poi:
		poi_exited.emit(was_inside)

	# Check artifact proximity
	nearby_artifact = null
	for poi in pois:
		if poi.artifact_collected:
			continue

		var artifact_world_pos := poi.get_world_artifact_position()
		var dist := player_position.distance_to(artifact_world_pos)

		if dist < artifact_collect_distance:
			nearby_artifact = poi
			break


## Animate artifacts (bobbing, rotation)
func _animate_artifacts(delta: float) -> void:
	for poi in pois:
		if poi.artifact_collected:
			continue

		var artifact: Node3D = artifact_nodes.get(poi)
		if artifact and artifact.visible:
			artifact.rotation.y += delta * 1.5
			artifact.position.y = poi.artifact_position.y + sin(Time.get_ticks_msec() * 0.003) * 0.3


## Update player position (called from planet_surface)
func update_player_position(pos: Vector3) -> void:
	player_position = pos


## Try to collect nearby artifact
func try_collect_artifact() -> bool:
	if nearby_artifact and not nearby_artifact.artifact_collected:
		nearby_artifact.artifact_collected = true
		artifact_collected.emit(nearby_artifact, nearby_artifact.artifact_name)

		# Hide artifact visual
		var artifact: Node3D = artifact_nodes.get(nearby_artifact)
		if artifact:
			artifact.visible = false

		return true

	return false


## Check if there's an artifact to collect
func can_collect_artifact() -> bool:
	return nearby_artifact != null and not nearby_artifact.artifact_collected


## Get distance to nearest undiscovered POI
func get_nearest_undiscovered_distance() -> float:
	var nearest_dist := INF

	for poi in pois:
		if not poi.discovered:
			var dist := player_position.distance_to(poi.position)
			if dist < nearest_dist:
				nearest_dist = dist

	return nearest_dist


## Get all discovered POIs
func get_discovered_pois() -> Array[POIGenerator.POIData]:
	var result: Array[POIGenerator.POIData] = []
	for poi in pois:
		if poi.discovered:
			result.append(poi)
	return result
