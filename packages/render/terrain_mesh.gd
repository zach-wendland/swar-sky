## terrain_mesh.gd - Generates 3D mesh from terrain tile data
## Creates procedural mesh with proper UVs, normals, and vertex colors for biomes
class_name TerrainMesh
extends RefCounted


## Mesh generation settings
const DEFAULT_HEIGHT_SCALE: float = 100.0  # Meters of height variation
const UV_SCALE: float = 0.1                 # UV tiling


## Generate a MeshInstance3D from tile data
static func create_tile_mesh(tile: TerrainGenerator.TerrainTileData, tile_size: float, height_scale: float = DEFAULT_HEIGHT_SCALE) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _generate_mesh(tile, tile_size, height_scale)
	mesh_instance.name = "Tile_%d_%d" % [tile.tile_coords.x, tile.tile_coords.y]

	# Position the mesh at tile world position
	mesh_instance.position = Vector3(
		tile.tile_coords.x * tile_size,
		0,
		tile.tile_coords.y * tile_size
	)

	return mesh_instance


## Generate the actual mesh data
static func _generate_mesh(tile: TerrainGenerator.TerrainTileData, tile_size: float, height_scale: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var surface_array := []
	surface_array.resize(Mesh.ARRAY_MAX)

	var res := tile.resolution
	var vertex_count := res * res
	var index_count := (res - 1) * (res - 1) * 6

	# Allocate arrays
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)
	colors.resize(vertex_count)
	indices.resize(index_count)

	var step := tile_size / (res - 1)

	# Generate vertices
	for y in range(res):
		for x in range(res):
			var idx := y * res + x

			# Position
			var height := tile.heightmap[idx] * height_scale
			vertices[idx] = Vector3(x * step, height, y * step)

			# Normal (from tile data or recalculate)
			if tile.normal_map.size() > idx:
				normals[idx] = tile.normal_map[idx]
			else:
				normals[idx] = Vector3.UP

			# UVs
			uvs[idx] = Vector2(x * step * UV_SCALE, y * step * UV_SCALE)

			# Vertex color from biome
			var biome: int = tile.biome_map[idx] if tile.biome_map.size() > idx else 0
			colors[idx] = _get_biome_color(biome)

	# Generate indices (two triangles per quad)
	var tri_idx := 0
	for y in range(res - 1):
		for x in range(res - 1):
			var tl := y * res + x           # Top-left
			var tr := y * res + x + 1       # Top-right
			var bl := (y + 1) * res + x     # Bottom-left
			var br := (y + 1) * res + x + 1 # Bottom-right

			# First triangle (tl, bl, tr)
			indices[tri_idx] = tl
			indices[tri_idx + 1] = bl
			indices[tri_idx + 2] = tr

			# Second triangle (tr, bl, br)
			indices[tri_idx + 3] = tr
			indices[tri_idx + 4] = bl
			indices[tri_idx + 5] = br

			tri_idx += 6

	# Build surface array
	surface_array[Mesh.ARRAY_VERTEX] = vertices
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_COLOR] = colors
	surface_array[Mesh.ARRAY_INDEX] = indices

	# Create mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)

	return mesh


## Get color for a biome (for vertex coloring)
static func _get_biome_color(biome: int) -> Color:
	if TerrainGenerator.BIOME_DATA.has(biome):
		return TerrainGenerator.BIOME_DATA[biome]["color"]
	return Color.MAGENTA  # Error color


## Create a simple material for terrain
static func create_terrain_material(use_vertex_colors: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()

	if use_vertex_colors:
		mat.vertex_color_use_as_albedo = true
	else:
		mat.albedo_color = Color(0.4, 0.5, 0.3)

	# Basic shading settings
	mat.roughness = 0.9
	mat.metallic = 0.0

	# Enable backface culling
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	return mat


## Create a water plane mesh
static func create_water_mesh(size: float, sea_level: float, height_scale: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Water"

	# Create simple plane
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(size, size)
	plane_mesh.subdivide_width = 1
	plane_mesh.subdivide_depth = 1

	mesh_instance.mesh = plane_mesh

	# Position at sea level
	mesh_instance.position = Vector3(size / 2.0, sea_level * height_scale, size / 2.0)

	# Water material
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.1, 0.3, 0.5, 0.7)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.1
	water_mat.metallic = 0.3

	mesh_instance.material_override = water_mat

	return mesh_instance


## Generate a lower-LOD mesh (fewer vertices)
static func create_lod_mesh(tile: TerrainGenerator.TerrainTileData, tile_size: float, height_scale: float, lod_factor: int) -> MeshInstance3D:
	# Create a simplified tile with fewer samples
	var simplified := _simplify_tile(tile, lod_factor)
	return create_tile_mesh(simplified, tile_size, height_scale)


## Simplify tile data by sampling every Nth point
static func _simplify_tile(tile: TerrainGenerator.TerrainTileData, factor: int) -> TerrainGenerator.TerrainTileData:
	var new_res := (tile.resolution - 1) / factor + 1
	var simplified := TerrainGenerator.TerrainTileData.new()
	simplified.tile_coords = tile.tile_coords
	simplified.lod = tile.lod + factor
	simplified.seed = tile.seed
	simplified.resolution = new_res

	var new_count := new_res * new_res
	simplified.heightmap.resize(new_count)
	simplified.biome_map.resize(new_count)
	simplified.normal_map.resize(new_count)

	for y in range(new_res):
		for x in range(new_res):
			var src_x := x * factor
			var src_y := y * factor
			var src_idx := src_y * tile.resolution + src_x
			var dst_idx := y * new_res + x

			simplified.heightmap[dst_idx] = tile.heightmap[src_idx] if src_idx < tile.heightmap.size() else 0.0
			simplified.biome_map[dst_idx] = tile.biome_map[src_idx] if src_idx < tile.biome_map.size() else 0
			simplified.normal_map[dst_idx] = tile.normal_map[src_idx] if src_idx < tile.normal_map.size() else Vector3.UP

	return simplified
