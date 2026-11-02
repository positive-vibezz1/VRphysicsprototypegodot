@tool
class_name ProfileMesh
extends PrimitiveMesh
## A flat shaded extrusion of a 2D outline, for gun parts whose shape is a side profile: slides, frames,
## receivers, grips, stocks. Each point is (z, y) in the part's local space, so the outline is drawn as seen
## from the gun's right side with the muzzle toward -Z, and the solid spans `width` across X. Points may be
## in either winding. Rotate the MeshInstance3D to extrude along another axis.

@export var points := PackedVector2Array([Vector2(-0.05, -0.01), Vector2(0.05, -0.01), Vector2(0.05, 0.01), Vector2(-0.05, 0.01)]):
	set(value):
		points = value
		request_update()
@export var width := 0.03:
	set(value):
		width = value
		request_update()


func _create_mesh_array() -> Array:
	var outline := points
	if outline.size() < 3:
		return []
	if Geometry2D.is_polygon_clockwise(outline):
		outline = outline.duplicate()
		outline.reverse()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var half := width * 0.5

	# Side caps, triangulated from the outline.
	var cap := Geometry2D.triangulate_polygon(outline)
	for side: float in [half, -half]:
		var normal := Vector3(signf(side), 0.0, 0.0)
		var i := 0
		while i < cap.size():
			var a := outline[cap[i]]
			var b := outline[cap[i + 1]]
			var c := outline[cap[i + 2]]
			_add_face(vertices, normals, uvs, normal, [
				Vector3(side, a.y, a.x), Vector3(side, b.y, b.x), Vector3(side, c.y, c.x),
			], [a, b, c])
			i += 3

	# Walls, one quad per outline edge. The outline is counter-clockwise, so the outside is to the right.
	for i: int in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var edge := b - a
		var normal := Vector3(0.0, -edge.x, edge.y).normalized()
		var run := edge.length()
		_add_face(vertices, normals, uvs, normal, [
			Vector3(-half, a.y, a.x), Vector3(half, a.y, a.x), Vector3(half, b.y, b.x),
		], [Vector2(0.0, 0.0), Vector2(width, 0.0), Vector2(width, run)])
		_add_face(vertices, normals, uvs, normal, [
			Vector3(-half, a.y, a.x), Vector3(half, b.y, b.x), Vector3(-half, b.y, b.x),
		], [Vector2(0.0, 0.0), Vector2(width, run), Vector2(0.0, run)])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


## Adds one triangle wound clockwise as seen from its outside, which is what Godot draws as a front face.
static func _add_face(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		normal: Vector3, corners: Array[Vector3], texcoords: Array[Vector2]) -> void:
	var order: Array[int] = [0, 1, 2]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		order = [0, 2, 1]
	for k: int in order:
		vertices.append(corners[k])
		normals.append(normal)
		uvs.append(texcoords[k])
