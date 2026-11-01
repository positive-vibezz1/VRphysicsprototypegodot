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


func test_left_stick_walks_where_the_head_looks() -> void:
	await wait_physics_frames(10)
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(45)
	var moved := _player.global_position - start
	assert_almost_eq(moved.length(), _player.move_speed * 46.0 * DT, 0.25)
	assert_lt(moved.z, 0.0, "forward is -Z here")
	assert_almost_eq(moved.x, 0.0, 0.01)


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
	_right.set_input(&"ax_button", true)
	await wait_physics_frames(2)
	assert_false(pistol.mag_well.latched, "A/X drops the magazine")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	assert_null(hand.held, "letting go drops the gun")
