# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
# © 2025-2026 Stefan Schätz

class_name VertexDragConstraint
extends RefCounted

var _initial_position_3d: Vector3
var _initial_position_2d: Vector2
var _neighbor_positions_2d: Array[Vector2]
var _non_adjacent_edges_2d: Array  # Array of [Vector2, Vector2]
var _tangent: Vector3
var _bitangent: Vector3

func _init(
	initial_pos_3d: Vector3,
	neighbors_2d: Array[Vector2],
	non_adjacent_edges_2d: Array,
	tangent: Vector3,
	bitangent: Vector3
) -> void:
	_tangent = tangent
	_bitangent = bitangent
	_initial_position_3d = initial_pos_3d
	_initial_position_2d = _to_2d(initial_pos_3d)
	_neighbor_positions_2d = neighbors_2d
	_non_adjacent_edges_2d = non_adjacent_edges_2d

## Clamps proposed_position_3d to the furthest position along the drag path
## from the initial position that does not create a self-intersecting polygon.
func clamp_position(proposed_position_3d: Vector3) -> Vector3:
	var proposed_2d := _to_2d(proposed_position_3d)
	var drag_delta := proposed_2d - _initial_position_2d
	if drag_delta.length_squared() < 1e-12:
		return proposed_position_3d

	var t_max := 1.0
	for neighbor_2d: Vector2 in _neighbor_positions_2d:
		for edge: Array in _non_adjacent_edges_2d:
			var t := _find_first_intersection_t(
				neighbor_2d, _initial_position_2d, drag_delta, edge[0], edge[1]
			)
			if t < t_max:
				t_max = t

	var t_clamped := maxf(0.0, t_max - 1e-4)
	return _initial_position_3d \
		+ t_clamped * drag_delta.x * _tangent \
		+ t_clamped * drag_delta.y * _bitangent

func _to_2d(v: Vector3) -> Vector2:
	return Vector2(v.dot(_tangent), v.dot(_bitangent))

## Returns the smallest t in (0, 1] at which segment origin-B(t) first intersects
## segment p-q, where B(t) = b_init + t * drag_delta. Returns 1.0 if none.
static func _find_first_intersection_t(
	origin: Vector2, b_init: Vector2, drag_delta: Vector2, p: Vector2, q: Vector2
) -> float:
	var pq := q - p
	# d3: which side of line PQ origin is on (constant throughout the drag)
	var d3 := _cross2d(pq, origin - p)
	# d4(t): which side of line PQ B(t) is on (linear in t)
	var d4_0 := _cross2d(pq, b_init - p)
	var d4_slope := _cross2d(pq, drag_delta)
	# d1(t): which side of line origin-B(t) p is on (linear in t)
	var b_init_from_origin := b_init - origin
	var d1_0 := _cross2d(b_init_from_origin, p - origin)
	var d1_slope := _cross2d(drag_delta, p - origin)
	# d2(t): which side of line origin-B(t) q is on (linear in t)
	var d2_0 := _cross2d(b_init_from_origin, q - origin)
	var d2_slope := _cross2d(drag_delta, q - origin)

	# Segments intersect when d3*d4 < 0 AND d1*d2 < 0
	if d3 * d4_0 < 0.0 and d1_0 * d2_0 < 0.0:
		return 0.0  # already intersecting at drag start (invalid initial state)

	# Collect the t values at which each sign product transitions through zero
	var candidates: Array[float] = []
	_add_sign_change_t(candidates, d4_0, d4_slope)
	_add_sign_change_t(candidates, d1_0, d1_slope)
	_add_sign_change_t(candidates, d2_0, d2_slope)
	candidates.sort()

	for t: float in candidates:
		# Evaluate conditions just after the transition point, not at it,
		# because the sign products are exactly zero at t and become negative
		# only for t + ε. We return t (the boundary), not t_check.
		var t_check := t + 1e-6
		if d3 * (d4_0 + t_check * d4_slope) < 0.0 and \
				(d1_0 + t_check * d1_slope) * (d2_0 + t_check * d2_slope) < 0.0:
			return t

	return 1.0

## Adds t = -value_0 / slope to candidates if it falls in (1e-6, 1].
static func _add_sign_change_t(candidates: Array[float], value_0: float, slope: float) -> void:
	if abs(slope) > 1e-10:
		var t := -value_0 / slope
		if t > 1e-6 and t <= 1.0:
			candidates.append(t)

static func _cross2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x
