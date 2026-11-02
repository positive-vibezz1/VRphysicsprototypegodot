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


func test_left_stick_walks_where_the_head_looks() -> void:
	await wait_physics_frames(10)
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(45)
	var moved := _player.global_position - start
	assert_almost_eq(moved.length(), _player.move_speed * 46.0 * DT, 0.3)
	assert_lt(moved.z, 0.0, "forward is -Z here")
	assert_almost_eq(moved.x, 0.0, 0.01)


func test_clicking_the_left_stick_runs() -> void:
	await wait_physics_frames(10)
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 1))
	_left.set_input(&"sprint", true)
	await wait_physics_frames(45)
	assert_gt((_player.global_position - start).length(), _player.move_speed * 46.0 * DT + 0.5)


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
	await wait_physics_frames(10)
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
	_right.set_input(&"mag_release", true)
	await wait_physics_frames(2)
	assert_false(pistol.mag_well.latched, "its button drops the magazine")
	_right.set_input(&"grip", 0.0)
	await wait_physics_frames(2)
	assert_null(hand.held, "letting go drops the gun")
