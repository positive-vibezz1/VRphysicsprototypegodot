class_name Dummy
extends Node3D
## Bean shaped target on a weighted stand. Bullets push it through Jolt like anything else, and hurt it by the energy
## they lose on contact. Sprung joints hold the body and head up: at zero health the springs let go and gravity tips
## it over, and when it recovers the same springs stand it back up. Neither is scripted.

## About 2 degrees. Jolt sleeps anything that moves under 15 mm in half a second, which catches a slow swing at its
## far end and would freeze the dummy leaning, so it may only sleep once it is back up.
const UPRIGHT := 0.9994
## 60 degrees, about where the stand's own weight stops bringing it back. Its springs can't lift it from there.
const TIPPED := 0.5

## Wounding goes with energy left in the body, not momentum, which is close between 9 mm and 5.56 mm. At 18 J per
## point, a 9 mm (about 520 J) takes 4 body hits and a 5.56 mm (about 1580 J) takes 2.
@export var joules_per_health := 18.0
@export var max_health := 100.0
## A head hit is worth this many body hits, enough to end it in one from either gun at range distances.
@export var head_factor := 5.0
@export var recovery_time := 6.0

var health := 0.0

var _home: Array[Transform3D] = []

@onready var _stand: RigidBody3D = $Stand
@onready var _body: RigidBody3D = $Body
@onready var _head: RigidBody3D = $Head
@onready var _parts: Array[RigidBody3D] = [_stand, _body, _head]
@onready var _waist: Generic6DOFJoint3D = $Waist
@onready var _neck: Generic6DOFJoint3D = $Neck
@onready var _readout: Label3D = $Readout


func _ready() -> void:
	health = max_health
	for part: RigidBody3D in _parts:
		_home.append(part.global_transform)
	Ballistics.pool.bullet_hit.connect(_on_bullet_hit)
	_show_health("")


func _physics_process(_delta: float) -> void:
	_readout.global_position = _head.global_position + Vector3.UP * 0.35
	_body.can_sleep = health <= 0.0 or _body.global_basis.y.y > UPRIGHT
	if health > 0.0 and _stand.global_basis.y.y < TIPPED:
		_go_down("knocked over")


func _on_bullet_hit(collider: Object, energy: float) -> void:
	if health <= 0.0 or (collider != _body and collider != _head):
		return
	var damage := energy * (head_factor if collider == _head else 1.0) / joules_per_health
	var hit := "%s %.0f J  -%.0f" % ["head" if collider == _head else "body", energy, damage]
	health -= damage
	if health > 0.0:
		_show_health(hit)
	else:
		_go_down(hit)


func _go_down(cause: String) -> void:
	health = 0.0
	_show_health(cause)
	_set_springs(false)
	get_tree().create_timer(recovery_time, false, true).timeout.connect(_recover)


func _recover() -> void:
	health = max_health
	_show_health("")
	_set_springs(true)
	if _stand.global_basis.y.y < TIPPED:
		for i: int in _parts.size():
			_parts[i].global_transform = _home[i]
			_parts[i].linear_velocity = Vector3.ZERO
			_parts[i].angular_velocity = Vector3.ZERO


func _set_springs(holding: bool) -> void:
	for joint: Generic6DOFJoint3D in [_waist, _neck]:
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, holding)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, holding)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, holding)
	_body.sleeping = false


func _show_health(last_hit: String) -> void:
	_readout.text = "%.0f HP\n%s" % [health, last_hit]
