extends GutTest
## The block course in the range: its dummies stand where they were put, each can be shot from the route, and the
## player can walk and jump the whole route. The last wall is a climb, which test_player covers.

const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const DUMMY_COUNT := 7
## Where each dummy is shot from on the route, at eye height, in the course's space.
const FIRING_POINTS: Dictionary[String, Vector3] = {
	"Dummy1": Vector3(1.2, 1.6, 1.0),
	"Dummy2": Vector3(-1.2, 1.6, -5.0),
	"Dummy3": Vector3(0.0, 3.1, -16.0),
	"Dummy4": Vector3(0.0, 3.1, -19.0),
	"Dummy5": Vector3(0.0, 2.8, -25.5),
	"Dummy6": Vector3(2.5, 1.6, -32.5),
	"Dummy7": Vector3(7.5, 3.6, -32.0),
}

var _left: XRControllerTracker
var _right: XRControllerTracker
var _player: Player
var _course: Node3D


func before_each() -> void:
	Ballistics.pool.clear()
	_left = _tracker(&"left_hand", Vector3(-0.2, 1.1, -0.2))
	_right = _tracker(&"right_hand", Vector3(0.2, 1.1, -0.2))
	var range_scene: Node3D = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(range_scene)
	_player = range_scene.get_node("Player")
	_course = range_scene.get_node("BlockCourse")
	_player.global_position = _course.to_global(Vector3(1.2, 0, 1))
	await wait_physics_frames(10)


func after_each() -> void:
	XRServer.remove_tracker(_left)
	XRServer.remove_tracker(_right)


func _tracker(tracker_name: StringName, at: Vector3) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = tracker_name
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	var pose := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), at)
	tracker.set_pose(&"grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	return tracker


## Steers the left stick at a spot on the course's floor plan until the player is there.
func _walk_to(x: float, z: float) -> void:
	var target := _course.to_global(Vector3(x, 0, z))
	for i: int in 400:
		var to := target - _player.global_position
		to.y = 0.0
		if to.length() < 0.3:
			return
		var direction := to.normalized()
		_left.set_input(&"primary", Vector2(direction.x, -direction.z))
		await get_tree().physics_frame
	fail_test("never got to %s, stuck at %s" % [Vector2(x, z), _course.to_local(_player.global_position)])


func test_every_dummy_stands_where_it_was_put() -> void:
	await wait_physics_frames(90)
	var dummies := 0
	for child: Node in _course.get_children():
		if child is Dummy:
			dummies += 1
			var stand: RigidBody3D = child.get_node("Stand")
			var body: RigidBody3D = child.get_node("Body")
			assert_almost_eq(stand.global_position.y, (child as Dummy).global_position.y + 0.14, 0.02, child.name + " on its block")
			assert_gt(body.global_basis.y.y, 0.99, child.name + " upright")
	assert_eq(dummies, DUMMY_COUNT)
	assert_eq(FIRING_POINTS.size(), DUMMY_COUNT, "and each has somewhere to be shot from")


func test_every_dummy_can_be_shot_from_the_route() -> void:
	await wait_physics_frames(30)
	for dummy_name: String in FIRING_POINTS:
		var dummy: Dummy = _course.get_node(dummy_name)
		var from := _course.to_global(FIRING_POINTS[dummy_name])
		var chest: Vector3 = (dummy.get_node("Body") as RigidBody3D).global_position + Vector3.UP * 0.25
		Ballistics.pool.fire_bullet(NINE, from, from.direction_to(chest) * 370.0)
		await wait_physics_frames(8)
		assert_lt(dummy.health, dummy.max_health, dummy_name + " hit")


func test_course_is_clear_of_the_steel_lanes() -> void:
	for child: Node in _course.get_children():
		if child is Node3D and child.name != "ClimbLip":
			assert_gt((child as Node3D).global_position.x, 7.0, child.name)


func test_the_route_can_be_walked_and_jumped_to_the_last_wall() -> void:
	await _walk_to(1.2, -4.5)
	await _walk_to(-1.2, -5.0)
	await _walk_to(-1.2, -8.0)
	await _walk_to(0.0, -11.5)
	await _walk_to(0.0, -16.5)
	assert_almost_eq(_player.global_position.y, 1.5, 0.15, "walked up the ramp onto the deck")

	# Walk off the far edge of the deck with a jump, at walking speed.
	_left.set_input(&"primary", Vector2(0, 1))
	while _course.to_local(_player.global_position).z > -20.2:
		await get_tree().physics_frame
	_right.set_input(&"jump", true)
	await wait_physics_frames(2)
	_right.set_input(&"jump", false)
	await wait_physics_frames(30)
	while _course.to_local(_player.global_position).z > -24.0:
		await get_tree().physics_frame
	assert_almost_eq(_player.global_position.y, 1.2, 0.15, "cleared the gap")

	await _walk_to(0.0, -32.0)
	assert_almost_eq(_player.global_position.y, 0.0, 0.1, "dropped into the alley")
	await _walk_to(3.5, -32.5)
	await _walk_to(6.4, -32.5)
	_left.set_input(&"primary", Vector2.ZERO)
	assert_almost_eq(_player.global_position.y, 0.0, 0.1, "at the foot of the last wall")


func test_the_last_wall_has_a_lip_a_hand_can_reach() -> void:
	var lip: StaticBody3D = _course.get_node("ClimbLip")
	assert_ne(lip.collision_layer & PhysicsHand.CLIMBABLE_LAYER, 0, "can be gripped")
	assert_between(lip.global_position.y, 1.8, 2.3, "and reached from the floor")
