## system_space.gd - 3D spaceflight within a star system
## Player flies ship, approaches planets, can land or return to galaxy
extends Node3D


signal back_to_galaxy_requested()
signal landing_requested(body: SystemGenerator.OrbitalBody, detail: PlanetGenerator.PlanetDetail)


## System data
var sector_coords: Vector3i = Vector3i.ZERO
var system_index: int = 0
var system_data: SystemGenerator.SystemData = null
var star_data: GalaxyGenerator.StarData = null

## Scene scale (1 unit = 1000 km for space scenes)
const SPACE_SCALE: float = 0.001  # 1 unit = 1000 km
const AU_TO_UNITS: float = 149597.87  # AU in thousands of km
const ORBIT_SCALE: float = 50.0  # Visual scale for orbits (compressed)
const PLANET_SCALE: float = 0.1  # Visual scale for planets
const STAR_SCALE: float = 2.0  # Visual scale for star

## Animation
var orbit_time: float = 0.0
var animate_orbits: bool = true

## Planet visuals
var planet_meshes: Dictionary = {}  # body -> MeshInstance3D
var planet_bodies: Array[SystemGenerator.OrbitalBody] = []

## References
## Note: Using Variant to avoid parse-time dependency on autoloads
@onready var ship = $Ship  # ShipController
@onready var star_mesh: MeshInstance3D = $StarMesh
@onready var ui: CanvasLayer = $UI
@onready var target_label: Label = $UI/HUD/TargetLabel
@onready var speed_label: Label = $UI/HUD/SpeedLabel
@onready var system_label: Label = $UI/HUD/SystemLabel
@onready var back_button: Button = $UI/BackButton


func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	if ship:
		ship.target_planet_changed.connect(_on_target_changed)
		ship.speed_changed.connect(_on_speed_changed)
		ship.landing_requested.connect(_on_landing_requested)


func _process(delta: float) -> void:
	if animate_orbits:
		orbit_time += delta * 0.05  # Slow orbit animation
		_update_planet_positions()

	_update_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				back_to_galaxy_requested.emit()
			KEY_SPACE:
				animate_orbits = not animate_orbits


## Initialize the system
func load_system(sector: Vector3i, sys_index: int, spawn_near_planet: SystemGenerator.OrbitalBody = null) -> void:
	sector_coords = sector
	system_index = sys_index

	# Get star data
	star_data = GalaxyGenerator.get_star(sector, sys_index)
	if star_data == null:
		push_error("Failed to load star data")
		return

	# Generate system
	system_data = SystemGenerator.generate_system(sector, sys_index, star_data)

	# Build 3D scene
	_create_star()
	_create_planets()

	# Set ship nearby bodies for targeting
	if ship:
		ship.set_nearby_bodies(planet_bodies)

		# Spawn ship
		if spawn_near_planet:
			_spawn_ship_near_planet(spawn_near_planet)
		else:
			_spawn_ship_default()

	_update_ui()


## Create the central star
func _create_star() -> void:
	if not star_mesh:
		star_mesh = MeshInstance3D.new()
		star_mesh.name = "StarMesh"
		add_child(star_mesh)

	# Create star mesh
	var sphere := SphereMesh.new()
	sphere.radius = STAR_SCALE
	sphere.height = STAR_SCALE * 2
	sphere.radial_segments = 32
	sphere.rings = 16
	star_mesh.mesh = sphere

	# Create emissive material
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = star_data.get_color() if star_data else Color.YELLOW
	mat.emission_energy_multiplier = 5.0
	mat.albedo_color = mat.emission
	star_mesh.material_override = mat

	star_mesh.position = Vector3.ZERO

	# Add point light
	var light := OmniLight3D.new()
	light.name = "StarLight"
	light.light_color = mat.emission
	light.light_energy = 2.0
	light.omni_range = 500.0
	star_mesh.add_child(light)


## Create planet meshes
func _create_planets() -> void:
	# Clear existing
	for mesh in planet_meshes.values():
		mesh.queue_free()
	planet_meshes.clear()
	planet_bodies.clear()

	if not system_data:
		return

	for body in system_data.bodies:
		var mesh := _create_planet_mesh(body)
		planet_meshes[body] = mesh
		planet_bodies.append(body)
		add_child(mesh)

	_update_planet_positions()


func _create_planet_mesh(body: SystemGenerator.OrbitalBody) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = body.name

	# Size based on planet radius (scaled)
	var visual_radius := clampf(body.radius_km * SPACE_SCALE * PLANET_SCALE, 0.3, 3.0)

	var sphere := SphereMesh.new()
	sphere.radius = visual_radius
	sphere.height = visual_radius * 2
	sphere.radial_segments = 24
	sphere.rings = 12
	mesh_instance.mesh = sphere

	# Material based on planet type
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body.get_color()

	# Add atmosphere glow for habitable planets
	var type_data := body.get_type_data()
	if type_data.get("atmosphere", false):
		mat.emission_enabled = true
		mat.emission = body.get_color().lightened(0.5)
		mat.emission_energy_multiplier = 0.3

	mesh_instance.material_override = mat

	# Add rings if present
	if body.has_rings:
		var ring := _create_ring_mesh(visual_radius)
		mesh_instance.add_child(ring)

	return mesh_instance


func _create_ring_mesh(planet_radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "Rings"

	# Use a torus for rings
	var torus := TorusMesh.new()
	torus.inner_radius = planet_radius * 1.3
	torus.outer_radius = planet_radius * 2.5
	torus.rings = 32
	torus.ring_segments = 16
	ring.mesh = torus

	# Ring material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.75, 0.6, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat

	# Tilt rings
	ring.rotation_degrees.x = 80

	return ring


## Update planet positions based on orbit time
func _update_planet_positions() -> void:
	for body in planet_bodies:
		var mesh: MeshInstance3D = planet_meshes.get(body)
		if not mesh:
			continue

		# Calculate orbital position
		var orbit_radius := body.orbital_radius * ORBIT_SCALE
		var orbital_speed := TAU / (body.orbital_period / 365.25)  # Radians per year
		var angle := orbit_time * orbital_speed + body.seed * 0.001

		var pos := Vector3(
			cos(angle) * orbit_radius,
			0,
			sin(angle) * orbit_radius
		)

		mesh.position = pos

		# Store world position on body for targeting
		body.set_meta("world_position", pos)


## Spawn ship near a planet (for taking off)
func _spawn_ship_near_planet(body: SystemGenerator.OrbitalBody) -> void:
	if not ship:
		return

	var body_pos: Vector3 = body.get_meta("world_position", Vector3.ZERO)
	var offset := Vector3(0, 2, 10)  # Slightly above and behind
	ship.set_ship_state(body_pos + offset, Vector3(0, PI, 0))


## Default spawn position
func _spawn_ship_default() -> void:
	if not ship:
		return

	# Spawn between star and first planet
	var spawn_pos := Vector3(10, 2, 10)
	if planet_bodies.size() > 0:
		var first_orbit := planet_bodies[0].orbital_radius * ORBIT_SCALE * 0.3
		spawn_pos = Vector3(first_orbit, 2, 0)

	ship.set_ship_state(spawn_pos, Vector3(0, -PI/2, 0))


## Update HUD
func _update_ui() -> void:
	if system_label and star_data:
		var class_data: Dictionary = GalaxyGenerator.STAR_CLASS_DATA[star_data.star_class]
		system_label.text = "%s - Class %s | %d planets" % [
			star_data.star_name,
			class_data["name"],
			system_data.bodies.size() if system_data else 0
		]

	if target_label and ship:
		if ship.target_body:
			var dist: float = ship.get_distance_to_target()
			var can_land: bool = ship.can_land()

			# Color based on distance: green when landable, yellow when close, gold when far
			if can_land:
				target_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))  # Green
				target_label.text = ">>> %s (%.0f km) - PRESS F TO LAND <<<" % [ship.target_body.name, dist * 1000]
			elif dist < ship.landing_distance * 2:
				target_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))  # Yellow
				target_label.text = "Target: %s (%.0f km) - Approaching..." % [ship.target_body.name, dist * 1000]
			else:
				target_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))  # Gold
				target_label.text = "Target: %s (%.0f km)" % [ship.target_body.name, dist * 1000]
		else:
			target_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))  # Gray
			target_label.text = "No Target [T to cycle]"

	if speed_label and ship:
		var speed_kmh: float = ship.current_speed * 1000 * 3.6  # Convert to km/h
		var throttle_pct: float = ship.throttle * 100
		var boost_text := " [BOOST]" if ship.is_boosting else ""
		speed_label.text = "Speed: %.0f km/h (%.0f%%)%s" % [speed_kmh, throttle_pct, boost_text]


func _on_target_changed(body: SystemGenerator.OrbitalBody) -> void:
	# Could add visual indicator on target
	pass


func _on_speed_changed(_speed: float) -> void:
	pass


func _on_landing_requested(body: SystemGenerator.OrbitalBody) -> void:
	# Generate planet detail and request landing
	var detail := PlanetGenerator.generate_planet_detail(body.seed, body.planet_type)
	landing_requested.emit(body, detail)


func _on_back_pressed() -> void:
	back_to_galaxy_requested.emit()


## Get current ship position (for saving state)
func get_ship_state() -> Dictionary:
	if ship:
		return ship.get_ship_data()
	return {}
