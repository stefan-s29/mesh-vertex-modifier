# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

@tool
class_name MeshDrawerPlugin
extends EditorPlugin

var _gizmo_plugin: VertexGizmoPlugin
var _inspector_watcher := MeshInspectorWatcher.new()

func _enter_tree():
	_gizmo_plugin = preload("res://addons/mesh_vertex_modifier/gizmo/vertex_gizmo_plugin.gd").new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	
	_inspector_watcher.start_watching(get_undo_redo())

func _exit_tree():
	if _inspector_watcher:
		_inspector_watcher.stop_watching()
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null
