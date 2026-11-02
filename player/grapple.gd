class_name Grapple
extends RayCast3D
## A cable shot from an empty hand at the parkour surface it points at. A dot and a thin line show what it would catch,
## and squeezing connects: the line turns thick and orange and the controller thumps. The cable can only pull. The body
## swings on it under its own weight and momentum, pulling the arm back hauls on it, and letting go keeps whatever
## speed the body has.

## Trigger squeeze: past FIRE shoots, and it holds on until the squeeze drops below HOLD.
const HOLD := 0.3
const FIRE := 0.6
## An arm pulling slower than this, or a body turning with the hand held out, isn't hauling.
const SLOWEST_HAUL := 1.0
## Radius of the dot as a share of its distance, so it's the same size to the eye up close and across the course.
const DOT_SIZE := 0.006
const CONNECTED_DOT_SCALE := 2.5

@export var max_range := 40.0
## Cable taken in per meter of arm pulled, on top of the arm itself. At 1 a hard 70 cm haul throws the body at about
## 4 m/s, as much as the tension allows in that time, and a longer one faster.
@export var haul_gain := 1.0
## About three times body weight: a hard haul launches the body, and a hard swing doesn't stretch it far.
@export var max_tension := 2500.0
## How fast it takes up stretch, in rad/s. A critically damped spring: higher is stiffer.
@export var response := 12.0
## Stops taking in cable this far from the anchor, so it can't pull the hand into it.
@export var min_length := 0.8

var attached := false
var anchor := Vector3.ZERO
var length := 0.0

## Must be let off before firing, so dropping a gun or a hold with the trigger still in doesn't shoot.
var _armed := false
var _previous_distance := 0.0
var _peak_tension := 0.0

@onready var _aim_line: MeshInstance3D = $AimLine
@onready var _line: MeshInstance3D = $Line
@onready var _dot: MeshInstance3D = $Dot


func update(hand: PhysicsHand, body: RigidBody3D, delta: float) -> void:
	var free := not hand.held and not hand.climbing
	var squeeze := hand.input_trigger
	if not free or squeeze < HOLD:
		_armed = free
		if attached:
			DebugLog.event("grapple", "let go at %.1f m of cable, body at %.1f m/s, peak tension %.0f N" % [length, body.linear_velocity.length(), _peak_tension])
		attached = false
	_aim_line.visible = false
	_line.visible = false
	_dot.visible = false
	if attached:
		_pull(hand, body, delta)
	elif free and not hand.remote_target:
		_aim(hand, squeeze)


func _aim(hand: PhysicsHand, squeeze: float) -> void:
	var from := hand.target.origin
	var pointing := hand.aim_direction if hand.aim_direction != Vector3.ZERO else -hand.global_basis.y
	global_position = from
	target_position = pointing * max_range
	force_raycast_update()
	if not is_colliding():
		return
	anchor = get_collision_point()
	if squeeze > FIRE and _armed:
		attached = true
		_armed = false
		length = from.distance_to(anchor)
		_previous_distance = length
		_peak_tension = 0.0
		DebugLog.event("grapple", "caught %s %.1f m out" % [(get_collider() as Node).name, length])
		hand.controller.trigger_haptic_pulse(&"haptic", 0.0, 0.8, 0.06, 0.0)
	_show(hand, _line if attached else _aim_line)


## Measured from the controller and not the body, so pulling the arm back hauls on the cable.
func _pull(hand: PhysicsHand, body: RigidBody3D, delta: float) -> void:
	var to_anchor := anchor - hand.target.origin
	var distance := to_anchor.length()
	var along := to_anchor.normalized()
	var hauling := haul_gain * maxf((body.linear_velocity - hand.controller_velocity).dot(along) - SLOWEST_HAUL, 0.0)
	# Any slack is taken in, so it's already taut when it's next needed: reach out, then pull again.
	length = maxf(minf(length, distance) - hauling * delta, min_length)
	var stretching := (distance - _previous_distance) / delta + hauling
	_previous_distance = distance
	var tension := body.mass * (response * response * (distance - length) + 2.0 * response * stretching)
	if tension > 0.0:
		body.apply_central_force(along * minf(tension, max_tension))
		_peak_tension = maxf(_peak_tension, minf(tension, max_tension))
	_show(hand, _line)


func _show(hand: PhysicsHand, line: MeshInstance3D) -> void:
	line.visible = true
	stretch_line(line, hand.global_position, anchor)
	_dot.visible = true
	_dot.global_position = anchor
	var size := hand.global_position.distance_to(anchor) * DOT_SIZE
	_dot.scale = Vector3.ONE * (size * CONNECTED_DOT_SCALE if attached else size)


## Lays a 1 m long mesh along its Z axis between two points.
static func stretch_line(line: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var offset := to - from
	var up := Vector3.UP if absf(offset.normalized().y) < 0.99 else Vector3.RIGHT
	var along := Basis.looking_at(offset, up)
	along.z *= offset.length()
	line.global_transform = Transform3D(along, from + offset * 0.5)
