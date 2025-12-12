## character_controller.gd - Third-person character controller for planet exploration
## Handles movement, camera, and terrain following
class_name CharacterController
extends Node3D


signal position_changed(world_pos: Vector3)

## Movement settings
@export var move_speed: float = 10.0
@export var run_multiplier: float = 2.0
@export var jump_velocity: float = 8.0
@export var gravity: float = 20.0
@export var turn_speed: float = 10.0

## Camera settings
@export var camera_distance: float = 8.0
@export var camera_height: float = 3.0
@export var camera_smoothing: float = 5.0
@export var camera_sensitivity: float = 0.003
@export var min_pitch: float = -80.0
@export var max_pitch: float = 60.0

## References
var tile_streamer: TileStreamer = null

## State
var _velocity: Vector3 = Vector3.ZERO
var _is_grounded: bool = false
var _camera_yaw: float = 0.0
var _camera_pitch: float = -20.0
var _target_position: Vector3 = Vector3.ZERO
var _mouse_captured: bool = true

## Child nodes (created in _ready)
var _character_body: Node3D = null
var _camera_pivot: Node3D = null
var _camera: Camera3D = null
var _character_mesh: MeshInstance3D = null


func _ready() -> void:
	_create_character()
	_create_camera()

	# Capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true


func _create_character() -> void:
	# Character body (visual representation)
	_character_body = Node3D.new()
	_character_body.name = "CharacterBody"
	add_child(_character_body)

	# Simple capsule mesh for the character
	_character_mesh = MeshInstance3D.new()
	_character_mesh.name = "CharacterMesh"

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_character_mesh.mesh = capsule

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.4, 0.8)
	_character_mesh.material_override = mat

	_character_mesh.position.y = 0.9  # Half height
	_character_body.add_child(_character_mesh)


func _create_camera() -> void:
	# Camera pivot (for rotation)
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	add_child(_camera_pivot)

	# Camera
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 70.0
	_camera.far = 5000.0
	_camera_pivot.add_child(_camera)

	# Initial camera position
	_update_camera_position(1.0)


func _process(delta: float) -> void:
	_handle_input(delta)
	_update_physics(delta)
	_update_camera_position(delta)

	# Notify streamer of position
	if tile_streamer:
		tile_streamer.update_player_position(global_position)

	position_changed.emit(global_position)


func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and _mouse_captured:
		_camera_yaw -= event.relative.x * camera_sensitivity
		_camera_pitch -= event.relative.y * camera_sensitivity
		_camera_pitch = clampf(_camera_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

	# Toggle mouse capture
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_mouse_captured = not _mouse_captured
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
			)


func _handle_input(delta: float) -> void:
	# Movement input
	var input_dir := Vector3.ZERO

	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1

	# Transform input to world space based on camera yaw
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		var yaw_transform := Transform3D().rotated(Vector3.UP, _camera_yaw)
		input_dir = yaw_transform * input_dir

	# Apply speed
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= run_multiplier

	_target_position = input_dir * speed

	# Jump
	if (Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)) and _is_grounded:
		_velocity.y = jump_velocity


func _update_physics(delta: float) -> void:
	# Horizontal movement
	_velocity.x = _target_position.x
	_velocity.z = _target_position.z

	# Gravity
	if not _is_grounded:
		_velocity.y -= gravity * delta

	# Get terrain height at current position
	var terrain_height := 0.0
	if tile_streamer:
		terrain_height = tile_streamer.get_height_at(global_position)

	# Apply movement
	global_position += _velocity * delta

	# Ground check and snap
	var character_bottom := global_position.y
	if character_bottom <= terrain_height + 0.1:
		global_position.y = terrain_height
		_velocity.y = maxf(_velocity.y, 0.0)
		_is_grounded = true
	else:
		_is_grounded = false

	# Rotate character body to face movement direction
	if _velocity.length_squared() > 0.1:
		var target_angle := atan2(_velocity.x, _velocity.z)
		_character_body.rotation.y = lerp_angle(_character_body.rotation.y, target_angle, delta * turn_speed)


func _update_camera_position(delta: float) -> void:
	# Update pivot rotation
	_camera_pivot.rotation.y = _camera_yaw
	_camera_pivot.rotation.x = _camera_pitch

	# Camera position relative to pivot
	var camera_offset := Vector3(0, camera_height, camera_distance)
	_camera.position = camera_offset

	# Pivot follows character with smoothing
	var target_pivot_pos := global_position + Vector3(0, 1.5, 0)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(
		target_pivot_pos,
		delta * camera_smoothing
	)

	# Camera looks at character
	_camera.look_at(global_position + Vector3(0, 1.0, 0), Vector3.UP)


## Set initial position
func set_character_position(pos: Vector3) -> void:
	global_position = pos
	_camera_pivot.global_position = pos + Vector3(0, 1.5, 0)


## Get character world position
func get_world_position() -> Vector3:
	return global_position


## Check if character is grounded
func is_grounded() -> bool:
	return _is_grounded


## Get camera reference
func get_camera() -> Camera3D:
	return _camera
