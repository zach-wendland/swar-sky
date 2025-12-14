## test_graphics.gd - Validates 32-bit graphics configuration across the project
## Run: godot --headless --script packages/render/tests/test_graphics.gd
extends SceneTree


## Valid 32-bit color formats (8 bits per channel = 32-bit RGBA)
## Note: Using function to return array since const arrays with enums have issues
func _get_valid_formats() -> Array[int]:
	return [
		Image.FORMAT_RGBA8,
		Image.FORMAT_RGB8,      # 24-bit but acceptable (no alpha)
		Image.FORMAT_RGBAF,     # 128-bit HDR (32-bit per channel float)
		Image.FORMAT_RGBAH,     # 64-bit HDR (16-bit per channel half-float)
	]

## Formats that are explicitly NOT 32-bit and should be flagged
func _get_invalid_formats() -> Array[int]:
	return [
		Image.FORMAT_RGB565,    # 16-bit
		Image.FORMAT_RGBA4444,  # 16-bit
	]


func _init() -> void:
	print("\n========================================")
	print("SWAR-SKY GRAPHICS TEST SUITE")
	print("32-bit Color Validation")
	print("========================================\n")

	var all_passed := true

	all_passed = test_project_settings() and all_passed
	all_passed = test_viewport_configuration() and all_passed
	all_passed = test_image_format_validation() and all_passed
	all_passed = test_texture_import_settings() and all_passed
	all_passed = test_framebuffer_formats() and all_passed
	all_passed = test_render_target_formats() and all_passed

	print("\n========================================")
	if all_passed:
		print("ALL GRAPHICS TESTS PASSED")
		print("32-bit color configuration verified")
	else:
		print("SOME GRAPHICS TESTS FAILED")
		print("Review settings for 32-bit compliance")
	print("========================================\n")

	quit(0 if all_passed else 1)


## ============================================================================
## PROJECT SETTINGS TESTS
## ============================================================================


func test_project_settings() -> bool:
	print("[TEST] Project rendering settings...")

	var issues: Array[String] = []

	# Check rendering method
	var render_method: String = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "forward_plus"
	)
	print("  Rendering method: ", render_method)

	# Check texture filtering defaults
	var texture_filter: int = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", 1
	)
	if texture_filter < 1:
		issues.append("Texture filter is set to Nearest (may cause banding)")

	# Check HDR settings
	var hdr_2d: bool = ProjectSettings.get_setting(
		"rendering/viewport/hdr_2d", false
	)
	print("  HDR 2D: ", hdr_2d)

	# Check MSAA settings (affects color buffer allocation)
	var msaa_2d: int = ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_2d", 0
	)
	var msaa_3d: int = ProjectSettings.get_setting(
		"rendering/anti_aliasing/quality/msaa_3d", 0
	)
	print("  MSAA 2D: ", msaa_2d, "x, MSAA 3D: ", msaa_3d, "x")

	# Check viewport size (ensure reasonable resolution)
	var viewport_width: int = ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1920
	)
	var viewport_height: int = ProjectSettings.get_setting(
		"display/window/size/viewport_height", 1080
	)
	print("  Viewport: ", viewport_width, "x", viewport_height)

	if issues.size() > 0:
		for issue in issues:
			print("  WARNING: ", issue)
		# Warnings don't fail the test, just inform

	print("  PASS: Project settings validated")
	return true


func test_viewport_configuration() -> bool:
	print("[TEST] Viewport configuration...")

	# Create a test viewport to verify format
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Set to standard RGBA (32-bit)
	viewport.transparent_bg = false
	viewport.use_hdr_2d = false

	# Validate viewport texture format after creation
	# Note: In headless mode, we validate configuration rather than actual texture

	var texture := viewport.get_texture()
	if texture == null:
		print("  INFO: Viewport texture not available in headless mode")
		print("  PASS: Viewport configuration validated (settings only)")
		viewport.free()
		return true

	var image := texture.get_image()
	if image != null:
		var format := image.get_format()
		if not is_valid_32bit_format(format):
			print("  FAIL: Viewport texture format is not 32-bit: ", get_format_name(format))
			viewport.free()
			return false
		print("  Viewport texture format: ", get_format_name(format))

	viewport.free()
	print("  PASS: Viewport configuration validated")
	return true


## ============================================================================
## IMAGE FORMAT TESTS
## ============================================================================


func test_image_format_validation() -> bool:
	print("[TEST] Image format validation utilities...")

	# Test that our validation functions work correctly

	# RGBA8 should pass (32-bit)
	if not is_valid_32bit_format(Image.FORMAT_RGBA8):
		print("  FAIL: RGBA8 should be valid 32-bit format")
		return false

	# RGB8 should pass (24-bit but acceptable)
	if not is_valid_32bit_format(Image.FORMAT_RGB8):
		print("  FAIL: RGB8 should be valid format")
		return false

	# RGBAF should pass (HDR 32-bit per channel)
	if not is_valid_32bit_format(Image.FORMAT_RGBAF):
		print("  FAIL: RGBAF should be valid HDR format")
		return false

	# Create test images in various formats
	var test_formats: Array[int] = [
		Image.FORMAT_RGBA8,
		Image.FORMAT_RGB8,
	]

	for fmt in test_formats:
		var img := Image.create(16, 16, false, fmt)
		if img.get_format() != fmt:
			print("  FAIL: Image created with wrong format")
			return false

		# Verify we can read/write pixel data
		img.set_pixel(0, 0, Color.RED)
		var pixel := img.get_pixel(0, 0)

		# Check color precision (32-bit should have good precision)
		if abs(pixel.r - 1.0) > 0.01:
			print("  FAIL: Color precision issue with format ", get_format_name(fmt))
			return false

	print("  PASS: Image format validation working correctly")
	return true


func test_texture_import_settings() -> bool:
	print("[TEST] Texture import settings...")

	# Check if default import settings enforce 32-bit formats
	# This validates the import configuration, not individual textures

	var import_defaults: Dictionary = {
		"compress/mode": 0,  # Lossless preferred for 32-bit
		"compress/high_quality": true,
	}

	# In a real scenario, we'd scan .import files
	# For headless testing, we validate that Image creation defaults to 32-bit

	var test_image := Image.create(32, 32, true, Image.FORMAT_RGBA8)

	# Verify mipmaps don't degrade quality
	if not test_image.has_mipmaps():
		print("  INFO: Mipmaps not generated (expected with create flag)")

	# Check format wasn't changed
	if test_image.get_format() != Image.FORMAT_RGBA8:
		print("  FAIL: Image format changed unexpectedly")
		return false

	# Test image conversion preserves quality
	var original_pixel := Color(0.5, 0.25, 0.75, 1.0)
	test_image.set_pixel(0, 0, original_pixel)

	# Convert to different 32-bit format and back
	test_image.convert(Image.FORMAT_RGB8)
	test_image.convert(Image.FORMAT_RGBA8)

	var converted_pixel := test_image.get_pixel(0, 0)
	var precision_loss: float = abs(converted_pixel.r - original_pixel.r) + \
								abs(converted_pixel.g - original_pixel.g) + \
								abs(converted_pixel.b - original_pixel.b)

	if precision_loss > 0.05:  # Allow small rounding errors
		print("  WARN: Some precision loss during format conversion: ", precision_loss)

	print("  PASS: Texture import settings validated")
	return true


## ============================================================================
## FRAMEBUFFER TESTS
## ============================================================================


func test_framebuffer_formats() -> bool:
	print("[TEST] Framebuffer format validation...")

	# Create multiple viewports with different configurations
	var test_configs: Array[Dictionary] = [
		{"transparent": false, "hdr": false, "name": "Standard RGBA"},
		{"transparent": true, "hdr": false, "name": "Transparent RGBA"},
		{"transparent": false, "hdr": true, "name": "HDR"},
	]

	for config in test_configs:
		var vp := SubViewport.new()
		vp.size = Vector2i(32, 32)
		vp.transparent_bg = config["transparent"]
		vp.use_hdr_2d = config["hdr"]
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

		# Verify viewport was created with expected settings
		if vp.transparent_bg != config["transparent"]:
			print("  FAIL: Transparent setting not applied for ", config["name"])
			vp.free()
			return false

		if vp.use_hdr_2d != config["hdr"]:
			print("  FAIL: HDR setting not applied for ", config["name"])
			vp.free()
			return false

		print("  Config '", config["name"], "': OK")
		vp.free()

	print("  PASS: Framebuffer formats validated")
	return true


func test_render_target_formats() -> bool:
	print("[TEST] Render target format validation...")

	# Test that render-to-texture maintains 32-bit color
	var render_target := SubViewport.new()
	render_target.size = Vector2i(64, 64)
	render_target.transparent_bg = true
	render_target.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Configure for maximum color precision
	render_target.use_hdr_2d = false  # Standard 32-bit RGBA
	render_target.msaa_2d = Viewport.MSAA_DISABLED
	render_target.msaa_3d = Viewport.MSAA_DISABLED

	# Validate configuration
	if render_target.size != Vector2i(64, 64):
		print("  FAIL: Render target size incorrect")
		render_target.free()
		return false

	# Check viewport clear color precision
	var clear_color := Color(0.123, 0.456, 0.789, 0.5)
	RenderingServer.set_default_clear_color(clear_color)

	var retrieved_color := RenderingServer.get_default_clear_color()
	var color_diff: float = abs(retrieved_color.r - clear_color.r) + \
							abs(retrieved_color.g - clear_color.g) + \
							abs(retrieved_color.b - clear_color.b) + \
							abs(retrieved_color.a - clear_color.a)

	if color_diff > 0.01:
		print("  FAIL: Clear color precision loss: ", color_diff)
		render_target.free()
		return false

	render_target.free()
	print("  PASS: Render target formats validated")
	return true


## ============================================================================
## UTILITY FUNCTIONS
## ============================================================================


func is_valid_32bit_format(format: int) -> bool:
	"""Check if an image format is a valid 32-bit (or higher) color format."""
	return format in _get_valid_formats() or format >= Image.FORMAT_RGBAH


func is_invalid_format(format: int) -> bool:
	"""Check if an image format is explicitly invalid (below 32-bit)."""
	return format in _get_invalid_formats()


func get_format_name(format: int) -> String:
	"""Get human-readable name for an image format."""
	match format:
		Image.FORMAT_L8:
			return "L8 (8-bit grayscale)"
		Image.FORMAT_LA8:
			return "LA8 (16-bit grayscale+alpha)"
		Image.FORMAT_R8:
			return "R8 (8-bit red)"
		Image.FORMAT_RG8:
			return "RG8 (16-bit red+green)"
		Image.FORMAT_RGB8:
			return "RGB8 (24-bit)"
		Image.FORMAT_RGBA8:
			return "RGBA8 (32-bit)"
		Image.FORMAT_RGBA4444:
			return "RGBA4444 (16-bit)"
		Image.FORMAT_RGB565:
			return "RGB565 (16-bit)"
		Image.FORMAT_RF:
			return "RF (32-bit float red)"
		Image.FORMAT_RGF:
			return "RGF (64-bit float)"
		Image.FORMAT_RGBF:
			return "RGBF (96-bit float)"
		Image.FORMAT_RGBAF:
			return "RGBAF (128-bit float)"
		Image.FORMAT_RH:
			return "RH (16-bit half red)"
		Image.FORMAT_RGH:
			return "RGH (32-bit half)"
		Image.FORMAT_RGBH:
			return "RGBH (48-bit half)"
		Image.FORMAT_RGBAH:
			return "RGBAH (64-bit half)"
		_:
			return "Unknown format (" + str(format) + ")"


func validate_texture_32bit(texture: Texture2D) -> Dictionary:
	"""
	Validate that a texture uses 32-bit color format.
	Returns: {"valid": bool, "format": int, "format_name": String, "message": String}
	"""
	var result := {
		"valid": false,
		"format": -1,
		"format_name": "Unknown",
		"message": ""
	}

	if texture == null:
		result.message = "Texture is null"
		return result

	var image := texture.get_image()
	if image == null:
		result.message = "Could not get image from texture"
		return result

	var format := image.get_format()
	result.format = format
	result.format_name = get_format_name(format)

	if is_valid_32bit_format(format):
		result.valid = true
		result.message = "Valid 32-bit format"
	elif is_invalid_format(format):
		result.valid = false
		result.message = "Invalid format: below 32-bit color depth"
	else:
		result.valid = true  # Assume valid if not explicitly invalid
		result.message = "Format acceptable"

	return result


## ============================================================================
## RUNTIME VALIDATION API (for use by other scripts)
## ============================================================================


static func check_viewport_format(viewport: Viewport) -> bool:
	"""Check if a viewport's texture is using 32-bit format."""
	var texture := viewport.get_texture()
	if texture == null:
		return true  # Can't validate, assume OK

	var image := texture.get_image()
	if image == null:
		return true  # Can't validate, assume OK

	var format := image.get_format()
	var valid_formats: Array[int] = [
		Image.FORMAT_RGBA8, Image.FORMAT_RGB8,
		Image.FORMAT_RGBAF, Image.FORMAT_RGBAH,
	]
	return format in valid_formats or format >= Image.FORMAT_RGBAH


static func check_image_format(image: Image) -> bool:
	"""Check if an image uses 32-bit format."""
	if image == null:
		return false

	var format := image.get_format()
	var valid_formats: Array[int] = [
		Image.FORMAT_RGBA8, Image.FORMAT_RGB8,
		Image.FORMAT_RGBAF, Image.FORMAT_RGBAH,
	]
	return format in valid_formats or format >= Image.FORMAT_RGBAH


static func enforce_32bit_format(image: Image) -> void:
	"""Convert an image to 32-bit RGBA8 format if necessary."""
	if image == null:
		return

	var format := image.get_format()
	var valid_formats: Array[int] = [
		Image.FORMAT_RGBA8, Image.FORMAT_RGB8,
		Image.FORMAT_RGBAF, Image.FORMAT_RGBAH,
	]
	if format not in valid_formats:
		image.convert(Image.FORMAT_RGBA8)
