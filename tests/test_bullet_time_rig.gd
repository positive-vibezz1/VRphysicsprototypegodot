extends GutTest
## Bullet time on the whole XR rig in the range, through real XRServer trackers: the button, what stays in real time and
## what doesn't, with the debug log on so every line the rig and range can print gets built.

const LEFT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(-0.2, 1.1, -0.2))
const RIGHT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.2, 1.1, -0.2))
const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const TICK := 1.0 / 90.0

var _left: XRControllerTracker
var _right: XRControllerTracker
var _range: Node3D
var _player: Player
var _bullet_time: BulletTime
var _was_logging := false


func before_each() -> void:
	_was_logging = DebugLog.enabled
	DebugLog.enabled = true
	_left = _tracker(&"left_hand", LEFT_REST)
	_right = _tracker(&"right_hand", RIGHT_REST)
	_range = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(_range)
	_player = _range.get_node("Player")
	_bullet_time = _player.get_node("BulletTime")
	_player.global_position = Vector3(0, 0, 3)
	_set_pose(_left, LEFT_REST)
	_set_pose(_right, RIGHT_REST)
	await wait_physics_frames(10)


func after_each() -> void:
	DebugLog.enabled = _was_logging
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
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


func _go_slow() -> void:
	_right.set_input(&"bullet_time", true)
	await wait_physics_frames(2)
	_right.set_input(&"bullet_time", false)
	await wait_physics_frames(roundi(_bullet_time.ramp_time / TICK) + 2)
	assert_almost_eq(Engine.time_scale, _bullet_time.slow_scale, 0.001, "slowed")


func test_either_hand_starts_and_stops_it_and_the_meter_shows() -> void:
	var meter: Node3D = _player.get_node("LeftHand/BulletTimeMeter")
	assert_false(meter.visible, "nothing to show with a full meter")
	await _go_slow()
	assert_true(_bullet_time.active)
	assert_true(meter.visible)
	assert_lt(meter.scale.y, 1.0)
	_left.set_input(&"bullet_time", true)
	await wait_physics_frames(2)
	_left.set_input(&"bullet_time", false)
	await wait_physics_frames(roundi(_bullet_time.ramp_time / TICK) + 2)
	assert_false(_bullet_time.active)
	assert_eq(Engine.time_scale, 1.0)


func test_the_stick_turns_the_view_in_real_time() -> void:
	await _go_slow()
	var origin: XROrigin3D = _player.get_node("XROrigin3D")
	var before := origin.global_basis
	_right.set_input(&"primary", Vector2(1, 0))
	await wait_physics_frames(45)
	var turned := (before.inverse() * origin.global_basis).get_rotation_quaternion().get_angle()
	# Half a real second at full rate, less a moment to get up to it.
	assert_almost_eq(turned, _player.turn_speed * 0.5, 0.2)


func test_the_body_stays_in_world_time() -> void:
	await _go_slow()
	var start := _player.global_position
	_left.set_input(&"primary", Vector2(0, 1))
	await wait_physics_frames(90)
	# A real second is 0.1 s of world time: 7 m/s2 of legs takes it about 3.5 cm from a standing start.
	assert_almost_eq((_player.global_position - start).length(), 0.035, 0.015)


func test_an_arm_swing_counts_at_its_real_speed() -> void:
	await _go_slow()
	var top := _player.global_position.y
	_right.set_input(&"jump", true)
	for i: int in 13:
		# Both hands up at 3 m/s of real time: an ordinary swing, and far over the limit in world time.
		_set_pose(_left, LEFT_REST.translated(Vector3.UP * 3.0 * TICK * i))
		_set_pose(_right, RIGHT_REST.translated(Vector3.UP * 3.0 * TICK * i))
		await wait_physics_frames(1)
	_right.set_input(&"jump", false)
	var boosted := _player.linear_velocity.y
	assert_gt(boosted, _player.jump_speed + 0.5, "the swing raised the jump")
	assert_lt(boosted, _player.jump_speed + _player.max_arm_swing_jump + 0.5)
	assert_gt(_player.global_position.y, top)


func test_hanging_from_a_hold_stays_put_in_slow_time() -> void:
	var pipe: StaticBody3D = StaticBody3D.new()
	pipe.set_script(load("res://sandbox/parkour_pipe.gd"))
	pipe.position = Vector3(0.2, 1.1, 2.73)
	_range.add_child(pipe)
	_right.set_input(&"grip", 1.0)
	await wait_physics_frames(3)
	var hand: PhysicsHand = _player.get_node("RightHand")
	assert_true(hand.climbing)
	await _go_slow()
	var start := _player.global_position
	await wait_physics_frames(180)
	assert_true(hand.climbing, "still on")
	assert_lt((_player.global_position - start).length(), 0.02)


func test_a_bullet_still_hurts_a_dummy_in_slow_time() -> void:
	await _go_slow()
	var dummy: Dummy = _range.get_node("Dummy")
	var body: Node3D = dummy.get_node("Body")
	var health := dummy.health
	Ballistics.pool.fire_bullet(NINE, body.global_position + Vector3(0, 0, 1), Vector3(0, 0, -360))
	await wait_physics_frames(30)
	# The same energy as at normal speed: about 520 J, or 29 points, as tuned in Dummy.
	assert_almost_eq(health - dummy.health, 29.0, 6.0)
