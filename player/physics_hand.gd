class_name PhysicsHand
extends RigidBody3D
## A hand body pulled toward the tracked controller pose by a PD controller, with the force and torque capped.
## Whatever it holds hangs on a joint, so its weight sags the hand and its recoil throws the hand around.
##
## Damping follows the carried mass, and stiffness is capped per axis to what the tick rate can integrate, so
## the hand stays stable from an empty palm to a loaded AR.

## Grip squeeze hysteresis.
const GRIP_ON := 0.6
const GRIP_OFF := 0.4
## Largest stiffness * dt^2 / inertia that stays well damped in Jolt's semi-implicit integration.
const MAX_STEP_STIFFNESS := 0.4

## Arm stiffness with an empty hand. The tick rate may cap it.
@export var linear_stiffness := 5000.0
## Carrying this much mass halves the stiffness. Nothing pushes back on the real hand, so a heavy gun has to
## read through how far it lags and sags behind the controller.
@export var arm_softening_mass := 0.6
@export var max_force := 350.0
## A wrist: a loaded AR held by the grip alone droops several degrees, a pistol hardly at all.
@export var angular_stiffness := 40.0
@export var max_torque := 15.0
## Under 1 so a heavy gun carries on a little when the hand stops, instead of stopping dead.
@export var damping_ratio := 0.7
## With both hands on one body the wrist gives way to the support hand, so the gun points along the hands.
@export var two_hand_wrist_scale := 0.25
## Past this distance from the controller the hand lets go and jumps back.
@export var max_separation := 0.7
## Force a fully squeezed trigger puts on the gun's trigger, about 10 lb.
@export var max_finger_force := 45.0
## Pointing at a gun or magazine this close shows a laser, and squeezing brings it to the hand.
@export var remote_grab_range := 1.5
## How far off the pointing direction still counts as pointing at it.
@export var remote_grab_cone := 8.0

var controller: XRController3D
var other_hand: PhysicsHand
var held: GrabPoint
## What pointing would pick up right now.
var remote_target: GrabPoint
## Poses and inputs for this tick, set by the player (or a test).
var target := Transform3D.IDENTITY
## World pointing direction. Zero means the way the fingers point.
var aim_direction := Vector3.ZERO
var input_grip := 0.0
var input_trigger := 0.0
var input_mag_release := false
var input_bolt_button := false

var _joint: Joint3D
## Inertia of hand and held parts about the palm, along the held body's axes. Set when grabbing.
var _carried_inertia := Vector3.ZERO
var _previous_target := Transform3D.IDENTITY
var _target_valid := false
var _grip_armed := true
var _was_mag_release := false
var _was_bolt_button := false

@onready var _laser: MeshInstance3D = $Laser


func _ready() -> void:
	body_entered.connect(_on_touched)


func set_target(pose: Transform3D) -> void:
	target = pose
	if not _target_valid:
		_target_valid = true
		_previous_target = pose
		global_transform = pose


func _physics_process(delta: float) -> void:
	if _target_valid:
		_track(delta)
	_update_remote_target()
	_update_grab()
	_update_held_controls()


func _track(delta: float) -> void:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	var to_target := target.origin - state.transform.origin
	if to_target.length() > max_separation:
		release()
		global_transform = target
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_previous_target = target
		return

	var carried := 0.0
	if held:
		carried = held.owner.held_mass() if held.mode == GrabPoint.Mode.SNAP else held.body.mass

	var target_velocity := (target.origin - _previous_target.origin) / delta
	var total_mass := mass + carried
	var stiffness := linear_stiffness / (1.0 + carried / arm_softening_mass)
	var pull := minf(stiffness, MAX_STEP_STIFFNESS * total_mass / (delta * delta))
	var damping := 2.0 * damping_ratio * sqrt(pull * total_mass)
	var force := pull * to_target + damping * (target_velocity - state.linear_velocity)
	apply_central_force(force.limit_length(max_force))

	var current_rotation := state.transform.basis.get_rotation_quaternion()
	var target_rotation := target.basis.get_rotation_quaternion()
	var angle_error := _rotation_vector(target_rotation * current_rotation.inverse())
	var target_spin := _rotation_vector(target_rotation * _previous_target.basis.get_rotation_quaternion().inverse()) / delta
	var spin_error := target_spin - state.angular_velocity
	# Work along the held body's axes: a long AR is much harder to pitch than to roll.
	var axes := held.body.global_basis if held else state.transform.basis
	var angle_along := axes.inverse() * angle_error
	var spin_along := axes.inverse() * spin_error
	var wrist := angular_stiffness * (two_hand_wrist_scale if _is_two_handed() else 1.0)
	var torque := Vector3(
		_axis_torque(angle_along.x, spin_along.x, wrist, inertia.x + _carried_inertia.x, delta),
		_axis_torque(angle_along.y, spin_along.y, wrist, inertia.y + _carried_inertia.y, delta),
		_axis_torque(angle_along.z, spin_along.z, wrist, inertia.z + _carried_inertia.z, delta)
	)
	apply_torque((axes * torque).limit_length(max_torque))

	_previous_target = target


## Grabbing happens on the squeeze, so a hand still squeezing after a magazine clicks home grabs nothing else.
func _update_grab() -> void:
	if input_grip < GRIP_OFF:
		_grip_armed = true
		release()
	elif input_grip > GRIP_ON and _grip_armed:
		_grip_armed = false
		if not held:
			_grab_nearest()


func _update_held_controls() -> void:
	var gun: Gun = held.owner as Gun if held else null
	var on_grip := gun != null and held == gun.grip
	if on_grip:
		gun.finger_force = input_trigger * max_finger_force
		if input_mag_release and not _was_mag_release:
			gun.release_magazine()
		if input_bolt_button and not _was_bolt_button:
			gun.press_bolt_button()
			_pulse(0.3, 0.02)
	_was_mag_release = input_mag_release
	_was_bolt_button = input_bolt_button


func _grab_nearest() -> void:
	var point := _nearest_point()
	if not point:
		point = remote_target
	if point:
		grab(point)


func _nearest_point() -> GrabPoint:
	var best: GrabPoint
	var best_distance := 0.0
	for point: GrabPoint in GrabPoint.all:
		if not point.enabled or point.holder:
			continue
		var distance := point.reach_distance(global_position)
		if distance < best_distance:
			best = point
			best_distance = distance
	return best


## Looks for the gun or magazine the hand points at, and draws the laser to it. Only whole objects: the parts
## of a gun that need a hand on them, like the slide, are only reachable in person.
func _update_remote_target() -> void:
	remote_target = null
	if not held and not _nearest_point():
		var pointing := aim_direction if aim_direction != Vector3.ZERO else -global_basis.y
		var best := cos(deg_to_rad(remote_grab_cone))
		for point: GrabPoint in GrabPoint.all:
			if point.mode != GrabPoint.Mode.SNAP or not point.enabled or point.holder:
				continue
			var offset := point.global_position - global_position
			var distance := offset.length()
			if distance > remote_grab_range or distance < 0.001:
				continue
			var alignment := offset.dot(pointing) / distance
			if alignment > best:
				best = alignment
				remote_target = point
	_laser.visible = remote_target != null
	if remote_target:
		var offset := remote_target.global_position - global_position
		var up := Vector3.UP if absf(offset.normalized().y) < 0.99 else Vector3.RIGHT
		var along := Basis.looking_at(offset, up)
		along.z *= offset.length()
		_laser.global_transform = Transform3D(along, global_position + offset * 0.5)


func grab(point: GrabPoint) -> void:
	held = point
	point.holder = self
	if point.mode == GrabPoint.Mode.SNAP:
		point.snap_to(global_transform)
		_joint = Generic6DOFJoint3D.new()
	else:
		_joint = PinJoint3D.new()
	add_child(_joint)
	_joint.global_position = global_position
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(point.body)
	_carried_inertia = point.carried_inertia(global_position)
	_notify_owner(point)
	if point.owner is Gun:
		var gun: Gun = point.owner
		gun.shot_fired.connect(_on_shot_fired)
		gun.bolt_stopped.connect(_on_bolt_stopped)
		gun.surface_hit.connect(_on_gun_touched)


func release() -> void:
	if not held:
		return
	var point := held
	held = null
	point.holder = null
	_joint.queue_free()
	_joint = null
	_carried_inertia = Vector3.ZERO
	_notify_owner(point)
	if point.owner is Gun:
		var gun: Gun = point.owner
		gun.shot_fired.disconnect(_on_shot_fired)
		gun.bolt_stopped.disconnect(_on_bolt_stopped)
		gun.surface_hit.disconnect(_on_gun_touched)


## Swaps a rigid hold for a pin, when something else (magazine rails) takes over the orientation.
func regrab_as_pin() -> void:
	_joint.queue_free()
	_carried_inertia = Vector3.ZERO
	_joint = PinJoint3D.new()
	add_child(_joint)
	_joint.global_position = global_position
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(held.body)


func _is_two_handed() -> bool:
	return held != null and other_hand != null and other_hand.held != null and other_hand.held.body == held.body


func _notify_owner(point: GrabPoint) -> void:
	if point.owner is Gun:
		(point.owner as Gun).grab_changed()


func _on_shot_fired(shot: GasSim.Shot, _strike_energy: float) -> void:
	var gun: Gun = held.owner
	_pulse(shot.breech_impulse / 7.0, gun.haptic_duration, gun.haptic_frequency)


func _on_bolt_stopped(impulse: float) -> void:
	var gun: Gun = held.owner
	_pulse(impulse / 2.5, 0.015, gun.haptic_frequency)


func _on_gun_touched(speed: float) -> void:
	_pulse(speed / 3.0, 0.03)


## The real hand meets nothing when the virtual one does, so a touch has to come through the controller.
func _on_touched(_body: Node) -> void:
	var speed := linear_velocity.length()
	if speed > 0.1:
		_pulse(clampf(speed * 0.5, 0.1, 0.6), 0.02)


func _pulse(amplitude: float, duration: float, frequency := 0.0) -> void:
	if controller:
		controller.trigger_haptic_pulse(&"haptic", frequency, clampf(amplitude, 0.0, 1.0), duration, 0.0)


func _axis_torque(angle: float, spin: float, stiffness: float, axis_inertia: float, delta: float) -> float:
	var k := minf(stiffness, MAX_STEP_STIFFNESS * axis_inertia / (delta * delta))
	return k * angle + 2.0 * damping_ratio * sqrt(k * axis_inertia) * spin


## Rotation vector (axis * angle) of the shortest path of a quaternion.
static func _rotation_vector(q: Quaternion) -> Vector3:
	var shortest := -q if q.w < 0.0 else q
	var sine := Vector3(shortest.x, shortest.y, shortest.z)
	var length := sine.length()
	if length < 1.0e-6:
		return sine * 2.0
	return sine * (2.0 * atan2(length, shortest.w) / length)
