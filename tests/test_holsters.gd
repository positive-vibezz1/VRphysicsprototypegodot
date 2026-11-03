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


func test_a_lefty_uses_the_left_hip() -> void:
	var left_hip := _holster(Transform3D(Basis.IDENTITY, Vector3(-0.22, -0.6, 0.03)))
	var pistol: Gun = await _gun_in(_left, PISTOL_SCENE)
	await _move(_left, left_hip.spot().origin)
	_left.input_grip = 0.0
	await wait_physics_frames(2)
	assert_eq(left_hip.gun, pistol)
	assert_null(_hip.gun)
	assert_lt(pistol.muzzle.global_position.y, pistol.grip.global_position.y - 0.05, "muzzle down")
	_left.input_grip = 1.0
	await wait_physics_frames(2)
	assert_eq(_left.held, pistol.grip, "drawn with the left hand")
	assert_null(left_hip.gun)


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


func test_the_player_has_a_hip_and_a_shoulder_holster_on_each_side() -> void:
	var range_scene: Node = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(range_scene)
	var camera: Node3D = range_scene.get_node("Player/XROrigin3D/XRCamera3D")
	for spot: String in ["HipHolster", "ShoulderHolster"]:
		var left: Holster = range_scene.get_node("Player/Left" + spot)
		var right: Holster = range_scene.get_node("Player/Right" + spot)
		assert_eq(left.head, camera)
		assert_eq(right.head, camera)
		# Mirror images: across the body, and the gun turned the other way about the vertical.
		var mirror := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
		assert_almost_eq(left.pose.origin, mirror * right.pose.origin, Vector3.ONE * 1.0e-6, spot)
		assert_true(left.pose.basis.is_equal_approx(mirror * right.pose.basis * mirror), spot)
	await wait_physics_frames(1)


## Drives the player's real rig, as test_player does.
func _tracker(tracker_name: StringName, pose: Transform3D) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = tracker_name
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	return tracker


func test_a_rifle_swung_back_over_the_shoulder_gets_past_it_into_the_holster() -> void:
	var aim := Transform3D(LEVEL_GRIP, Vector3(0.2, 1.3, -0.35))
	var right := _tracker(&"right_hand", aim)
	var left := _tracker(&"left_hand", Transform3D(LEVEL_GRIP, Vector3(-0.2, 1.1, -0.2)))
	var range_scene: Node3D = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(range_scene)
	var player: Player = range_scene.get_node("Player")
	player.global_position = Vector3(0, 0, 3)
	var hand: PhysicsHand = player.get_node("RightHand")
	var ar: Gun = range_scene.get_node("AR")
	# A live runtime sends a pose every frame. Send one now that the rig is listening.
	right.set_pose(&"grip", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	left.set_pose(&"grip", left.get_pose(&"grip").transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await wait_physics_frames(30)
	ar.grip.snap_to(hand.global_transform)
	right.set_input(&"grip", 1.0)
	await wait_physics_frames(20)
	assert_eq(hand.held, ar.grip, "in the hand")
	var shoulder: AnimatableBody3D = player.get_node("RightShoulder")
	assert_eq(shoulder.collision_layer, 256, "aimed, the stock braces on the shoulder")
	# Back past the shoulder in half a second, barrel up, straight to the spot.
	var behind := Transform3D(Basis(Vector3.RIGHT, PI / 2) * LEVEL_GRIP, Vector3(0.15, 1.48, 0.18))
	for i: int in 60:
		right.set_pose(&"grip", aim.interpolate_with(behind, (i + 1) / 60.0), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await wait_physics_frames(1)
	assert_eq(shoulder.collision_layer, 0, "pointing up, it goes by")
	assert_eq(hand.held, ar.grip, "still in the hand")
	right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	assert_eq((player.get_node("RightShoulderHolster") as Holster).gun, ar, "put away")
	XRServer.remove_tracker(right)
	XRServer.remove_tracker(left)
