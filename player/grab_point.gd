class_name GrabPoint
extends Marker3D
## A place a hand can take hold of. The parent must be the rigid body that gets held. The marker's pose is where
## the palm goes, its -Z along the part the fingers wrap, and its origin in the middle of that part.
## SNAP brings the point into the palm and locks it rigidly: firing grips and loose magazines.
## SUPPORT brings the palm to the point and locks it rigidly: spots for a second hand on a gun already held.
## PIN holds the body where the hand touched it and leaves rotation free: slide, charging handle.

enum Mode { SNAP, PIN, SUPPORT }
## How a right hand takes a point laid out for a left hand.
enum RightHand { SAME, TURNED, MIRRORED }

@export var mode := Mode.SNAP
@export var radius := 0.1
@export var enabled := true
@export var right_hand := RightHand.SAME
## How far the fingers close here: 1 is a fist, and lower wraps something thicker. 0.55 fits a 44 mm grip.
@export var finger_closure := 0.55
## A second hand far along the gun steers it, so the wrists give way to it. One right by the grip can't.
@export var steers := false
## Where the palm ends up relative to this point, along its local axes. A hand can hold a part well away from
## itself, so two real controllers don't collide when the part has to go somewhere close to the other hand.
@export var palm_offset := Vector3.ZERO

## Every grab point in the scene, so hands can search them each tick without allocating.
static var all: Array[GrabPoint] = []

var holder: PhysicsHand

@onready var body: RigidBody3D = get_parent()


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## How far outside this point's reach a position is. Negative means in reach.
func reach_distance(from: Vector3) -> float:
	return to_local(from).length() - radius


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


## The palm's pose when holding this point, relative to the held body.
func palm_pose(left_hand := true) -> Transform3D:
	var pose := transform.translated_local(palm_offset)
	if not left_hand:
		match right_hand:
			RightHand.TURNED:
				pose.basis *= Basis(Vector3.BACK, PI)
			RightHand.MIRRORED:
				pose.origin.x = -pose.origin.x
	return pose


## The same in world space.
func palm_transform(left_hand := true) -> Transform3D:
	return body.global_transform * palm_pose(left_hand)


## Teleports the owning gun or magazine so that the palm pose lands on the given transform.
func snap_to(target: Transform3D, left_hand := true) -> void:
	owner.teleport(target * palm_transform(left_hand).affine_inverse())
