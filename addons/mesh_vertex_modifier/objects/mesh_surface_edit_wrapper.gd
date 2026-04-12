# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

class_name MeshSurfaceEditWrapper
extends RefCounted

var id: int
var _vertices: PackedVector3Array
var unique_points: Array[Vector3]
var _unique_points_id_to_vertex_ids: Dictionary[int,Array] = {}
var _vertices_precommit: PackedVector3Array = PackedVector3Array()
var _boundary_loop: Array[int] = []
var _face_normal: Vector3 = Vector3.ZERO

func _init(_id: int, mesh: ArrayMesh):
	id = _id
	var surface_arrays := mesh.surface_get_arrays(_id)
	_vertices = surface_arrays[Mesh.ARRAY_VERTEX]
	_extract_unique_points()
	_extract_boundary_loop(surface_arrays[Mesh.ARRAY_INDEX])
	_compute_face_normal(surface_arrays[Mesh.ARRAY_INDEX])

func _extract_unique_points():
	var new_unique_points: Array[Vector3] = []
	var unique_points_vector_to_id: Dictionary[Vector3,int] = {}
	var unique_points_id_to_vertex_ids: Dictionary[int,Array] = {}

	for vertex_id in _vertices.size():
		var vertex := _vertices[vertex_id]
		var unique_point_id: int
		if unique_points_vector_to_id.has(vertex):
			unique_point_id = unique_points_vector_to_id[vertex]
			unique_points_id_to_vertex_ids[unique_point_id].append(vertex_id)
		else:
			unique_point_id = new_unique_points.size() # unique point id = array index
			new_unique_points.append(vertex)
			unique_points_vector_to_id[vertex] = unique_point_id
			unique_points_id_to_vertex_ids[unique_point_id] = [vertex_id]
	unique_points = new_unique_points
	_unique_points_id_to_vertex_ids = unique_points_id_to_vertex_ids

func _extract_boundary_loop(indices: PackedInt32Array) -> void:
	if indices == null or indices.size() < 3:
		return

	# For each undirected edge, count how many triangles contain it
	# and record the directed version (a→b as it appears in the first triangle)
	var edge_counts: Dictionary = {}  # Vector2i(min,max) -> int
	var edge_directed: Dictionary = {}  # Vector2i(min,max) -> Vector2i(from,to)
	var i := 0
	while i + 2 < indices.size():
		for j in range(3):
			var a := indices[i + j]
			var b := indices[i + (j + 1) % 3]
			var key := Vector2i(min(a, b), max(a, b))
			if not edge_counts.has(key):
				edge_counts[key] = 0
				edge_directed[key] = Vector2i(a, b)
			edge_counts[key] += 1
		i += 3

	# Boundary edges appear in exactly one triangle
	var next_boundary_vertex: Dictionary = {}  # vertex -> next_boundary_vertex vertex along boundary
	for key: Vector2i in edge_counts:
		if edge_counts[key] == 1:
			var dir: Vector2i = edge_directed[key]
			next_boundary_vertex[dir.x] = dir.y

	if next_boundary_vertex.is_empty():
		return

	# Walk the boundary into an ordered loop
	var start: int = next_boundary_vertex.keys()[0]
	var current := start
	var loop: Array[int] = []
	for _i in next_boundary_vertex.size():
		loop.append(current)
		current = next_boundary_vertex[current]
		if current == start:
			break

	if loop.size() >= 3:
		_boundary_loop = loop

func _compute_face_normal(indices: PackedInt32Array) -> void:
	if indices == null or indices.size() < 3:
		return
	
	var edge_a := _vertices[indices[1]] - _vertices[indices[0]]
	var edge_b := _vertices[indices[2]] - _vertices[indices[0]]
	var unnormalized_normal := edge_a.cross(edge_b)
	
	# A degenerate triangle has collinear or coincident vertices, producing a
	# zero-length cross product. The threshold guards against floating point errors.
	var is_non_degenerate := unnormalized_normal.length_squared() > 1e-10
	if is_non_degenerate:
		_face_normal = unnormalized_normal.normalized()

## Re-triangulates the polygon defined by _boundary_loop using the given vertex
## positions, by projecting it onto its own plane and running ear-clipping via
## Geometry2D.triangulate_polygon. Returns an empty array if the boundary loop
## is missing or the polygon is degenerate.
func get_retriangulated_indices(committed_vertices: PackedVector3Array) -> PackedInt32Array:
	if _boundary_loop.size() < 3 or _face_normal == Vector3.ZERO:
		return PackedInt32Array()

	# Use the normal stored at load time so that vertex moves can never flip
	# the projection plane and invert the winding order.
	var normal := _face_normal

	# Build an orthonormal 2D frame on the polygon plane
	var tangent: Vector3
	if abs(normal.dot(Vector3.UP)) < 0.99:
		tangent = Vector3.UP.cross(normal).normalized()
	else:
		tangent = Vector3.RIGHT.cross(normal).normalized()
	var bitangent := normal.cross(tangent)

	# Project each boundary vertex onto the plane
	var vertex_projections := PackedVector2Array()
	for vertex_id in _boundary_loop:
		var v := committed_vertices[vertex_id]
		vertex_projections.append(Vector2(v.dot(tangent), v.dot(bitangent)))

	var tri_indices := Geometry2D.triangulate_polygon(vertex_projections)
	if tri_indices.is_empty():
		return PackedInt32Array()

	# Geometry2D may use a different winding convention than the 3D mesh.
	# Check the first output triangle and flip all triangles if necessary.
	var p0 := committed_vertices[_boundary_loop[tri_indices[0]]]
	var p1 := committed_vertices[_boundary_loop[tri_indices[1]]]
	var p2 := committed_vertices[_boundary_loop[tri_indices[2]]]
	var edge_a := p1 - p0
	var edge_b := p2 - p0
	if edge_a.cross(edge_b).dot(normal) < 0.0:
		for i in range(0, tri_indices.size(), 3):
			var tmp := tri_indices[i + 1]
			tri_indices[i + 1] = tri_indices[i + 2]
			tri_indices[i + 2] = tmp

	# Map the 2D indices back to 3D vertex IDs
	var new_indices := PackedInt32Array()
	for loop_index in tri_indices:
		new_indices.append(_boundary_loop[loop_index])
	return new_indices

func get_modified_vertices_array(unique_point_id: int, new_position: Vector3) -> PackedVector3Array:
	var modified_vertices = _unique_points_id_to_vertex_ids[unique_point_id]
	var new_vertices = _vertices.duplicate()
	for vertex_id in modified_vertices:
		new_vertices[vertex_id] = new_position
	return new_vertices

func get_modified_vertices_array_multi(point_positions: Dictionary[int, Vector3]) -> PackedVector3Array:
	var new_vertices = _vertices.duplicate()
	for unique_point_id in point_positions:
		var new_position: Vector3 = point_positions[unique_point_id]
		for vertex_id in _unique_points_id_to_vertex_ids[unique_point_id]:
			new_vertices[vertex_id] = new_position
	return new_vertices

func update_unique_point_position(unique_point_id: int, new_position: Vector3) -> void:
	unique_points[unique_point_id] = new_position

func set_vertices_precommit(vertices_local: PackedVector3Array) -> void:
	_vertices_precommit = vertices_local.duplicate()

func has_vertices_precommit() -> bool:
	return _vertices_precommit.size() > 0

func get_vertices_precommit() -> PackedVector3Array:
	return _vertices_precommit
