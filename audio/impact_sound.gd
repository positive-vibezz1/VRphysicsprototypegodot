class_name ImpactSound
extends Node
## Child of a rigid body: makes it ring when it hits something, and says what it's made of. Jolt estimates what each
## contact will do before solving it, which is meant for just this. Half impulse times closing speed is then the energy
## the hit takes out. Whatever it hit rings too, on its own node, or from here if that's a static body with no node.

## Slower than this is weight, not a hit. Gravity alone closes a resting contact at g * dt, 0.14 m/s at 72 Hz.
const SLOWEST_HIT := 0.25
## Bounces closer together than this are one rattle, in real seconds.
const SHORTEST_GAP := 0.06

@export var surface := Sounds.Surface.METAL
## The mass of everything held rigidly to this body, which rings as one. 0 is just the body.
@export var ringing_mass := 0.0

var _velocity := Vector3.ZERO
var _touching := false
var _next_frame := 0

@onready var _body: RigidBody3D = get_parent()


func _ready() -> void:
	_body.set_meta(&"surface", surface)
	_body.contact_monitor = true
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 4)


func _physics_process(_delta: float) -> void:
	if _body.sleeping:
		return
	var state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	var change := state.linear_velocity.distance_to(_velocity)
	_velocity = state.linear_velocity
	var was_touching := _touching
	var contacts := state.get_contact_count()
	_touching = contacts > 0
	if contacts == 0 or Engine.get_physics_frames() < _next_frame:
		return
	var impulse := 0.0
	var closing := 0.0
	var strongest := 0
	for i: int in contacts:
		impulse += state.get_contact_impulse(i).length()
		var speed := (state.get_contact_collider_velocity_at_position(i) - state.get_contact_local_velocity_at_position(i)).dot(state.get_contact_local_normal(i))
		if speed > closing:
			closing = speed
			strongest = i
	# Jolt's closing speed already has this tick's forces in it, up to 5 m/s for a hand pressed into a table with all its
	# arm's force. So on a contact that's still there, a hit is only as hard as the body really changed speed.
	var strike := minf(closing, change) if was_touching else closing
	if strike < SLOWEST_HIT:
		return
	var collider := state.get_contact_collider_object(strongest)
	# A bullet reports its own hits, and a stock on a shoulder is no knock.
	if collider is Bullet or collider is AnimatableBody3D:
		return
	var energy := 0.5 * impulse * strike * strike / closing
	var point := state.get_contact_local_position(strongest)
	var other := collider as RigidBody3D
	Sounds.pool.impact(
		point, surface, energy * other.mass / (other.mass + _body.mass) if other else energy, strike,
		ringing_mass if ringing_mass > 0.0 else _body.mass, Sounds.surface_of(collider), other.mass if other else 0.0
	)
	if not other:
		Sounds.pool.impact_on(collider, point, energy, strike, _body.mass, surface)
	_next_frame = Engine.get_physics_frames() + int(SHORTEST_GAP * Engine.physics_ticks_per_second)
