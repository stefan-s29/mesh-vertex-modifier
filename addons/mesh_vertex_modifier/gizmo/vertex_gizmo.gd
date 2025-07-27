# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

@tool
class_name VertexGizmo
extends EditorNode3DGizmo

const SURFACE_ZERO_ID = 0;

var _mesh_instance: MeshInstance3D
var _mesh_edit_wrapper: MeshEditWrapper

func _init(mesh_instance: MeshInstance3D):
	print('init')
	_update_mesh_instance(mesh_instance)

func _update_mesh_instance(mesh_instance: MeshInstance3D):
	_mesh_instance = mesh_instance
	var array_mesh := MeshUtils.ensure_array_mesh(mesh_instance.mesh)
	_mesh_edit_wrapper = MeshEditWrapper.new(array_mesh)

func _get_handle_name(handle_id: int, secondary: bool) -> String:
	return 'Vertex ' + str(handle_id)

func _get_handle_value(handle_id: int, secondary: bool) -> Variant:
	return _mesh_instance.name

func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and node.mesh != null

func _redraw() -> void:
	clear()
	
	var node3D = get_node_3d()
	if !(node3D is MeshInstance3D):
		_mesh_instance = null
		_mesh_edit_wrapper = null
		return
	
	var current_mesh_instance = node3D as MeshInstance3D
	if _mesh_edit_wrapper.mesh != current_mesh_instance.mesh:
		_update_mesh_instance(current_mesh_instance)
	
	var handles = PackedVector3Array(_mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID))
	var handles_material = get_plugin().get_material("handles")
	add_handles(handles, handles_material, [], false, false)

func _set_handle(handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2):
	var new_position = _get_3D_point_from_screen_pos(camera, screen_pos)
	_mesh_edit_wrapper.move_point(handle_id, new_position, SURFACE_ZERO_ID)
	_mesh_instance.mesh = _mesh_edit_wrapper.mesh # Overwrites original mesh!

func _get_mesh_instance_3d_from_gizmo(gizmo: EditorNode3DGizmo) -> MeshInstance3D:
	var mesh_instance = gizmo.get_node_3d() as MeshInstance3D
	if !mesh_instance:
		print('Not a mesh instance: ', mesh_instance)
	return mesh_instance

func _get_3D_point_from_screen_pos(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	var plane = Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(ray_origin, ray_dir)
