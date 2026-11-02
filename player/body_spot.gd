class_name BodySpot
extends Node3D
## A place on the body that a hand finds by feel, like a pouch or a holster. Nothing tracks the torso, so it follows
## the head, but lazily: the torso stays put while the head turns to look down at a hip or back over a shoulder, and
## only comes round once the head turns further than a neck does. A stick turn turns it at once, since that turns the
## XR origin the head is in.

## The eyes, a child of the XR origin.
@export var head: Node3D
## Relative to the eyes, along the torso's right, up and back.
@export var pose := Transform3D.IDENTITY
@export var radius := 0.15
## How far the head turns from the torso before the torso turns with it.
@export_range(0.0, 180.0, 1.0, "radians_as_degrees") var max_twist := deg_to_rad(45.0)

## Torso yaw in the XR origin.
var _yaw := NAN


func _process(_delta: float) -> void:
	global_transform = spot()


## The head's right axis stays level while looking down, where its forward axis points at the floor.
func spot() -> Transform3D:
	var right := head.basis.x
	var head_yaw := atan2(-right.z, right.x)
	if is_nan(_yaw):
		_yaw = head_yaw
	var twist := angle_difference(_yaw, head_yaw)
	_yaw += twist - clampf(twist, -max_twist, max_twist)
	var torso := head.get_parent_node_3d().global_basis * Basis(Vector3.UP, _yaw)
	return Transform3D(torso, head.global_position) * pose


func in_reach(point: Vector3) -> bool:
	return spot().origin.distance_to(point) < radius
