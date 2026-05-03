# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

@tool
class_name VertexGizmo
extends EditorNode3DGizmo

const SURFACE_ZERO_ID = 0
const HANDLE_PICK_RADIUS_PX = 10.0
const BOUNDARY_DRAG_COLOR = Color(1.0, 0.0, 0.6)

var _mesh_instance: MeshInstance3D
var _mesh_edit_wrapper: MeshEditWrapper
var _undo_redo: EditorUndoRedoManager
var _initialized := false
var _selected_handle_ids: Array[int] = []
var _drag_initial_positions: PackedVector3Array = PackedVector3Array()
var _drag_before_snapshot: Array = []

func _init(mesh_instance: MeshInstance3D, undo_redo: EditorUndoRedoManager):
	_undo_redo = undo_redo
	_set_mesh_instance(mesh_instance)

func get_selected_handle_count() -> int:
	return _selected_handle_ids.size()

func get_total_handle_count() -> int:
	if _mesh_edit_wrapper == null:
		return 0
	return _mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID).size()

func is_handle_selected(handle_id: int) -> bool:
	return handle_id in _selected_handle_ids

func delete_selected_handles() -> void:
	if _mesh_edit_wrapper == null or _selected_handle_ids.is_empty():
		return
	_mesh_edit_wrapper.delete_unique_points(_selected_handle_ids, SURFACE_ZERO_ID)
	_selected_handle_ids.clear()
	_mesh_instance.update_gizmos()

func add_vertex_at_selection_midpoint() -> void:
	if _mesh_edit_wrapper == null or _selected_handle_ids.size() < 2:
		return
	_mesh_edit_wrapper.split_edge_between_unique_points(
		_selected_handle_ids[0], _selected_handle_ids[1], SURFACE_ZERO_ID
	)
	_selected_handle_ids.clear()
	_mesh_instance.update_gizmos()

func find_handle_at_screen_pos(camera: Camera3D, screen_pos: Vector2) -> int:
	if _mesh_edit_wrapper == null:
		return -1
	var handle_positions := _mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)
	var best_id := -1
	var best_dist := HANDLE_PICK_RADIUS_PX
	for i in handle_positions.size():
		var world_pos := _mesh_instance.to_global(handle_positions[i])
		if camera.is_position_behind(world_pos):
			continue
		var dist := camera.unproject_position(world_pos).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best_id = i
	return best_id

func select_handle(handle_id: int, add_to_selection: bool) -> void:
	if add_to_selection:
		if handle_id in _selected_handle_ids:
			_selected_handle_ids.erase(handle_id)
		else:
			_selected_handle_ids.append(handle_id)
	else:
		_selected_handle_ids = [handle_id]
	_redraw()

func clear_selection() -> void:
	if _selected_handle_ids.is_empty():
		return
	_selected_handle_ids.clear()
	_redraw()

func _get_handle_name(handle_id: int, secondary: bool) -> String:
	return 'Vertex ' + str(handle_id)

func _get_handle_value(handle_id: int, secondary: bool) -> Variant:
	if _mesh_edit_wrapper == null:
		return null
	var points := _mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)
	if handle_id >= points.size():
		return null
	_drag_before_snapshot = []
	for s in _mesh_edit_wrapper.mesh.get_surface_count():
		_drag_before_snapshot.append(_mesh_edit_wrapper.mesh.surface_get_arrays(s))
	return points[handle_id]

func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and node.mesh != null

func _redraw() -> void:
	clear()

	if !_initialized:
		return

	var current_mesh_instance = get_node_3d() as MeshInstance3D
	if !current_mesh_instance:
		_mesh_instance = null
		_mesh_edit_wrapper = null
		return

	if _has_mesh_been_replaced(current_mesh_instance):
		_selected_handle_ids.clear()
		_set_mesh_instance(current_mesh_instance)

	if _mesh_edit_wrapper != null:
		_draw_handles()

func _set_handle(handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2):
	var new_position_global := _get_3D_point_from_screen_pos(camera, screen_pos)
	var new_position_local := _mesh_instance.to_local(new_position_global)

	if _drag_initial_positions.is_empty():
		_drag_initial_positions = PackedVector3Array(
			_mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)
		)
		var plugin := get_plugin() as VertexGizmoPlugin
		if plugin.clamping_enabled:
			if _should_drag_as_group(handle_id):
				_mesh_edit_wrapper.begin_group_drag(_selected_handle_ids, SURFACE_ZERO_ID)
			else:
				_mesh_edit_wrapper.begin_drag(handle_id, SURFACE_ZERO_ID)

	if _should_drag_as_group(handle_id):
		_mesh_edit_wrapper.move_points(_get_group_positions(handle_id, new_position_local), SURFACE_ZERO_ID)
	else:
		_mesh_edit_wrapper.move_point(handle_id, new_position_local, SURFACE_ZERO_ID)

	_mesh_instance.mesh = _mesh_edit_wrapper.mesh # Overwrites original mesh!
	_redraw()


func _get_group_positions(handle_id: int, new_position_local: Vector3) -> Dictionary[int, Vector3]:
	var delta := new_position_local - _drag_initial_positions[handle_id]
	var point_positions: Dictionary[int, Vector3] = {}
	for id in _selected_handle_ids:
		point_positions[id] = _drag_initial_positions[id] + delta
	return point_positions

func _should_drag_as_group(handle_id: int) -> bool:
	return handle_id in _selected_handle_ids and _selected_handle_ids.size() > 1

func _commit_handle(handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	_drag_initial_positions = PackedVector3Array()
	if _mesh_edit_wrapper:
		_mesh_edit_wrapper.end_drag()
	if not _mesh_instance or not _mesh_edit_wrapper:
		_drag_before_snapshot = []
		return
	if cancel:
		if not _drag_before_snapshot.is_empty():
			_mesh_edit_wrapper.restore_state(_drag_before_snapshot, _mesh_instance)
		_drag_before_snapshot = []
		return
	_mesh_edit_wrapper.commit_changes(_mesh_instance)
	_record_move_undo_action(_drag_before_snapshot)
	_drag_before_snapshot = []

func _record_move_undo_action(before_snapshot: Array) -> void:
	if _undo_redo == null or before_snapshot.is_empty():
		return
	var after_snapshot: Array = []
	for s in _mesh_edit_wrapper.mesh.get_surface_count():
		after_snapshot.append(_mesh_edit_wrapper.mesh.surface_get_arrays(s))
	_undo_redo.create_action("Move vertices")
	_undo_redo.add_do_method(_mesh_edit_wrapper, &"restore_state", after_snapshot, _mesh_instance)
	_undo_redo.add_undo_method(_mesh_edit_wrapper, &"restore_state", before_snapshot, _mesh_instance)
	_undo_redo.commit_action(false)

func _draw_handles() -> void:
	var handle_positions := _mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)
	var normal_positions := PackedVector3Array()
	var normal_ids := PackedInt32Array()
	var selected_positions := PackedVector3Array()
	var selected_ids := PackedInt32Array()
	for i in handle_positions.size():
		if i in _selected_handle_ids:
			selected_positions.append(handle_positions[i])
			selected_ids.append(i)
		else:
			normal_positions.append(handle_positions[i])
			normal_ids.append(i)
	if normal_positions.size() > 0:
		add_handles(normal_positions, get_plugin().get_material("handles"), normal_ids)
	if selected_positions.size() > 0:
		add_handles(selected_positions, get_plugin().get_material("handles_selected"), selected_ids)
	if not _drag_initial_positions.is_empty():
		_draw_boundary_lines()

func _draw_boundary_lines() -> void:
	var positions := _mesh_edit_wrapper.get_boundary_positions_for_surface(SURFACE_ZERO_ID)
	if positions.size() < 2:
		return
	# Offset slightly along both sides of the face normal so the lines float just
	# above the mesh surface regardless of which side the camera is on.
	var normal := _mesh_edit_wrapper.get_face_normal_for_surface(SURFACE_ZERO_ID)
	var offset := normal * 0.001
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(BOUNDARY_DRAG_COLOR)
	for i in positions.size():
		var a := positions[i]
		var b := positions[(i + 1) % positions.size()]
		im.surface_add_vertex(a + offset)
		im.surface_add_vertex(b + offset)
		im.surface_add_vertex(a - offset)
		im.surface_add_vertex(b - offset)
	im.surface_end()
	add_mesh(im, get_plugin().get_material("polygon_outline"))

func _has_mesh_been_replaced(current_mesh_instance):
	var current_mesh_null = current_mesh_instance == null
	var previous_mesh_wrapper_null = _mesh_edit_wrapper == null
	if current_mesh_null != previous_mesh_wrapper_null:
		return true
	return _mesh_edit_wrapper.mesh != current_mesh_instance.mesh

func _set_mesh_instance(mesh_instance: MeshInstance3D):
	_mesh_instance = mesh_instance
	_update_mesh_edit_wrapper()

func _update_mesh_edit_wrapper():
	if _mesh_instance.mesh == null:
		_mesh_edit_wrapper = null
		_initialized = true
		return
	var array_mesh := MeshUtils.ensure_array_mesh(_mesh_instance.mesh)
	_mesh_instance.mesh = null
	await _mesh_instance.get_tree().process_frame
	_mesh_instance.mesh = array_mesh
	_mesh_edit_wrapper = MeshEditWrapper.new(array_mesh)
	_initialized = true

func _get_3D_point_from_screen_pos(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var face_normal_local := _mesh_edit_wrapper.get_face_normal_for_surface(SURFACE_ZERO_ID)
	var face_normal_world := (_mesh_instance.global_transform.basis * face_normal_local).normalized()
	var points := _mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)
	if face_normal_world == Vector3.ZERO or points.is_empty():
		return Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_dir)
	var plane := Plane(face_normal_world, _mesh_instance.to_global(points[0]))
	return plane.intersects_ray(ray_origin, ray_dir)
