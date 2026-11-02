extends GutTest
## The time trial west of the range: its gates start, split and finish a run in order, each section asks for the way of
## moving it's named for and no more than the player can do, and the walking half can be run with the sticks.

const LEFT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(-0.2, 1.1, -0.2))
const RIGHT_REST := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.2, 1.1, -0.2))
const BEST_PATH := "user://test_time_trial.cfg"
## How far a hand reaches past the one holding on, climbing.
const REACH := 0.8

var _left: XRControllerTracker
var _right: XRControllerTracker
var _range: Node3D
var _player: Player
var _trial: TimeTrial
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func before_each() -> void:
	DirAccess.remove_absolute(BEST_PATH)
	_left = _tracker(&"left_hand", LEFT_REST)
	_right = _tracker(&"right_hand", RIGHT_REST)
	_range = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	_trial = _range.get_node("TimeTrial")
	_trial.best_path = BEST_PATH
	add_child_autofree(_range)
	_player = _range.get_node("Player")
	_set_pose(_left, LEFT_REST)
	_set_pose(_right, RIGHT_REST)


func after_each() -> void:
	XRServer.remove_tracker(_left)
	XRServer.remove_tracker(_right)
	DirAccess.remove_absolute(BEST_PATH)


func _tracker(tracker_name: StringName, pose: Transform3D) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = tracker_name
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	_set_pose(tracker, pose)
	return tracker


func _set_pose(tracker: XRControllerTracker, pose: Transform3D) -> void:
	tracker.set_pose(&"grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _gate(gate_name: String) -> TrialGate:
	return _trial.get_node("Gates/" + gate_name)


func _part(part_name: String) -> Node3D:
	return _trial.get_node(part_name)


## Top of a block, in the course's space.
func _top(block_name: String) -> float:
	var block := _part(block_name)
	return block.position.y + (block.get("size") as Vector3).y * 0.5


## Puts the player on the floor of a gate's box, which is the ground or the top of what it stands on.
func _stand_in(gate_name: String) -> void:
	var gate := _gate(gate_name)
	_player.global_position = gate.global_position + Vector3.DOWN * (gate.size.y * 0.5 - 0.05)
	_player.linear_velocity = Vector3.ZERO
	await wait_physics_frames(3)


func _leave_the_start() -> void:
	await _stand_in("Start")
	_player.global_position += Vector3(-3, 0, 0)
	await wait_physics_frames(3)


func test_a_run_goes_from_the_start_through_every_checkpoint_to_the_finish() -> void:
	await _stand_in("Start")
	assert_false(_trial.running, "standing in the start box")
	await _leave_the_start()
	assert_true(_trial.running, "leaving it starts the clock")
	var gates := _trial.get_node("Gates").get_children()
	for gate: Node in gates.slice(1):
		await wait_physics_frames(9)
		await _stand_in(gate.name)
	assert_false(_trial.running, "stopped at the finish")
	assert_eq(_trial.splits.size(), gates.size() - 1, "a split for each section")
	var total := 0.0
	for split: float in _trial.splits:
		assert_gt(split, 0.1, "each took its time")
		total += split
	assert_almost_eq(total, _trial.time, 0.001, "and they add up to the run")
	assert_almost_eq(_trial.best_time, _trial.time, 0.0001, "the first run is the best yet")
	var config := ConfigFile.new()
	assert_eq(config.load(BEST_PATH), OK, "kept for next time")
	assert_almost_eq(config.get_value("best", "time", 0.0) as float, _trial.time, 0.0001)
	assert_almost_eq(config.get_value("best", "SPRINT", 0.0) as float, _trial.splits[0], 0.0001)


func test_checkpoints_only_count_in_order() -> void:
	await _leave_the_start()
	await _stand_in("Jumps")
	assert_eq(_trial.splits.size(), 0, "skipping ahead doesn't count")
	await _stand_in("Sprint")
	assert_eq(_trial.splits.size(), 1, "the next one does")
	await _stand_in("Finish")
	assert_true(_trial.running, "and the finish needs all of them")


func test_walking_back_into_the_start_calls_the_run_off() -> void:
	await _leave_the_start()
	await _stand_in("Sprint")
	await _stand_in("Start")
	assert_false(_trial.running, "called off")
	_player.global_position += Vector3(-3, 0, 0)
	await wait_physics_frames(3)
	assert_true(_trial.running, "and the next run starts")
	assert_eq(_trial.runs, 2)
	assert_eq(_trial.splits.size(), 0, "from scratch")


func test_the_course_overlaps_nothing_else_in_the_range() -> void:
	await wait_physics_frames(2)
	var ours: Array[RID] = [(_range.get_node("Floor") as StaticBody3D).get_rid()]
	for child: Node in _trial.get_children():
		if child is CollisionObject3D:
			ours.append((child as CollisionObject3D).get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.exclude = ours
	var space := _player.get_world_3d().direct_space_state
	for child: Node in _trial.get_children():
		for shape: Node in child.get_children():
			if child is StaticBody3D and shape is CollisionShape3D:
				query.shape = (shape as CollisionShape3D).shape
				query.transform = (shape as CollisionShape3D).global_transform
				assert_eq(space.intersect_shape(query, 1).size(), 0, child.name + " is clear")


func test_the_grapple_only_catches_the_purple_anchors() -> void:
	var anchors: Array[String] = []
	var grapple_layers := (_player.get_node("RightGrapple") as Grapple).collision_mask
	for child: Node in _trial.get_children():
		if child is StaticBody3D and (child as StaticBody3D).collision_layer & grapple_layers:
			anchors.append(child.name)
	assert_eq(anchors, ["SwingBeam", "HaulBeam", "Hook"] as Array[String])


func test_slopes_and_steps_are_what_the_legs_can_and_cant_do() -> void:
	for i: int in range(1, 7):
		var rise := _top("Step%d" % i) - (_top("Step%d" % (i - 1)) if i > 1 else 0.0)
		assert_lt(rise, 0.25, "step %d is stepped up" % i)
	assert_lt(_part("Ramp").global_basis.y.angle_to(Vector3.UP), _player.floor_max_angle, "the ramp can be walked up")
	var slide := _part("Slide").global_basis.y.angle_to(Vector3.UP)
	assert_gt(slide, _player.floor_max_angle, "the slide is too steep to stand on")


func test_the_jumps_take_a_walk_a_good_walk_and_a_run() -> void:
	var air_time := 2.0 * _player.jump_speed / _gravity
	var walk := _player.move_speed * air_time
	var run := _player.sprint_speed * air_time
	var gaps: Array[float] = []
	var blocks: Array[String] = ["RampTop", "Hop1", "Hop2", "Hop3"]
	for i: int in 3:
		var near := _part(blocks[i])
		var far := _part(blocks[i + 1])
		var near_edge := near.position.z - (near.get("size") as Vector3).z * 0.5
		gaps.append(near_edge - (far.position.z + (far.get("size") as Vector3).z * 0.5))
		assert_almost_eq(_top(blocks[i + 1]), _top(blocks[i]), 0.01, blocks[i + 1] + " is level")
	assert_lt(gaps[0], walk - 0.8, "the first is an easy walk")
	assert_lt(gaps[1], walk, "the second can be walked")
	assert_gt(gaps[2], walk + 0.5, "the third can't")
	assert_lt(gaps[2], run - 0.2, "but can be run")
	assert_gt((_part("Hop1").get("size") as Vector3).z, run - gaps[0], "a run at the first doesn't overshoot")


func test_the_ladder_and_bars_are_within_reach() -> void:
	var tower_top := _top("LadderTower")
	var rung := 0.0
	for i: int in range(1, 11):
		var height := _part("Rung%d" % i).position.y
		assert_lt(height - rung, 0.45, "rung %d is a step up" % i)
		rung = height
	assert_between(tower_top - rung, 0.0, 0.4, "the top rung is close enough to the top to mantle from")
	var bars: Array[Node3D] = []
	for child: Node in _trial.get_children():
		if child.name.begins_with("Bar") and not child.name.begins_with("BarRail") and child.name != "BarTower":
			bars.append(child as Node3D)
	assert_between(bars[0].position.y - tower_top, 1.6, 2.0, "the bars are an overhead reach from the tower top")
	for i: int in range(1, bars.size()):
		assert_lt(absf(bars[i].position.x - bars[i - 1].position.x), 0.5, bars[i].name + " is a hand's reach on")
	var near := _part("LadderTower")
	var far := _part("BarTower")
	assert_lt(bars[0].position.x, near.position.x + 1.0, "they start over the ladder tower")
	assert_gt(bars[-1].position.x, far.position.x - 1.0, "and end over the next")


func test_the_rock_wall_has_one_way_up_and_needs_the_traverse() -> void:
	var holds: Array[Node3D] = []
	for child: Node in _trial.get_children():
		if child.name.begins_with("Crevice"):
			holds.append(child as Node3D)
	assert_lt(holds[0].position.y, 1.3, "the first hold is in reach from the ground")
	for i: int in range(1, holds.size()):
		var nearest := INF
		for j: int in i:
			nearest = minf(nearest, holds[i].position.distance_to(holds[j].position))
		assert_lt(nearest, REACH, holds[i].name + " can be reached from a hold below it")
	var lip := _part("RockLip")
	var lip_size: Vector3 = lip.get("size")
	var lip_nearest := func(hold: Node3D) -> float:
		var along := clampf(hold.position.z, lip.position.z - lip_size.z * 0.5, lip.position.z + lip_size.z * 0.5)
		return hold.position.distance_to(Vector3(lip.position.x, lip.position.y, along))
	assert_lt(lip_nearest.call(holds[-1]) as float, REACH, "the lip is in reach from the last hold")
	for hold: Node3D in holds.slice(0, 8):
		assert_gt(lip_nearest.call(hold) as float, REACH * 1.5, hold.name + " is too far from the lip to skip the traverse")
	assert_almost_eq(lip.position.y + lip_size.y * 0.5, _top("Rock"), 0.02, "the lip is at the top")


func test_each_grapple_anchor_is_in_range_and_the_swing_clears_the_ground() -> void:
	var grapple: Grapple = _player.get_node("RightGrapple")
	var hand_height := 1.2
	var beam := _part("SwingBeam").position
	var rock := _part("Rock")
	var from := Vector3(rock.position.x + 2.0, _top("Rock") + hand_height, rock.position.z)
	var cable := from.distance_to(beam)
	assert_lt(cable, grapple.max_range, "the swing beam is in range from the rock")
	assert_gt(beam.y - cable, 1.8, "the lowest point of the swing leaves the feet off the ground")
	assert_lt(_top("SwingTower"), _top("Rock"), "and it lands lower than it set off")
	var past := _part("SwingTower").position.x - 2.0 - beam.x
	assert_lt(past, beam.x - from.x + 0.01, "and no further past the beam than it set off before it")
	var haul_from := _part("SwingTower").position + Vector3(2, _top("SwingTower") + hand_height, 0)
	assert_lt(haul_from.distance_to(_part("HaulBeam").position), grapple.max_range, "the haul beam is in range")
	assert_gt(_part("HaulBeam").position.y, _top("HaulTower") + 2.5, "and high enough over its tower to haul onto it")
	var drop_from := _part("HaulTower").position + Vector3(0, _top("HaulTower") + hand_height, 0)
	var hook := _part("Hook").position
	assert_lt(drop_from.distance_to(hook), grapple.max_range, "the hook is in range")
	assert_gt(hook.y - drop_from.distance_to(hook), 1.8, "and swinging from it clears the ground")


## Steers the left stick at a spot on the course's floor plan until the player is there.
func _walk_to(x: float, z: float) -> void:
	var target := _trial.to_global(Vector3(x, 0, z))
	for i: int in 1500:
		var to := target - _player.global_position
		to.y = 0.0
		if to.length() < 0.3:
			return
		var direction := to.normalized()
		_left.set_input(&"primary", Vector2(direction.x, -direction.z))
		await get_tree().physics_frame
	fail_test("never got to %s, stuck at %s" % [Vector2(x, z), _trial.to_local(_player.global_position)])


func _here() -> Vector3:
	return _trial.to_local(_player.global_position)


## Heads south (-Z) and jumps once past a line, then waits to come down.
func _jump_south_at(z: float) -> void:
	await _head_south_past(z)
	_right.set_input(&"jump", true)
	await wait_physics_frames(2)
	_right.set_input(&"jump", false)
	await wait_physics_frames(60)


func _head_south_past(z: float) -> void:
	_left.set_input(&"primary", Vector2(0, 1))
	for i: int in 300:
		if _here().z <= z:
			return
		await get_tree().physics_frame
	fail_test("never got past %.2f, stuck at %s" % [z, _here()])


func _swing_arms_up(distance: float, ticks: int) -> void:
	for i: int in ticks:
		var rise := Vector3.UP * distance * (i + 1.0) / ticks
		_set_pose(_left, LEFT_REST.translated(rise))
		_set_pose(_right, RIGHT_REST.translated(rise))
		await wait_physics_frames(1)


func test_the_walking_half_can_be_run_with_the_sticks() -> void:
	await _stand_in("Start")
	await _walk_to(-31.0, 10.0)
	assert_eq(_trial.splits.size(), 1, "sprint")

	# Through the slalom.
	var slalom: Array[Vector2] = [
		Vector2(-32.5, 11.3), Vector2(-35.5, 11.3), Vector2(-37.0, 8.7), Vector2(-39.5, 8.7), Vector2(-41.0, 11.3),
		Vector2(-43.5, 11.3), Vector2(-44.1, 8.7), Vector2(-49.0, 8.7), Vector2(-51.0, 10.0),
	]
	for waypoint: Vector2 in slalom:
		await _walk_to(waypoint.x, waypoint.y)
	assert_eq(_trial.splits.size(), 2, "slalom")

	await _walk_to(-54.0, 7.0)
	await _walk_to(-54.0, 1.4)
	await _walk_to(-54.0, -4.5)
	assert_almost_eq(_here().y, 2.6, 0.1, "up the steps and the ramp")
	assert_eq(_trial.splits.size(), 3, "steps")

	# The jumps at a run.
	_left.set_input(&"primary", Vector2(0, 1))
	_left.set_input(&"sprint", true)
	await wait_physics_frames(2)
	_left.set_input(&"sprint", false)
	await _jump_south_at(-6.2)
	assert_almost_eq(_here().y, 2.6, 0.1, "made the first gap")
	await _jump_south_at(-10.75)
	assert_almost_eq(_here().y, 2.6, 0.1, "made the second gap")
	await _jump_south_at(-19.2)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(60)
	assert_almost_eq(_here().y, 2.6, 0.1, "made the long jump")
	assert_eq(_trial.splits.size(), 4, "jumps")

	# A plain jump falls short of the swing wall, and swinging the arms up gets onto it.
	# Both take off two steps out, since the body keeps going forward as it rises.
	await _walk_to(-54.0, -24.0)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(30)
	await _jump_south_at(-25.4)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(60)
	assert_almost_eq(_here().y, 2.6, 0.1, "a plain jump doesn't make it")
	await _walk_to(-54.0, -24.0)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(30)
	await _head_south_past(-25.0)
	await _swing_arms_up(0.4, 10)
	_right.set_input(&"jump", true)
	await wait_physics_frames(90)
	_right.set_input(&"jump", false)
	_left.set_input(&"primary", Vector2.ZERO)
	_set_pose(_left, LEFT_REST)
	_set_pose(_right, RIGHT_REST)
	await wait_physics_frames(30)
	assert_almost_eq(_here().y, 3.8, 0.1, "a swing jump does")
	assert_eq(_trial.splits.size(), 5, "swing jump")

	# Down the slide to the foot of the ladder.
	await _walk_to(-44.0, -28.5)
	_left.set_input(&"primary", Vector2.ZERO)
	await wait_physics_frames(60)
	assert_almost_eq(_here().y, 0.0, 0.05, "slid down to the ladder")
