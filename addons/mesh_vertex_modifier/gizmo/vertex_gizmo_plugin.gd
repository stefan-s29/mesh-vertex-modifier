# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

@tool
class_name VertexGizmoPlugin
extends EditorNode3DGizmoPlugin

var _mesh_edit_wrapper: MeshEditWrapper

const SURFACE_ZERO_ID = 0;

func _init():
	create_material("vertex", Color.RED)
	create_handle_material("handles")

func _get_gizmo_name():
	return 'MeshDrawer Gizmo'

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return 'Vertex ' + str(handle_id)

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var mesh_instance = gizmo.get_node_3d() as MeshInstance3D
	return mesh_instance.name

func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and node.mesh != null

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	
	var mesh_instance = _get_mesh_instance_3d_from_gizmo(gizmo)
	if mesh_instance == null || mesh_instance.mesh == null:
		_mesh_edit_wrapper = null
		return
	
	if _mesh_edit_wrapper == null || _mesh_edit_wrapper.mesh != mesh_instance.mesh:
		var array_mesh := MeshUtils.ensure_array_mesh(mesh_instance.mesh)
		_mesh_edit_wrapper = MeshEditWrapper.new(array_mesh)
	
	gizmo.add_handles(
		PackedVector3Array(_mesh_edit_wrapper.get_unique_points_for_surface(SURFACE_ZERO_ID)),
		get_material("handles", gizmo),
		[],
		false,
		false,
	)

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2):
	var mesh_instance = _get_mesh_instance_3d_from_gizmo(gizmo)
	if mesh_instance == null || mesh_instance.mesh == null: return
	
	var new_position = _get_3D_point_from_screen_pos(camera, screen_pos)
	_mesh_edit_wrapper.move_point(handle_id, new_position, SURFACE_ZERO_ID)
	mesh_instance.mesh = _mesh_edit_wrapper.mesh # Overwrites original mesh!

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
