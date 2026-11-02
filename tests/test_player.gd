extends GutTest
## The XR rig driven through real XRServer trackers, so everything but OpenXR itself runs as it does in the headset.

const DT := 1.0 / 90.0
## Controller held out in front at waist height, in origin space.
const LEFT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(-0.2, 1.1, -0.2))
const RIGHT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.2, 1.1, -0.2))

var _left: XRControllerTracker
var _right: XRControllerTracker
var _range: Node3D
var _player: Player
var _camera: XRCamera3D


## A dud stops a gun until it is racked, which would fail these tests at random. test_fire_control covers duds.
func before_all() -> void:
	(load("res://weapons/parts/cartridge_9x19.tres") as CartridgeSpec).dud_chance = 0.0
	(load("res://weapons/parts/cartridge_556x45.tres") as CartridgeSpec).dud_chance = 0.0


func before_each() -> void:
	_left = _tracker(&"left_hand", LEFT_REST)
	_right = _tracker(&"right_hand", RIGHT_REST)
	_range = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(_range)
	_player = _range.get_node("Player")
	_camera = _player.get_node("XROrigin3D/XRCamera3D")
	# Back from the table so nothing is in the way.
	_player.global_position = Vector3(0, 0, 3)
	# A live runtime sends a pose every frame. Send one now that the rig is listening.
	_set_pose(_left, LEFT_REST)
	_set_pose(_right, RIGHT_REST)


func after_each() -> void:
	XRServer.remove_tracker(_left)
	XRServer.remove_tracker(_right)


func _tracker(tracker_name: StringName, pose: Transform3D) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = tracker_name
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	_set_pose(tracker, pose)
	return tracker


func _set_pose(tracker: XRControllerTracker, pose: Transform3D) -> void:
	tracker.set_pose(&"grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _add_block(center: Vector3, size: Vector3, climbable := false) -> void:
	var block: StaticBody3D = StaticBody3D.new()
	block.set_script(load("res://sandbox/parkour_block.gd"))
	block.set("size", size)
	block.set("climbable", climbable)
	block.position = center
	_range.add_child(block)


func test_left_stick_walks_where_the_head_looks() -> void:
	await wait_physics_frames(10)
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(45)
	var moved := _player.global_position - start
	assert_lt(moved.z, -0.5, "forward is -Z here")
	assert_almost_eq(moved.x, 0.0, 0.01)


func test_speed_builds_up_at_what_the_legs_can_push() -> void:
	await wait_physics_frames(10)
	var acceleration := _player.leg_force / _player.mass
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(20)
	assert_almost_eq(_player.linear_velocity.x, acceleration * 20.0 * DT, 0.25, "no instant speed")
	await wait_physics_frames(60)
	assert_almost_eq(_player.linear_velocity.x, _player.move_speed, 0.05, "then holds the walking speed")


func test_clicking_the_left_stick_runs() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await _click_sprint()
	await wait_physics_frames(100)
	assert_almost_eq(_player.linear_velocity.x, _player.sprint_speed, 0.05, "one click runs without holding it")
	await _click_sprint()
	await wait_physics_frames(60)
	assert_almost_eq(_player.linear_velocity.x, _player.move_speed, 0.05, "a second click walks")


func test_running_ends_with_the_walk() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await _click_sprint()
	await wait_physics_frames(30)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(60)
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(100)
	assert_almost_eq(_player.linear_velocity.x, _player.move_speed, 0.05)


func test_run_can_be_clicked_before_setting_off() -> void:
	await wait_physics_frames(10)
	await _click_sprint()
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(100)
	assert_almost_eq(_player.linear_velocity.x, _player.sprint_speed, 0.05)


func _click_sprint() -> void:
	_left.set_input(&"sprint", true)
	await wait_physics_frames(2)
	_left.set_input(&"sprint", false)
	await wait_physics_frames(1)


func test_a_moving_body_takes_time_to_stop() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(70)
	_left.set_input(&"primary", Vector2.ZERO)
	var speed := _player.linear_velocity.x
	var start := _player.global_position.x
	await wait_physics_frames(5)
	assert_gt(_player.linear_velocity.x, speed * 0.5, "still moving")
	await wait_physics_frames(80)
	var stopping := speed * speed * 0.5 * _player.mass / _player.brake_force
	assert_almost_eq(_player.global_position.x - start, stopping, 0.15, "and brakes harder than it speeds up")
	assert_almost_eq(_player.linear_velocity.length(), 0.0, 0.01, "and comes to rest")


func test_a_running_jump_keeps_its_speed_and_barely_steers() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await _click_sprint()
	await wait_physics_frames(100)
	var speed := _player.linear_velocity.x
	_right.set_input(&"jump", true)
	_left.set_input(&"primary", Vector2(-1, 0))
	await wait_physics_frames(30)
	assert_gt(_player.global_position.y, 0.2, "in the air")
	assert_gt(_player.linear_velocity.x, speed - 1.0, "only the air under the stick to push on")


func test_letting_go_of_the_stick_in_a_jump_doesnt_brake_it() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(70)
	var speed := _player.linear_velocity.x
	_right.set_input(&"jump", true)
	await wait_physics_frames(1)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(25)
	assert_gt(_player.linear_velocity.x, speed - 0.4, "it carries on through the air")


func test_a_gentle_turn_keeps_its_speed_and_a_reversal_brakes() -> void:
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(70)
	var speed := _player.linear_velocity.length()
	_left.set_input(&"primary", Vector2(1, 0.4))
	await wait_physics_frames(3)
	assert_gt(_player.linear_velocity.length(), speed - 0.15, "steering doesn't brake")
	_left.set_input(&"primary", Vector2(-1, 0))
	var brake_ticks := 0
	while _player.linear_velocity.x > 0.0 and brake_ticks < 90:
		await wait_physics_frames(1)
		brake_ticks += 1
	assert_lt(brake_ticks * DT, speed * _player.mass / _player.leg_force * 0.75, "reversing brakes hard")


## Swings both hands up at once, as in a jump. A real arm comes up to about head height.
func _swing_arms_up(distance: float, ticks: int) -> void:
	for i: int in ticks:
		var rise := Vector3.UP * distance * (i + 1.0) / ticks
		_set_pose(_left, LEFT_REST.translated(rise))
		_set_pose(_right, RIGHT_REST.translated(rise))
		await wait_physics_frames(1)


func _highest_until_landed() -> float:
	var highest := _player.global_position.y
	for i: int in 110:
		await wait_physics_frames(1)
		highest = maxf(highest, _player.global_position.y)
	return highest


func test_swinging_the_arms_up_into_a_jump_goes_higher() -> void:
	await wait_physics_frames(10)
	await _swing_arms_up(0.6, 14)
	_right.set_input(&"jump", true)
	var highest := await _highest_until_landed()
	assert_between(highest, 0.8, 1.2, "from about 50 cm to about a meter")


func test_arms_can_swing_just_after_the_button() -> void:
	await wait_physics_frames(10)
	_right.set_input(&"jump", true)
	await wait_physics_frames(2)
	await _swing_arms_up(0.6, 10)
	var highest := await _highest_until_landed()
	assert_gt(highest, 0.75)


func test_arms_too_late_or_too_slow_add_nothing() -> void:
	await wait_physics_frames(10)
	await _swing_arms_up(0.2, 30)
	_right.set_input(&"jump", true)
	var highest := await _highest_until_landed()
	assert_between(highest, 0.4, 0.65, "reaching slowly is a normal jump")
	_right.set_input(&"jump", false)
	_set_pose(_left, LEFT_REST)
	_set_pose(_right, RIGHT_REST)
	await wait_physics_frames(60)
	_right.set_input(&"jump", true)
	await wait_physics_frames(30)
	await _swing_arms_up(0.6, 14)
	assert_lt(_player.global_position.y + _player.linear_velocity.y * 0.5, 0.65, "already in the air")


func test_the_hardest_swing_is_capped() -> void:
	await wait_physics_frames(10)
	await _swing_arms_up(0.8, 10)
	_right.set_input(&"jump", true)
	var highest := await _highest_until_landed()
	var fastest := _player.jump_speed + _player.max_arm_swing_jump
	assert_lt(highest, fastest * fastest / (2.0 * 9.8) + 0.05)


func test_walking_into_a_wall_stops_the_view_too() -> void:
	_add_block(Vector3(0, 1, 0.5), Vector3(2, 2, 0.5))
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(180)
	assert_gt(_player.global_position.z, 0.75 + 0.2, "capsule stopped at the wall")
	assert_gt(_camera.global_position.z, 0.75 + 0.2, "and the view didn't carry on through it")
	assert_almost_eq(_player.linear_velocity.length(), 0.0, 0.05)


func test_a_jump_lands_on_bending_legs_that_straighten_again() -> void:
	await wait_physics_frames(10)
	_right.set_input(&"jump", true)
	await wait_physics_frames(30)
	var lowest := 1.0
	for i: int in 60:
		await wait_physics_frames(1)
		lowest = minf(lowest, _player.global_position.y)
	assert_between(lowest, -0.2, -0.01, "the view dips a little on landing")
	assert_almost_eq(_player.global_position.y, 0.0, 0.01, "and comes back up")


func test_a_small_step_is_walked_up_and_a_tall_one_stops_the_body() -> void:
	_add_block(Vector3(1.8, 0.1, 3), Vector3(2, 0.2, 2))
	_add_block(Vector3(5, 0.25, 3), Vector3(1, 0.5, 2))
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(70)
	assert_almost_eq(_player.global_position.y, 0.2, 0.03, "stepped up")
	await wait_physics_frames(90)
	assert_almost_eq(_player.global_position.y, 0.0, 0.03, "stepped back down the far side")
	assert_lt(_player.global_position.x, 4.5 - 0.2, "and stopped at the wall")


func test_hauling_up_a_wall_and_leaning_over_gets_on_top_of_it() -> void:
	_add_block(Vector3(0, 0.65, 2), Vector3(3, 1.3, 1.4))
	_add_block(Vector3(0, 1.33, 2.68), Vector3(3, 0.06, 0.1), true)
	var hand: PhysicsHand = _player.get_node("RightHand")
	_player.global_position = Vector3(0, 0, 3.05)
	await wait_physics_frames(5)
	var on_top := RIGHT_REST
	on_top.origin = Vector3(0.2, 1.38, -0.33)
	for i: int in 30:
		_set_pose(_right, RIGHT_REST.interpolate_with(on_top, float(i + 1) / 30.0))
		await wait_physics_frames(1)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true(hand.climbing, "took hold of the top")
	# Push the hand down to the hip, which gets the torso above the wall.
	var at_hip := on_top
	at_hip.origin.y = 0.85
	for i: int in 60:
		_set_pose(_right, on_top.interpolate_with(at_hip, float(i + 1) / 60.0))
		await wait_physics_frames(1)
	assert_gt(_player.global_position.y, 0.45, "hauled up")
	_camera.position += Vector3(0, 0, -0.7)
	await wait_physics_frames(10)
	assert_lt(_player.global_position.z, 2.6, "the torso follows the head over the top")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(90)
	assert_almost_eq(_player.global_position.y, 1.3, 0.03, "and stands up on it")
	assert_false(_player.get_node("Legs").disabled, "legs back out")


## Stands the player in front of a wall with a lip along its top, with the right hand gripping the lip.
func _grip_the_top_of_a_wall() -> void:
	_add_block(Vector3(0, 0.65, 2), Vector3(3, 1.3, 1.4))
	_add_block(Vector3(0, 1.33, 2.68), Vector3(3, 0.06, 0.1), true)
	_player.global_position = Vector3(0, 0, 3.05)
	await wait_physics_frames(5)
	var on_top := RIGHT_REST
	on_top.origin = Vector3(0.2, 1.38, -0.33)
	for i: int in 30:
		_set_pose(_right, RIGHT_REST.interpolate_with(on_top, float(i + 1) / 30.0))
		await wait_physics_frames(1)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true((_player.get_node("RightHand") as PhysicsHand).climbing, "gripping the lip")


func test_jump_while_gripping_a_ledge_mantles_onto_it() -> void:
	await _grip_the_top_of_a_wall()
	var hand: PhysicsHand = _player.get_node("RightHand")
	_right.set_input(&"jump", true)
	var fastest := 0.0
	for i: int in 150:
		await wait_physics_frames(1)
		fastest = maxf(fastest, _player.linear_velocity.length())
	assert_almost_eq(_player.global_position.y, 1.3, 0.03, "standing on top of the wall")
	assert_lt(_player.global_position.z, 2.7, "over the edge of it")
	assert_gt(_player.global_position.z, 1.3, "and still on it")
	assert_almost_eq(_player.global_position.x, 0.0, 0.03, "straight over, the way the head faces")
	assert_lt(fastest, _player.mantle_speed * 1.2, "at the speed of a mantle")
	assert_false(hand.climbing, "the hand came off the ledge")
	assert_false((_player.get_node("Legs") as CollisionShape3D).disabled, "legs back out")
	assert_lt(hand.global_position.distance_to(hand.target.origin), 0.1, "and the hand is back with the controller")


func test_mantle_carries_on_if_the_grip_lets_go() -> void:
	await _grip_the_top_of_a_wall()
	_right.set_input(&"jump", true)
	await wait_physics_frames(5)
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(150)
	assert_almost_eq(_player.global_position.y, 1.3, 0.03)


func test_no_mantle_without_room_to_stand_on_top() -> void:
	_add_block(Vector3(0, 2.3, 2), Vector3(3, 1, 1.4))
	await _grip_the_top_of_a_wall()
	var height := _player.global_position.y
	_right.set_input(&"jump", true)
	await wait_physics_frames(60)
	assert_almost_eq(_player.global_position.y, height, 0.1, "the wall's top is under a ceiling")
	assert_true((_player.get_node("RightHand") as PhysicsHand).climbing, "so the hand stays on")


func test_no_mantle_from_a_hold_partway_up_a_wall() -> void:
	_add_block(Vector3(0, 3, 2), Vector3(3, 6, 1.4))
	_add_block(Vector3(0, 1.33, 2.68), Vector3(3, 0.06, 0.1), true)
	_player.global_position = Vector3(0, 0, 3.05)
	await wait_physics_frames(5)
	var on_hold := RIGHT_REST
	on_hold.origin = Vector3(0.2, 1.38, -0.28)
	for i: int in 30:
		_set_pose(_right, RIGHT_REST.interpolate_with(on_hold, float(i + 1) / 30.0))
		await wait_physics_frames(1)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	var hand: PhysicsHand = _player.get_node("RightHand")
	assert_true(hand.climbing)
	_right.set_input(&"jump", true)
	await wait_physics_frames(60)
	assert_lt(_player.global_position.y, 0.3, "nothing to stand on up there")
	assert_true(hand.climbing)


func test_no_mantle_from_a_bar_in_the_open() -> void:
	_bar_at_right_hand()
	await wait_physics_frames(10)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	_right.set_input(&"jump", true)
	await wait_physics_frames(30)
	assert_true((_player.get_node("RightHand") as PhysicsHand).climbing)


func test_walking_up_a_ramp_and_standing_on_it() -> void:
	var ramp_top_y := 2.0
	_player.global_position = Vector3(-3, 0.5, 8.2)
	await wait_physics_frames(30)
	var standing := _player.global_position
	await wait_physics_frames(60)
	assert_almost_eq(_player.global_position.distance_to(standing), 0.0, 0.03, "legs hold it on the slope")
	_left.set_input(&"primary", Vector2(0, -1))
	await wait_physics_frames(180)
	assert_almost_eq(_player.global_position.y, ramp_top_y, 0.15, "walked up onto the platform")


func test_ground_too_steep_for_the_legs_slides_away() -> void:
	_player.global_position = Vector3(1, 1.7, 8.1)
	await wait_physics_frames(60)
	assert_lt(_player.global_position.y, 1.0, "slid down it")
	assert_lt(_player.global_position.z, 7.9)


func test_walking_into_a_cube_shoves_it() -> void:
	var cube: RigidBody3D = _range.get_node("Parkour/PushCube1")
	var start := cube.global_position
	_player.global_position = Vector3(start.x, 0, start.z + 1.5)
	await wait_physics_frames(10)
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(90)
	assert_lt(cube.global_position.z, start.z - 0.3, "the cube went along")
	assert_almost_eq(cube.global_position.x, start.x, 0.1)


func test_standing_on_a_cube_stays_on_top_of_it() -> void:
	var cube: RigidBody3D = _range.get_node("Parkour/PushCube1")
	_player.global_position = cube.global_position + Vector3.UP * 0.4
	await wait_physics_frames(60)
	assert_almost_eq(_player.global_position.y, 0.7, 0.03, "cube holds the weight")
	assert_almost_eq(cube.global_position.y, 0.35, 0.03)
	assert_almost_eq(_player.global_position.z, cube.global_position.z, 0.05)


## A bar in reach of where the right hand rests, clear of the body, for a player at z = 3 and the height given.
func _bar_at_right_hand(player_y := 0.0) -> void:
	_add_block(Vector3(0.2, player_y + 1.2, 2.73), Vector3(0.5, 0.05, 0.05), true)


func test_pulling_down_on_a_hold_lifts_the_body_and_it_hangs_there() -> void:
	_bar_at_right_hand()
	await wait_physics_frames(10)
	var hand: PhysicsHand = _player.get_node("RightHand")
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true(hand.climbing, "squeezing takes hold")
	var on_hold := hand.global_position
	await _pull_right_hand_down(0.4, 60)
	assert_almost_eq(_player.global_position.y, 0.4, 0.06, "the body rose as far as the hand came down")
	await wait_physics_frames(60)
	assert_almost_eq(_player.global_position.y, 0.4, 0.02, "and the arm holds its weight")
	assert_almost_eq(hand.global_position.distance_to(on_hold), 0.0, 0.001, "the hand stays on the hold")


func test_letting_go_mid_pull_flies_on_and_falls() -> void:
	_bar_at_right_hand()
	await wait_physics_frames(10)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	await _pull_right_hand_down(0.5, 25)
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	assert_false(_player.get_node("RightHand").climbing, "let go")
	var rising := _player.linear_velocity.y
	assert_gt(rising, 0.4, "keeps the speed of the pull")
	var height := _player.global_position.y
	await wait_physics_frames(5)
	assert_gt(_player.global_position.y, height, "still going up")
	await wait_physics_frames(120)
	assert_almost_eq(_player.global_position.y, 0.0, 0.03, "and comes back down")


func test_two_arms_haul_up_faster_than_one() -> void:
	_add_block(Vector3(0, 1.2, 2.73), Vector3(1, 0.05, 0.05), true)
	await wait_physics_frames(10)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	await _pull_right_hand_down(0.5, 15)
	var one_arm := _player.global_position.y
	_right.set_input(&"grip", 0.0)
	_set_pose(_right, RIGHT_REST)
	await wait_physics_frames(120)
	assert_almost_eq(_player.global_position.y, 0.0, 0.03, "back on the ground")

	_right.set_input(&"grip", 1.0)
	_left.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true(_player.get_node("LeftHand").climbing)
	var left_low := LEFT_REST
	left_low.origin.y -= 0.5
	for i: int in 15:
		_set_pose(_left, LEFT_REST.interpolate_with(left_low, float(i + 1) / 15.0))
		await _pull_right_hand_down(0.5 * (i + 1.0) / 15.0, 1)
	assert_gt(_player.global_position.y, one_arm + 0.1)


func test_an_arm_too_weak_for_the_body_slips_off() -> void:
	_player.global_position = Vector3(0, 4, 3)
	_bar_at_right_hand(4.0)
	var hand: PhysicsHand = _player.get_node("RightHand")
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true(hand.climbing)
	_player.arm_force = 500.0
	await wait_physics_frames(80)
	assert_false(hand.climbing, "sank until the grip failed")
	assert_lt(_player.linear_velocity.y, -1.0, "and falling")


func test_only_climbable_surfaces_can_be_gripped() -> void:
	_add_block(Vector3(0.2, 1.2, 2.73), Vector3(0.5, 0.05, 0.05))
	await wait_physics_frames(10)
	var hand: PhysicsHand = _player.get_node("RightHand")
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_false(hand.climbing, "a plain block is no use")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	var pipe: StaticBody3D = StaticBody3D.new()
	pipe.set_script(load("res://sandbox/parkour_pipe.gd"))
	pipe.position = Vector3(0.2, 1.1, 2.73)
	_range.add_child(pipe)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_true(hand.climbing, "a pipe is")


func _pull_right_hand_down(distance: float, ticks: int) -> void:
	var low := RIGHT_REST
	low.origin.y -= distance
	for i: int in ticks:
		_set_pose(_right, RIGHT_REST.interpolate_with(low, float(i + 1) / ticks))
		await wait_physics_frames(1)


func _point_right_hand(direction: Vector3) -> void:
	var aim := Transform3D(Basis.looking_at(direction, Vector3.BACK), RIGHT_REST.origin)
	_right.set_pose(&"aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func test_pointing_at_a_grapple_target_shows_what_it_would_catch() -> void:
	_add_block(Vector3(0.2, 8, 2.8), Vector3(2, 0.5, 2))
	await wait_physics_frames(10)
	var grapple: Grapple = _player.get_node("RightGrapple")
	var aim_line: MeshInstance3D = grapple.get_node("AimLine")
	var line: MeshInstance3D = grapple.get_node("Line")
	var dot: MeshInstance3D = grapple.get_node("Dot")
	_point_right_hand(Vector3.DOWN)
	await wait_physics_frames(2)
	assert_false(dot.visible, "nothing shows pointing at the floor")
	_point_right_hand(Vector3.UP)
	await wait_physics_frames(2)
	assert_true(aim_line.visible and dot.visible, "without touching the trigger")
	assert_false(line.visible, "and it isn't connected yet")
	assert_almost_eq(dot.global_position.y, 7.75, 0.01, "the dot sits on the surface")
	var aiming_size := dot.scale.x
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(2)
	assert_true(grapple.attached)
	assert_true(line.visible, "connecting swaps to the thick line")
	assert_false(aim_line.visible)
	assert_gt(dot.scale.x, aiming_size * 2.0, "and grows the dot")
	_right.set_input(&"trigger", 0.0)
	await wait_physics_frames(2)
	assert_false(line.visible, "letting go ends it")
	assert_true(aim_line.visible, "and it's back to aiming")


func test_connecting_alone_doesnt_move_the_body() -> void:
	_add_block(Vector3(0.2, 8, 2.8), Vector3(2, 0.5, 2))
	await wait_physics_frames(10)
	var start := _player.global_position
	_point_right_hand(Vector3.UP)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(60)
	assert_true((_player.get_node("RightGrapple") as Grapple).attached)
	assert_almost_eq(_player.global_position.distance_to(start), 0.0, 0.05, "a full squeeze doesn't wind it in")


func test_pulling_the_arm_back_hauls_the_body_and_it_flies_on() -> void:
	_add_block(Vector3(0.2, 8, 2.8), Vector3(2, 0.5, 2))
	await wait_physics_frames(10)
	var grapple: Grapple = _player.get_node("RightGrapple")
	_point_right_hand(Vector3.UP)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(3)
	assert_true(grapple.attached, "squeezing shoots it")
	assert_almost_eq(grapple.anchor.y, 7.75, 0.01, "at the surface it points at")
	# A hard haul: 3.6 m/s down from about head height.
	var high := RIGHT_REST.translated(Vector3.UP * 0.4)
	for i: int in 20:
		_set_pose(_right, RIGHT_REST.interpolate_with(high, float(i + 1) / 20.0))
		await wait_physics_frames(1)
	await wait_physics_frames(20)
	var low := RIGHT_REST.translated(Vector3.DOWN * 0.3)
	for i: int in 12:
		_set_pose(_right, high.interpolate_with(low, float(i + 1) / 12.0))
		await wait_physics_frames(1)
	var fastest := grapple.max_tension / _player.mass * 13.0 * DT
	assert_gt(_player.linear_velocity.y, 3.0, "the haul threw the body up")
	assert_lt(_player.linear_velocity.y, fastest, "no harder than the cable can pull")
	var rising := _player.linear_velocity.y
	_right.set_input(&"trigger", 0.0)
	await wait_physics_frames(2)
	assert_false(grapple.attached, "letting off lets go")
	assert_gt(_player.linear_velocity.y, rising - 1.0, "and the body flies on")


func test_grapple_swings_at_a_held_length() -> void:
	_add_block(Vector3(5, 9, 3), Vector3(2, 0.5, 2))
	_player.global_position = Vector3(0, 4, 3)
	var grapple: Grapple = _player.get_node("RightGrapple")
	var hand: PhysicsHand = _player.get_node("RightHand")
	await wait_physics_frames(2)
	_point_right_hand(hand.global_position.direction_to(Vector3(5, 8.75, 3)))
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(2)
	assert_true(grapple.attached)
	var length := grapple.length
	await wait_physics_frames(60)
	assert_lt(grapple.anchor.distance_to(hand.target.origin), length + 0.3, "it holds the body")
	assert_gt(_player.linear_velocity.x, 2.0, "swinging under the anchor")
	assert_gt(_player.global_position.y, 1.0, "not dropping to the floor")


func test_grapple_only_catches_parkour_surfaces() -> void:
	await wait_physics_frames(10)
	var grapple: Grapple = _player.get_node("RightGrapple")
	_point_right_hand(Vector3.DOWN)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(3)
	assert_false(grapple.attached, "the floor is not one")
	assert_false((grapple.get_node("Dot") as MeshInstance3D).visible)


func test_grapple_doesnt_fire_from_a_hand_holding_a_gun() -> void:
	_add_block(Vector3(0.2, 8, 2.8), Vector3(2, 0.5, 2))
	await wait_physics_frames(10)
	var grapple: Grapple = _player.get_node("RightGrapple")
	var hand: PhysicsHand = _player.get_node("RightHand")
	_right.set_input(&"grip", 1.0)
	hand.grab((_range.get_node("Pistol") as Gun).grip)
	_point_right_hand(Vector3.UP)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(3)
	assert_false(grapple.attached)
	assert_false((grapple.get_node("Dot") as MeshInstance3D).visible, "no aiming with a gun in hand")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(3)
	assert_null(hand.held, "dropped it")
	assert_false(grapple.attached, "the trigger has to come up before it shoots")
	_right.set_input(&"trigger", 0.0)
	await wait_physics_frames(2)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(2)
	assert_true(grapple.attached, "then it does")


func test_right_stick_click_jumps_and_lands() -> void:
	await wait_physics_frames(10)
	var floor_y := _player.global_position.y
	_right.set_input(&"jump", true)
	var highest := floor_y
	for i: int in 70:
		await wait_physics_frames(1)
		highest = maxf(highest, _player.global_position.y)
	assert_between(highest - floor_y, 0.4, 0.65, "a standing jump of about 50 cm")
	assert_almost_eq(_player.global_position.y, floor_y, 0.02, "held click does not keep jumping")


func test_flicking_the_right_stick_up_jumps() -> void:
	await wait_physics_frames(10)
	var floor_y := _player.global_position.y
	_right.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(15)
	assert_gt(_player.global_position.y, floor_y + 0.2)


func test_fire_mode_button_moves_the_selector_on_a_held_ar() -> void:
	_player.global_position = Vector3.ZERO
	var ar: Gun = _range.get_node("AR")
	await wait_physics_frames(30)
	var hand: PhysicsHand = _player.get_node("RightHand")
	var reach := RIGHT_REST
	var start := reach.origin
	var goal := ar.grip.global_position + Vector3(0, 0.08, 0)
	for i: int in 45:
		reach.origin = start.lerp(goal, float(i + 1) / 45.0)
		_set_pose(_right, reach)
		await wait_physics_frames(1)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_eq(hand.held, ar.grip)
	_right.set_input(&"fire_mode", true)
	await wait_physics_frames(2)
	_right.set_input(&"fire_mode", false)
	await wait_physics_frames(2)
	assert_eq(ar.fire_control.selector, FireControl.Selector.BURST)
	_right.set_input(&"fire_mode", true)
	await wait_physics_frames(2)
	_right.set_input(&"fire_mode", false)
	await wait_physics_frames(2)
	assert_eq(ar.fire_control.selector, FireControl.Selector.AUTO)


func test_aim_pose_points_the_laser() -> void:
	_player.global_position = Vector3.ZERO
	var pistol: Gun = _range.get_node("Pistol")
	await wait_physics_frames(30)
	var hand: PhysicsHand = _player.get_node("RightHand")
	# Point the aim pose at the pistol from where the hand is resting.
	var from := hand.global_position
	var aim_at := Basis.looking_at(from.direction_to(pistol.grip.global_position))
	_right.set_pose(&"aim", Transform3D(aim_at, RIGHT_REST.origin), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await wait_physics_frames(3)
	assert_eq(hand.remote_target, pistol.grip, "the aim pose picks the target")


func _hold_fit_buttons() -> void:
	_left.set_input(&"hand_fit", true)
	await wait_physics_frames(95)
	_left.set_input(&"hand_fit", false)
	await wait_physics_frames(2)


func test_hand_fit_moves_the_hands_and_comes_back_next_time() -> void:
	_player.fit_path = "user://test_hand_fit.cfg"
	await wait_physics_frames(10)
	var model: Node3D = _player.get_node("RightHand").find_child("HandRight", true, false)
	var left_model: Node3D = _player.get_node("LeftHand").find_child("HandLeft", true, false)
	var start := model.position
	var left_start := left_model.position
	var label: Label3D = _player.get_node("LeftHand/FitLabel")
	assert_false(label.visible)

	await _hold_fit_buttons()
	assert_true(label.visible, "holding the button enters the mode")

	var standing := _player.global_position
	_left.set_input(&"primary", Vector2(1, 0.5))
	_right.set_input(&"primary", Vector2(0.5, 1))
	await wait_physics_frames(45)
	_left.set_input(&"primary", Vector2.ZERO)
	_right.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(2)
	assert_almost_eq((_player.global_position - standing).length(), 0.0, 0.01, "sticks don't walk in this mode")
	assert_almost_eq(_player.global_position.y, standing.y, 0.01, "and don't jump")
	assert_gt(model.position.x, start.x + 0.005, "right hand moved outward")
	assert_lt(left_model.position.x, left_start.x - 0.005, "left hand mirrors it")
	var fitted := model.transform

	await _hold_fit_buttons()
	assert_false(label.visible, "holding again leaves the mode")
	await wait_physics_frames(2)
	_left.set_input(&"primary", Vector2(0, 1))
	var before_walk := _player.global_position
	await wait_physics_frames(20)
	assert_gt((_player.global_position - before_walk).length(), 0.1, "sticks walk again")
	_left.set_input(&"primary", Vector2.ZERO)

	var next_time: Player = (load("res://player/player.tscn") as PackedScene).instantiate()
	next_time.fit_path = _player.fit_path
	add_child_autofree(next_time)
	var reloaded: Node3D = next_time.get_node("RightHand").find_child("HandRight", true, false)
	assert_true(reloaded.transform.is_equal_approx(fitted), "the fit is remembered")
	DirAccess.remove_absolute(_player.fit_path)


func test_a_gun_goes_into_the_fitted_hand() -> void:
	_player.global_position = Vector3.ZERO
	var pistol: Gun = _range.get_node("Pistol")
	var hand: PhysicsHand = _player.get_node("RightHand")
	var fit := Transform3D(Basis.IDENTITY, Vector3(0.02, -0.03, 0.01))
	hand.set_fit(fit)
	await wait_physics_frames(30)
	hand.set_target(Transform3D(RIGHT_REST.basis, pistol.grip.global_position + Vector3(0, 0.08, 0)))
	hand.grab(pistol.grip)
	var expected: Vector3 = (hand.global_transform * fit).origin
	assert_almost_eq(pistol.grip.global_position.distance_to(expected), 0.0, 0.001)
	hand.release()


func test_the_range_shows_the_controls_for_the_controller_in_use() -> void:
	var controls: Label3D = _range.get_node("Table/Controls")
	assert_string_contains(controls.text, "B or Y", "Touch style by default")
	_right.profile = "/interaction_profiles/valve/frame_controller_valve"
	await wait_physics_frames(1)
	assert_string_contains(controls.text, "D-pad", "Frame layout")
	assert_string_contains(controls.text, "R3", "Frame layout")
	_right.profile = "/interaction_profiles/oculus/touch_controller"
	await wait_physics_frames(1)
	assert_string_contains(controls.text, "B or Y", "and back")


func test_each_kind_of_controller_keeps_its_own_hand_fit() -> void:
	_player.fit_path = "user://test_hand_fit.cfg"
	DirAccess.remove_absolute(_player.fit_path)
	await wait_physics_frames(5)
	_right.profile = "/interaction_profiles/oculus/touch_controller"
	await wait_physics_frames(1)
	_player._fit_offset = Vector3(0.01, 0.02, 0.03)
	_player._save_fit()
	_right.profile = "/interaction_profiles/valve/frame_controller_valve"
	await wait_physics_frames(1)
	assert_eq(_player._fit_offset, Vector3.ZERO, "the Frame starts from its own fit")
	_right.profile = "/interaction_profiles/oculus/touch_controller"
	await wait_physics_frames(1)
	assert_eq(_player._fit_offset, Vector3(0.01, 0.02, 0.03), "and Touch gets its back")
	DirAccess.remove_absolute(_player.fit_path)


func test_every_action_is_bound_on_the_frame_and_on_touch() -> void:
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	var action_set: OpenXRActionSet = map.action_sets[0]
	for profile_path: String in ["/interaction_profiles/valve/frame_controller_valve", "/interaction_profiles/oculus/touch_controller"]:
		var profile := map.find_interaction_profile(profile_path)
		assert_not_null(profile, profile_path)
		for action: OpenXRAction in action_set.actions:
			var bound := false
			for binding: OpenXRIPBinding in profile.bindings:
				bound = bound or binding.action == action
			assert_true(bound, action.resource_name + " on " + profile_path)


func test_game_only_reads_actions_in_the_map() -> void:
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	var action_set: OpenXRActionSet = map.action_sets[0]
	var code := FileAccess.get_file_as_string("res://player/player.gd") + FileAccess.get_file_as_string("res://player/physics_hand.gd")
	var used := RegEx.create_from_string("(?:is_button_pressed|get_float|get_vector2|trigger_haptic_pulse)\\(&\"(\\w+)\"")
	var found := used.search_all(code)
	assert_gt(found.size(), 5, "the search finds the reads")
	var names: Array[String] = []
	for action: OpenXRAction in action_set.actions:
		names.append(action.resource_name)
	for match_result: RegExMatch in found:
		assert_has(names, match_result.get_string(1))


## Moves a controller at human speed to a world position.
func _reach(tracker: XRControllerTracker, from: Transform3D, goal: Vector3) -> void:
	var origin: Node3D = _player.get_node("XROrigin3D")
	var pose := from
	var start := from.origin
	for i: int in 30:
		pose.origin = start.lerp(origin.to_local(goal), float(i + 1) / 30.0)
		_set_pose(tracker, pose)
		await wait_physics_frames(1)


func test_carrying_the_ar_in_two_hands_while_running_and_jumping() -> void:
	_player.global_position = Vector3(0.3, 0, 0)
	var ar: Gun = _range.get_node("AR")
	var right: PhysicsHand = _player.get_node("RightHand")
	var left: PhysicsHand = _player.get_node("LeftHand")
	await wait_physics_frames(30)
	await _reach(_right, RIGHT_REST, ar.grip.global_position + Vector3(0, 0.08, 0))
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_eq(right.held, ar.grip, "main hand takes the grip")

	var origin: Node3D = _player.get_node("XROrigin3D")
	var raised := Transform3D(RIGHT_REST.basis, origin.to_local(right.global_position))
	await _reach(_right, raised, origin.to_global(RIGHT_REST.origin))
	await wait_physics_frames(30)
	var spot: GrabPoint = ar.frame.get_node("Handguard2")
	await _reach(_left, LEFT_REST, spot.global_position + Vector3(-0.03, -0.03, 0))
	_left.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	assert_eq(left.held, spot, "off hand takes a handguard spot")

	_left.set_input(&"primary", Vector2(0, -1))
	_left.set_input(&"sprint", true)
	await wait_physics_frames(60)
	_right.set_input(&"jump", true)
	await wait_physics_frames(5)
	_right.set_input(&"jump", false)
	await wait_physics_frames(50)
	assert_gt(_player.global_position.z, 1.0, "the player did run")
	assert_eq(right.held, ar.grip, "main hand still holding")
	assert_eq(left.held, spot, "off hand still holding")
	assert_almost_eq(ar.grip.global_position.distance_to(right.global_position), 0.0, 0.03, "grip stays in the fist")
	assert_almost_eq(spot.global_position.distance_to(left.global_position), 0.0, 0.03, "handguard stays in the other")

	watch_signals(ar)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(3)
	_right.set_input(&"trigger", 0.0)
	assert_signal_emitted(ar, "shot_fired", "fires on the run")
	await wait_physics_frames(30)
	assert_eq(right.held, ar.grip, "main hand holds through the shot")
	assert_eq(left.held, spot, "off hand holds through the shot")
	_left.set_input(&"primary", Vector2.ZERO)
	_left.set_input(&"sprint", false)


func test_small_stick_input_is_ignored() -> void:
	await wait_physics_frames(10)
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 0.1))
	await wait_physics_frames(20)
	assert_almost_eq((_player.global_position - start).length(), 0.0, 0.001)


func test_right_stick_turns_smoothly() -> void:
	await wait_physics_frames(10)
	_right.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(1)
	var first := -_camera.global_basis.z
	await wait_physics_frames(1)
	var step := first.angle_to(-_camera.global_basis.z)
	assert_lt(step, 0.1, "no snap turn")
	await wait_physics_frames(45)
	assert_gt(first.signed_angle_to(-_camera.global_basis.z, Vector3.UP), -3.2)
	assert_lt(first.signed_angle_to(-_camera.global_basis.z, Vector3.UP), -0.5, "turned right")


func test_turning_pivots_on_the_head() -> void:
	await wait_physics_frames(10)
	_camera.position += Vector3(0.3, 0, 0)
	await wait_physics_frames(5)
	var view := _camera.global_position
	_right.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(60)
	assert_almost_eq((_camera.global_position - view).length(), 0.0, 0.01)


func test_capsule_follows_real_steps_without_moving_the_view() -> void:
	await wait_physics_frames(10)
	_camera.position += Vector3(0.3, 0, 0)
	var view := _camera.global_position
	await wait_physics_frames(5)
	assert_almost_eq((_camera.global_position - view).length(), 0.0, 0.01, "view stays put")
	assert_almost_eq(_player.global_position.x, view.x, 0.01, "capsule came along")


func test_leaning_over_the_table_is_allowed() -> void:
	_player.global_position = Vector3(0, 0, -0.1)
	await wait_physics_frames(10)
	_camera.position += Vector3(0, 0, -0.5)
	var view := _camera.global_position
	await wait_physics_frames(5)
	assert_almost_eq((_camera.global_position - view).length(), 0.0, 0.01, "not pushed back")
	assert_gt(_player.global_position.z, -0.2, "capsule stopped at the table")


func test_hands_follow_the_controllers_while_walking() -> void:
	await wait_physics_frames(10)
	var hand: PhysicsHand = _player.get_node("RightHand")
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(45)
	var controller: XRController3D = _player.get_node("XROrigin3D/RightController")
	assert_lt((hand.global_position - controller.global_position).length(), 0.06)


func test_shoulders_ride_with_the_head() -> void:
	await wait_physics_frames(10)
	var shoulder: AnimatableBody3D = _player.get_node("RightShoulder")
	assert_almost_eq(shoulder.global_position.y, _camera.global_position.y + _player.shoulder_offset.y, 0.02)
	assert_gt(shoulder.global_position.x, _camera.global_position.x)


func test_controller_buttons_pick_up_and_fire() -> void:
	_player.global_position = Vector3.ZERO
	var pistol: Gun = _range.get_node("Pistol")
	await wait_physics_frames(30)
	# Reach for the grip at human speed.
	var reach := Transform3D(RIGHT_REST.basis, RIGHT_REST.origin)
	var goal := pistol.grip.global_position + Vector3(0, 0.08, 0)
	var start := reach.origin
	for i: int in 45:
		reach.origin = start.lerp(goal, float(i + 1) / 45.0)
		_set_pose(_right, reach)
		await wait_physics_frames(1)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	var hand: PhysicsHand = _player.get_node("RightHand")
	assert_eq(hand.held, pistol.grip, "squeeze picks it up")
	watch_signals(pistol)
	_right.set_input(&"trigger", 1.0)
	await wait_physics_frames(3)
	_right.set_input(&"trigger", 0.0)
	assert_signal_emitted(pistol, "shot_fired", "trigger fires it")
	_right.set_input(&"mag_release", true)
	await wait_physics_frames(2)
	assert_false(pistol.mag_well.latched, "its button drops the magazine")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	assert_null(hand.held, "letting go drops the gun")
