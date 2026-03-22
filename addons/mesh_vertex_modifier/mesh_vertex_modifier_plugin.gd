# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

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

func _handles(object: Object) -> bool:
	return object is MeshInstance3D

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not event is InputEventMouseButton:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var node := selected_nodes[0]
	if not node is MeshInstance3D:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var gizmo := _get_vertex_gizmo(node as MeshInstance3D)
	if not gizmo:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var clicked_id := gizmo.find_handle_at_screen_pos(camera, mb.position)
	if clicked_id >= 0:
		gizmo.select_handle(clicked_id, mb.shift_pressed)
	else:
		gizmo.clear_selection()
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _get_vertex_gizmo(node: MeshInstance3D) -> VertexGizmo:
	for gizmo in node.get_gizmos():
		if gizmo is VertexGizmo:
			return gizmo
	return null
