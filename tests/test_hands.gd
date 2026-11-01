extends GutTest
## Physics hands driven by a fake controller pose: tracking, weight, recoil and the two-handed AR.

const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _shots := 0


func before_each() -> void:
	_shots = 0
	Ballistics.pool.clear()


func _hand(at: Vector3) -> PhysicsHand:
	var hand: PhysicsHand = HAND_SCENE.instantiate()
	add_child_autofree(hand)
	hand.set_target(Transform3D(LEVEL_GRIP, at))
	return hand


func _hold(hand: PhysicsHand, point: GrabPoint) -> void:
	hand.input_grip = 1.0
	hand.grab(point)


func _gun(scene: PackedScene, at: Vector3) -> Gun:
	var gun: Gun = scene.instantiate()
	gun.position = at
	add_child_autofree(gun)
	gun.shot_fired.connect(func(_s: GasSim.Shot, _e: float) -> void: _shots += 1)
	return gun


func test_hand_follows_a_moving_target_closely() -> void:
	var hand := _hand(Vector3(0, 100, 0))
	await wait_physics_frames(5)
	var pose := Transform3D(LEVEL_GRIP, Vector3(0, 100, 0))
	var worst := 0.0
	for i: int in 45:
		pose.origin.x += 1.0 / 90.0
		hand.set_target(pose)
		await wait_physics_frames(1)
		if i > 15:
			worst = maxf(worst, (hand.global_position - pose.origin).length())
	assert_lt(worst, 0.03, "lags a 1 m/s move by under 3 cm")


func test_hand_is_not_parented_to_its_target_and_turns_by_torque() -> void:
	var hand := _hand(Vector3(10, 100, 0))
	await wait_physics_frames(3)
	var turned := Basis(Vector3.UP, 1.0) * LEVEL_GRIP
	hand.set_target(Transform3D(turned, Vector3(10, 100, 0)))
	await wait_physics_frames(1)
	var angle_one_tick := (hand.global_basis.get_rotation_quaternion().inverse() * turned.get_rotation_quaternion()).get_angle()
	assert_gt(angle_one_tick, 0.05, "does not teleport to the new rotation")
	await wait_physics_frames(45)
	var error := (hand.global_basis.get_rotation_quaternion().inverse() * turned.get_rotation_quaternion()).get_angle()
	assert_lt(error, 0.03, "settles on the new rotation")


func test_grabbing_snaps_the_grip_into_the_palm() -> void:
	var at := Vector3(20, 100, 0)
	var gun := _gun(PISTOL_SCENE, at + Vector3(0.03, -0.02, 0.02))
	var hand := _hand(at)
	await wait_physics_frames(2)
	hand.input_grip = 1.0
	await wait_physics_frames(2)
	assert_eq(hand.held, gun.grip)
	assert_almost_eq((gun.grip.global_position - hand.global_position).length(), 0.0, 0.02)


func test_held_weight_sags_the_hand() -> void:
	var at := Vector3(30, 100, 0)
	var light := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, light.grip)
	await wait_physics_frames(60)
	var pistol_sag := at.y - hand.global_position.y
	assert_between(pistol_sag, 0.001, 0.02, "pistol sags a little")
	hand.input_grip = 0.0
	await wait_physics_frames(1)
	light.queue_free()

	var heavy_at := Vector3(40, 100, 0)
	var heavy := _gun(AR_SCENE, heavy_at)
	var strong := _hand(heavy_at)
	await wait_physics_frames(2)
	_hold(strong, heavy.grip)
	await wait_physics_frames(60)
	var ar_sag := heavy_at.y - strong.global_position.y
	assert_gt(ar_sag, pistol_sag * 1.5, "the AR sags more")
	assert_lt(ar_sag, 0.05, "but stays in hand")
	assert_eq(strong.held, heavy.grip)


func test_pistol_recoil_moves_the_hand_and_it_comes_back() -> void:
	var at := Vector3(50, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(45)
	var rest_position := hand.global_position
	var rest_forward := -gun.frame.global_basis.z
	hand.input_trigger = 1.0
	await wait_physics_frames(2)
	hand.input_trigger = 0.0
	assert_eq(_shots, 1)
	var furthest := 0.0
	var most_flip := 0.0
	for i: int in 30:
		await wait_physics_frames(1)
		furthest = maxf(furthest, (hand.global_position - rest_position).length())
		most_flip = maxf(most_flip, rest_forward.angle_to(-gun.frame.global_basis.z))
	assert_between(furthest, 0.005, 0.12, "hand gets pushed centimeters")
	assert_between(rad_to_deg(most_flip), 2.0, 40.0, "muzzle flips")
	assert_gt((-gun.frame.global_basis.z).y, rest_forward.y - 0.02, "and flips up, not down")
	await wait_physics_frames(60)
	assert_lt((hand.global_position - rest_position).length(), 0.01, "recovers")
	assert_lt(rad_to_deg(rest_forward.angle_to(-gun.frame.global_basis.z)), 2.0, "aim recovers")
	assert_eq(hand.held, gun.grip, "still holding on")


func test_support_hand_can_rack_the_slide() -> void:
	var at := Vector3(60, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	gun.chamber = Gun.Chamber.EMPTY
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(30)
	var slide_point: GrabPoint = gun.bolt.get_node("SlideGrab")
	assert_true(slide_point.enabled, "slide grabbable once the gun is in hand")
	var pull_start := slide_point.global_position
	var other := _hand(pull_start)
	other.other_hand = hand
	hand.other_hand = other
	await wait_physics_frames(3)
	other.input_grip = 1.0
	await wait_physics_frames(2)
	assert_eq(other.held, slide_point)
	var rear := gun.frame.global_basis.z
	for i: int in 40:
		other.set_target(Transform3D(LEVEL_GRIP, pull_start + rear * 0.14 * (float(i) / 40.0)))
		await wait_physics_frames(1)
	assert_gt(gun._rail.travel, gun.feed_travel, "pulled back by hand")
	other.input_grip = 0.0
	await wait_physics_frames(30)
	assert_eq(gun.chamber, Gun.Chamber.LIVE, "released and chambered")
	assert_almost_eq(gun._rail.travel, 0.0, 0.003)


func test_ar_two_handed_points_along_the_hands_and_fires() -> void:
	var at := Vector3(70, 100, 0)
	var gun := _gun(AR_SCENE, at)
	var primary := _hand(at)
	await wait_physics_frames(2)
	_hold(primary, gun.grip)
	await wait_physics_frames(45)
	var support_at: Vector3 = (gun.frame.get_node("HandguardGrab") as Node3D).global_position
	var support := _hand(support_at)
	primary.other_hand = support
	support.other_hand = primary
	await wait_physics_frames(2)
	support.input_grip = 1.0
	await wait_physics_frames(30)
	assert_not_null(support.held)
	# Raise the support hand 15 cm: the muzzle should follow it.
	var before := (-gun.frame.global_basis.z).y
	support.set_target(Transform3D(LEVEL_GRIP, support_at + Vector3(0, 0.15, 0)))
	await wait_physics_frames(45)
	assert_gt((-gun.frame.global_basis.z).y, before + 0.15, "muzzle rises with the support hand")
	primary.input_trigger = 1.0
	await wait_physics_frames(3)
	primary.input_trigger = 0.0
	assert_eq(_shots, 1, "fires")
	await wait_physics_frames(45)
	assert_eq(primary.held, gun.grip)
	assert_eq(support.held != null, true)


func test_stock_on_the_shoulder_takes_the_recoil() -> void:
	var free_travel := await _ar_kick(Vector3(90, 100, 0), false)
	var braced_travel := await _ar_kick(Vector3(100, 100, 0), true)
	assert_gt(free_travel, 0.01, "unbraced AR comes back into the hand")
	assert_lt(braced_travel, free_travel * 0.7, "shoulder stops it sooner")


## Fires one shot from a level AR and returns the furthest the stock moved back along the bore.
func _ar_kick(at: Vector3, braced: bool) -> float:
	# Raked like a wrist on a real pistol grip, so the gun itself is level.
	var pose := Transform3D(LEVEL_GRIP * Basis(Vector3.RIGHT, deg_to_rad(18.0)), at)
	var gun := _gun(AR_SCENE, at)
	var primary := _hand(at)
	primary.set_target(pose)
	await wait_physics_frames(2)
	_hold(primary, gun.grip)
	await wait_physics_frames(40)
	var rear := gun.frame.global_basis.z
	var stock: Vector3 = gun.frame.global_position + gun.frame.global_basis * Vector3(0, 0.03, 0.305)
	if braced:
		var shoulder := AnimatableBody3D.new()
		shoulder.collision_layer = 256
		shoulder.collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.06
		shape.shape = sphere
		shoulder.add_child(shape)
		add_child_autofree(shoulder)
		shoulder.global_position = stock + rear * 0.0605
		await wait_physics_frames(2)
	var start := gun.frame.global_position
	var furthest := 0.0
	primary.input_trigger = 1.0
	for i: int in 25:
		await wait_physics_frames(1)
		furthest = maxf(furthest, (gun.frame.global_position - start).dot(rear))
	primary.input_trigger = 0.0
	primary.input_grip = 0.0
	await wait_physics_frames(1)
	return furthest


func test_hand_drops_what_it_holds_when_pulled_too_far_away() -> void:
	var at := Vector3(80, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(2)
	hand.set_target(Transform3D(LEVEL_GRIP, at + Vector3(5, 0, 0)))
	await wait_physics_frames(3)
	assert_null(hand.held)
	assert_almost_eq(hand.global_position.x, at.x + 5.0, 0.2, "hand jumped to the controller")
