class_name MagWell
extends Area3D
## Takes a magazine on a slider joint, latches it when seated and lets it fall out when released.
## The node's transform is the seated magazine pose, with +Y pointing up into the gun.

@export var cartridge: CartridgeSpec
## How far below the seated pose the magazine starts or stops being on the rails.
@export var engage_length := 0.09
## A magazine pushed this close snaps home, like the last bit of a real one clicking in.
@export var seat_tolerance := 0.015
## Maximum lateral miss and alignment (dot of the axes) that still go in.
@export var capture_radius := 0.04
@export var capture_alignment := 0.8
## Latch release speed from the magazine's spring pressure.
@export var eject_speed := 0.3

var magazine: Magazine
var latched := false

var _candidate: Magazine
## The latch only catches a magazine that has been out, not one just released from it.
var _latch_armed := false
var _joint: SliderJoint3D
var _frame: RigidBody3D
## Depth at the moment the joint was made: the joint measures from there.
var _joint_depth := 0.0


func _ready() -> void:
	_frame = get_parent()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Seats a magazine directly, for loaded guns at scene start.
func seat(mag: Magazine) -> void:
	mag.global_transform = global_transform
	_make_joint(mag)
	_latch()


func tick() -> void:
	if magazine == null:
		if _candidate and _can_capture(_candidate):
			_begin_insert(_candidate)
		return
	if latched:
		return
	var depth := _depth_of(magazine)
	if depth > 2.0 * seat_tolerance:
		_latch_armed = true
	if depth <= seat_tolerance and _latch_armed:
		_latch()
	elif depth >= engage_length:
		_remove()


func release() -> void:
	if magazine == null or not latched:
		return
	latched = false
	_latch_armed = false
	_set_limits(0.0, engage_length + 0.002)
	magazine.grab_point.enabled = true
	var out := -global_basis.y
	magazine.apply_central_impulse(out * eject_speed * magazine.mass)
	_frame.apply_central_impulse(-out * eject_speed * magazine.mass)


func _can_capture(mag: Magazine) -> bool:
	if mag.cartridge != cartridge:
		return false
	var depth := _depth_of(mag)
	# The margin stops a magazine that just dropped out from being caught again.
	if depth < 0.0 or depth > engage_length - 0.015:
		return false
	var lateral := (mag.global_position - global_position) + global_basis.y * depth
	return lateral.length() < capture_radius and mag.global_basis.y.dot(global_basis.y) > capture_alignment


func _begin_insert(mag: Magazine) -> void:
	var holder := mag.grab_point.holder
	var depth := clampf(_depth_of(mag), 0.0, engage_length)
	mag.global_transform = global_transform.translated(-global_basis.y * depth)
	mag.linear_velocity = _frame.linear_velocity
	mag.angular_velocity = _frame.angular_velocity
	_make_joint(mag)
	_joint_depth = depth
	_set_limits(0.0, engage_length + 0.002)
	if holder:
		# The rails now set the orientation, so the hand only pushes along them.
		holder.regrab_as_pin()


func _make_joint(mag: Magazine) -> void:
	magazine = mag
	_candidate = null
	_joint_depth = 0.0
	_joint = SliderJoint3D.new()
	add_child(_joint)
	# Joint X points out of the well.
	_joint.global_transform = Transform3D(Basis(-global_basis.y, global_basis.x, global_basis.z), mag.global_position)
	_joint.node_a = _joint.get_path_to(_frame)
	_joint.node_b = _joint.get_path_to(mag)


func _latch() -> void:
	latched = true
	_set_limits(0.0, 0.0)
	magazine.grab_point.enabled = false
	if magazine.grab_point.holder:
		magazine.grab_point.holder.release()


func _remove() -> void:
	_joint.queue_free()
	_joint = null
	magazine = null
	latched = false


## Limits in depth below the seated pose.
func _set_limits(lowest: float, deepest: float) -> void:
	_joint.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, lowest - _joint_depth)
	_joint.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_UPPER, deepest - _joint_depth)


func _depth_of(mag: Magazine) -> float:
	return (global_position - mag.global_position).dot(global_basis.y)


func _on_body_entered(body: Node3D) -> void:
	if body is Magazine and magazine == null:
		_candidate = body


func _on_body_exited(body: Node3D) -> void:
	if body == _candidate:
		_candidate = null
