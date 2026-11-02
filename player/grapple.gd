class_name Grapple
extends RayCast3D
## A cable shot from an empty hand at the parkour surface it points at. It can only pull: the body swings on it under
## its own weight and momentum, a harder squeeze winds it in, and letting go keeps whatever speed the body has.

## Trigger squeeze: past AIM shows where it would hit, past FIRE shoots and starts winding in, and anywhere above
## HOLD keeps hold of it without winding, for swinging.
const AIM := 0.1
const HOLD := 0.3
const FIRE := 0.6

@export var max_range := 40.0
## Winding speed at a full squeeze.
@export var reel_speed := 8.0
## About twice body weight: lifts the body at about 1 g, and a hard swing doesn't stretch it far.
@export var max_tension := 1500.0
## How fast it takes up stretch, in rad/s. A critically damped spring: higher is stiffer.
@export var response := 12.0
## Stops winding in this far from the anchor, so it can't pull the hand into it.
@export var min_length := 0.8

var attached := false
var anchor := Vector3.ZERO
var length := 0.0

## Must be let off before firing, so dropping a gun or a hold with the trigger still in doesn't shoot.
var _armed := false
var _previous_distance := 0.0

@onready var _line: MeshInstance3D = $Line


func update(hand: PhysicsHand, body: RigidBody3D, delta: float) -> void:
	var free := not hand.held and not hand.climbing
	var squeeze := hand.input_trigger
	if not free or squeeze < AIM:
		_armed = free
	if attached and (not free or squeeze < HOLD):
		attached = false
	_line.visible = false
	if attached:
		_pull(hand, body, squeeze, delta)
	elif free and squeeze >= AIM:
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
		hand.controller.trigger_haptic_pulse(&"haptic", 0.0, 0.6, 0.04, 0.0)
	_line.visible = true
	stretch_line(_line, hand.global_position, anchor)


## Measured from the controller and not the body, so hauling on the cable with an arm yanks the body along it.
func _pull(hand: PhysicsHand, body: RigidBody3D, squeeze: float, delta: float) -> void:
	var to_anchor := anchor - hand.target.origin
	var distance := to_anchor.length()
	var winding := reel_speed * clampf(inverse_lerp(FIRE, 1.0, squeeze), 0.0, 1.0)
	# Any slack winds itself in, so it's already taut when it's next needed.
	length = maxf(minf(length, distance) - winding * delta, min_length)
	var stretching := (distance - _previous_distance) / delta + winding
	_previous_distance = distance
	var tension := body.mass * (response * response * (distance - length) + 2.0 * response * stretching)
	if tension > 0.0:
		body.apply_central_force(to_anchor.normalized() * minf(tension, max_tension))
	_line.visible = true
	stretch_line(_line, hand.global_position, anchor)


## Lays a 1 m long mesh along its Z axis between two points.
static func stretch_line(line: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var offset := to - from
	var up := Vector3.UP if absf(offset.normalized().y) < 0.99 else Vector3.RIGHT
	var along := Basis.looking_at(offset, up)
	along.z *= offset.length()
	line.global_transform = Transform3D(along, from + offset * 0.5)
