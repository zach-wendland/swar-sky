## jedi_ruins.gd - Procedural Jedi temple ruins generator
## Uses grammar rules to create varied ancient temple layouts
class_name JediRuinsGenerator
extends RefCounted


## Structure element types
enum ElementType {
	ENTRANCE_ARCH,
	PILLAR,
	WALL_SEGMENT,
	FLOOR_TILE,
	ALTAR,
	MEDITATION_CIRCLE,
	STATUE,
	RUBBLE,
	STEPS,
	ARTIFACT_PEDESTAL,
	HOLOCRON_ALCOVE,
	COLLAPSED_SECTION,
}

## Element visual data
const ELEMENT_DATA: Dictionary = {
	ElementType.ENTRANCE_ARCH: {
		"mesh": "arch",
		"size": Vector3(8, 6, 2),
		"color": Color(0.6, 0.55, 0.5),
	},
	ElementType.PILLAR: {
		"mesh": "cylinder",
		"size": Vector3(1.5, 8, 1.5),
		"color": Color(0.55, 0.5, 0.45),
	},
	ElementType.WALL_SEGMENT: {
		"mesh": "box",
		"size": Vector3(6, 4, 1),
		"color": Color(0.5, 0.45, 0.4),
	},
	ElementType.FLOOR_TILE: {
		"mesh": "box",
		"size": Vector3(4, 0.3, 4),
		"color": Color(0.45, 0.4, 0.38),
	},
	ElementType.ALTAR: {
		"mesh": "box",
		"size": Vector3(3, 1.5, 2),
		"color": Color(0.4, 0.35, 0.5),
	},
	ElementType.MEDITATION_CIRCLE: {
		"mesh": "cylinder",
		"size": Vector3(5, 0.2, 5),
		"color": Color(0.35, 0.4, 0.5),
	},
	ElementType.STATUE: {
		"mesh": "statue",
		"size": Vector3(1.5, 4, 1.5),
		"color": Color(0.5, 0.5, 0.55),
	},
	ElementType.RUBBLE: {
		"mesh": "rubble",
		"size": Vector3(3, 1.5, 3),
		"color": Color(0.4, 0.38, 0.35),
	},
	ElementType.STEPS: {
		"mesh": "steps",
		"size": Vector3(6, 2, 4),
		"color": Color(0.48, 0.45, 0.42),
	},
	ElementType.ARTIFACT_PEDESTAL: {
		"mesh": "pedestal",
		"size": Vector3(1, 1.2, 1),
		"color": Color(0.5, 0.55, 0.6),
		"emissive": true,
	},
	ElementType.HOLOCRON_ALCOVE: {
		"mesh": "alcove",
		"size": Vector3(2, 3, 1.5),
		"color": Color(0.45, 0.5, 0.55),
	},
	ElementType.COLLAPSED_SECTION: {
		"mesh": "collapsed",
		"size": Vector3(8, 3, 8),
		"color": Color(0.38, 0.35, 0.32),
	},
}


## Structure element instance
class StructureElement extends RefCounted:
	var element_type: ElementType = ElementType.PILLAR
	var local_position: Vector3 = Vector3.ZERO
	var rotation: float = 0.0
	var scale: Vector3 = Vector3.ONE
	var damaged: bool = false  # Visual weathering

	func get_data() -> Dictionary:
		return ELEMENT_DATA.get(element_type, {})


## Generated ruins layout
class RuinsLayout extends RefCounted:
	var seed: int = 0
	var size: float = 50.0
	var elements: Array[StructureElement] = []
	var artifact_position: Vector3 = Vector3.ZERO
	var entrance_direction: float = 0.0  # Radians


## Generate a complete ruins layout
static func generate_ruins(poi_seed: int, size: float) -> RuinsLayout:
	var layout := RuinsLayout.new()
	layout.seed = poi_seed
	layout.size = size

	var rng := PRNG.new(poi_seed)

	# Determine temple style (affects layout)
	var style := rng.next_int_range(0, 3)  # 0=circular, 1=linear, 2=clustered

	# Entrance direction (faces a random direction)
	layout.entrance_direction = rng.next_float() * TAU

	match style:
		0:
			_generate_circular_temple(layout, rng)
		1:
			_generate_linear_temple(layout, rng)
		2:
			_generate_clustered_ruins(layout, rng)

	# Add weathering and damage
	_add_weathering(layout, rng)

	return layout


## Circular temple layout (meditation focus)
static func _generate_circular_temple(layout: RuinsLayout, rng: PRNG) -> void:
	var radius := layout.size * 0.4

	# Central meditation circle
	var center := StructureElement.new()
	center.element_type = ElementType.MEDITATION_CIRCLE
	center.local_position = Vector3.ZERO
	center.scale = Vector3(radius * 0.3, 1, radius * 0.3)
	layout.elements.append(center)

	# Ring of pillars
	var pillar_count := rng.next_int_range(6, 12)
	for i in range(pillar_count):
		var angle := (float(i) / pillar_count) * TAU
		var pillar := StructureElement.new()
		pillar.element_type = ElementType.PILLAR
		pillar.local_position = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		pillar.rotation = angle
		pillar.damaged = rng.next_float() < 0.3  # 30% damaged
		layout.elements.append(pillar)

	# Entrance arch
	var arch := StructureElement.new()
	arch.element_type = ElementType.ENTRANCE_ARCH
	arch.local_position = Vector3(cos(layout.entrance_direction) * radius * 1.2, 0, sin(layout.entrance_direction) * radius * 1.2)
	arch.rotation = layout.entrance_direction
	layout.elements.append(arch)

	# Steps leading to entrance
	var steps := StructureElement.new()
	steps.element_type = ElementType.STEPS
	steps.local_position = Vector3(cos(layout.entrance_direction) * radius * 1.5, -1, sin(layout.entrance_direction) * radius * 1.5)
	steps.rotation = layout.entrance_direction
	layout.elements.append(steps)

	# Artifact pedestal at center
	var pedestal := StructureElement.new()
	pedestal.element_type = ElementType.ARTIFACT_PEDESTAL
	pedestal.local_position = Vector3(0, 0.1, 0)
	layout.elements.append(pedestal)
	layout.artifact_position = pedestal.local_position + Vector3(0, 1.5, 0)

	# Scattered statues
	var statue_count := rng.next_int_range(2, 5)
	for i in range(statue_count):
		var angle := rng.next_float() * TAU
		var dist := rng.next_float_range(radius * 0.5, radius * 0.9)
		var statue := StructureElement.new()
		statue.element_type = ElementType.STATUE
		statue.local_position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		statue.rotation = rng.next_float() * TAU
		statue.damaged = rng.next_float() < 0.4
		layout.elements.append(statue)


## Linear temple layout (processional path)
static func _generate_linear_temple(layout: RuinsLayout, rng: PRNG) -> void:
	var length := layout.size * 0.8
	var width := layout.size * 0.3

	# Main axis direction
	var axis := layout.entrance_direction

	# Floor tiles along path
	var tile_count := int(length / 5.0)
	for i in range(tile_count):
		var t := float(i) / tile_count
		var pos := Vector3(cos(axis) * (t * length - length * 0.5), -0.1, sin(axis) * (t * length - length * 0.5))

		var tile := StructureElement.new()
		tile.element_type = ElementType.FLOOR_TILE
		tile.local_position = pos
		tile.rotation = axis
		layout.elements.append(tile)

	# Pillars along sides
	var pillar_pairs := rng.next_int_range(4, 8)
	for i in range(pillar_pairs):
		var t := float(i + 1) / (pillar_pairs + 1)
		var center_pos := Vector3(cos(axis) * (t * length - length * 0.5), 0, sin(axis) * (t * length - length * 0.5))

		# Left pillar
		var perp := Vector3(-sin(axis), 0, cos(axis))
		var left := StructureElement.new()
		left.element_type = ElementType.PILLAR
		left.local_position = center_pos + perp * width * 0.4
		left.damaged = rng.next_float() < 0.25
		layout.elements.append(left)

		# Right pillar
		var right := StructureElement.new()
		right.element_type = ElementType.PILLAR
		right.local_position = center_pos - perp * width * 0.4
		right.damaged = rng.next_float() < 0.25
		layout.elements.append(right)

	# Entrance arch at start
	var arch := StructureElement.new()
	arch.element_type = ElementType.ENTRANCE_ARCH
	arch.local_position = Vector3(cos(axis) * (-length * 0.5), 0, sin(axis) * (-length * 0.5))
	arch.rotation = axis
	layout.elements.append(arch)

	# Altar at end
	var altar := StructureElement.new()
	altar.element_type = ElementType.ALTAR
	altar.local_position = Vector3(cos(axis) * (length * 0.4), 0, sin(axis) * (length * 0.4))
	altar.rotation = axis + PI
	layout.elements.append(altar)

	# Artifact pedestal behind altar
	var pedestal := StructureElement.new()
	pedestal.element_type = ElementType.ARTIFACT_PEDESTAL
	pedestal.local_position = Vector3(cos(axis) * (length * 0.45), 0, sin(axis) * (length * 0.45))
	layout.elements.append(pedestal)
	layout.artifact_position = pedestal.local_position + Vector3(0, 1.5, 0)

	# Wall segments
	for side: int in [-1, 1]:
		var perp_offset: Vector3 = Vector3(-sin(axis), 0, cos(axis)) * float(side) * width * 0.5
		var wall_count := rng.next_int_range(2, 4)
		for i in range(wall_count):
			var t := rng.next_float_range(0.1, 0.8)
			var wall := StructureElement.new()
			wall.element_type = ElementType.WALL_SEGMENT
			wall.local_position = Vector3(cos(axis) * (t * length - length * 0.5), 0, sin(axis) * (t * length - length * 0.5)) + perp_offset
			wall.rotation = axis
			wall.damaged = rng.next_float() < 0.4
			layout.elements.append(wall)


## Clustered ruins layout (heavily damaged, scattered)
static func _generate_clustered_ruins(layout: RuinsLayout, rng: PRNG) -> void:
	var radius := layout.size * 0.45

	# Multiple collapsed sections
	var collapse_count := rng.next_int_range(2, 4)
	for i in range(collapse_count):
		var angle := rng.next_float() * TAU
		var dist := rng.next_float_range(radius * 0.3, radius * 0.7)

		var collapsed := StructureElement.new()
		collapsed.element_type = ElementType.COLLAPSED_SECTION
		collapsed.local_position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		collapsed.rotation = rng.next_float() * TAU
		collapsed.scale = Vector3.ONE * rng.next_float_range(0.6, 1.2)
		layout.elements.append(collapsed)

	# Scattered rubble
	var rubble_count := rng.next_int_range(5, 10)
	for i in range(rubble_count):
		var angle := rng.next_float() * TAU
		var dist := rng.next_float_range(0, radius)

		var rubble := StructureElement.new()
		rubble.element_type = ElementType.RUBBLE
		rubble.local_position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		rubble.rotation = rng.next_float() * TAU
		rubble.scale = Vector3.ONE * rng.next_float_range(0.5, 1.5)
		layout.elements.append(rubble)

	# Surviving pillars (few)
	var pillar_count := rng.next_int_range(2, 5)
	for i in range(pillar_count):
		var angle := rng.next_float() * TAU
		var dist := rng.next_float_range(radius * 0.2, radius * 0.6)

		var pillar := StructureElement.new()
		pillar.element_type = ElementType.PILLAR
		pillar.local_position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		pillar.damaged = true  # All damaged in collapsed ruins
		layout.elements.append(pillar)

	# One surviving alcove with artifact
	var alcove_angle := rng.next_float() * TAU
	var alcove := StructureElement.new()
	alcove.element_type = ElementType.HOLOCRON_ALCOVE
	alcove.local_position = Vector3(cos(alcove_angle) * radius * 0.5, 0, sin(alcove_angle) * radius * 0.5)
	alcove.rotation = alcove_angle + PI
	layout.elements.append(alcove)

	# Artifact pedestal in alcove
	var pedestal := StructureElement.new()
	pedestal.element_type = ElementType.ARTIFACT_PEDESTAL
	pedestal.local_position = alcove.local_position + Vector3(cos(alcove_angle) * 1.5, 0, sin(alcove_angle) * 1.5)
	layout.elements.append(pedestal)
	layout.artifact_position = pedestal.local_position + Vector3(0, 1.5, 0)


## Add weathering effects
static func _add_weathering(layout: RuinsLayout, rng: PRNG) -> void:
	# Add random rubble around damaged elements
	var new_rubble: Array[StructureElement] = []

	for element in layout.elements:
		if element.damaged and rng.next_float() < 0.5:
			var rubble := StructureElement.new()
			rubble.element_type = ElementType.RUBBLE
			rubble.local_position = element.local_position + Vector3(
				rng.next_float_range(-2, 2),
				0,
				rng.next_float_range(-2, 2)
			)
			rubble.scale = Vector3.ONE * rng.next_float_range(0.3, 0.7)
			new_rubble.append(rubble)

	for rubble in new_rubble:
		layout.elements.append(rubble)
