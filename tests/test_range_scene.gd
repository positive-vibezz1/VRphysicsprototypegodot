extends GutTest
## The main scene end to end, with fake controllers standing in for the headset.

const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
## Raked like a wrist on a pistol grip, so a gun held this way points level.
const AIM_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0.309017, 0.951057), Vector3(0, -0.951057, 0.309017))

var _range: Node3D


func before_each() -> void:
	_range = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(_range)


func test_range_loads_and_settles() -> void:
	var pistol: Gun = _range.get_node("Pistol")
	var ar: Gun = _range.get_node("AR")
	await wait_physics_frames(90)
	assert_gt(pistol.frame.global_position.y, 0.85, "pistol stayed on the table")
	assert_gt(ar.frame.global_position.y, 0.85, "AR stayed on the table")
	assert_lt(pistol.frame.linear_velocity.length(), 0.2)
	assert_lt(ar.frame.linear_velocity.length(), 0.2)
	assert_eq(pistol.chamber, Gun.Chamber.LIVE)
	assert_eq(ar.chamber, Gun.Chamber.LIVE)


func test_pick_up_the_pistol_and_hit_a_steel_plate() -> void:
	var pistol: Gun = _range.get_node("Pistol")
	var hand: PhysicsHand = _range.get_node("Player/RightHand")
	var plate: RigidBody3D = _range.get_node("Steel10m/Plate")
	await wait_physics_frames(30)

	hand.set_target(Transform3D(LEVEL_GRIP, pistol.grip.global_position + Vector3(0, 0.08, 0)))
	await wait_physics_frames(10)
	hand.input_grip = 1.0
	await wait_physics_frames(3)
	assert_eq(hand.held, pistol.grip, "picked up off the table")

	# Raise it and aim at the plate. The muzzle sits above the palm, so aim from where it really is.
	var palm := Vector3(0.1, 1.3, -0.3)
	await _move(hand, Transform3D(AIM_GRIP, palm))
	await wait_physics_frames(20)
	var aim_error := pistol.muzzle.global_position.direction_to(plate.global_position)
	var aim_basis := Basis.looking_at(aim_error) * AIM_GRIP
	await _move(hand, Transform3D(aim_basis, palm), 20)
	await wait_physics_frames(45)
	var off_target := (-pistol.frame.global_basis.z).angle_to(pistol.muzzle.global_position.direction_to(plate.global_position))
	assert_lt(rad_to_deg(off_target), 2.0, "pointing at the plate")

	hand.input_trigger = 1.0
	await wait_physics_frames(2)
	hand.input_trigger = 0.0
	assert_eq(pistol.mag_well.magazine.count, _capacity(pistol), "first shot was the chambered round")
	var hit := false
	for i: int in 30:
		await wait_physics_frames(1)
		hit = hit or plate.angular_velocity.length() > 0.3
	assert_true(hit, "plate swings from the bullet")
	assert_eq(pistol.chamber, Gun.Chamber.LIVE, "next round chambered")


func test_two_hands_can_swap_a_magazine() -> void:
	var pistol: Gun = _range.get_node("Pistol")
	var right: PhysicsHand = _range.get_node("Player/RightHand")
	var left: PhysicsHand = _range.get_node("Player/LeftHand")
	right.other_hand = left
	left.other_hand = right
	var spare: Magazine = _range.get_node("SpareMag9mm")
	await wait_physics_frames(30)

	right.set_target(Transform3D(LEVEL_GRIP, pistol.grip.global_position + Vector3(0, 0.08, 0)))
	await wait_physics_frames(10)
	right.input_grip = 1.0
	await wait_physics_frames(3)
	var palm := Vector3(0.2, 1.3, -0.3)
	await _move(right, Transform3D(AIM_GRIP, palm))
	await wait_physics_frames(20)

	# Drop the magazine with the button: gravity takes it out of the well.
	var old_mag := pistol.mag_well.magazine
	right.input_mag_release = true
	await wait_physics_frames(45)
	right.input_mag_release = false
	assert_null(pistol.mag_well.magazine, "old magazine fell out")
	assert_lt(old_mag.global_position.y, palm.y - 0.2, "and it is falling")

	# Take the spare off the table and bring it up under the well.
	left.set_target(Transform3D(LEVEL_GRIP, spare.grab_point.global_position + Vector3(0, 0.06, 0)))
	await wait_physics_frames(10)
	left.input_grip = 1.0
	await wait_physics_frames(3)
	assert_eq(left.held, spare.grab_point, "picked up the spare")
	var well := pistol.mag_well
	var below := well.global_position - well.global_basis.y * 0.25
	var offset := spare.global_position - spare.grab_point.global_position
	var hold_upright := well.global_basis * Basis(Vector3.RIGHT, PI * 0.5)
	await _move(left, Transform3D(hold_upright, below - offset), 60)
	await wait_physics_frames(20)

	# Push it up the well, far enough to seat it through the hand's lag.
	for i: int in 45:
		var depth := 0.25 - 0.3 * (float(i) / 45.0)
		left.set_target(Transform3D(hold_upright, well.global_position - well.global_basis.y * depth - offset))
		await wait_physics_frames(1)
	assert_eq(well.magazine, spare, "spare went in")
	assert_true(well.latched, "and latched")
	assert_null(left.held, "the hand lets go once it clicks in")


func _capacity(gun: Gun) -> int:
	return gun.mag_well.magazine.capacity


## Moves a hand at human speed: a controller never jumps, and a hand that falls too far behind lets go.
func _move(hand: PhysicsHand, to: Transform3D, ticks := 40) -> void:
	var from := hand.target
	for i: int in ticks:
		hand.set_target(from.interpolate_with(to, float(i + 1) / ticks))
		await wait_physics_frames(1)


func test_refresh_rate_snaps_to_a_known_value() -> void:
	assert_eq(Player._nearest_refresh_rate(89.7), 90)
	assert_eq(Player._nearest_refresh_rate(71.0), 72)
	assert_eq(Player._nearest_refresh_rate(143.0), 144)
