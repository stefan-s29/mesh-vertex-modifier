# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

class_name MeshEditWrapper
extends RefCounted

const MeshSurfaceVertexFilter = preload("res://addons/mesh_vertex_modifier/objects/mesh_surface_vertex_filter.gd")

var mesh: ArrayMesh
var _surface_wrappers: Array[MeshSurfaceEditWrapper]

func _init(_mesh: ArrayMesh):
	mesh = _mesh
	mesh.resource_local_to_scene = true
	_rebuild_surface_wrappers()

func _rebuild_surface_wrappers():
	_surface_wrappers.clear()
	var new_surface_wrappers: Array[MeshSurfaceEditWrapper] = []
	for surface_id in mesh.get_surface_count():
		new_surface_wrappers.append(MeshSurfaceEditWrapper.new(surface_id, mesh))
	_surface_wrappers = new_surface_wrappers

func get_unique_points_for_surface(surface_id: int = 0) -> Array[Vector3]:
	if _surface_wrappers.size() <= surface_id:
		return []
	return _surface_wrappers[surface_id].unique_points

## Updates the vertex position on the GPU, which is immediately visible in the 3D view;
## the CPU update is heavy and therefore carried out by calling commit_changes()
## after the movement is finished
func move_point(unique_point_id: int, new_position_local: Vector3, surface_id: int = 0):
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in move_point")
		return
	var new_vertices_precommit: PackedVector3Array = _surface_wrappers[surface_id].get_modified_vertices_array(
		unique_point_id,
		new_position_local
	)
	# surface_update_vertex_region only updates the vertices on the GPU
	mesh.surface_update_vertex_region(surface_id, 0, new_vertices_precommit.to_byte_array())
	_surface_wrappers[surface_id].set_vertices_precommit(new_vertices_precommit)
	_surface_wrappers[surface_id].update_unique_point_position(unique_point_id, new_position_local)

## Moves multiple unique points atomically on the GPU
func move_points(point_positions: Dictionary[int, Vector3], surface_id: int = 0):
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in move_points")
		return
	var new_vertices_precommit := _surface_wrappers[surface_id].get_modified_vertices_array_multi(point_positions)
	mesh.surface_update_vertex_region(surface_id, 0, new_vertices_precommit.to_byte_array())
	_surface_wrappers[surface_id].set_vertices_precommit(new_vertices_precommit)
	for unique_point_id in point_positions:
		_surface_wrappers[surface_id].update_unique_point_position(unique_point_id, point_positions[unique_point_id])

## Updates the vertices on the CPU after the movement was finished (CPU-heavy)
func commit_changes(mesh_instance: MeshInstance3D) -> void:
	if mesh == null: return
	var arrays_list: Array = []
	for s in mesh.get_surface_count():
		arrays_list.append(_get_surface_arrays(s))
	_rebuild_all_surfaces(arrays_list)
	mesh_instance.update_gizmos()

## Removes unique points from the mesh and rebuilds it
func delete_unique_points(unique_point_ids: Array[int], surface_id: int = 0) -> void:
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in delete_unique_points")
		return

	var vertex_ids_to_remove := _collect_vertex_ids_to_remove(unique_point_ids, surface_id)
	var arrays := mesh.surface_get_arrays(surface_id)
	var filtered_arrays := MeshSurfaceVertexFilter.new(arrays, vertex_ids_to_remove).apply()

	var all_arrays: Array = []
	for s in mesh.get_surface_count():
		if s == surface_id:
			all_arrays.append(filtered_arrays)
		else:
			all_arrays.append(mesh.surface_get_arrays(s))
	_rebuild_all_surfaces(all_arrays)

func _collect_vertex_ids_to_remove(unique_point_ids: Array[int], surface_id: int) -> Dictionary:
	var vertex_ids_to_remove: Dictionary = {}
	var surface_wrapper := _surface_wrappers[surface_id]
	for uid in unique_point_ids:
		for vid in surface_wrapper._unique_points_id_to_vertex_ids[uid]:
			vertex_ids_to_remove[vid] = true
	return vertex_ids_to_remove

func _rebuild_all_surfaces(new_arrays_per_surface: Array) -> void:
	var surface_count := mesh.get_surface_count()
	var prim_list: Array = []
	var mat_list: Array = []
	var blend_list: Array = []
	var lods_list: Array = []
	for s in surface_count:
		prim_list.append(mesh.surface_get_primitive_type(s))
		mat_list.append(mesh.surface_get_material(s))
		blend_list.append(mesh.surface_get_blend_shape_arrays(s))
		lods_list.append(mesh.surface_get_lods(s) if mesh.has_method("surface_get_lods") else {} as Dictionary)

	mesh.clear_surfaces()
	for s in new_arrays_per_surface.size():
		mesh.add_surface_from_arrays(prim_list[s], new_arrays_per_surface[s], blend_list[s], lods_list[s])
		mesh.surface_set_material(s, mat_list[s])

	var aabb := _calculate_aabb(new_arrays_per_surface)
	mesh.custom_aabb = aabb
	mesh.emit_changed()
	_rebuild_surface_wrappers()

func _get_surface_arrays(surface_id: int):
	var arrays := mesh.surface_get_arrays(surface_id)
	if arrays.is_empty():
		arrays = []; arrays.resize(Mesh.ARRAY_MAX)

	if surface_id < _surface_wrappers.size() and _surface_wrappers[surface_id].has_vertices_precommit():
		arrays[Mesh.ARRAY_VERTEX] = _surface_wrappers[surface_id].get_vertices_precommit()
	return arrays

## Calculates the new axis-aligned boundary box for the mesh
func _calculate_aabb(arrays_list: Array) -> AABB:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var have := false
	for arrays in arrays_list:
		if arrays.is_empty(): continue
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in vs:
			have = true
			min_v.x = minf(min_v.x, v.x); min_v.y = minf(min_v.y, v.y); min_v.z = minf(min_v.z, v.z)
			max_v.x = maxf(max_v.x, v.x); max_v.y = maxf(max_v.y, v.y); max_v.z = maxf(max_v.z, v.z)
	if have:
		return AABB(min_v, max_v - min_v)
	return AABB()
