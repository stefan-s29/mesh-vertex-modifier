# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

@tool
class_name MeshDrawerPlugin
extends EditorPlugin

var gizmo_plugin: VertexGizmoPlugin

func _enter_tree():
	gizmo_plugin = preload("res://addons/mesh_vertex_modifier/gizmo/vertex_gizmo_plugin.gd").new()
	add_node_3d_gizmo_plugin(gizmo_plugin)

func _exit_tree():
	remove_node_3d_gizmo_plugin(gizmo_plugin)
