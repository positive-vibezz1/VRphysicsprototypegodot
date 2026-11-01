class_name Magazine
extends RigidBody3D
## A box of cartridges. Its mass follows the round count, so a full magazine really is heavier.
## The node origin is the top of the magazine, which lines up with the MagWell when seated.

@export var cartridge: CartridgeSpec
@export var capacity := 17
## Empty magazine including follower and spring.
@export var empty_mass := 0.07

@onready var count := capacity
@onready var grab_point: GrabPoint = $GrabPoint
@onready var top_round: Node3D = $TopRound


func _ready() -> void:
	_refresh()


func take_round() -> bool:
	if count <= 0:
		return false
	count -= 1
	_refresh()
	return true


func teleport(delta_transform: Transform3D) -> void:
	global_transform = delta_transform * global_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false


func held_mass() -> float:
	return mass


func bodies() -> Array[RigidBody3D]:
	return [self]


func _refresh() -> void:
	mass = empty_mass + count * cartridge.round_mass
	top_round.visible = count > 0
