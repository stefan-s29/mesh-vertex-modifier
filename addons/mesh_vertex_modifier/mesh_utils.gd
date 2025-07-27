# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025 Stefan Schätz

class_name MeshUtils
extends RefCounted

static func get_vertices_from_points(points: Array[Vector3]) -> Array[Vector3]:
	var center = Vector3.ZERO
	for p in points:
		center += p
	center /= points.size()

	var vertices: Array[Vector3] = []
	for i in range(points.size()):
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		vertices.append(center)
		vertices.append(a)
		vertices.append(b)
	return vertices

static func ensure_array_mesh(mesh: Mesh) -> ArrayMesh:
	if mesh is ArrayMesh:
		return mesh as ArrayMesh

	var array_mesh := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, i)
		st.commit(array_mesh)
	return array_mesh
