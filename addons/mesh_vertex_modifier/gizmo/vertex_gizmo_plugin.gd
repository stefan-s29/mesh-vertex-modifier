# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

@tool
class_name VertexGizmoPlugin
extends EditorNode3DGizmoPlugin

func _init():
	create_material("vertex", Color.RED)
	create_handle_material("handles")

func _get_gizmo_name():
	return 'Mesh Vertex Modifier Gizmo'

func _create_gizmo(node: Node3D):
	if node is MeshInstance3D:
		return VertexGizmo.new(node as MeshInstance3D)
	else:
		return null
