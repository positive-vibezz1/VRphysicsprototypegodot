@tool
extends StaticBody3D
## A pipe, rung or bar on the parkour course, running along its local Y. Unlike a block, a hand can grip it.

@export var length := 1.0:
	set(value):
		length = value
		_refresh()
@export var radius := 0.025:
	set(value):
		radius = value
		_refresh()
@export var material: Material:
	set(value):
		material = value
		_refresh()

var _mesh := CylinderMesh.new()
var _shape := CylinderShape3D.new()


func _ready() -> void:
	# World, climbable and grapple target. Nothing pushes a static body, so it needs no mask.
	collision_layer = 3073
	collision_mask = 0
	_mesh.radial_segments = 12
	_mesh.rings = 1
	_refresh()
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)


func _refresh() -> void:
	_mesh.height = length
	_mesh.top_radius = radius
	_mesh.bottom_radius = radius
	_mesh.material = material
	_shape.height = length
	_shape.radius = radius
