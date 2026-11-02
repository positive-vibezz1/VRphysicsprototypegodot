@tool
class_name MediumVolume
extends Area3D
## A box of something other than the air around it, with nothing holding it in. What's at any point in the world is
## here, for anything that depends on it, and FluidDrag and Bullet get their drag and buoyancy from its density. A liquid
## also splashes when something goes in.

## A body going in slower than this makes no splash.
const SLOWEST_SPLASH := 0.3
## Player, hand, gun frame, magazine, casing and target. Bullets check for themselves, because they can cross a box
## between two ticks.
const LIQUID_MASK := 686

## Every volume in the scene, for looking up what's at a point without a physics query.
static var all: Array[MediumVolume] = []

@export var medium: Medium
@export var size := Vector3.ONE:
	set(value):
		size = value
		_mesh.size = value
		_shape.size = value
@export var material: Material:
	set(value):
		material = value
		_mesh.material = value

var _mesh := BoxMesh.new()
var _shape := BoxShape3D.new()


static func medium_at(point: Vector3) -> Medium:
	for volume: MediumVolume in all:
		if volume.contains(point):
			return volume.medium
	return Medium.ambient


static func liquid_at(point: Vector3) -> MediumVolume:
	for volume: MediumVolume in all:
		if volume.medium.is_liquid and volume.contains(point):
			return volume
	return null


## How much fluid a straight line goes through, in kg/m2.
static func column(from: Vector3, to: Vector3) -> float:
	var total := Medium.ambient.density * from.distance_to(to)
	for volume: MediumVolume in all:
		total += (volume.medium.density - Medium.ambient.density) * volume.path_length(from, to)
	return total


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	collision_layer = 0
	monitorable = false
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)
	if medium.is_liquid:
		collision_mask = LIQUID_MASK
		set_meta(&"surface", Sounds.Surface.WATER)
		if not Engine.is_editor_hint():
			body_entered.connect(_on_body_entered)
	else:
		collision_mask = 0
		monitoring = false


func contains(point: Vector3) -> bool:
	var local := to_local(point).abs() - size * 0.5
	return local.x <= 0.0 and local.y <= 0.0 and local.z <= 0.0


## How much of a straight line runs through the box, in meters.
func path_length(from: Vector3, to: Vector3) -> float:
	var span := _clip(from, to)
	return (span.y - span.x) * from.distance_to(to) if span.y > span.x else 0.0


## Where a straight line that runs through the box goes in.
func entry_point(from: Vector3, to: Vector3) -> Vector3:
	return from.lerp(to, _clip(from, to).x)


## The share of a line from `from` to `to` where it goes in and comes out, by clipping it against each pair of faces.
func _clip(from: Vector3, to: Vector3) -> Vector2:
	var start := to_local(from)
	var along := to_local(to) - start
	var span := Vector2(0.0, 1.0)
	for axis: int in 3:
		var half := size[axis] * 0.5
		if is_zero_approx(along[axis]):
			if absf(start[axis]) > half:
				return Vector2.ZERO
		else:
			var one := (-half - start[axis]) / along[axis]
			var other := (half - start[axis]) / along[axis]
			span.x = maxf(span.x, minf(one, other))
			span.y = minf(span.y, maxf(one, other))
	return span


func _on_body_entered(body: Node3D) -> void:
	var moving := body as RigidBody3D
	if not moving:
		return
	var speed := moving.linear_velocity.length()
	if speed >= SLOWEST_SPLASH:
		var energy := 0.5 * moving.mass * speed * speed
		Sounds.pool.impact_on(self, moving.global_position, energy, speed, moving.mass, Sounds.surface_of(moving))
