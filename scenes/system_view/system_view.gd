## system_view.gd - 2D orbital view of a star system
## Shows star at center with planets in orbit, clickable for details
extends Node2D


signal planet_selected(body: SystemGenerator.OrbitalBody)
signal planet_detail_requested(body: SystemGenerator.OrbitalBody, detail: PlanetGenerator.PlanetDetail)
signal back_to_galaxy_requested()

## Current system data
var sector_coords: Vector3i = Vector3i.ZERO
var system_index: int = 0
var system_data: SystemGenerator.SystemData = null
var star_data: GalaxyGenerator.StarData = null

## Selection state
var selected_body: SystemGenerator.OrbitalBody = null
var hovered_body: SystemGenerator.OrbitalBody = null
var selected_detail: PlanetGenerator.PlanetDetail = null

## View settings
var view_scale: float = 1.0
var min_scale: float = 0.1
var max_scale: float = 10.0
var orbit_time: float = 0.0  # For animation
var animate_orbits: bool = true

## Visual constants
const STAR_SIZE: float = 40.0
const PLANET_SIZE_MIN: float = 8.0
const PLANET_SIZE_MAX: float = 25.0
const ORBIT_SCALE: float = 80.0  # Pixels per AU at scale 1.0
const ORBIT_LINE_COLOR: Color = Color(0.3, 0.4, 0.5, 0.3)
const RING_COLOR: Color = Color(0.8, 0.7, 0.5, 0.5)

@onready var planet_info_panel: Control = $UI/PlanetInfoPanel
@onready var system_label: Label = $UI/SystemLabel
@onready var back_button: Button = $UI/BackButton


func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)


func _process(delta: float) -> void:
	if animate_orbits:
		orbit_time += delta * 0.1  # Slow orbital motion
		queue_redraw()


func load_system(sector: Vector3i, sys_index: int) -> void:
	sector_coords = sector
	system_index = sys_index

	# Get star data
	star_data = GalaxyGenerator.get_star(sector, sys_index)
	if star_data == null:
		push_error("Failed to load star data")
		return

	# Generate full system
	system_data = SystemGenerator.generate_system(sector, sys_index, star_data)

	selected_body = null
	hovered_body = null
	selected_detail = null
	view_scale = 1.0

	_update_ui()
	queue_redraw()


func _update_ui() -> void:
	if system_label and star_data:
		var class_data: Dictionary = GalaxyGenerator.STAR_CLASS_DATA[star_data.star_class]
		system_label.text = "%s - Class %s | %d planets" % [
			star_data.star_name,
			class_data["name"],
			system_data.bodies.size() if system_data else 0
		]

	if planet_info_panel:
		if selected_body and selected_detail:
			planet_info_panel.visible = true
			_update_planet_info_panel()
		else:
			planet_info_panel.visible = false


func _update_planet_info_panel() -> void:
	var info_label: RichTextLabel = planet_info_panel.get_node_or_null("InfoLabel")
	if not info_label or not selected_body or not selected_detail:
		return

	var type_data := selected_body.get_type_data()
	var hazards := selected_detail.get_hazard_names()
	var hazard_text := ", ".join(hazards) if hazards.size() > 0 else "None"

	info_label.text = """[b]%s[/b]
%s

[u]Physical[/u]
Radius: %.0f km
Gravity: %.2fg
Orbit: %.2f AU (%.0f days)

[u]Climate[/u]
Temperature: %.0f°C
Atmosphere: %s
Water: %.0f%%

[u]Hazards[/u]
%s

[u]Resources[/u]
%s

%s

[color=yellow][Right-click to LAND][/color]""" % [
		selected_body.name,
		type_data.get("name", "Unknown"),
		selected_body.radius_km,
		selected_body.gravity,
		selected_body.orbital_radius,
		selected_body.orbital_period,
		selected_detail.avg_temperature_c,
		selected_detail.atmosphere_composition if selected_detail.has_atmosphere else "None",
		selected_detail.water_coverage * 100,
		hazard_text,
		selected_detail.get_resource_summary(),
		selected_detail.description
	]


func _draw() -> void:
	if not system_data:
		return

	var viewport_size := get_viewport_rect().size
	var center := viewport_size / 2.0

	# Draw orbit lines
	for body in system_data.bodies:
		var orbit_radius := body.orbital_radius * ORBIT_SCALE * view_scale
		draw_arc(center, orbit_radius, 0, TAU, 64, ORBIT_LINE_COLOR, 1.0)

	# Draw star
	var star_color := star_data.get_color() if star_data else Color.YELLOW
	var star_size := STAR_SIZE * view_scale

	# Star glow
	var glow := star_color
	glow.a = 0.2
	draw_circle(center, star_size * 3, glow)
	glow.a = 0.4
	draw_circle(center, star_size * 1.5, glow)

	# Star core
	draw_circle(center, star_size, star_color)

	# Draw planets
	for body in system_data.bodies:
		_draw_planet(body, center)


func _draw_planet(body: SystemGenerator.OrbitalBody, center: Vector2) -> void:
	var orbit_radius := body.orbital_radius * ORBIT_SCALE * view_scale

	# Calculate position based on orbital period (animated)
	var angle := orbit_time / (body.orbital_period / 365.25) * TAU + body.seed * 0.001
	var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius

	# Planet size based on physical radius
	var size_t := inverse_lerp(2000.0, 100000.0, body.radius_km)
	var planet_size := lerpf(PLANET_SIZE_MIN, PLANET_SIZE_MAX, clampf(size_t, 0, 1)) * view_scale

	var color := body.get_color()

	# Highlight states
	if body == selected_body:
		# Selection ring
		draw_arc(pos, planet_size + 4, 0, TAU, 32, Color.WHITE, 2.0)
	elif body == hovered_body:
		color = color.lightened(0.3)
		planet_size *= 1.2

	# Draw rings if present
	if body.has_rings:
		var ring_inner := planet_size * 1.3
		var ring_outer := planet_size * 2.0
		draw_arc(pos, ring_inner, 0, TAU, 32, RING_COLOR, (ring_outer - ring_inner) * 0.3)
		draw_arc(pos, (ring_inner + ring_outer) / 2, 0, TAU, 32, RING_COLOR, (ring_outer - ring_inner) * 0.3)

	# Planet atmosphere glow (if has atmosphere)
	var type_data := body.get_type_data()
	if type_data.get("atmosphere", false):
		var atmo_color := color
		atmo_color.a = 0.2
		draw_circle(pos, planet_size * 1.3, atmo_color)

	# Planet body
	draw_circle(pos, planet_size, color)

	# Draw moons (small dots)
	for i in range(mini(body.num_moons, 4)):  # Cap visible moons
		var moon_angle := orbit_time * 5.0 + i * TAU / body.num_moons
		var moon_dist := planet_size * 2.0 + i * 5.0
		var moon_pos := pos + Vector2(cos(moon_angle), sin(moon_angle)) * moon_dist
		draw_circle(moon_pos, 2.0 * view_scale, Color.GRAY)

	# Station indicator
	if body.has_station:
		var station_pos := pos + Vector2(planet_size + 8, -planet_size - 8)
		draw_rect(Rect2(station_pos - Vector2(3, 3), Vector2(6, 6)), Color.CYAN)

	# Name label for selected/hovered
	if body == selected_body or body == hovered_body:
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(planet_size + 5, 5), body.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed and hovered_body:
				selected_body = hovered_body
				selected_detail = PlanetGenerator.generate_planet_detail(
					selected_body.seed,
					selected_body.planet_type
				)
				planet_selected.emit(selected_body)
				_update_ui()
				queue_redraw()

		MOUSE_BUTTON_RIGHT:
			if event.pressed and selected_body:
				planet_detail_requested.emit(selected_body, selected_detail)

		MOUSE_BUTTON_WHEEL_UP:
			view_scale = clampf(view_scale * 1.1, min_scale, max_scale)
			queue_redraw()

		MOUSE_BUTTON_WHEEL_DOWN:
			view_scale = clampf(view_scale * 0.9, min_scale, max_scale)
			queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var old_hover := hovered_body
	hovered_body = _hit_test(event.position)
	if hovered_body != old_hover:
		queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			if selected_body:
				selected_body = null
				selected_detail = null
				_update_ui()
				queue_redraw()
			else:
				back_to_galaxy_requested.emit()

		KEY_BACKSPACE:
			back_to_galaxy_requested.emit()

		KEY_SPACE:
			animate_orbits = not animate_orbits

		KEY_HOME:
			view_scale = 1.0
			queue_redraw()


func _hit_test(screen_pos: Vector2) -> SystemGenerator.OrbitalBody:
	if not system_data:
		return null

	var viewport_size := get_viewport_rect().size
	var center := viewport_size / 2.0

	for body in system_data.bodies:
		var orbit_radius := body.orbital_radius * ORBIT_SCALE * view_scale
		var angle := orbit_time / (body.orbital_period / 365.25) * TAU + body.seed * 0.001
		var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius

		var size_t := inverse_lerp(2000.0, 100000.0, body.radius_km)
		var planet_size := lerpf(PLANET_SIZE_MIN, PLANET_SIZE_MAX, clampf(size_t, 0, 1)) * view_scale

		if screen_pos.distance_to(pos) <= planet_size * 1.5:
			return body

	return null


func _on_back_pressed() -> void:
	back_to_galaxy_requested.emit()
