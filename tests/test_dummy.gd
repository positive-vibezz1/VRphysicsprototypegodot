extends GutTest
## The test dummy on a real floor, shot with real bullets.

const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const RIFLE: CartridgeSpec = preload("res://weapons/parts/cartridge_556x45.tres")
const NINE_SPEED := 370.0
const RIFLE_SPEED := 890.0
const CHEST := Vector3(0.0, 1.0, 0.0)
const HEAD := Vector3(0.0, 1.58, 0.0)

var _dummy: Dummy
var _stand: RigidBody3D
var _body: RigidBody3D
var _head: RigidBody3D


func before_each() -> void:
	Ballistics.pool.clear()
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	_dummy = (load("res://sandbox/dummy.tscn") as PackedScene).instantiate()
	add_child_autofree(_dummy)
	_stand = _dummy.get_node("Stand")
	_body = _dummy.get_node("Body")
	_head = _dummy.get_node("Head")
	await wait_physics_frames(10)


## Shoots from 3 m in front, and waits for the bullet to get there.
func _shoot(cartridge: CartridgeSpec, at: Vector3, speed: float) -> void:
	Ballistics.pool.fire_bullet(cartridge, at + Vector3(0, 0, 3), Vector3(0, 0, -speed))
	await wait_physics_frames(6)


func _tilt() -> float:
	return rad_to_deg(_body.global_basis.y.angle_to(Vector3.UP))


func _damage_of(cartridge: CartridgeSpec, at: Vector3, speed: float) -> float:
	_dummy.health = _dummy.max_health
	await _shoot(cartridge, at, speed)
	return _dummy.max_health - _dummy.health


func test_stands_still_by_itself() -> void:
	await wait_physics_frames(180)
	assert_lt(_tilt(), 1.0, "stays upright")
	assert_almost_eq(_head.global_position, HEAD, Vector3.ONE * 0.02, "head stays on")
	assert_eq(_dummy.health, _dummy.max_health)


func test_body_hit_rocks_it_and_it_comes_back_to_rest() -> void:
	await _shoot(NINE, CHEST, NINE_SPEED)
	assert_lt(_dummy.health, _dummy.max_health, "hurt")
	assert_gt(_dummy.health, 0.0, "not down from one")
	var most := 0.0
	for i: int in 90:
		await wait_physics_frames(1)
		most = maxf(most, _tilt())
	gut.p("Rocked %.1f degrees from one 9 mm" % most)
	assert_between(most, 1.5, 15.0, "rocks visibly, and no further than a bullet's momentum can push it")
	await wait_physics_frames(630)
	assert_lt(_tilt(), 2.0, "the spring brings it back")
	assert_true(_body.sleeping, "and it goes to sleep")


func test_damage_comes_from_the_energy_of_the_bullet() -> void:
	var damage := await _damage_of(NINE, CHEST, NINE_SPEED)
	var energy := 0.5 * NINE.bullet_mass * NINE_SPEED * NINE_SPEED
	assert_almost_eq(damage, energy / _dummy.joules_per_health, 3.0)


func test_half_the_speed_does_a_quarter_of_the_damage() -> void:
	var fast := await _damage_of(NINE, CHEST, NINE_SPEED)
	var slow := await _damage_of(NINE, CHEST, NINE_SPEED * 0.5)
	assert_almost_eq(slow, fast * 0.25, fast * 0.05)


func test_rifle_takes_fewer_hits_than_pistol() -> void:
	var pistol := await _damage_of(NINE, CHEST, NINE_SPEED)
	var rifle := await _damage_of(RIFLE, CHEST, RIFLE_SPEED)
	assert_eq(ceili(_dummy.max_health / pistol), 4, "9 mm body hits")
	assert_eq(ceili(_dummy.max_health / rifle), 2, "5.56 mm body hits")


func test_glancing_hit_does_less_than_a_square_one() -> void:
	var square := await _damage_of(RIFLE, CHEST, RIFLE_SPEED)
	var glancing := await _damage_of(RIFLE, CHEST + Vector3(0.235, 0, 0), RIFLE_SPEED)
	assert_gt(glancing, 0.0, "it did hit")
	assert_lt(glancing, square * 0.7)


func test_head_hit_snaps_the_head_and_ends_it() -> void:
	await _shoot(NINE, HEAD, NINE_SPEED)
	assert_eq(_dummy.health, 0.0, "one is enough")
	await wait_physics_frames(5)
	assert_gt(rad_to_deg(_body.global_basis.y.angle_to(_head.global_basis.y)), 5.0, "the head snapped back")
	await wait_physics_frames(180)
	assert_gt(_tilt(), 60.0, "and it fell over")


func test_hitting_the_stand_does_no_damage() -> void:
	await _shoot(NINE, Vector3(0, 0.15, 0), NINE_SPEED)
	assert_eq(_dummy.health, _dummy.max_health)


func test_goes_down_at_zero_health_and_gets_back_up() -> void:
	for i: int in 4:
		await _shoot(NINE, CHEST, NINE_SPEED)
	assert_eq(_dummy.health, 0.0, "down after four")
	await wait_physics_frames(180)
	assert_gt(_tilt(), 60.0, "fell over")
	assert_lt(_head.global_position.y, 0.6, "and is lying on the floor")
	assert_lt(_stand.global_basis.y.angle_to(Vector3.UP), 0.2, "off a stand that stayed put")
	await _shoot(NINE, _body.global_position + Vector3(0, 0.1, 0), NINE_SPEED)
	assert_eq(_dummy.health, 0.0, "stays down while it is down")
	await wait_physics_frames(int(_dummy.recovery_time * Engine.physics_ticks_per_second))
	assert_eq(_dummy.health, _dummy.max_health, "healed")
	await wait_physics_frames(540)
	assert_lt(_tilt(), 5.0, "and the springs stood it back up")


func test_knocked_off_its_stand_it_comes_back_where_it_started() -> void:
	_body.apply_impulse(Vector3(0, 0, -300.0), Vector3(0, 0.3, 0))
	await wait_physics_frames(45)
	assert_gt(rad_to_deg(_stand.global_basis.y.angle_to(Vector3.UP)), 60.0, "over it goes")
	assert_eq(_dummy.health, 0.0, "and that puts it down")
	await wait_physics_frames(int(_dummy.recovery_time * Engine.physics_ticks_per_second))
	assert_eq(_dummy.health, _dummy.max_health, "healed")
	await wait_physics_frames(270)
	assert_lt(rad_to_deg(_stand.global_basis.y.angle_to(Vector3.UP)), 1.0, "stand is back up")
	assert_lt(_stand.global_position.distance_to(Vector3(0, 0.14, 0)), 0.02, "where it started")
	assert_lt(_tilt(), 5.0)


func test_momentum_goes_into_the_dummy() -> void:
	for part: RigidBody3D in [_stand, _body, _head]:
		part.gravity_scale = 0.0
	_dummy.global_position.y = 40.0
	await wait_physics_frames(2)
	await _shoot(NINE, CHEST + Vector3(0, 40, 0), NINE_SPEED)
	var got := _stand.linear_velocity * _stand.mass + _body.linear_velocity * _body.mass + _head.linear_velocity * _head.mass
	var momentum := NINE.bullet_mass * NINE_SPEED
	assert_almost_eq(got.z, -momentum, momentum * 0.25)
