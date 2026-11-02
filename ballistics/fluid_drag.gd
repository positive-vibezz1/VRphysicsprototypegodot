class_name FluidDrag
extends Node
## Child of the ballistics pool: what air or water does to every rigid body that's moving, whichever scene it came from.
## Drag is 0.5 rho v^2 Cd A against the motion and buoyancy rho V g upward, with rho from MediumVolume. Bullets do their
## own drag, since they can cross a whole box between ticks. Each one's size is worked out from its collision shapes
## the first time it moves, so a pooled casing keeps the size of its first cartridge, which only shows in water. A body
## with an unusual shape or fill can say otherwise with metadata: `drag_coefficient` for Cd, `bulk_density` in kg/m3 for
## what it displaces.

## Layer 5, moving gun parts. They ride inside the frame, where air never reaches them, and this skips up to two more
## bodies per gun.
const MOVING_GUN_PART := 16
## Bluff bodies are all about here: 1.05 for a cube, about 1.1 for a person, 1.2 for a tumbling cylinder.
const DRAG_COEFFICIENT := 1.0
## Speed in m/s under which something with little lift is left alone, since touching it stops Jolt putting it to sleep.
## This is Jolt's sleep threshold, and drag at this speed is next to nothing even in water.
const STILL := 0.03
## Lift as a share of weight under which it can't move what's resting on something.
const SMALLEST_LIFT := 0.1

var _entries: Array[Entry] = []
var _gravity := 9.8


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


## A body that fills a share f of its bounding box is taken to show f^(2/3) of what the box shows, the box showing a
## quarter of its surface on average from all sides (Cauchy's formula). That gives a person 0.6 m2, a real figure.
static func measure(entry: Entry) -> void:
	entry.volume = 0.0
	var bounds := AABB()
	for child: Node in entry.body.get_children():
		var collider := child as CollisionShape3D
		if not collider or not collider.shape:
			continue
		var size := Vector3.ZERO
		var fill := 1.0
		if collider.shape is BoxShape3D:
			size = (collider.shape as BoxShape3D).size
		elif collider.shape is SphereShape3D:
			size = Vector3.ONE * 2.0 * (collider.shape as SphereShape3D).radius
			fill = PI / 6.0
		elif collider.shape is CylinderShape3D:
			var cylinder := collider.shape as CylinderShape3D
			size = Vector3(2.0 * cylinder.radius, cylinder.height, 2.0 * cylinder.radius)
			fill = PI / 4.0
		elif collider.shape is CapsuleShape3D:
			var capsule := collider.shape as CapsuleShape3D
			size = Vector3(2.0 * capsule.radius, capsule.height, 2.0 * capsule.radius)
			fill = PI / 4.0 * (1.0 - 2.0 * capsule.radius / (3.0 * capsule.height))
		else:
			size = collider.shape.get_debug_mesh().get_aabb().size
		var box := collider.transform * AABB(size * -0.5, size)
		bounds = bounds.merge(box) if entry.volume > 0.0 else box
		entry.volume += size.x * size.y * size.z * fill
	if entry.volume <= 0.0:
		return
	var s := bounds.size
	var share := minf(entry.volume / bounds.get_volume(), 1.0)
	var area := 0.5 * (s.x * s.y + s.y * s.z + s.z * s.x) * pow(share, 2.0 / 3.0)
	entry.drag_area = 0.5 * float(entry.body.get_meta(&"drag_coefficient", DRAG_COEFFICIENT)) * area
	entry.center = bounds.get_center()
	entry.half = s * 0.5
	entry.radius = entry.half[entry.half.max_axis_index()]
	if entry.body.has_meta(&"bulk_density"):
		entry.volume = entry.body.mass / float(entry.body.get_meta(&"bulk_density"))


func _physics_process(delta: float) -> void:
	for entry: Entry in _entries:
		var body := entry.body
		if body.sleeping or body.freeze or not body.can_process():
			continue
		if entry.volume < 0.0:
			measure(entry)
		if entry.volume <= 0.0:
			continue
		# How much of each medium its height is in, which also takes care of being half sunk.
		var axes := body.global_basis
		var middle := body.global_transform * entry.center
		var reach := Vector3.UP * (
			absf(axes.x.y) * entry.half.x + absf(axes.y.y) * entry.half.y + absf(axes.z.y) * entry.half.z
		)
		var density := MediumVolume.column(middle - reach, middle + reach) / (2.0 * reach.y)
		var lift := density * entry.volume / body.mass
		var velocity := body.linear_velocity
		var speed := velocity.length()
		var spin := body.angular_velocity
		var tip_speed := spin.length() * entry.radius
		if lift < SMALLEST_LIFT and speed + tip_speed < STILL:
			continue
		# exp() is the exact fall in speed over a stretch of quadratic drag, dv/dx = -k v, so it holds at any tick. Water
		# can take most of a light body's speed in one.
		var per_mass := entry.drag_area * density * delta / body.mass
		body.apply_central_impulse(
			body.mass * (velocity * (exp(-per_mass * speed) - 1.0) + Vector3.UP * lift * _gravity * body.gravity_scale * delta)
		)
		# The same drag at the speed of its tips: a torque of 0.5 rho Cd A (w r)^2 r / 4 from a surface spread out along
		# the radius, on an inertia of about 0.4 m r^2.
		if tip_speed > 0.0:
			body.angular_velocity = spin * exp(-0.625 * per_mass * tip_speed)


func _on_node_added(node: Node) -> void:
	var body := node as RigidBody3D
	if body and not body is Bullet and not body.collision_layer & MOVING_GUN_PART:
		var entry := Entry.new()
		entry.body = body
		_entries.append(entry)


func _on_node_removed(node: Node) -> void:
	if node is RigidBody3D:
		for i: int in _entries.size():
			if _entries[i].body == node:
				_entries.remove_at(i)
				return


## One body and the numbers that don't change as it moves.
class Entry:
	var body: RigidBody3D
	## Negative until measured.
	var volume := -1.0
	## 0.5 Cd A, in m2.
	var drag_area := 0.0
	## Middle and half size of the box around its shapes, in its own space.
	var center := Vector3.ZERO
	var half := Vector3.ZERO
	var radius := 0.0
