class_name Holster
extends BodySpot
## Puts away a gun whose grip is let go of here, and carries it with the body until a hand takes the grip again. The
## pose is the palm's as if holding the grip there. A holstered gun is frozen and moved along with the body each tick:
## hanging on a joint, it would snag on every wall the body brushes past.

## Every holster in the scene, for a hand letting go of a gun to look through.
static var all: Array[Holster] = []

var gun: Gun


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## Puts the gun in the nearest free holster, if its grip is in that one's reach. Returns whether it took it.
static func stow(released: Gun) -> bool:
	var grip := released.grip.global_position
	var nearest: Holster
	var off := Vector3.INF
	for holster: Holster in all:
		var from_spot := holster._from_spot(grip)
		if not holster.gun and from_spot.length() < off.length():
			nearest = holster
			off = from_spot
	if nearest and off.length() < nearest.radius:
		nearest._take(released)
		return true
	# Which way a near miss was, for placing them where hands go.
	if nearest and off.length() < 0.5:
		DebugLog.event("hand", "%s let go %.2f m from the %s (%+.2f right, %+.2f up, %+.2f back), which takes one within %.2f m" % [released.name, off.length(), nearest.name, off.x, off.y, off.z, nearest.radius])
	return false


## Where a point is from the spot, along the torso's right, up and back.
func _from_spot(point: Vector3) -> Vector3:
	var at := spot()
	return pose.basis * (at.basis.inverse() * (point - at.origin))


## Frees a gun a hand is taking, before the hand weighs it: a frozen body has no inertia to carry.
static func draw(taken: Gun) -> void:
	for holster: Holster in all:
		if holster.gun == taken:
			DebugLog.event("hand", "%s drawn from the %s" % [taken.name, holster.name])
			holster._set_frozen(false)
			holster.gun = null


func _physics_process(_delta: float) -> void:
	if gun:
		gun.grip.snap_to(spot())


func _take(taken: Gun) -> void:
	gun = taken
	_set_frozen(true)
	gun.grip.snap_to(spot())
	Ballistics.pool.play_click(gun.grip.global_position)
	DebugLog.event("hand", "%s put away in the %s" % [gun.name, name])


func _set_frozen(frozen: bool) -> void:
	for body: RigidBody3D in gun.bodies():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = frozen
