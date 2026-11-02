extends GutTest
## Holsters: a gun let go of at the hip or the shoulder is put away and carried along until a hand draws it.

const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
const HEAD := Vector3(0, 201.6, 0)
const AWAY := Vector3(0.1, 201.0, -0.5)

var _world: Node3D
var _head: Node3D
var _hip: Holster
var _shoulder: Holster
var _left: PhysicsHand
var _right: PhysicsHand


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_head = Node3D.new()
	_head.position = HEAD
	_world.add_child(_head)
	_left = _hand(AWAY + Vector3(-0.3, 0, 0), true)
	_right = _hand(AWAY, false)
	_left.other_hand = _right
	_right.other_hand = _left
	_hip = _holster(Transform3D(Basis.IDENTITY, Vector3(0.22, -0.6, 0.03)))
	_shoulder = _holster(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(0.15, -0.12, 0.18)))


func _hand(at: Vector3, left: bool) -> PhysicsHand:
	var hand: PhysicsHand = HAND_SCENE.instantiate()
	hand.is_left = left
	_world.add_child(hand)
	hand.set_target(Transform3D(LEVEL_GRIP, at))
	return hand


func _holster(pose: Transform3D) -> Holster:
	var holster := Holster.new()
	holster.head = _head
	holster.pose = pose
	_world.add_child(holster)
	return holster


## Waits for the new hands to settle first, as test_hands does.
func _gun_in(hand: PhysicsHand, scene: PackedScene) -> Gun:
	await wait_physics_frames(2)
	var gun: Gun = scene.instantiate()
	_world.add_child(gun)
	hand.input_grip = 1.0
	hand.grab(gun.grip)
	return gun


## Swings the arm there over a third of a second, as a real one would, and lets it settle.
func _move(hand: PhysicsHand, to: Vector3) -> void:
	var from := hand.target.origin
	for i: int in 30:
		hand.set_target(Transform3D(LEVEL_GRIP, from.lerp(to, minf((i + 1) / 20.0, 1.0))))
		await wait_physics_frames(1)


func _all_frozen(gun: Gun, frozen: bool) -> bool:
	return gun.bodies().all(func(body: RigidBody3D) -> bool: return body.freeze == frozen)


func test_letting_go_of_the_pistol_at_the_hip_holsters_it() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await _move(_right, _hip.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	assert_eq(_hip.gun, pistol)
	assert_true(_all_frozen(pistol, true), "held still in it")
	assert_lt(pistol.grip.global_position.distance_to(_hip.spot().origin), 0.001, "grip where the hand let go")
	assert_lt(pistol.muzzle.global_position.y, pistol.grip.global_position.y - 0.05, "muzzle down")


func test_a_holstered_gun_goes_where_the_body_goes() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await _move(_right, _hip.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	_head.position += Vector3(3, 0.5, -2)
	await wait_physics_frames(2)
	assert_lt(pistol.grip.global_position.distance_to(_hip.spot().origin), 0.001)
	assert_true(pistol.frame.linear_velocity.is_zero_approx(), "without being thrown")


func test_gripping_it_again_draws_it_and_it_goes_with_the_hand() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await _move(_right, _hip.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	_right.input_grip = 1.0
	await wait_physics_frames(2)
	assert_eq(_right.held, pistol.grip, "in the hand")
	assert_null(_hip.gun, "out of the holster")
	assert_true(_all_frozen(pistol, false), "free to move again")
	assert_lt(pistol.frame.linear_velocity.length(), 1.0, "not flung out of it")
	await _move(_right, AWAY)
	assert_lt(pistol.grip.palm_transform(false).origin.distance_to(_right.global_position), 0.05, "follows the hand")


func test_a_holstered_gun_cant_be_pulled_from_afar() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await _move(_right, _hip.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	_left.aim_direction = (pistol.grip.global_position - _left.global_position).normalized()
	await wait_physics_frames(2)
	assert_null(_left.remote_target, "reached into in person")


func test_the_ar_goes_over_the_shoulder() -> void:
	var ar: Gun = await _gun_in(_right, AR_SCENE)
	await _move(_right, _shoulder.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	assert_eq(_shoulder.gun, ar)
	assert_null(_hip.gun)


func test_letting_go_away_from_the_holsters_drops_it() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await wait_physics_frames(10)
	_right.input_grip = 0.0
	await wait_physics_frames(10)
	assert_null(_hip.gun)
	assert_null(_shoulder.gun)
	assert_true(_all_frozen(pistol, false))
	assert_lt(pistol.frame.linear_velocity.y, -0.5, "falling")


func test_a_holster_holds_one_gun() -> void:
	var pistol: Gun = await _gun_in(_right, PISTOL_SCENE)
	await _move(_right, _hip.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	var ar: Gun = await _gun_in(_left, AR_SCENE)
	await _move(_left, _hip.spot().origin + Vector3(0, 0, 0.05))
	_left.input_grip = 0.0
	await wait_physics_frames(2)
	assert_eq(_hip.gun, pistol)
	assert_true(_all_frozen(ar, false), "the second one drops")


func test_not_while_the_other_hand_still_holds_it() -> void:
	var ar: Gun = await _gun_in(_right, AR_SCENE)
	await wait_physics_frames(2)
	var handguard: GrabPoint = ar.frame.get_node("Handguard2")
	_left.input_grip = 1.0
	_left.grab(handguard)
	await _move(_right, _shoulder.spot().origin)
	_right.input_grip = 0.0
	await wait_physics_frames(2)
	assert_null(_shoulder.gun, "the support hand keeps it")


func test_the_player_has_both_holsters() -> void:
	var range_scene: Node = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(range_scene)
	var camera: Node3D = range_scene.get_node("Player/XROrigin3D/XRCamera3D")
	assert_eq((range_scene.get_node("Player/HipHolster") as Holster).head, camera)
	assert_eq((range_scene.get_node("Player/ShoulderHolster") as Holster).head, camera)
	await wait_physics_frames(1)
