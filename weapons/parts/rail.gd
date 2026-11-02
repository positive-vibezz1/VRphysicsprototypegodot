class_name Rail
extends RefCounted
## A spring loaded part sliding on the frame along the frame's +Z (rearward), such as a slide or bolt carrier.
##
## The spring is a real force between the two bodies, and the joint's limits are the stops. A bolt at 8 m/s
## crosses its whole travel in one 11 ms tick and Jolt only enforces a limit once a part is past it, so a fast
## approach is slowed here to land on the stop, as equal and opposite impulses on the bolt and the frame. The
## momentum goes into the frame at the rail either way, and that is what makes the frame kick.

## Slower than this into a stop is a part resting on it, not an impact.
const IMPACT_SPEED := 0.3
const SETTLE_GAP := 0.001
## Jolt measures travel a hair differently, so stops are predicted this far past them too.
const STOP_BAND := 0.0005

var frame: RigidBody3D
var body: RigidBody3D
var joint: SliderJoint3D
## Mass the rail reacts against: the frame plus whatever is rigidly attached to it right now.
var frame_mass := 0.0
var preload_force := 0.0
var rate := 0.0
var front_stop := 0.0
var rear_stop := 0.0
## Impulse of the stop this part ran into during the last tick, for haptics and sound.
var last_stop_impulse := 0.0
## Rearward travel from the rest position, and its speed relative to the frame.
var travel := 0.0
var velocity := 0.0

var _rest_z := 0.0
var _previous_travel := 0.0


func _init(
	p_frame: RigidBody3D, p_body: RigidBody3D, p_joint: SliderJoint3D, p_rear_stop: float,
	p_preload: float, p_rate: float
) -> void:
	frame = p_frame
	body = p_body
	joint = p_joint
	frame_mass = frame.mass
	rear_stop = p_rear_stop
	preload_force = p_preload
	rate = p_rate
	_rest_z = (frame.global_transform.affine_inverse() * body.global_position).z
	joint.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_UPPER, rear_stop)
	joint.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, front_stop)


## Moves the front stop, for a bolt catch.
func set_front_stop(stop: float) -> void:
	if stop != front_stop:
		front_stop = stop
		joint.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, stop)


## Reads travel and speed. Velocities come from the direct state so that impulses from this tick count.
func update() -> void:
	var offset := body.global_position - frame.global_position
	travel = (frame.global_transform.affine_inverse() * body.global_position).z - _rest_z
	var frame_v := PhysicsServer3D.body_get_direct_state(frame.get_rid()).get_velocity_at_local_position(offset)
	var body_v := PhysicsServer3D.body_get_direct_state(body.get_rid()).linear_velocity
	velocity = (body_v - frame_v).dot(frame.global_basis.z)


## Applies the spring and any stop that the next tick would run into.
func apply(delta: float) -> void:
	update()
	var axis := frame.global_basis.z
	var offset := body.global_position - frame.global_position
	var force := preload_force + rate * travel
	var inverse_mass := 1.0 / body.mass + 1.0 / frame_mass
	# The part's own weight along the rail counts too, or a gun pointing up would hold its bolt out of battery.
	var weight := body.get_gravity().dot(axis) * body.gravity_scale
	var coasting := velocity + (weight - force * inverse_mass) * delta
	var next := travel + coasting * delta

	var wanted := coasting
	# Past a stop the joint limit is active and handles it alone. Short of one the limit is off, so even a part
	# a hair off its stop needs this, or the spring throws it through the stop for a whole tick.
	if next > rear_stop and travel < rear_stop + STOP_BAND:
		wanted = _landing_speed(maxf(rear_stop - travel, 0.0), delta)
	elif next < front_stop and travel > front_stop - STOP_BAND:
		wanted = _landing_speed(minf(front_stop - travel, 0.0), delta)

	last_stop_impulse = 0.0
	if absf(velocity) > IMPACT_SPEED:
		if wanted != coasting:
			last_stop_impulse = absf(velocity - wanted) / inverse_mass
		elif (travel >= rear_stop and _previous_travel < rear_stop) or (travel <= front_stop and _previous_travel > front_stop):
			# Came in faster than predicted and the joint limit caught it.
			last_stop_impulse = absf(velocity) / inverse_mass
	_previous_travel = travel
	if wanted != coasting:
		var impulse := axis * (wanted - coasting) / inverse_mass
		body.apply_central_impulse(impulse)
		frame.apply_impulse(-impulse, offset)

	body.apply_central_force(-axis * force)
	frame.apply_force(axis * force, offset)


## Speed that covers a gap to a stop in one tick. The last millimeter closes at half that: the frame's real
## inertia isn't known exactly here, and a full correction every tick would buzz.
func _landing_speed(gap: float, delta: float) -> float:
	if absf(gap) < SETTLE_GAP and absf(velocity) < IMPACT_SPEED:
		return 0.5 * gap / delta
	return gap / delta


## Removes energy from the moving part, such as cocking the hammer or stripping a round. The reaction goes
## into the frame. At low speed this reduces to a force over the tick.
func take_energy(work: float) -> void:
	var speed := absf(velocity)
	if speed < 0.01 or work <= 0.0:
		return
	var inverse_mass := 1.0 / body.mass + 1.0 / frame_mass
	var impulse := minf(work / speed, speed / inverse_mass) * -signf(velocity)
	var kick := frame.global_basis.z * impulse
	body.apply_central_impulse(kick)
	frame.apply_impulse(-kick, body.global_position - frame.global_position)
