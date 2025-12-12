## galaxy_map.gd - 2D interactive galaxy visualization
## Displays stars in current sector, allows clicking to view systems
extends Node2D


signal star_selected(star_data: GalaxyGenerator.StarData)
signal system_requested(sector: Vector3i, system_index: int)

## Current view state
var current_sector: Vector3i = Vector3i.ZERO
var stars: Array[GalaxyGenerator.StarData] = []
var selected_star: GalaxyGenerator.StarData = null
var hovered_star: GalaxyGenerator.StarData = null

## View settings
var view_offset: Vector2 = Vector2.ZERO
var view_scale: float = 1.0
var min_scale: float = 0.2
var max_scale: float = 5.0

## Visual settings
const STAR_BASE_SIZE: float = 4.0
const STAR_HOVER_MULT: float = 1.5
const STAR_SELECT_MULT: float = 2.0
const GRID_SIZE: float = 100.0
const GRID_COLOR: Color = Color(0.2, 0.3, 0.4, 0.3)

## Interaction
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

@onready var star_info_panel: Control = $UI/StarInfoPanel
@onready var sector_label: Label = $UI/SectorLabel
@onready var instructions_label: Label = $UI/InstructionsLabel


func _ready() -> void:
	_load_sector(current_sector)
	_update_ui()


func _load_sector(sector: Vector3i) -> void:
	current_sector = sector
	stars = GalaxyGenerator.generate_sector(sector)
	selected_star = null
	hovered_star = null
	queue_redraw()
	_update_ui()


func _update_ui() -> void:
	if sector_label:
		sector_label.text = "Sector: (%d, %d, %d) | Stars: %d" % [
			current_sector.x, current_sector.y, current_sector.z, stars.size()
		]

	if star_info_panel:
		if selected_star:
			star_info_panel.visible = true
			_update_star_info_panel(selected_star)
		else:
			star_info_panel.visible = false


func _update_star_info_panel(star: GalaxyGenerator.StarData) -> void:
	var info_label: RichTextLabel = star_info_panel.get_node_or_null("InfoLabel")
	if info_label:
		var class_data: Dictionary = star.get_class_data()
		var faction_name: String = "Unclaimed" if star.faction_id < 0 else "Faction %d" % star.faction_id
		var danger_text: String = ["Safe", "Low", "Moderate", "Dangerous", "Hostile", "Extreme"][star.danger_level]

		info_label.text = """[b]%s[/b]
Class %s Star
Planets: %d
Station: %s
Control: %s
Danger: %s

[Click to enter system]""" % [
			star.star_name,
			class_data["name"],
			star.num_planets,
			"Yes" if star.has_station else "No",
			faction_name,
			danger_text
		]


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var center := viewport_size / 2.0

	# Draw grid
	_draw_grid(center)

	# Draw stars
	for star in stars:
		var screen_pos := _world_to_screen(star.position, center)

		# Skip if off screen
		if not _is_on_screen(screen_pos, viewport_size):
			continue

		var color := star.get_color()
		var size := STAR_BASE_SIZE * view_scale

		# Highlight states
		if star == selected_star:
			size *= STAR_SELECT_MULT
			# Selection ring
			draw_arc(screen_pos, size + 4, 0, TAU, 32, Color.WHITE, 2.0)
		elif star == hovered_star:
			size *= STAR_HOVER_MULT
			color = color.lightened(0.3)

		# Draw star glow
		var glow_color := color
		glow_color.a = 0.3
		draw_circle(screen_pos, size * 2, glow_color)

		# Draw star core
		draw_circle(screen_pos, size, color)

		# Draw name for selected/hovered
		if star == selected_star or star == hovered_star:
			var font := ThemeDB.fallback_font
			var font_size := 14
			draw_string(font, screen_pos + Vector2(size + 5, 5), star.star_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_grid(center: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var grid_spacing := GRID_SIZE * view_scale

	if grid_spacing < 20:
		return  # Don't draw grid when zoomed out too far

	var offset := fmod(view_offset.x * view_scale, grid_spacing)
	var x := offset
	while x < viewport_size.x:
		draw_line(Vector2(x, 0), Vector2(x, viewport_size.y), GRID_COLOR)
		x += grid_spacing

	offset = fmod(view_offset.y * view_scale, grid_spacing)
	var y := offset
	while y < viewport_size.y:
		draw_line(Vector2(0, y), Vector2(viewport_size.x, y), GRID_COLOR)
		y += grid_spacing


func _world_to_screen(world_pos: Vector3, center: Vector2) -> Vector2:
	# Project 3D sector position to 2D (top-down view, ignore Y for now)
	var flat_pos := Vector2(world_pos.x, world_pos.z)
	return center + (flat_pos - Vector2(0.5, 0.5)) * 800.0 * view_scale + view_offset * view_scale


func _screen_to_world(screen_pos: Vector2, center: Vector2) -> Vector2:
	return (screen_pos - center) / (800.0 * view_scale) - view_offset / 800.0 + Vector2(0.5, 0.5)


func _is_on_screen(pos: Vector2, viewport_size: Vector2) -> bool:
	var margin := 50.0
	return pos.x >= -margin and pos.x <= viewport_size.x + margin and \
	       pos.y >= -margin and pos.y <= viewport_size.y + margin


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
			if event.pressed:
				if hovered_star:
					selected_star = hovered_star
					star_selected.emit(selected_star)
					_update_ui()
					queue_redraw()
			else:
				is_dragging = false

		MOUSE_BUTTON_RIGHT:
			if event.pressed and selected_star:
				# Enter system view
				system_requested.emit(current_sector, selected_star.index)

		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_dragging = true
				drag_start = event.position
			else:
				is_dragging = false

		MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.1, event.position)

		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.9, event.position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		view_offset += event.relative / view_scale
		queue_redraw()
	else:
		# Hit test for hover
		var old_hover := hovered_star
		hovered_star = _hit_test(event.position)
		if hovered_star != old_hover:
			queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			if selected_star:
				selected_star = null
				_update_ui()
				queue_redraw()
			else:
				get_tree().quit()

		KEY_ENTER, KEY_KP_ENTER:
			if selected_star:
				system_requested.emit(current_sector, selected_star.index)

		KEY_HOME:
			view_offset = Vector2.ZERO
			view_scale = 1.0
			queue_redraw()

		# Navigate sectors with arrow keys + shift
		KEY_LEFT:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(-1, 0, 0))
		KEY_RIGHT:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(1, 0, 0))
		KEY_UP:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(0, 0, -1))
		KEY_DOWN:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(0, 0, 1))
		KEY_PAGEUP:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(0, 1, 0))
		KEY_PAGEDOWN:
			if event.shift_pressed:
				_load_sector(current_sector + Vector3i(0, -1, 0))


func _zoom(factor: float, focus_point: Vector2) -> void:
	var old_scale := view_scale
	view_scale = clampf(view_scale * factor, min_scale, max_scale)

	# Zoom toward mouse position
	if view_scale != old_scale:
		var viewport_center := get_viewport_rect().size / 2.0
		var mouse_offset := focus_point - viewport_center
		view_offset -= mouse_offset * (1.0 / old_scale - 1.0 / view_scale)
		queue_redraw()


func _hit_test(screen_pos: Vector2) -> GalaxyGenerator.StarData:
	var viewport_size := get_viewport_rect().size
	var center := viewport_size / 2.0
	var hit_radius := STAR_BASE_SIZE * view_scale * 2.0

	for star in stars:
		var star_screen := _world_to_screen(star.position, center)
		if screen_pos.distance_to(star_screen) <= hit_radius:
			return star

	return null


## Public API

func go_to_sector(sector: Vector3i) -> void:
	_load_sector(sector)


func select_star_by_index(index: int) -> void:
	for star in stars:
		if star.index == index:
			selected_star = star
			star_selected.emit(selected_star)
			_update_ui()
			queue_redraw()
			return
