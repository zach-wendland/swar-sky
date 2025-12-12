## ship_controller.gd - Spaceship flight controller
## 6-DOF simplified flight with arcade-style handling
class_name ShipController
extends Node3D


signal position_changed(pos: Vector3)
signal speed_changed(speed: float)
signal target_planet_changed(body: SystemGenerator.OrbitalBody)
signal landing_requested(body: SystemGenerator.OrbitalBody)


## Ship physics
@export var max_speed: float = 500.0  # Units per second
@export var boost_multiplier: float = 3.0
@export var acceleration: float = 200.0
@export var deceleration: float = 150.0
@export var rotation_speed: float = 2.0
@export var roll_speed: float = 1.5

## Current state
var velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_boosting: bool = false
var throttle: float = 0.0  # 0-1 for forward thrust

## Targeting
var target_body: SystemGenerator.OrbitalBody = null
var nearby_bodies: Array[SystemGenerator.OrbitalBody] = []
var landing_distance: float = 50.0  # Distance to trigger landing option

## Camera reference
var camera: Camera3D = null
var camera_pivot: Node3D = null

## Ship visual
var ship_mesh: MeshInstance3D = null
var engine_light: OmniLight3D = null

## Mouse input
var mouse_delta: Vector2 = Vector2.ZERO
var mouse_captured: bool = true


func _ready() -> void:
	_setup_ship_visual()
	_setup_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_ship_visual() -> void:
	# Create a simple ship mesh (cone shape pointing forward)
	ship_mesh = MeshInstance3D.new()
	ship_mesh.name = "ShipMesh"

	# Create ship geometry using a prism/cone
	var ship_body := PrismMesh.new()
	ship_body.size = Vector3(1.5, 3.0, 0.8)  # Wing span, length, height
	ship_mesh.mesh = ship_body

	# Rotate so it points forward (-Z)
	ship_mesh.rotation_degrees = Vector3(90, 0, 0)

	# Ship material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4)
	mat.metallic = 0.7
	mat.roughness = 0.3
	ship_mesh.material_override = mat

	add_child(ship_mesh)

	# Engine glow light
	engine_light = OmniLight3D.new()
	engine_light.name = "EngineLight"
	engine_light.light_color = Color(0.5, 0.7, 1.0)
	engine_light.light_energy = 0.5
	engine_light.omni_range = 5.0
	engine_light.position = Vector3(0, 0, 1.5)  # Behind ship
	add_child(engine_light)


func _setup_camera() -> void:
	# Create camera pivot (for smooth following)
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)

	# Create camera
	camera = Camera3D.new()
	camera.name = "ShipCamera"
	camera.position = Vector3(0, 3, 15)  # Behind and above ship
	camera.fov = 75.0
	camera_pivot.add_child(camera)
	camera.look_at(Vector3.ZERO)


func _process(delta: float) -> void:
	_handle_input(delta)
	_update_movement(delta)
	_update_camera(delta)
	_check_nearby_bodies()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		mouse_delta += event.relative

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_toggle_mouse_capture()
			KEY_T:
				_cycle_target()
			KEY_F:
				_request_landing()


func _handle_input(delta: float) -> void:
	# Throttle control - W/S or Arrow Up/Down
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		throttle = minf(throttle + delta * 2.0, 1.0)
	elif Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		throttle = maxf(throttle - delta * 2.0, 0.0)

	# Mouse steering
	var pitch_input := 0.0
	var yaw_input := 0.0
	var roll_input := 0.0

	if mouse_captured:
		pitch_input = mouse_delta.y * 0.002
		yaw_input = mouse_delta.x * 0.002
		mouse_delta = Vector2.ZERO

	# Keyboard roll
	if Input.is_key_pressed(KEY_Q):
		roll_input = roll_speed * delta
	if Input.is_key_pressed(KEY_E):
		roll_input = -roll_speed * delta

	# Apply rotation
	rotate_object_local(Vector3.RIGHT, -pitch_input)
	rotate_object_local(Vector3.UP, -yaw_input)
	rotate_object_local(Vector3.FORWARD, roll_input)

	# Boost
	is_boosting = Input.is_key_pressed(KEY_SHIFT)

	# Strafe left/right with A/D
	var strafe := Vector3.ZERO
	if Input.is_key_pressed(KEY_A):
		strafe.x = -1.0
	if Input.is_key_pressed(KEY_D):
		strafe.x = 1.0

	# Convert strafe to world space velocity contribution
	if strafe != Vector3.ZERO:
		var strafe_world := global_transform.basis * strafe.normalized()
		velocity += strafe_world * acceleration * delta * 0.5


func _update_movement(delta: float) -> void:
	var effective_max := max_speed * (boost_multiplier if is_boosting else 1.0)

	# Forward thrust based on throttle
	var forward_dir := -global_transform.basis.z
	var target_velocity := forward_dir * throttle * effective_max

	# Blend current velocity toward target
	if throttle > 0.01:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		# Decelerate when no throttle
		velocity = velocity.move_toward(Vector3.ZERO, deceleration * delta * 0.5)

	# Apply movement
	global_position += velocity * delta

	# Update speed
	current_speed = velocity.length()
	speed_changed.emit(current_speed)
	position_changed.emit(global_position)

	# Update engine glow based on throttle
	if engine_light:
		var intensity := 0.2 + throttle * 1.5
		if is_boosting:
			intensity *= 2.0
			engine_light.light_color = Color(0.8, 0.5, 0.3)  # Orange for boost
		else:
			engine_light.light_color = Color(0.5, 0.7, 1.0)  # Blue for normal
		engine_light.light_energy = intensity


func _update_camera(delta: float) -> void:
	if not camera or not camera_pivot:
		return

	# Camera follows ship smoothly
	var target_distance := 15.0 + current_speed * 0.02  # Pull back at speed
	var target_fov := 75.0 + current_speed * 0.05  # Widen FOV at speed

	camera.position = camera.position.lerp(Vector3(0, 3, target_distance), delta * 5.0)
	camera.fov = lerpf(camera.fov, clampf(target_fov, 75.0, 100.0), delta * 3.0)


func _check_nearby_bodies() -> void:
	if nearby_bodies.is_empty():
		return

	var closest: SystemGenerator.OrbitalBody = null
	var closest_dist := INF

	for body in nearby_bodies:
		var body_pos := _get_body_world_position(body)
		var dist := global_position.distance_to(body_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = body

	if closest != target_body:
		target_body = closest
		target_planet_changed.emit(target_body)


func _get_body_world_position(body: SystemGenerator.OrbitalBody) -> Vector3:
	# This would be calculated based on current orbit time
	# For now, return a placeholder - will be set by SystemSpace scene
	return body.get_meta("world_position", Vector3.ZERO)


func _toggle_mouse_capture() -> void:
	mouse_captured = not mouse_captured
	if mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cycle_target() -> void:
	if nearby_bodies.is_empty():
		return

	var current_idx := nearby_bodies.find(target_body)
	var next_idx := (current_idx + 1) % nearby_bodies.size()
	target_body = nearby_bodies[next_idx]
	target_planet_changed.emit(target_body)


func _request_landing() -> void:
	if target_body == null:
		return

	var body_pos := _get_body_world_position(target_body)
	var dist := global_position.distance_to(body_pos)

	if dist < landing_distance:
		landing_requested.emit(target_body)


## Set nearby bodies for targeting
func set_nearby_bodies(bodies: Array[SystemGenerator.OrbitalBody]) -> void:
	nearby_bodies = bodies


## Get current ship data
func get_ship_data() -> Dictionary:
	return {
		"position": global_position,
		"rotation": global_rotation,
		"velocity": velocity,
		"speed": current_speed,
		"throttle": throttle,
		"is_boosting": is_boosting,
	}


## Set ship position and orientation (for spawning)
func set_ship_state(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	global_position = pos
	global_rotation = rot
	velocity = Vector3.ZERO
	throttle = 0.0


## Distance to target body
func get_distance_to_target() -> float:
	if target_body == null:
		return -1.0
	var body_pos := _get_body_world_position(target_body)
	return global_position.distance_to(body_pos)


## Check if close enough to land
func can_land() -> bool:
	return target_body != null and get_distance_to_target() < landing_distance
