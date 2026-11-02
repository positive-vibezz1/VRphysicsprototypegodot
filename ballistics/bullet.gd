class_name Bullet
extends RigidBody3D
## Pooled projectile with real mass. Jolt carries it and hands its momentum to whatever it hits.

const AIR_DENSITY := 1.225
const LIFETIME := 4.0

var _drag_factor := 0.0
var _age := 0.0
var _arriving_velocity := Vector3.ZERO

@onready var _tracer: Node3D = $Tracer


## Speed after dt under quadratic drag: the exact solution of dv/dt = -k v^2, so it is stable at any tick.
static func drag_speed(speed: float, factor: float, dt: float) -> float:
	return speed / (1.0 + factor * speed * dt)


func launch(cartridge: CartridgeSpec, from: Vector3, velocity: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	mass = cartridge.bullet_mass
	_drag_factor = 0.5 * AIR_DENSITY * cartridge.drag_coefficient * cartridge.bore_area() / cartridge.bullet_mass
	_age = 0.0
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(velocity, up), from)
	linear_velocity = velocity
	_arriving_velocity = velocity
	angular_velocity = Vector3.ZERO
	_tracer.scale.z = velocity.length() * 0.006


func park() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() > 0:
		# The contact is already solved here, so what it took out of the bullet is what it gave the target.
		var energy := 0.5 * mass * (_arriving_velocity.length_squared() - state.linear_velocity.length_squared())
		Ballistics.pool.on_bullet_hit.call_deferred(
			self, state.get_contact_local_position(0), state.get_contact_local_normal(0),
			state.get_contact_collider_object(0), energy
		)
	_age += state.step
	if _age > LIFETIME:
		park.call_deferred()
		return
	var velocity := state.linear_velocity
	var speed := velocity.length()
	if speed > 0.0:
		state.linear_velocity = velocity * drag_speed(speed, _drag_factor, state.step) / speed
	_arriving_velocity = state.linear_velocity
