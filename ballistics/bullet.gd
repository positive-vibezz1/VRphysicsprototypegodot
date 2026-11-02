class_name Bullet
extends RigidBody3D
## Pooled projectile with real mass. Jolt carries it and hands its momentum to whatever it hits.

const AIR_DENSITY := 1.225
const LIFETIME := 4.0
const MIN_TRACER_LENGTH := 0.05
const MIN_TRACER_WIDTH := 0.003

## How wide the near end of the tracer looks from the player, in radians. About 4 pixels on a headset: the bullet itself
## is under a pixel past a couple of meters, and a line that thin breaks up into specks with no antialiasing.
@export var tracer_angle := 0.003

var _drag_factor := 0.0
var _age := 0.0
var _arriving_velocity := Vector3.ZERO
var _launched_from := Vector3.ZERO
var _launch_direction := Vector3.ZERO
var _in_liquid := false

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
	_in_liquid = false
	_launched_from = from
	_launch_direction = velocity.normalized()
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(velocity, up), from)
	linear_velocity = velocity
	_arriving_velocity = velocity
	angular_velocity = Vector3.ZERO
	_show_tracer(velocity.length())


func park() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false


func _physics_process(_delta: float) -> void:
	_show_tracer(linear_velocity.length())


## A streak over the path it just covered, which is what the eye sees of something this fast. It runs back from the
## bullet and no further than the muzzle, so it shows where the bullet really is at every frame.
func _show_tracer(speed: float) -> void:
	var path := speed * Engine.time_scale / Engine.physics_ticks_per_second
	var length := clampf(path, MIN_TRACER_LENGTH, maxf(global_position.distance_to(_launched_from), MIN_TRACER_LENGTH))
	var camera := get_viewport().get_camera_3d()
	var width := MIN_TRACER_WIDTH
	if camera:
		var tail := global_position + global_basis.z * length
		width = maxf(width, tail.distance_to(camera.global_position) * tracer_angle)
	_tracer.scale = Vector3(width, width, length)


## At 10 m a tick a bullet could cross a whole box of water between ticks, so this goes by its path and not a point.
func _splash(from: Vector3, to: Vector3, speed: float) -> void:
	var was_in_liquid := _in_liquid
	_in_liquid = false
	for volume: MediumVolume in MediumVolume.all:
		if volume.medium.is_liquid and volume.path_length(from, to) > 0.0:
			_in_liquid = true
			if not was_in_liquid:
				Sounds.pool.impact_on.call_deferred(
					volume, volume.entry_point(from, to), 0.5 * mass * speed * speed, speed, mass, Sounds.Surface.METAL
				)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() > 0:
		# The contact is already solved here, so what it took out of the bullet is what it gave the target.
		var energy := 0.5 * mass * (_arriving_velocity.length_squared() - state.linear_velocity.length_squared())
		if DebugLog.enabled:
			var collider := state.get_contact_collider_object(0) as Node
			var flown := global_position - _launched_from
			DebugLog.event("hit", "bullet hit %s %.1f m out after %.0f ms, %.1f cm off the line it left on, %.0f to %.0f m/s, %.0f J, %.2f N s" % [
				collider.name if collider else &"?", flown.length(), _age * 1000.0,
				(flown - _launch_direction * flown.dot(_launch_direction)).length() * 100.0, _arriving_velocity.length(),
				state.linear_velocity.length(), energy, mass * (_arriving_velocity - state.linear_velocity).length()
			])
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
	_splash(state.transform.origin, state.transform.origin + velocity * state.step, speed)
	if speed > 0.0:
		state.linear_velocity = velocity * drag_speed(speed, _drag_factor, state.step) / speed
	_arriving_velocity = state.linear_velocity
