# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

@tool
class_name VertexGizmoPlugin
extends EditorNode3DGizmoPlugin

func _init():
	create_material("vertex", Color.RED)
	# Albedo unused — actual color comes from surface_set_color via use_vertex_color=true.
	create_material("polygon_outline", Color.WHITE, false, true, true)
	var boundary_mat := get_material("polygon_outline") as StandardMaterial3D
	if boundary_mat:
		boundary_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	create_handle_material("handles")
	create_handle_material("handles_selected")
	var selected_mat := get_material("handles_selected") as StandardMaterial3D
	if selected_mat:
		selected_mat.albedo_color = Color(1.0, 0.7, 0.0)

func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null

func _get_gizmo_name():
	return 'Mesh Vertex Modifier Gizmo'

func _create_gizmo(node: Node3D):
	if node is MeshInstance3D and node.mesh != null:
		return VertexGizmo.new(node as MeshInstance3D)
	else:
		return null
