@tool
extends StaticBody3D
## A block of the parkour course. It builds its own mesh and shape from its size, so a block is just a size and a
## place in the scene, and can be moved and resized in the editor. The grapple catches any block unless told not to, so
## a course can keep it for the parts meant for it. A hand can only grip one marked climbable, such as a ledge's lip or
## a crevice.

## Layer 12, what the grapple catches.
const GRAPPLE_TARGET_LAYER := 2048

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
@export var grapple_target := true

var _mesh := BoxMesh.new()
var _shape := BoxShape3D.new()


func _ready() -> void:
	# World, and climbable and grapple target if it is. Nothing pushes a static body, so it needs no mask.
	collision_layer = 1 | (PhysicsHand.CLIMBABLE_LAYER if climbable else 0)
	if grapple_target:
		collision_layer |= GRAPPLE_TARGET_LAYER
	collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)
