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

func _init(_id: int, mesh: ArrayMesh):
	id = _id
	var surface_arrays := mesh.surface_get_arrays(_id)
	_vertices = surface_arrays[Mesh.ARRAY_VERTEX]
	_extract_unique_points()

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
