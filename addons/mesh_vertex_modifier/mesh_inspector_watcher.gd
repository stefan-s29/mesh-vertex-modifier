# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

@tool
class_name MeshInspectorWatcher

var _undo_redo: EditorUndoRedoManager    

var _mesh_instance: MeshInstance3D

func start_watching(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	
	var selection := EditorInterface.get_selection()
	selection.selection_changed.connect(_on_selection_changed)
	_undo_redo.version_changed.connect(_on_undo_redo_version_changed)
	EditorInterface.get_inspector().property_edited.connect(_on_inspector_property_edited)

func stop_watching() -> void:
	var selection := EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	if _undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
		_undo_redo.version_changed.disconnect(_on_undo_redo_version_changed)
	if EditorInterface.get_inspector().property_edited.is_connected(_on_inspector_property_edited):
		EditorInterface.get_inspector().property_edited.disconnect(_on_inspector_property_edited)
	_undo_redo = null

func _on_selection_changed() -> void:
	_mesh_instance = _first_selected_mesh_instance()
	_update_gizmos()

func _on_undo_redo_version_changed() -> void:
	_update_gizmos()

func _on_inspector_property_edited(prop: StringName) -> void:
	_update_gizmos()

func _update_gizmos() -> void:
	if _mesh_instance:
		_mesh_instance.update_gizmos()

func _first_selected_mesh_instance() -> MeshInstance3D:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	for n in nodes:
		if n is MeshInstance3D:
			return n as MeshInstance3D
	return null
