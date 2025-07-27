# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

class_name MeshEditWrapper
extends RefCounted

var mesh: ArrayMesh
var _surface_wrappers: Array[MeshSurfaceEditWrapper]

func _init(_mesh: ArrayMesh):
	mesh = _mesh
	_surface_wrappers = []
	for surface_id in mesh.get_surface_count():
		_surface_wrappers.append(MeshSurfaceEditWrapper.new(surface_id, _mesh))

func get_unique_points_for_surface(surface_id: int = 0) -> Array[Vector3]:
	if _surface_wrappers.size() <= surface_id:
		return []
	return _surface_wrappers[surface_id].unique_points

func move_point(unique_point_id: int, new_position: Vector3, surface_id: int = 0):
	if _surface_wrappers.size() <= surface_id:
		print('Invalid surface ID in move_point')
		return
	var new_vertices: PackedVector3Array = _surface_wrappers[surface_id].get_modified_vertices_array(
		unique_point_id,
		new_position
	)
	mesh.surface_update_vertex_region(surface_id, 0, new_vertices.to_byte_array())
	_surface_wrappers[surface_id] = MeshSurfaceEditWrapper.new(surface_id, mesh)
