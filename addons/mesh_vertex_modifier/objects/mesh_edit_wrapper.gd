# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

class_name MeshEditWrapper
extends RefCounted

const MeshSurfaceVertexFilter = preload("res://addons/mesh_vertex_modifier/objects/mesh_surface_vertex_filter.gd")

var mesh: ArrayMesh
var _surface_wrappers: Array[MeshSurfaceEditWrapper]
var _drag_constraints: Dictionary[int, VertexDragConstraint] = {}
var _drag_start_positions: Dictionary[int, Vector3] = {}

func _init(_mesh: ArrayMesh):
	mesh = _mesh
	mesh.resource_local_to_scene = true
	_rebuild_surface_wrappers()

func _rebuild_surface_wrappers():
	var preserved_normals: Array[Vector3] = []
	for sw in _surface_wrappers:
		preserved_normals.append(sw.get_face_normal())
	_surface_wrappers.clear()
	var new_surface_wrappers: Array[MeshSurfaceEditWrapper] = []
	for surface_id in mesh.get_surface_count():
		var known_normal := preserved_normals[surface_id] if surface_id < preserved_normals.size() else Vector3.ZERO
		new_surface_wrappers.append(MeshSurfaceEditWrapper.new(surface_id, mesh, known_normal))
	_surface_wrappers = new_surface_wrappers

func get_unique_points_for_surface(surface_id: int = 0) -> Array[Vector3]:
	if _surface_wrappers.size() <= surface_id:
		return []
	return _surface_wrappers[surface_id].unique_points

func get_boundary_positions_for_surface(surface_id: int = 0) -> PackedVector3Array:
	if _surface_wrappers.size() <= surface_id:
		return PackedVector3Array()
	return _surface_wrappers[surface_id].get_boundary_positions()

func get_face_normal_for_surface(surface_id: int = 0) -> Vector3:
	if _surface_wrappers.size() <= surface_id:
		return Vector3.ZERO
	return _surface_wrappers[surface_id].get_face_normal()

## Precomputes the drag constraint for a single vertex so that move_point can
## clamp its position during the drag. Call end_drag when the drag finishes.
func begin_drag(unique_point_id: int, surface_id: int = 0) -> void:
	if _surface_wrappers.size() <= surface_id:
		return
	_drag_constraints.clear()
	_drag_start_positions.clear()
	var constraint := _surface_wrappers[surface_id].build_drag_constraint(unique_point_id)
	if constraint != null:
		_drag_constraints[unique_point_id] = constraint
	_drag_start_positions[unique_point_id] = _surface_wrappers[surface_id].unique_points[unique_point_id]

## Precomputes drag constraints for a group of vertices moving together so that
## move_points can clamp them uniformly. Call end_drag when the drag finishes.
## Each vertex is constrained as if it were the only one moving — treating all
## neighbors as fixed — and the minimum safe t across all vertices is applied
## uniformly, preserving relative positions.
func begin_group_drag(unique_point_ids: Array[int], surface_id: int = 0) -> void:
	if _surface_wrappers.size() <= surface_id:
		return
	_drag_constraints.clear()
	_drag_start_positions.clear()
	for uid in unique_point_ids:
		var constraint := _surface_wrappers[surface_id].build_drag_constraint(uid)
		if constraint != null:
			_drag_constraints[uid] = constraint
		_drag_start_positions[uid] = _surface_wrappers[surface_id].unique_points[uid]

func end_drag() -> void:
	_drag_constraints.clear()
	_drag_start_positions.clear()

## Updates the vertex position on the GPU, which is immediately visible in the 3D view;
## the CPU update is heavy and therefore carried out by calling commit_changes()
## after the movement is finished
func move_point(unique_point_id: int, new_position_local: Vector3, surface_id: int = 0):
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in move_point")
		return
	var clamped_position := new_position_local
	if _drag_constraints.has(unique_point_id):
		clamped_position = _drag_constraints[unique_point_id].clamp_position(new_position_local)
	var new_vertices_precommit: PackedVector3Array = _surface_wrappers[surface_id].get_modified_vertices_array(
		unique_point_id,
		clamped_position
	)
	# surface_update_vertex_region only updates the vertices on the GPU
	mesh.surface_update_vertex_region(surface_id, 0, new_vertices_precommit.to_byte_array())
	_surface_wrappers[surface_id].set_vertices_precommit(new_vertices_precommit)
	_surface_wrappers[surface_id].update_unique_point_position(unique_point_id, clamped_position)

## Moves multiple unique points atomically on the GPU
func move_points(point_positions: Dictionary[int, Vector3], surface_id: int = 0):
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in move_points")
		return
	var constrained_positions := _apply_group_constraints(point_positions)
	var new_vertices_precommit := _surface_wrappers[surface_id].get_modified_vertices_array_multi(constrained_positions)
	mesh.surface_update_vertex_region(surface_id, 0, new_vertices_precommit.to_byte_array())
	_surface_wrappers[surface_id].set_vertices_precommit(new_vertices_precommit)
	for uid in constrained_positions:
		_surface_wrappers[surface_id].update_unique_point_position(uid, constrained_positions[uid])

## Finds the most restrictive safe t across all group drag constraints and
## scales all positions back to that t from their drag start positions.
func _apply_group_constraints(
	point_positions: Dictionary[int, Vector3]
) -> Dictionary[int, Vector3]:
	if _drag_constraints.is_empty():
		return point_positions
	var min_t := 1.0
	for uid: int in _drag_constraints:
		if point_positions.has(uid):
			var t: float = _drag_constraints[uid].compute_max_safe_t(point_positions[uid])
			if t < min_t:
				min_t = t
	if min_t >= 1.0:
		return point_positions
	var result: Dictionary[int, Vector3] = {}
	for uid: int in point_positions:
		var start: Vector3 = _drag_start_positions[uid]
		result[uid] = start + min_t * (point_positions[uid] - start)
	return result

## Rebuilds the mesh from a previously captured surface arrays snapshot.
## Used by undo/redo and drag cancellation.
func restore_state(arrays_per_surface: Array, mesh_instance: MeshInstance3D) -> void:
	_rebuild_all_surfaces(arrays_per_surface)
	mesh_instance.update_gizmos()

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

## Splits the edge between two unique points by inserting a midpoint vertex.
## All triangles containing that edge are split into two; the direct edge is removed.
func split_edge_between_unique_points(uid_a: int, uid_b: int, surface_id: int = 0) -> void:
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in split_edge_between_unique_points")
		return

	var surface_wrapper := _surface_wrappers[surface_id]
	var vids_a: Array = surface_wrapper._unique_points_id_to_vertex_ids[uid_a]
	var vids_b: Array = surface_wrapper._unique_points_id_to_vertex_ids[uid_b]
	var vids_a_set: Dictionary = {}
	var vids_b_set: Dictionary = {}
	for v in vids_a: vids_a_set[v] = true
	for v in vids_b: vids_b_set[v] = true

	var arrays := mesh.surface_get_arrays(surface_id)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var midpoint := (surface_wrapper.unique_points[uid_a] + surface_wrapper.unique_points[uid_b]) / 2.0
	var vid_mid := vertices.size()
	vertices.append(midpoint)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays = _append_default_vertex_to_arrays(arrays)

	var old_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if old_indices != null and old_indices.size() > 0:
		var new_indices := PackedInt32Array()
		var i := 0
		while i + 2 < old_indices.size():
			var tri := [old_indices[i], old_indices[i + 1], old_indices[i + 2]]
			var has_a := -1
			var has_b := -1
			for t in 3:
				if vids_a_set.has(tri[t]): has_a = t
				if vids_b_set.has(tri[t]): has_b = t
			if has_a >= 0 and has_b >= 0:
				var vid_a: int = tri[has_a]
				var vid_b: int = tri[has_b]
				var pos_c := 3 - has_a - has_b
				var vid_c: int = tri[pos_c]
				# Preserve winding: if edge goes a→b in the original triangle, emit:
				# [vid_a, vid_mid, vid_c] and [vid_mid, vid_b, vid_c]
				# otherwise (edge goes b→a): [vid_b, vid_mid, vid_c] and [vid_mid, vid_a, vid_c]
				if (has_a + 1) % 3 == has_b:
					new_indices.append_array(PackedInt32Array([vid_a, vid_mid, vid_c]))
					new_indices.append_array(PackedInt32Array([vid_mid, vid_b, vid_c]))
				else:
					new_indices.append_array(PackedInt32Array([vid_b, vid_mid, vid_c]))
					new_indices.append_array(PackedInt32Array([vid_mid, vid_a, vid_c]))
			else:
				new_indices.append_array(PackedInt32Array([tri[0], tri[1], tri[2]]))
			i += 3
		arrays[Mesh.ARRAY_INDEX] = new_indices

	var all_arrays: Array = []
	for s in mesh.get_surface_count():
		all_arrays.append(arrays if s == surface_id else mesh.surface_get_arrays(s))
	_rebuild_all_surfaces(all_arrays)

## Adds a new vertex at the given local position and rebuilds the mesh
func add_vertex_at_position(position: Vector3, surface_id: int = 0) -> void:
	if _surface_wrappers.size() <= surface_id:
		push_error("Invalid surface ID in add_vertex_at_position")
		return

	var arrays := mesh.surface_get_arrays(surface_id)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	vertices.append(position)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays = _append_default_vertex_to_arrays(arrays)

	var all_arrays: Array = []
	for s in mesh.get_surface_count():
		all_arrays.append(arrays if s == surface_id else mesh.surface_get_arrays(s))
	_rebuild_all_surfaces(all_arrays)

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

	if surface_id < _surface_wrappers.size():
		var wrapper := _surface_wrappers[surface_id]
		if wrapper.has_vertices_precommit():
			arrays[Mesh.ARRAY_VERTEX] = wrapper.get_vertices_precommit()
		var new_indices := wrapper.get_retriangulated_indices(arrays[Mesh.ARRAY_VERTEX])
		if not new_indices.is_empty():
			arrays[Mesh.ARRAY_INDEX] = new_indices
	return arrays

func _append_default_vertex_to_arrays(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		normals.append(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		arrays[Mesh.ARRAY_TANGENT] = tangents
	if arrays[Mesh.ARRAY_COLOR] != null:
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		colors.append(Color.WHITE)
		arrays[Mesh.ARRAY_COLOR] = colors
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		uvs.append(Vector2.ZERO)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if arrays[Mesh.ARRAY_TEX_UV2] != null:
		var uvs2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		uvs2.append(Vector2.ZERO)
		arrays[Mesh.ARRAY_TEX_UV2] = uvs2
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
