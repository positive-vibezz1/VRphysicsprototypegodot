extends GutTest
## Bullet and casing bodies in the real physics server.

const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const RIFLE: CartridgeSpec = preload("res://weapons/parts/cartridge_556x45.tres")


func before_each() -> void:
	Ballistics.pool.clear()


func _wall(at: Vector3, thickness: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, thickness)
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = at
	return wall


func test_drag_matches_the_closed_form() -> void:
	var factor := 0.5 * Bullet.AIR_DENSITY * NINE.drag_coefficient * NINE.bore_area() / NINE.bullet_mass
	var speed := 360.0
	for i: int in 90:
		speed = Bullet.drag_speed(speed, factor, 1.0 / 90.0)
	assert_almost_eq(speed, 360.0 / (1.0 + factor * 360.0 * 1.0), 0.01)
	# 9 mm tables lose about 90 m/s over the first 300 m, about one second of flight.
	assert_between(speed, 235.0, 290.0)


func test_rifle_bullet_keeps_its_speed_on_launch() -> void:
	var bullet := Ballistics.pool.fire_bullet(RIFLE, Vector3(0, 50, 0), Vector3(0, 0, -900))
	await wait_physics_frames(3)
	# M855 tables lose about 100 m/s per 100 m, and Jolt's default 500 m/s limit must not clamp it.
	assert_between(bullet.linear_velocity.length(), 850.0, 885.0)
	assert_lt(bullet.global_position.z, -20.0)


func test_bullet_slows_down_in_flight() -> void:
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(0, 50, 0), Vector3(0, 0, -360))
	await wait_physics_frames(45)
	assert_between(bullet.linear_velocity.length(), 265.0, 325.0)


func test_rifle_bullet_does_not_tunnel_through_a_thin_wall() -> void:
	_wall(Vector3(0, 60, -25), 0.01)
	var bullet := Ballistics.pool.fire_bullet(RIFLE, Vector3(0, 60, 0), Vector3(0, 0, -900))
	await wait_physics_frames(10)
	assert_eq(bullet.process_mode, Node.PROCESS_MODE_DISABLED, "stopped and went back in the pool")
	assert_gt(bullet.global_position.z, -26.0, "stopped at the wall")


func test_bullet_gives_its_momentum_to_a_loose_target() -> void:
	var target := RigidBody3D.new()
	target.collision_layer = 512
	# A body only gets pushed by layers in its own mask.
	target.collision_mask = 64
	target.gravity_scale = 0.0
	target.mass = 2.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.05)
	shape.shape = box
	target.add_child(shape)
	add_child_autofree(target)
	target.global_position = Vector3(0, 70, -5)
	await wait_physics_frames(2)
	Ballistics.pool.fire_bullet(NINE, Vector3(0, 70, 0), Vector3(0, 0, -360))
	await wait_physics_frames(6)
	var momentum := NINE.bullet_mass * 360.0
	assert_almost_eq(target.linear_velocity.length() * target.mass, momentum, momentum * 0.25)
	assert_lt(target.linear_velocity.z, 0.0, "pushed away from the shooter")


func test_casing_pool_gives_real_mass_and_keeps_going_round() -> void:
	var first := Ballistics.pool.eject_casing(NINE, Vector3(0, 80, 0), Basis.IDENTITY, Vector3(1, 0, 0), Vector3.ZERO, false)
	assert_almost_eq(first.mass, NINE.casing_mass, 1.0e-6)
	var live := Ballistics.pool.eject_casing(RIFLE, Vector3(1, 80, 0), Basis.IDENTITY, Vector3(1, 0, 0), Vector3.ZERO, true)
	assert_almost_eq(live.mass, RIFLE.round_mass, 1.0e-6)
	for i: int in Ballistics.CASING_COUNT:
		assert_not_null(Ballistics.pool.eject_casing(NINE, Vector3(2, 80, 0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, false))
