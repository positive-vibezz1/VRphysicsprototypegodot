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


## Puts the gun in the first free holster its grip is in. Returns whether one took it.
static func stow(released: Gun) -> bool:
	var grip := released.grip.global_position
	for holster: Holster in all:
		if not holster.gun and holster.in_reach(grip):
			holster._take(released)
			return true
	# How far off a near miss was, for placing them where hands go.
	for holster: Holster in all:
		var off := holster.spot().origin.distance_to(grip)
		if off < holster.radius * 3.0:
			DebugLog.event("hand", "%s let go %.2f m from the %s, which takes one within %.2f m" % [released.name, off, holster.name, holster.radius])
	return false


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
