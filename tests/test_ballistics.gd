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
	var factor := 0.5 * Medium.ambient.density * NINE.drag_coefficient * NINE.bore_area() / NINE.bullet_mass
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(-20, 500, 0), Vector3(0, 0, -360))
	await wait_physics_frames(90)
	var speed := bullet.linear_velocity.length()
	assert_almost_eq(speed, 360.0 / (1.0 + factor * 360.0 * 1.0), 4.0)
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


func test_bullet_falls_under_gravity_as_it_flies() -> void:
	var from := Vector3(10, 500, 0)
	var bullet := Ballistics.pool.fire_bullet(NINE, from, Vector3(0, 0, -360))
	await wait_physics_frames(45)
	# Half a second: 1.2 m by g t^2 / 2. A tick either way is 10 cm of that.
	assert_almost_eq(from.y - bullet.global_position.y, 1.2, 0.15)
	# Under the 4.9 m/s of a fall in a vacuum, since drag works against the fall too: g (1 - exp(-k v t)) / (k v), with k v about 0.4/s.
	assert_almost_eq(bullet.linear_velocity.y, -4.43, 0.3)
	assert_almost_eq(bullet.global_position.x, from.x, 0.001, "nothing pushes it sideways")
	# Slowing from 360 to about 295 m/s over that time, so short of the 180 m it would go at muzzle speed.
	assert_between(-bullet.global_position.z, 140.0, 170.0)


func test_a_bullet_takes_time_to_arrive_and_gets_there_lower_and_slower() -> void:
	var from := Vector3(20, 500, 0)
	var wall := _wall(Vector3(20, 500, -50), 0.2)
	var hits: Array[float] = []
	var count := func(collider: Object, energy: float) -> void:
		if collider == wall:
			hits.append(energy)
	Ballistics.pool.bullet_hit.connect(count)
	var bullet := Ballistics.pool.fire_bullet(NINE, from, Vector3(0, 0, -360))
	# 50 m at about 350 m/s is 0.14 s, or 13 ticks.
	await wait_physics_frames(9)
	assert_eq(hits.size(), 0, "still in the air")
	assert_gt(bullet.global_position.z, -50.0)
	await wait_physics_frames(8)
	Ballistics.pool.bullet_hit.disconnect(count)
	assert_eq(hits.size(), 1, "and now it has arrived")
	assert_almost_eq(from.y - bullet.global_position.y, 0.10, 0.03, "about 10 cm low")
	var muzzle_energy := 0.5 * NINE.bullet_mass * 360.0 * 360.0
	assert_lt(hits[0], muzzle_energy, "with less than it left the muzzle with")
	assert_gt(hits[0], muzzle_energy * 0.8)


func test_the_tracer_trails_the_bullet_from_the_muzzle() -> void:
	var from := Vector3(30, 500, 0)
	var bullet := Ballistics.pool.fire_bullet(NINE, from, Vector3(0, 0, -360))
	var tracer: Node3D = bullet.get_node("Tracer")
	var mesh: MeshInstance3D = tracer.get_node("Mesh")
	var bounds: AABB = mesh.transform * mesh.mesh.get_aabb()
	assert_almost_eq(bounds.position.z, 0.0, 0.001, "starts at the bullet")
	assert_almost_eq(bounds.end.z, 1.0, 0.001, "and runs back from it")
	assert_lt(tracer.scale.z, 0.1, "barely out of the muzzle")
	var forward := Vector3.FORWARD
	for i: int in 6:
		# As rendered: after the physics of this frame, so the streak and the bullet's position go together.
		await get_tree().process_frame
		var tail := tracer.global_position + tracer.global_basis.z.normalized() * tracer.scale.z
		assert_gte((tail - from).dot(forward), -Bullet.MIN_TRACER_LENGTH - 0.001, "the streak stays in front of the gun")
		assert_almost_eq(tracer.global_position.distance_to(bullet.global_position), 0.0, 0.001, "and nothing is drawn ahead of the bullet")
	assert_almost_eq(tracer.scale.z, bullet.linear_velocity.length() / 90.0, 0.1, "then covers the path of one tick")


func test_the_tracer_looks_the_same_width_from_any_distance() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(40, 500, 0)
	camera.make_current()
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(40, 500, -1), Vector3(0, 0, -360))
	await wait_physics_frames(10)
	var distance := bullet.global_position.distance_to(camera.global_position)
	assert_gt(distance, 30.0)
	# Set by the near end a tick ago, and each tick is 4 m.
	assert_almost_eq((bullet.get_node("Tracer") as Node3D).scale.x, (distance - 8.0) * bullet.tracer_angle, 4.5 * bullet.tracer_angle)


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


func test_bullet_reports_the_energy_the_contact_took_out_of_it() -> void:
	var wall := _wall(Vector3(0, 65, -5), 0.1)
	watch_signals(Ballistics.pool)
	Ballistics.pool.fire_bullet(NINE, Vector3(0, 65, 0), Vector3(0, 0, -360))
	await wait_physics_frames(6)
	var hit: Array = get_signal_parameters(Ballistics.pool, "bullet_hit")
	assert_eq(hit[0], wall)
	# Drag takes a little over 5 m, and the rest goes into the wall.
	var energy := 0.5 * NINE.bullet_mass * 360.0 * 360.0
	assert_between(hit[1] as float, energy * 0.95, energy)


func test_casing_pool_gives_real_mass_and_keeps_going_round() -> void:
	var first := Ballistics.pool.eject_casing(NINE, Vector3(0, 80, 0), Basis.IDENTITY, Vector3(1, 0, 0), Vector3.ZERO, false)
	assert_almost_eq(first.mass, NINE.casing_mass, 1.0e-6)
	var live := Ballistics.pool.eject_casing(RIFLE, Vector3(1, 80, 0), Basis.IDENTITY, Vector3(1, 0, 0), Vector3.ZERO, true)
	assert_almost_eq(live.mass, RIFLE.round_mass, 1.0e-6)
	for i: int in Ballistics.CASING_COUNT:
		assert_not_null(Ballistics.pool.eject_casing(NINE, Vector3(2, 80, 0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, false))
