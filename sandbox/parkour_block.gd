@tool
extends StaticBody3D
## A block of the parkour course. It builds its own mesh and shape from its size, so a block is just a size and a
## place in the scene, and can be moved and resized in the editor. The grapple catches any block. A hand can only grip
## one marked climbable, such as a ledge's lip or a crevice.

@export var size := Vector3.ONE:
	set(value):
		size = value
		_mesh.size = value
		_shape.size = value
@export var material: Material:
	set(value):
		material = value
		_mesh.material = value
@export var climbable := false

var _mesh := BoxMesh.new()
var _shape := BoxShape3D.new()


func _ready() -> void:
	# World, grapple target, and climbable if it is. Nothing pushes a static body, so it needs no mask.
	collision_layer = 3073 if climbable else 2049
	collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)
