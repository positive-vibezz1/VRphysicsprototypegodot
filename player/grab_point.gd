class_name GrabPoint
extends Marker3D
## A place a hand can take hold of. The parent must be the rigid body that gets held.
## SNAP brings the point into the palm and locks it rigidly: firing grips and loose magazines.
## PIN holds the body where the hand touched it and leaves rotation free: handguard, slide, charging handle.

enum Mode { SNAP, PIN }

@export var mode := Mode.SNAP
@export var radius := 0.1
## Half length of the grabbable segment along the local Z axis, for long parts like a handguard.
@export var half_length := 0.0
@export var enabled := true

var holder: PhysicsHand

@onready var body: RigidBody3D = get_parent()


func _ready() -> void:
	add_to_group(&"grab_points")


## How far outside this point's reach a position is. Negative means in reach.
func reach_distance(from: Vector3) -> float:
	var local := to_local(from)
	local.z -= clampf(local.z, -half_length, half_length)
	return local.length() - radius


## Inertia the hand has to turn when holding this point, about the palm along the held body's axes.
## A pin leaves rotation free, so it adds none.
func carried_inertia(palm: Vector3) -> Vector3:
	var total := Vector3.ZERO
	if mode == Mode.PIN:
		return total
	var to_local := body.global_basis.inverse()
	for part: RigidBody3D in owner.bodies():
		var state := PhysicsServer3D.body_get_direct_state(part.get_rid())
		var r := to_local * (part.global_transform * part.center_of_mass - palm)
		total += Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y) * part.mass
		total += Vector3.ONE / state.inverse_inertia
	return total


## Teleports the owning gun or magazine so that this point lands on the given transform.
func snap_to(target: Transform3D) -> void:
	owner.teleport(target * global_transform.affine_inverse())
