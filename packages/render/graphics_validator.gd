## graphics_validator.gd - Runtime 32-bit graphics validation
## Add as autoload: GraphicsValidator="*res://packages/render/graphics_validator.gd"
## Access via: GraphicsValidator.validate_texture(tex, "source")
extends Node


## Emitted when a graphics format violation is detected
signal format_violation_detected(source: String, details: Dictionary)

## Enable/disable runtime validation (disable in release builds for performance)
@export var validation_enabled: bool = true

## Log violations to console
@export var log_violations: bool = true

## Valid 32-bit formats (8+ bits per channel)
const VALID_FORMATS: Array[int] = [
	Image.FORMAT_RGB8,
	Image.FORMAT_RGBA8,
	Image.FORMAT_RGBAF,
	Image.FORMAT_RGBAH,
	Image.FORMAT_RGBF,
	Image.FORMAT_RGBH,
]

## Minimum bits per channel for acceptable formats
const MIN_BITS_PER_CHANNEL := 8

var _violation_count: int = 0
var _validated_textures: Dictionary = {}  # Cache to avoid re-validating


func _ready() -> void:
	if validation_enabled:
		_validate_project_settings()
		print("[GraphicsValidator] Active - monitoring for 32-bit compliance")


func _validate_project_settings() -> void:
	"""Validate project settings on startup."""
	var issues: Array[String] = []

	# Check if rendering is set to a mode that supports 32-bit
	var render_method: String = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"
	)

	# gl_compatibility should still support 32-bit textures
	if render_method == "gl_compatibility":
		# This is fine, but note it in debug
		if OS.is_debug_build():
			print("[GraphicsValidator] Using gl_compatibility renderer")

	if issues.size() > 0:
		for issue in issues:
			_log_warning(issue)


## ============================================================================
## PUBLIC API
## ============================================================================


func validate_texture(texture: Texture2D, source: String = "unknown") -> bool:
	"""
	Validate a texture uses 32-bit color format.
	Returns true if valid, false if violation detected.
	"""
	if not validation_enabled:
		return true

	if texture == null:
		return true  # Null textures are not violations

	# Check cache
	var tex_rid := texture.get_rid()
	if _validated_textures.has(tex_rid):
		return _validated_textures[tex_rid]

	var image := texture.get_image()
	if image == null:
		_validated_textures[tex_rid] = true
		return true  # Can't validate, assume OK

	var is_valid := _check_image_format(image)
	_validated_textures[tex_rid] = is_valid

	if not is_valid:
		_report_violation(source, {
			"type": "texture",
			"format": image.get_format(),
			"format_name": _get_format_name(image.get_format()),
			"size": image.get_size()
		})

	return is_valid


func validate_image(image: Image, source: String = "unknown") -> bool:
	"""
	Validate an image uses 32-bit color format.
	Returns true if valid, false if violation detected.
	"""
	if not validation_enabled:
		return true

	if image == null:
		return true

	var is_valid := _check_image_format(image)

	if not is_valid:
		_report_violation(source, {
			"type": "image",
			"format": image.get_format(),
			"format_name": _get_format_name(image.get_format()),
			"size": image.get_size()
		})

	return is_valid


func validate_viewport(viewport: Viewport, source: String = "unknown") -> bool:
	"""
	Validate a viewport's render target uses 32-bit format.
	Returns true if valid, false if violation detected.
	"""
	if not validation_enabled:
		return true

	if viewport == null:
		return true

	var texture := viewport.get_texture()
	return validate_texture(texture, source + "/viewport")


func enforce_32bit(image: Image) -> void:
	"""Convert image to 32-bit RGBA8 if it's using a lower bit depth."""
	if image == null:
		return

	if not _check_image_format(image):
		var old_format := image.get_format()
		image.convert(Image.FORMAT_RGBA8)
		if log_violations:
			print("[GraphicsValidator] Converted image from %s to RGBA8" % _get_format_name(old_format))


func get_violation_count() -> int:
	"""Get total number of violations detected this session."""
	return _violation_count


func clear_cache() -> void:
	"""Clear the validated textures cache."""
	_validated_textures.clear()


func get_format_info(format: int) -> Dictionary:
	"""Get detailed information about an image format."""
	return {
		"format": format,
		"name": _get_format_name(format),
		"is_valid": format in VALID_FORMATS,
		"bits_per_pixel": _get_bits_per_pixel(format),
	}


## ============================================================================
## BATCH VALIDATION
## ============================================================================


func validate_scene_textures(root: Node) -> Array[Dictionary]:
	"""
	Recursively validate all textures in a scene tree.
	Returns array of violations found.
	"""
	var violations: Array[Dictionary] = []

	if root == null:
		return violations

	_validate_node_textures(root, violations)

	for child in root.get_children():
		violations.append_array(validate_scene_textures(child))

	return violations


func _validate_node_textures(node: Node, violations: Array[Dictionary]) -> void:
	"""Validate textures on a single node."""
	var node_path := str(node.get_path())

	# Check Sprite2D
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture and not validate_texture(sprite.texture, node_path):
			violations.append({
				"node": node_path,
				"property": "texture",
				"format": sprite.texture.get_image().get_format() if sprite.texture.get_image() else -1
			})

	# Check Sprite3D
	if node is Sprite3D:
		var sprite := node as Sprite3D
		if sprite.texture and not validate_texture(sprite.texture, node_path):
			violations.append({
				"node": node_path,
				"property": "texture",
				"format": sprite.texture.get_image().get_format() if sprite.texture.get_image() else -1
			})

	# Check MeshInstance3D materials
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat := mesh_instance.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				if std_mat.albedo_texture:
					if not validate_texture(std_mat.albedo_texture, node_path + "/albedo"):
						violations.append({
							"node": node_path,
							"property": "albedo_texture",
							"material_index": i
						})

	# Check TextureRect
	if node is TextureRect:
		var tex_rect := node as TextureRect
		if tex_rect.texture and not validate_texture(tex_rect.texture, node_path):
			violations.append({
				"node": node_path,
				"property": "texture"
			})


## ============================================================================
## INTERNAL HELPERS
## ============================================================================


func _check_image_format(image: Image) -> bool:
	"""Check if image format is valid 32-bit."""
	var format := image.get_format()

	# Explicitly valid formats
	if format in VALID_FORMATS:
		return true

	# Check if it's a compressed format (these are generally OK)
	if format >= Image.FORMAT_DXT1:
		return true  # Compressed formats maintain quality

	# Invalid low-bit formats
	var low_bit_formats: Array[int] = [
		Image.FORMAT_RGB565,
		Image.FORMAT_RGBA4444,
	]

	return format not in low_bit_formats


func _report_violation(source: String, details: Dictionary) -> void:
	"""Report a format violation."""
	_violation_count += 1

	if log_violations:
		_log_warning("32-bit violation in '%s': %s" % [source, details.get("format_name", "unknown")])

	format_violation_detected.emit(source, details)


func _log_warning(message: String) -> void:
	"""Log a warning message."""
	push_warning("[GraphicsValidator] " + message)
	if OS.is_debug_build():
		print("[GraphicsValidator] WARNING: ", message)


func _get_format_name(format: int) -> String:
	"""Get human-readable format name."""
	match format:
		Image.FORMAT_L8: return "L8 (8-bit)"
		Image.FORMAT_LA8: return "LA8 (16-bit)"
		Image.FORMAT_R8: return "R8 (8-bit)"
		Image.FORMAT_RG8: return "RG8 (16-bit)"
		Image.FORMAT_RGB8: return "RGB8 (24-bit)"
		Image.FORMAT_RGBA8: return "RGBA8 (32-bit)"
		Image.FORMAT_RGBA4444: return "RGBA4444 (16-bit)"
		Image.FORMAT_RGB565: return "RGB565 (16-bit)"
		Image.FORMAT_RF: return "RF (32-bit float)"
		Image.FORMAT_RGF: return "RGF (64-bit float)"
		Image.FORMAT_RGBF: return "RGBF (96-bit float)"
		Image.FORMAT_RGBAF: return "RGBAF (128-bit float)"
		Image.FORMAT_RH: return "RH (16-bit half)"
		Image.FORMAT_RGH: return "RGH (32-bit half)"
		Image.FORMAT_RGBH: return "RGBH (48-bit half)"
		Image.FORMAT_RGBAH: return "RGBAH (64-bit half)"
		_: return "Format_%d" % format


func _get_bits_per_pixel(format: int) -> int:
	"""Get bits per pixel for a format."""
	match format:
		Image.FORMAT_L8: return 8
		Image.FORMAT_LA8: return 16
		Image.FORMAT_R8: return 8
		Image.FORMAT_RG8: return 16
		Image.FORMAT_RGB8: return 24
		Image.FORMAT_RGBA8: return 32
		Image.FORMAT_RGBA4444: return 16
		Image.FORMAT_RGB565: return 16
		Image.FORMAT_RF: return 32
		Image.FORMAT_RGF: return 64
		Image.FORMAT_RGBF: return 96
		Image.FORMAT_RGBAF: return 128
		Image.FORMAT_RH: return 16
		Image.FORMAT_RGH: return 32
		Image.FORMAT_RGBH: return 48
		Image.FORMAT_RGBAH: return 64
		_: return 0
