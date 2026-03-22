# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

## Computes the result of removing a set of vertices from a surface arrays snapshot.
## Call apply() to obtain the filtered arrays.
class_name MeshSurfaceVertexFilter
extends RefCounted

var _arrays: Array
var _vertex_ids_to_remove: Dictionary

func _init(arrays: Array, vertex_ids_to_remove: Dictionary):
	_arrays = arrays
	_vertex_ids_to_remove = vertex_ids_to_remove

func apply() -> Array:
	var vertex_index_remap := _build_vertex_remap()
	_filter_vertex_data(vertex_index_remap)
	_filter_index_array(vertex_index_remap)
	return _arrays

func _build_vertex_remap() -> Dictionary:
	var old_vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var vertex_index_remap: Dictionary = {}
	var new_index := 0
	for i in old_vertices.size():
		if not _vertex_ids_to_remove.has(i):
			vertex_index_remap[i] = new_index
			new_index += 1
	return vertex_index_remap

func _filter_vertex_data(vertex_index_remap: Dictionary) -> void:
	var old_vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var old_vertex_count := old_vertices.size()
	var new_vertices := PackedVector3Array()
	for i in old_vertex_count:
		if vertex_index_remap.has(i):
			new_vertices.append(old_vertices[i])
	_arrays[Mesh.ARRAY_VERTEX] = new_vertices
	_filter_vertex_attributes(old_vertex_count)

func _filter_index_array(vertex_index_remap: Dictionary) -> void:
	var old_indices: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	if old_indices == null or old_indices.size() == 0:
		return
	var new_indices := PackedInt32Array()
	var i := 0
	while i + 2 < old_indices.size():
		var a := old_indices[i]
		var b := old_indices[i + 1]
		var c := old_indices[i + 2]
		if vertex_index_remap.has(a) and vertex_index_remap.has(b) and vertex_index_remap.has(c):
			new_indices.append(vertex_index_remap[a])
			new_indices.append(vertex_index_remap[b])
			new_indices.append(vertex_index_remap[c])
		i += 3
	_arrays[Mesh.ARRAY_INDEX] = new_indices

func _filter_vertex_attributes(old_vertex_count: int) -> void:
	_filter_array_slot(Mesh.ARRAY_NORMAL, old_vertex_count)
	_filter_array_slot(Mesh.ARRAY_TANGENT, old_vertex_count, 4)
	_filter_array_slot(Mesh.ARRAY_COLOR, old_vertex_count)
	_filter_array_slot(Mesh.ARRAY_TEX_UV, old_vertex_count)
	_filter_array_slot(Mesh.ARRAY_TEX_UV2, old_vertex_count)

func _filter_array_slot(slot: int, old_vertex_count: int, elements_per_vertex: int = 1) -> void:
	if _arrays[slot] == null:
		return
	var old_array = _arrays[slot]
	var new_array = old_array.duplicate()
	new_array.resize(0)
	for i in old_vertex_count:
		if not _vertex_ids_to_remove.has(i):
			for j in elements_per_vertex:
				new_array.append(old_array[i * elements_per_vertex + j])
	_arrays[slot] = new_array
