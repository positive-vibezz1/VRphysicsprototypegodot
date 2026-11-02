extends GutTest
## Bullet time: the meter, physics that comes out the same at any time scale, and hands that stay in real time.

const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
const SLOW := 0.1
const TICK := 1.0 / 90.0

var _shots := 0


## A dud stops a gun until it is racked, which would fail these tests at random. test_fire_control covers duds.
func before_all() -> void:
	(load("res://weapons/parts/cartridge_9x19.tres") as CartridgeSpec).dud_chance = 0.0
	(load("res://weapons/parts/cartridge_556x45.tres") as CartridgeSpec).dud_chance = 0.0


func before_each() -> void:
	_shots = 0
	Ballistics.pool.clear()


func after_each() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


func _meter() -> BulletTime:
	var meter := BulletTime.new()
	add_child_autofree(meter)
	return meter


func _run(meter: BulletTime, seconds: float) -> void:
	for i: int in int(seconds / TICK):
		meter.update(false, TICK)


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


func test_a_press_eases_time_down_and_another_eases_it_back() -> void:
	var meter := _meter()
	assert_true(meter.update(true, TICK), "the press does something")
	meter.update(false, TICK)
	assert_lt(Engine.time_scale, 1.0)
	assert_gt(Engine.time_scale, meter.slow_scale, "not all at once")
	_run(meter, meter.ramp_time)
	assert_almost_eq(Engine.time_scale, meter.slow_scale, 0.001)
	assert_almost_eq(AudioServer.playback_speed_scale, meter.slowest_sound, 0.001, "sound slows, but not as far")
	meter.update(true, TICK)
	meter.update(false, TICK)
	assert_false(meter.active)
	_run(meter, meter.ramp_time)
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(AudioServer.playback_speed_scale, 1.0)


func test_the_meter_runs_out_in_real_seconds_and_refills() -> void:
	var meter := _meter()
	meter.update(true, TICK)
	meter.update(false, TICK)
	_run(meter, meter.capacity - 0.1)
	assert_true(meter.active, "still going just before the meter is empty")
	assert_lt(meter.charge, 0.05)
	_run(meter, 0.2)
	assert_false(meter.active, "ran out")
	_run(meter, meter.ramp_time)
	assert_eq(Engine.time_scale, 1.0, "and time came back")
	_run(meter, meter.recharge_time * 0.5)
	assert_almost_eq(meter.charge, 0.5, 0.02)
	_run(meter, meter.recharge_time)
	assert_eq(meter.charge, 1.0)


func test_a_nearly_empty_meter_will_not_start() -> void:
	var meter := _meter()
	meter.charge = meter.least_charge * 0.5
	assert_false(meter.update(true, TICK))
	assert_false(meter.active)
	assert_eq(Engine.time_scale, 1.0)


func test_leaving_the_scene_puts_time_back() -> void:
	var meter := BulletTime.new()
	add_child(meter)
	meter.update(true, TICK)
	assert_lt(Engine.time_scale, 1.0)
	remove_child(meter)
	meter.free()
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(AudioServer.playback_speed_scale, 1.0)


func test_ticks_keep_their_rate_and_get_shorter() -> void:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.collision_layer = 0
	body.collision_mask = 0
	add_child_autofree(body)
	body.global_position = Vector3(0, 300, 0)
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var start := body.linear_velocity.y
	await wait_physics_frames(90)
	# A second of ticks is a tenth of a second of world time.
	assert_almost_eq(body.linear_velocity.y - start, -9.8 * SLOW, 0.05)


func test_a_bullet_flies_the_same_in_world_time() -> void:
	var normal := await _bullet_after(1.0, 0.5)
	var slowed := await _bullet_after(SLOW, 0.5)
	assert_almost_eq(slowed.x, normal.x, 3.0, "same speed")
	# A tick either way is 3.5 m at normal speed.
	assert_almost_eq(slowed.y, normal.y, 5.0, "same distance")


## Fires a 9 mm and returns its speed and how far it has gone after this long in world time.
func _bullet_after(time_scale: float, world_time: float) -> Vector2:
	Engine.time_scale = time_scale
	await wait_physics_frames(1)
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(50, 500, 0), Vector3(0, 0, -360))
	await wait_physics_frames(roundi(world_time / TICK / time_scale))
	var result := Vector2(bullet.linear_velocity.length(), -bullet.global_position.z)
	bullet.park()
	return result


func test_the_streak_shortens_with_the_distance_covered_per_frame() -> void:
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(60, 500, 0), Vector3(0, 0, -360))
	await wait_physics_frames(10)
	assert_almost_eq((bullet.get_node("Tracer") as Node3D).scale.z, 360.0 * SLOW * TICK, 0.02)
	bullet.park()


func test_recoil_is_the_same_size_in_slow_time_and_takes_longer() -> void:
	var normal := await _recoil(1.0, Vector3(70, 100, 0))
	var slowed := await _recoil(SLOW, Vector3(75, 100, 0))
	assert_eq(_shots, 2)
	assert_almost_eq(slowed.flip, normal.flip, normal.flip * 0.3, "same muzzle flip")
	assert_almost_eq(slowed.travel, normal.travel, normal.travel * 0.2, "same slide travel")
	assert_almost_eq(slowed.world_time, normal.world_time, TICK, "the peak comes at the same world time, within a normal tick")


## Peak muzzle flip in degrees, the most the slide ran back and when the flip peaked, in world time.
func _recoil(time_scale: float, at: Vector3) -> Dictionary:
	var pose := Transform3D(LEVEL_GRIP, at)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	hand.set_target(pose)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(40)
	Engine.time_scale = time_scale
	await wait_physics_frames(1)
	var aim := -gun.frame.global_basis.z
	var rest := gun.frame.to_local(gun.bolt.global_position).z
	hand.input_trigger = 1.0
	var flip := 0.0
	var travel := 0.0
	var peak_tick := 0
	var ticks := roundi(0.3 / TICK / time_scale)
	for i: int in ticks:
		await wait_physics_frames(1)
		if i == 1:
			hand.input_trigger = 0.0
		var angle := rad_to_deg(aim.angle_to(-gun.frame.global_basis.z))
		if angle > flip:
			flip = angle
			peak_tick = i
		travel = maxf(travel, gun.frame.to_local(gun.bolt.global_position).z - rest)
	hand.input_grip = 0.0
	Engine.time_scale = 1.0
	await wait_physics_frames(1)
	return {flip = flip, travel = travel, world_time = peak_tick * TICK * time_scale}


func test_hands_stay_on_the_controller_in_real_time() -> void:
	Engine.time_scale = SLOW
	var hand := _hand(Vector3(80, 100, 0))
	await wait_physics_frames(30)
	var pose := Transform3D(LEVEL_GRIP, Vector3(80, 100, 0))
	var worst := 0.0
	for i: int in 45:
		# 1 m/s of real time, whatever the world is doing.
		pose.origin.x += TICK
		hand.set_target(pose)
		await wait_physics_frames(1)
		if i > 15:
			worst = maxf(worst, (hand.global_position - pose.origin).length())
	assert_lt(worst, 0.03, "lags a 1 m/s move by under 3 cm, as it does at normal speed")


func test_a_held_gun_turns_with_the_wrist_in_real_time() -> void:
	var lag := await _turn_gun(Vector3(85, 100, 0), 4.0)
	assert_lt(lag.x, 0.15, "keeps up with 4 rad/s of real time")
	assert_lt(lag.y, 0.05, "and settles on it")


func test_a_wrist_past_the_spin_limit_falls_behind_and_catches_up_without_going_backward() -> void:
	var lag := await _turn_gun(Vector3(87, 100, 0), 8.0)
	assert_gt(lag.x, 0.15, "47 rad/s of world time is 4.7 rad/s of real time at this scale")
	assert_lt(lag.y, 0.15, "a real second after the wrist stops it has caught up")


## Turns a held pistol for a quarter second of real time, then stops. Returns how far it lagged at the end of the turn
## and a real second later, in radians.
func _turn_gun(at: Vector3, rate: float) -> Vector2:
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(40)
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var pose := Transform3D(LEVEL_GRIP, at)
	var start := gun.frame.global_basis
	var goal := Basis.IDENTITY
	for i: int in 23:
		goal = Basis(Vector3.UP, rate * TICK) * goal
		pose.basis = goal * LEVEL_GRIP
		hand.set_target(pose)
		await wait_physics_frames(1)
	var ended := _angle_between(goal * start, gun.frame.global_basis)
	await wait_physics_frames(90)
	assert_eq(hand.held, gun.grip)
	return Vector2(ended, _angle_between(goal * start, gun.frame.global_basis))


func _angle_between(a: Basis, b: Basis) -> float:
	return (a.inverse() * b).get_rotation_quaternion().get_angle()


func test_waving_a_gun_in_slow_time_does_not_cycle_it() -> void:
	var at := Vector3(90, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(40)
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var rest := gun.frame.to_local(gun.bolt.global_position).z
	var furthest := 0.0
	var worst_lag := 0.0
	var along := gun.frame.global_basis.z
	# Back and forth along the bore, 15 cm at 2 Hz: 24 m/s2, or 2400 m/s2 in world time, which as a force would slam the
	# slide open against its 40 N spring.
	for i: int in 60:
		var pose := Transform3D(LEVEL_GRIP, at + along * 0.15 * sin(TAU * 2.0 * i * TICK))
		hand.set_target(pose)
		await wait_physics_frames(1)
		furthest = maxf(furthest, gun.frame.to_local(gun.bolt.global_position).z - rest)
		worst_lag = maxf(worst_lag, (hand.global_position - pose.origin).length())
	assert_lt(furthest, Gun.BATTERY_TOLERANCE, "slide stays home")
	assert_eq(gun.chamber, Gun.Chamber.LIVE, "and the round stays in")
	assert_lt(worst_lag, 0.06)
	assert_eq(hand.held, gun.grip)


func test_two_hands_carry_and_swing_an_ar_in_real_time() -> void:
	var at := Vector3(95, 100, 0)
	var gun := _gun(AR_SCENE, at)
	var primary := _hand(at)
	await wait_physics_frames(2)
	_hold(primary, gun.grip)
	await wait_physics_frames(20)
	var support_at: Vector3 = (gun.frame.get_node("Handguard2") as Node3D).global_position
	var support := _hand(support_at)
	primary.other_hand = support
	support.other_hand = primary
	await wait_physics_frames(2)
	support.input_grip = 1.0
	await wait_physics_frames(30)
	assert_not_null(support.held)
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var primary_pose := primary.target
	var support_pose := support.target
	var rest := gun.frame.to_local(gun.bolt.global_position).z
	var furthest := 0.0
	var worst_lag := 0.0
	# Carried 30 cm sideways over half a second, the support hand lifting 15 cm on the way.
	for i: int in 45:
		var t := float(i + 1) / 45.0
		var sideways := Vector3(0.3 * t, 0, 0)
		primary.set_target(primary_pose.translated(sideways))
		support.set_target(support_pose.translated(sideways + Vector3(0, 0.15 * t, 0)))
		await wait_physics_frames(1)
		furthest = maxf(furthest, gun.frame.to_local(gun.bolt.global_position).z - rest)
		worst_lag = maxf(worst_lag, (primary.global_position - primary.target.origin).length())
		worst_lag = maxf(worst_lag, (support.global_position - (support.target * support._hold_offset).origin).length())
	assert_eq(primary.held, gun.grip, "kept hold")
	assert_not_null(support.held, "with both hands")
	assert_lt(worst_lag, 0.06)
	assert_lt(furthest, Gun.BATTERY_TOLERANCE, "bolt stays home")


func test_a_free_hand_can_still_rack_the_slide_in_slow_time() -> void:
	var at := Vector3(105, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var primary := _hand(at)
	await wait_physics_frames(2)
	_hold(primary, gun.grip)
	await wait_physics_frames(30)
	var grab_at := gun.bolt.global_position + gun.bolt.global_basis.z * 0.03
	var rack := _hand(grab_at)
	primary.other_hand = rack
	rack.other_hand = primary
	await wait_physics_frames(2)
	rack.input_grip = 1.0
	await wait_physics_frames(2)
	assert_not_null(rack.held, "took the slide")
	Engine.time_scale = SLOW
	await wait_physics_frames(1)
	var rest := gun.frame.to_local(gun.bolt.global_position).z
	var from := rack.target
	var furthest := 0.0
	for i: int in 25:
		rack.set_target(from.translated(gun.frame.global_basis.z * 0.1 * float(i + 1) / 25.0))
		await wait_physics_frames(1)
		furthest = maxf(furthest, gun.frame.to_local(gun.bolt.global_position).z - rest)
	assert_gt(furthest, gun.eject_travel, "the slide came back past the ejector")
	assert_eq(primary.held, gun.grip)
