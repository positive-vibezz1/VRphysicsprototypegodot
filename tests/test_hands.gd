extends GutTest
## Physics hands driven by a fake controller pose: tracking, weight, recoil and the two-handed AR.

const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _shots := 0


## A dud stops a gun until it is racked, which would fail these tests at random. test_fire_control covers duds.
func before_all() -> void:
	(load("res://weapons/parts/cartridge_9x19.tres") as CartridgeSpec).dud_chance = 0.0
	(load("res://weapons/parts/cartridge_556x45.tres") as CartridgeSpec).dud_chance = 0.0


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


func test_pistol_fires_pointing_straight_up_and_down() -> void:
	for pitch: float in [PI * 0.5, -PI * 0.5]:
		var at := Vector3(190 + pitch, 100, 0)
		var gun := _gun(PISTOL_SCENE, at)
		var hand := _hand(at)
		await wait_physics_frames(2)
		_hold(hand, gun.grip)
		await wait_physics_frames(2)
		var aimed := Basis(Vector3.RIGHT, pitch - deg_to_rad(18.0)) * LEVEL_GRIP
		for i: int in 40:
			hand.set_target(Transform3D(LEVEL_GRIP.slerp(aimed, float(i + 1) / 40.0), at))
			await wait_physics_frames(1)
		await wait_physics_frames(45)
		assert_lt(gun._rail.travel, gun.BATTERY_TOLERANCE, "slide stays in battery under its own weight")
		var before := _shots
		hand.input_trigger = 1.0
		await wait_physics_frames(3)
		hand.input_trigger = 0.0
		assert_eq(_shots, before + 1, "and it fires")
		hand.input_grip = 0.0
		await wait_physics_frames(1)


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
	var support_at: Vector3 = (gun.frame.get_node("Handguard2") as Node3D).global_position
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


func _peak_recoil(scene: PackedScene, at: Vector3) -> Dictionary:
	var pose := Transform3D(LEVEL_GRIP * Basis(Vector3.RIGHT, deg_to_rad(18.0)), at)
	var gun := _gun(scene, at)
	var hand := _hand(at)
	hand.set_target(pose)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(60)
	var start := gun.frame.global_position
	var forward := -gun.frame.global_basis.z
	var result := {"move": 0.0, "flip": 0.0, "peak_tick": 0}
	hand.input_trigger = 1.0
	for i: int in 30:
		await wait_physics_frames(1)
		hand.input_trigger = 0.0
		var moved := (gun.frame.global_position - start).length()
		if moved > result["move"]:
			result["move"] = moved
			result["peak_tick"] = i
		result["flip"] = maxf(result["flip"], rad_to_deg(forward.angle_to(-gun.frame.global_basis.z)))
	hand.input_grip = 0.0
	await wait_physics_frames(1)
	return result


func test_pistol_snaps_and_the_ar_shoves() -> void:
	var pistol := await _peak_recoil(PISTOL_SCENE, Vector3(110, 100, 0))
	var ar := await _peak_recoil(AR_SCENE, Vector3(120, 100, 0))
	assert_gt(pistol["flip"], ar["flip"] * 1.4, "the light pistol flips more")
	assert_gt(ar["move"], pistol["move"] * 1.3, "the heavy rifle comes back further")
	assert_lt(pistol["peak_tick"], ar["peak_tick"], "and the pistol kick is over sooner")


func test_a_heavy_gun_lags_behind_a_swing_more_than_a_light_one() -> void:
	var pistol_lag := await _swing_lag(PISTOL_SCENE, Vector3(130, 100, 0))
	var ar_lag := await _swing_lag(AR_SCENE, Vector3(140, 100, 0))
	assert_gt(pistol_lag, 0.002, "even the pistol lags a little")
	assert_gt(ar_lag, pistol_lag * 1.8, "the AR lags far more")
	assert_lt(ar_lag, 0.3, "without dropping out of the hand")


## Sweeps the hand 60 cm in a third of a second and returns how far it fell behind.
func _swing_lag(scene: PackedScene, at: Vector3) -> float:
	var gun := _gun(scene, at)
	var hand := _hand(at)
	await wait_physics_frames(2)
	_hold(hand, gun.grip)
	await wait_physics_frames(30)
	var worst := 0.0
	for i: int in 30:
		var t := float(i + 1) / 30.0
		var pose := Transform3D(LEVEL_GRIP, at + Vector3.RIGHT * 0.6 * t * t * (3.0 - 2.0 * t))
		hand.set_target(pose)
		await wait_physics_frames(1)
		worst = maxf(worst, (hand.global_position - pose.origin).length())
	hand.input_grip = 0.0
	await wait_physics_frames(1)
	return worst


func test_the_whole_hand_stops_at_a_table() -> void:
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 0.2, 2)
	shape.shape = box
	table.add_child(shape)
	add_child_autofree(table)
	table.global_position = Vector3(150, 100, 0)
	var top := 100.1
	# Fingers straight down: the fingertips reach about 11 cm below the palm.
	var fingers_down := Basis.IDENTITY
	var above := Vector3(150, top + 0.3, 0)
	var hand := _hand(above)
	hand.set_target(Transform3D(fingers_down, above))
	await wait_physics_frames(30)
	for i: int in 45:
		hand.set_target(Transform3D(fingers_down, above + Vector3.DOWN * 0.7 * (float(i + 1) / 45.0)))
		await wait_physics_frames(1)
	await wait_physics_frames(10)
	assert_gt(hand.global_position.y, top + 0.09, "fingertips stay on top of the table")
	assert_lt(hand.global_position.y, top + 0.16, "and the hand did come all the way down")


func test_pointing_at_a_gun_shows_a_laser_and_squeezing_brings_it() -> void:
	var at := Vector3(160, 100, 0)
	var gun := _gun(PISTOL_SCENE, at + Vector3(0, 0, -1.2))
	var hand := _hand(at)
	await wait_physics_frames(2)
	var laser: MeshInstance3D = hand.get_node("Laser")
	hand.aim_direction = at.direction_to(gun.grip.global_position)
	await wait_physics_frames(2)
	assert_eq(hand.remote_target, gun.grip, "picked out by pointing")
	assert_true(laser.visible, "laser shows")
	assert_almost_eq((laser.global_position - at).length(), at.distance_to(gun.grip.global_position) * 0.5, 0.02, "laser spans the gap")
	hand.input_grip = 1.0
	await wait_physics_frames(3)
	assert_eq(hand.held, gun.grip, "squeeze takes it")
	assert_almost_eq(gun.grip.global_position.distance_to(hand.global_position), 0.0, 0.03, "and it is in the hand")
	assert_false(laser.visible, "no laser while holding")


func test_no_laser_when_pointing_away_or_out_of_range() -> void:
	var at := Vector3(170, 100, 0)
	var gun := _gun(PISTOL_SCENE, at + Vector3(0, 0, -1.2))
	var far := _gun(PISTOL_SCENE, at + Vector3(2.5, 0, 0))
	var hand := _hand(at)
	await wait_physics_frames(2)
	hand.aim_direction = at.direction_to(gun.grip.global_position) * -1.0
	await wait_physics_frames(2)
	assert_null(hand.remote_target, "pointing the other way")
	hand.aim_direction = at.direction_to(far.grip.global_position)
	await wait_physics_frames(2)
	assert_null(hand.remote_target, "2.5 m away is too far")
	hand.input_grip = 1.0
	await wait_physics_frames(3)
	assert_null(hand.held, "squeezing at nothing picks nothing up")


func test_laser_does_not_offer_a_part_of_a_gun() -> void:
	var at := Vector3(180, 100, 0)
	var gun := _gun(PISTOL_SCENE, at + Vector3(0, 0, -1.2))
	var hand := _hand(at)
	var other := _hand(gun.grip.global_position)
	await wait_physics_frames(2)
	_hold(other, gun.grip)
	await wait_physics_frames(2)
	var slide: GrabPoint = gun.bolt.get_node("SlideGrab")
	hand.aim_direction = at.direction_to(slide.global_position)
	await wait_physics_frames(2)
	assert_ne(hand.remote_target, slide, "the slide needs a hand on it")


func test_support_hand_snaps_to_the_nearest_handguard_spot() -> void:
	var at := Vector3(200, 100, 0)
	var gun := _gun(AR_SCENE, at)
	var primary := _hand(at)
	await wait_physics_frames(2)
	_hold(primary, gun.grip)
	await wait_physics_frames(30)
	for spot: String in ["Handguard1", "Handguard2", "Handguard3"]:
		var point: GrabPoint = gun.frame.get_node(spot)
		assert_true(point.enabled, spot + " is open once the gun is held")
		var reach_from := point.global_position + Vector3(0.02, -0.03, 0.01)
		var support := _hand(reach_from)
		support.is_left = true
		primary.other_hand = support
		support.other_hand = primary
		await wait_physics_frames(2)
		var frame_before := gun.frame.global_position
		support.input_grip = 1.0
		await wait_physics_frames(2)
		assert_eq(support.held, point, "the hand takes " + spot)
		assert_almost_eq(support.global_position.distance_to(point.global_position), 0.0, 0.01, "palm centred on " + spot)
		assert_almost_eq(gun.frame.global_position.distance_to(frame_before), 0.0, 0.015, "the gun doesn't jump to the hand")
		await wait_physics_frames(45)
		assert_almost_eq(support.global_position.distance_to(point.global_position), 0.0, 0.01, "and stays centred")
		assert_lt(gun.frame.linear_velocity.length(), 0.1, "and nothing fights")
		support.input_grip = 0.0
		await wait_physics_frames(30)
		assert_almost_eq(support.global_position.distance_to(reach_from), 0.0, 0.03, "letting go, the hand goes back to the controller")
		support.queue_free()
		primary.other_hand = null
		await wait_physics_frames(1)


func test_the_fist_closes_around_the_grip_marker() -> void:
	# Where the fingers of each model close at the grips' closure, measured in the model.
	var tubes := {"right": Vector3(-0.025, -0.008, -0.073), "left": Vector3(0.025, -0.008, -0.073)}
	var axes := {"right": Vector3(0.105, 0.988, -0.111), "left": Vector3(-0.105, 0.988, -0.111)}
	for side: String in tubes:
		var model: Node3D = (load("res://player/hands/hand_%s.tscn" % side) as PackedScene).instantiate()
		assert_almost_eq((model.transform * (tubes[side] as Vector3)).length(), 0.0, 0.001, side + " fist centred on the palm pose")
		assert_gt((model.transform.basis * (axes[side] as Vector3).normalized()).dot(Vector3.FORWARD), 0.999, side + " fingers wrap around -Z")
		model.free()


func test_either_hand_can_take_a_support_spot() -> void:
	var gun: Gun = AR_SCENE.instantiate()
	add_child_autofree(gun)
	var point: GrabPoint = gun.frame.get_node("Handguard2")
	var left := point.palm_pose(true)
	var right := point.palm_pose(false)
	assert_almost_eq(left.origin.distance_to(right.origin), 0.0, 0.0001, "same place on the handguard")
	assert_almost_eq(left.basis.x.dot(right.basis.x), -1.0, 0.001, "palm up either way, so the axes turn over")
	assert_almost_eq(left.basis.z.dot(right.basis.z), 1.0, 0.001, "thumb forward either way")
	var pistol: Gun = PISTOL_SCENE.instantiate()
	add_child_autofree(pistol)
	var spot: GrabPoint = pistol.frame.get_node("Support")
	assert_almost_eq(spot.palm_pose(true).origin.x, -spot.palm_pose(false).origin.x, 0.0001, "the pistol spot mirrors to the other side")


func test_two_handing_the_pistol_steadies_it_without_softening_the_wrist() -> void:
	var one_hand := await _peak_recoil(PISTOL_SCENE, Vector3(210, 100, 0))
	var at := Vector3(220, 100, 0)
	var pose := Transform3D(LEVEL_GRIP * Basis(Vector3.RIGHT, deg_to_rad(18.0)), at)
	var gun := _gun(PISTOL_SCENE, at)
	var main := _hand(at)
	main.set_target(pose)
	await wait_physics_frames(2)
	_hold(main, gun.grip)
	await wait_physics_frames(45)
	var spot: GrabPoint = gun.frame.get_node("Support")
	var support := _hand(spot.global_position + Vector3(-0.03, 0, 0))
	support.is_left = true
	main.other_hand = support
	support.other_hand = main
	await wait_physics_frames(2)
	support.input_grip = 1.0
	await wait_physics_frames(45)
	assert_eq(support.held, spot, "second hand takes the spot over the main hand")
	assert_false(main._is_steered(), "a hand right by the grip doesn't take over the aim")
	var forward := -gun.frame.global_basis.z
	var flip := 0.0
	main.input_trigger = 1.0
	for i: int in 30:
		await wait_physics_frames(1)
		main.input_trigger = 0.0
		flip = maxf(flip, rad_to_deg(forward.angle_to(-gun.frame.global_basis.z)))
	assert_eq(_shots, 2, "both guns fired")
	assert_lt(flip, one_hand["flip"] * 0.85, "two hands flip it less than one")
	assert_gt(flip, 1.0, "but it still kicks")


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


func test_grabbing_makes_a_sound_of_the_glove_and_what_it_closed_on() -> void:
	var at := Vector3(84, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(50)
	var surfaces: Array[Sounds.Surface] = []
	var listener := func(surface: Sounds.Surface, _energy: float, _volume: float, _pitch: float) -> void:
		surfaces.append(surface)
	Sounds.pool.played.connect(listener)
	_hold(hand, gun.grip)
	Sounds.pool.played.disconnect(listener)
	assert_has(surfaces, Sounds.Surface.HAND)
	assert_has(surfaces, Sounds.Surface.GUN)


func _sounds_during(sounds: Array[Dictionary]) -> Callable:
	var listener := func(surface: Sounds.Surface, _energy: float, volume: float, pitch: float) -> void:
		sounds.append({"surface": surface, "volume": volume, "pitch": pitch})
	Sounds.pool.played.connect(listener)
	return listener


func test_a_grip_is_a_quiet_hand_on_the_whole_gun() -> void:
	var at := Vector3(88, 100, 0)
	var gun := _gun(PISTOL_SCENE, at)
	var hand := _hand(at)
	await wait_physics_frames(50)
	var sounds: Array[Dictionary] = []
	var listener := _sounds_during(sounds)
	_hold(hand, gun.grip)
	Sounds.pool.played.disconnect(listener)
	assert_eq(sounds.size(), 2, str(sounds))
	for sound: Dictionary in sounds:
		assert_lt(sound["volume"] as float, 0.1, "far under a shot")
		# Hand and pistol both about the masses their sounds are tuned for, not the fingers or just the frame.
		assert_between(sound["pitch"] as float, 0.9, 1.2)


func _slap(surface: Sounds.Surface, at: Vector3) -> Dictionary[Sounds.Surface, float]:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 2, 2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = at + Vector3(0.3, 0, 0)
	wall.set_meta(&"surface", surface)
	add_child_autofree(wall)
	var hand := _hand(at)
	await wait_physics_frames(50)
	var sounds: Array[Dictionary] = []
	var listener := _sounds_during(sounds)
	# A hard swing through the wall, at 5 m/s.
	var pose := Transform3D(LEVEL_GRIP, at)
	for i: int in 30:
		pose.origin.x += 5.0 / 90.0
		hand.set_target(pose)
		await wait_physics_frames(1)
	Sounds.pool.played.disconnect(listener)
	var loudest: Dictionary[Sounds.Surface, float] = {}
	for sound: Dictionary in sounds:
		var heard: Sounds.Surface = sound["surface"]
		loudest[heard] = maxf(loudest.get(heard, 0.0), sound["volume"] as float)
	return loudest


func test_a_hand_on_a_steel_bar_is_a_solid_knock_of_the_bar() -> void:
	var loudest := await _slap(Sounds.Surface.BAR, Vector3(92, 100, 0))
	assert_between(loudest.get(Sounds.Surface.BAR, 0.0), 0.05, 0.25, "the steel is what you hear, and not too loudly")
	assert_gt(loudest.get(Sounds.Surface.BAR, 0.0), loudest.get(Sounds.Surface.HAND, 0.0), "more than the hand on it")
	assert_gt(loudest.get(Sounds.Surface.HAND, 0.0), 0.01, "though there's a hand in it")


func test_a_hand_barely_rings_a_thin_plate_compared_to_a_steel_bar() -> void:
	var plate := await _slap(Sounds.Surface.METAL, Vector3(96, 100, 0))
	assert_lt(plate.get(Sounds.Surface.METAL, 0.0), 0.1, "a hand's too soft to set off its high modes")
