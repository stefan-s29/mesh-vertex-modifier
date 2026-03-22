# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

@tool
class_name MeshDrawerPlugin
extends EditorPlugin

var _gizmo_plugin: VertexGizmoPlugin
var _inspector_watcher := MeshInspectorWatcher.new()
var _toolbar: HBoxContainer
var _btn_delete_vertex: Button

func _enter_tree():
	_gizmo_plugin = preload("res://addons/mesh_vertex_modifier/gizmo/vertex_gizmo_plugin.gd").new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	_inspector_watcher.start_watching(get_undo_redo())
	_create_toolbar()
	EditorInterface.get_selection().selection_changed.connect(_update_toolbar_state)

func _exit_tree():
	var selection := EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_update_toolbar_state):
		selection.selection_changed.disconnect(_update_toolbar_state)
	if _toolbar:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null
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
		if not mb.shift_pressed and gizmo.is_handle_selected(clicked_id):
			pass  # Preserve selection so dragging moves all selected handles
		else:
			gizmo.select_handle(clicked_id, mb.shift_pressed)
	else:
		gizmo.clear_selection()
	_update_toolbar_state()
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _create_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_child(VSeparator.new())

	_btn_delete_vertex = Button.new()
	_btn_delete_vertex.text = "Delete Vertex"
	_btn_delete_vertex.disabled = true
	_btn_delete_vertex.pressed.connect(_on_delete_vertex_pressed)
	_toolbar.add_child(_btn_delete_vertex)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()

func _update_toolbar_state() -> void:
	var gizmo := _get_current_vertex_gizmo()
	if not gizmo:
		_toolbar.hide()
		return
	_toolbar.show()
	var selected := gizmo.get_selected_handle_count()
	var total := gizmo.get_total_handle_count()
	_btn_delete_vertex.disabled = selected < 1 or (total - selected) < 3

func _on_delete_vertex_pressed() -> void:
	var gizmo := _get_current_vertex_gizmo()
	if gizmo:
		gizmo.delete_selected_handles()
	_update_toolbar_state()

func _get_current_vertex_gizmo() -> VertexGizmo:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		return null
	var node := selected_nodes[0]
	if not node is MeshInstance3D:
		return null
	return _get_vertex_gizmo(node as MeshInstance3D)

func _get_vertex_gizmo(node: MeshInstance3D) -> VertexGizmo:
	for gizmo in node.get_gizmos():
		if gizmo is VertexGizmo:
			return gizmo
	return null
