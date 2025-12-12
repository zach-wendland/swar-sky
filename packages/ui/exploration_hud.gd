## exploration_hud.gd - HUD for planet surface exploration
## Shows compass, objective markers, and interaction prompts
class_name ExplorationHUD
extends CanvasLayer


## References
var camera: Camera3D = null
var objective_system: ObjectiveSystem = null
var ship_landing: ShipLanding = null
var poi_renderer: POIRenderer = null

## UI elements
var compass_container: Control = null
var compass_needle: Control = null
var objective_label: Label = null
var objective_distance_label: Label = null
var interaction_prompt: Label = null
var artifact_popup: Control = null
var artifact_popup_label: Label = null

## Marker elements
var objective_marker: Control = null
var ship_marker: Control = null

## State
var player_position: Vector3 = Vector3.ZERO
var player_forward: Vector3 = Vector3.FORWARD
var popup_timer: float = 0.0


func _ready() -> void:
	_create_hud_elements()


func _process(delta: float) -> void:
	_update_compass()
	_update_markers()
	_update_objective_display()
	_update_interaction_prompt()
	_update_popup(delta)


## Create all HUD elements
func _create_hud_elements() -> void:
	# Compass at top center
	_create_compass()

	# Objective info at top left
	_create_objective_display()

	# Screen-edge markers
	_create_markers()

	# Interaction prompt at bottom center
	_create_interaction_prompt()

	# Artifact collection popup
	_create_artifact_popup()


## Create compass UI
func _create_compass() -> void:
	compass_container = Control.new()
	compass_container.name = "Compass"
	compass_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass_container.position = Vector2(-100, 10)
	compass_container.size = Vector2(200, 50)
	add_child(compass_container)

	# Compass background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.7)
	bg.size = Vector2(200, 40)
	compass_container.add_child(bg)

	# Direction labels
	var directions := ["N", "E", "S", "W"]
	for i in range(4):
		var label := Label.new()
		label.text = directions[i]
		label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		label.add_theme_font_size_override("font_size", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(i * 50 + 15, 10)
		label.size = Vector2(20, 20)
		compass_container.add_child(label)

	# Compass needle (center indicator)
	compass_needle = Control.new()
	compass_needle.name = "Needle"
	compass_needle.position = Vector2(100, 35)

	var needle_shape := ColorRect.new()
	needle_shape.color = Color(1, 0.8, 0.2)
	needle_shape.size = Vector2(4, 10)
	needle_shape.position = Vector2(-2, -5)
	compass_needle.add_child(needle_shape)
	compass_container.add_child(compass_needle)


## Create objective display
func _create_objective_display() -> void:
	var container := Control.new()
	container.name = "ObjectiveDisplay"
	container.position = Vector2(10, 140)
	container.size = Vector2(350, 80)
	add_child(container)

	# Background panel
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.12, 0.8)
	bg.size = Vector2(350, 70)
	container.add_child(bg)

	# Objective icon
	var icon := Label.new()
	icon.text = ">"
	icon.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	icon.add_theme_font_size_override("font_size", 20)
	icon.position = Vector2(10, 10)
	container.add_child(icon)

	# Objective title
	objective_label = Label.new()
	objective_label.text = "No Objective"
	objective_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.position = Vector2(35, 10)
	objective_label.size = Vector2(300, 25)
	container.add_child(objective_label)

	# Distance
	objective_distance_label = Label.new()
	objective_distance_label.text = ""
	objective_distance_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	objective_distance_label.add_theme_font_size_override("font_size", 14)
	objective_distance_label.position = Vector2(35, 38)
	objective_distance_label.size = Vector2(300, 20)
	container.add_child(objective_distance_label)


## Create screen-edge markers
func _create_markers() -> void:
	# Objective marker
	objective_marker = _create_marker_element(Color(1, 0.8, 0.2), "!")
	add_child(objective_marker)

	# Ship marker
	ship_marker = _create_marker_element(Color(0.3, 0.6, 1.0), "S")
	add_child(ship_marker)


func _create_marker_element(color: Color, symbol: String) -> Control:
	var marker := Control.new()
	marker.size = Vector2(40, 40)

	# Arrow/indicator
	var bg := ColorRect.new()
	bg.color = color
	bg.size = Vector2(30, 30)
	bg.position = Vector2(5, 5)
	marker.add_child(bg)

	# Symbol
	var label := Label.new()
	label.text = symbol
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(5, 5)
	label.size = Vector2(30, 30)
	marker.add_child(label)

	return marker


## Create interaction prompt
func _create_interaction_prompt() -> void:
	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = ""
	interaction_prompt.add_theme_color_override("font_color", Color(1, 1, 0.8))
	interaction_prompt.add_theme_font_size_override("font_size", 18)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	interaction_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_prompt.position = Vector2(-200, -100)
	interaction_prompt.size = Vector2(400, 30)

	add_child(interaction_prompt)


## Create artifact collection popup
func _create_artifact_popup() -> void:
	artifact_popup = Control.new()
	artifact_popup.name = "ArtifactPopup"
	artifact_popup.set_anchors_preset(Control.PRESET_CENTER)
	artifact_popup.position = Vector2(-200, -100)
	artifact_popup.size = Vector2(400, 80)
	artifact_popup.visible = false
	add_child(artifact_popup)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.15, 0.25, 0.9)
	bg.size = Vector2(400, 80)
	artifact_popup.add_child(bg)

	# Border
	var border := ColorRect.new()
	border.color = Color(0.3, 0.5, 1.0)
	border.size = Vector2(400, 3)
	artifact_popup.add_child(border)

	var border_bottom := ColorRect.new()
	border_bottom.color = Color(0.3, 0.5, 1.0)
	border_bottom.size = Vector2(400, 3)
	border_bottom.position = Vector2(0, 77)
	artifact_popup.add_child(border_bottom)

	# Title
	var title := Label.new()
	title.text = "ARTIFACT COLLECTED"
	title.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 10)
	title.size = Vector2(400, 20)
	artifact_popup.add_child(title)

	# Artifact name
	artifact_popup_label = Label.new()
	artifact_popup_label.text = "Unknown Artifact"
	artifact_popup_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	artifact_popup_label.add_theme_font_size_override("font_size", 20)
	artifact_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	artifact_popup_label.position = Vector2(0, 35)
	artifact_popup_label.size = Vector2(400, 30)
	artifact_popup.add_child(artifact_popup_label)


## Update compass based on player direction
func _update_compass() -> void:
	if not compass_container:
		return

	# Calculate compass rotation based on player facing
	var forward_2d := Vector2(player_forward.x, player_forward.z).normalized()
	var angle := atan2(forward_2d.x, forward_2d.y)

	# Update compass position/scroll based on angle
	# This is a simplified version - could scroll direction labels
	pass


## Update screen-edge markers
func _update_markers() -> void:
	if not camera:
		return

	var viewport_size := get_viewport().get_visible_rect().size

	# Update objective marker
	if objective_system and objective_marker:
		var target := objective_system.get_objective_target()
		if target != Vector3.ZERO:
			_position_marker(objective_marker, target, viewport_size)
		else:
			objective_marker.visible = false

	# Update ship marker
	if ship_landing and ship_marker:
		_position_marker(ship_marker, ship_landing.global_position, viewport_size)


func _position_marker(marker: Control, world_pos: Vector3, viewport_size: Vector2) -> void:
	if not camera:
		marker.visible = false
		return

	# Check if behind camera
	var cam_forward := -camera.global_transform.basis.z
	var to_target := (world_pos - camera.global_position).normalized()
	var dot := cam_forward.dot(to_target)

	if dot < 0:
		# Behind camera - show at screen edge in direction
		var screen_center := viewport_size / 2
		var dir := Vector2(to_target.x, to_target.z).normalized()
		var edge_pos := screen_center + dir * minf(viewport_size.x, viewport_size.y) * 0.4
		marker.position = edge_pos - marker.size / 2
		marker.visible = true
		return

	# Project to screen
	var screen_pos := camera.unproject_position(world_pos)

	# Check if on screen
	var margin := 50.0
	if screen_pos.x >= margin and screen_pos.x <= viewport_size.x - margin and \
	   screen_pos.y >= margin and screen_pos.y <= viewport_size.y - margin:
		# On screen - show marker at position
		marker.position = screen_pos - marker.size / 2
		marker.visible = true
	else:
		# Off screen - clamp to edge
		screen_pos.x = clampf(screen_pos.x, margin, viewport_size.x - margin)
		screen_pos.y = clampf(screen_pos.y, margin, viewport_size.y - margin)
		marker.position = screen_pos - marker.size / 2
		marker.visible = true


## Update objective text display
func _update_objective_display() -> void:
	if not objective_system:
		return

	if objective_label:
		objective_label.text = objective_system.get_objective_text()

	if objective_distance_label:
		var dist := objective_system.get_objective_distance()
		if dist >= 0:
			objective_distance_label.text = "Distance: %.0f m" % dist
		else:
			objective_distance_label.text = ""


## Update interaction prompt
func _update_interaction_prompt() -> void:
	if not interaction_prompt:
		return

	var prompts: Array[String] = []

	# Check for artifact collection
	if poi_renderer and poi_renderer.can_collect_artifact():
		prompts.append("[E] Collect Artifact")

	# Check for ship boarding
	if ship_landing and ship_landing.get_can_board():
		if objective_system and objective_system.can_leave_planet():
			prompts.append("[E] Board Ship")
		else:
			prompts.append("[E] Board Ship (Collect artifact first)")

	if prompts.size() > 0:
		interaction_prompt.text = " | ".join(prompts)
		interaction_prompt.visible = true
	else:
		interaction_prompt.visible = false


## Update popup timer
func _update_popup(delta: float) -> void:
	if popup_timer > 0:
		popup_timer -= delta
		if popup_timer <= 0:
			artifact_popup.visible = false


## Show artifact collected popup
func show_artifact_collected(artifact_name: String) -> void:
	if artifact_popup_label:
		artifact_popup_label.text = artifact_name

	artifact_popup.visible = true
	popup_timer = 3.0


## Set references
func set_camera(cam: Camera3D) -> void:
	camera = cam


func set_objective_system(system: ObjectiveSystem) -> void:
	objective_system = system


func set_ship_landing(ship: ShipLanding) -> void:
	ship_landing = ship


func set_poi_renderer(renderer: POIRenderer) -> void:
	poi_renderer = renderer


## Update player state
func update_player_state(pos: Vector3, forward: Vector3) -> void:
	player_position = pos
	player_forward = forward
