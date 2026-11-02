extends GutTest
## Drag and buoyancy on rigid bodies, and what the medium does to bullets.

const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const RIFLE: CartridgeSpec = preload("res://weapons/parts/cartridge_556x45.tres")
const WATER: Medium = preload("res://audio/water_medium.tres")
const THIN_AIR: Medium = preload("res://audio/thin_air_medium.tres")
## A 0.5 m cube shows 0.375 m2 on average, and Cd is 1.
const CUBE := 0.5
const CUBE_DRAG_AREA := 0.5 * 0.375

var _air_density := 0.0


func before_each() -> void:
	_air_density = Medium.ambient.density


func after_each() -> void:
	Medium.ambient.density = _air_density


func _box(mass: float, side: float, at: Vector3, velocity := Vector3.ZERO, gravity := 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.collision_layer = 0
	body.collision_mask = 0
	body.gravity_scale = gravity
	body.can_sleep = false
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * side
	collider.shape = box
	body.add_child(collider)
	add_child_autofree(body)
	body.global_position = at
	body.linear_velocity = velocity
	return body


func _volume(medium: Medium, at: Vector3, size: Vector3) -> MediumVolume:
	var volume := MediumVolume.new()
	volume.medium = medium
	volume.size = size
	add_child_autofree(volume)
	volume.global_position = at
	return volume


func _measured(body: RigidBody3D) -> FluidDrag.Entry:
	var entry := FluidDrag.Entry.new()
	entry.body = body
	FluidDrag.measure(entry)
	return entry


## dv/dt = -k v^2 from v0 for t seconds.
func _coasted(v0: float, k: float, t: float) -> float:
	return v0 / (1.0 + k * v0 * t)


func test_a_thrown_body_slows_like_the_closed_form() -> void:
	var body := _box(1.0, CUBE, Vector3(0, 100, 0), Vector3(20, 0, 0))
	await wait_physics_frames(90)
	assert_almost_eq(body.linear_velocity.x, _coasted(20.0, CUBE_DRAG_AREA * Medium.ambient.density, 1.0), 0.15)


func test_denser_air_slows_it_more() -> void:
	Medium.ambient.density = 2.0 * _air_density
	var body := _box(1.0, CUBE, Vector3(0, 100, 0), Vector3(20, 0, 0))
	await wait_physics_frames(90)
	assert_almost_eq(body.linear_velocity.x, _coasted(20.0, CUBE_DRAG_AREA * Medium.ambient.density, 1.0), 0.15)


func test_with_no_air_nothing_slows_it() -> void:
	Medium.ambient.density = 0.0
	var body := _box(1.0, CUBE, Vector3(0, 100, 0), Vector3(20, 0, 0))
	await wait_physics_frames(90)
	assert_almost_eq(body.linear_velocity.x, 20.0, 0.001, "the engine's own damping is off too")


func test_it_slows_less_in_a_box_of_thin_air() -> void:
	_volume(THIN_AIR, Vector3(0, 100, 0), Vector3(400, 10, 10))
	var body := _box(1.0, CUBE, Vector3(0, 100, 0), Vector3(20, 0, 0))
	await wait_physics_frames(90)
	assert_almost_eq(body.linear_velocity.x, _coasted(20.0, CUBE_DRAG_AREA * THIN_AIR.density, 1.0), 0.05)


func test_a_fall_tops_out_at_terminal_speed() -> void:
	var weight := (1.0 - Medium.ambient.density * CUBE * CUBE * CUBE) * 9.8
	var body := _box(1.0, CUBE, Vector3(0, 500, 0), Vector3.ZERO, 1.0)
	await wait_physics_frames(360)
	assert_almost_eq(-body.linear_velocity.y, sqrt(weight / (CUBE_DRAG_AREA * Medium.ambient.density)), 0.1)


func test_something_lighter_than_air_rises() -> void:
	var body := _box(0.05, CUBE, Vector3(0, 100, 0), Vector3.ZERO, 1.0)
	await wait_physics_frames(45)
	assert_gt(body.global_position.y, 100.0)


func test_spin_dies_down_like_the_closed_form() -> void:
	var body := _box(1.0, CUBE, Vector3(0, 100, 0))
	# The engine's own damping stays on by default, standing in for the rolling resistance Jolt doesn't have.
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_velocity = Vector3(0, 20, 0)
	await wait_physics_frames(90)
	var k := 0.625 * CUBE_DRAG_AREA * Medium.ambient.density * CUBE * 0.5
	assert_almost_eq(body.angular_velocity.y, _coasted(20.0, k, 1.0), 0.5)


func test_something_less_dense_than_water_floats_half_sunk() -> void:
	_volume(WATER, Vector3(0, 0, 0), Vector3(6, 4, 6))
	var body := _box(0.2 * 0.2 * 0.2 * 499.0, 0.2, Vector3(0, 1.2, 0), Vector3.ZERO, 1.0)
	await wait_physics_frames(540)
	assert_almost_eq(body.global_position.y, 2.0, 0.02, "half of it under the surface at y = 2")
	assert_almost_eq(body.linear_velocity.length(), 0.0, 0.03)


func test_something_dense_sinks_at_terminal_speed() -> void:
	_volume(WATER, Vector3(0, 0, 0), Vector3(6, 100, 6))
	var body := _box(0.2 * 0.2 * 0.2 * 3000.0, 0.2, Vector3(0, 40, 0), Vector3.ZERO, 1.0)
	await wait_physics_frames(180)
	var drag_area := 0.5 * 0.06
	assert_almost_eq(-body.linear_velocity.y, sqrt((3000.0 - WATER.density) * 0.008 * 9.8 / (drag_area * WATER.density)), 0.05)


func test_a_light_body_in_water_stays_stable() -> void:
	_volume(WATER, Vector3(0, 0, 0), Vector3(50, 50, 50))
	var body := _box(0.01, 0.1, Vector3(-20, 0, 0), Vector3(50, 0, 0))
	body.angular_velocity = Vector3(100, 0, 0)
	await wait_physics_frames(2)
	assert_between(body.linear_velocity.x, 0.0, 50.0, "drag can't push it backward, however much it takes in a tick")
	assert_lt(body.angular_velocity.length(), 100.0)


func test_a_body_at_rest_goes_to_sleep_and_stays_there() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10, 1, 10)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)
	floor_body.global_position = Vector3(200, -0.5, 0)
	var body := _box(4.0, 0.35, Vector3(200, 0.3, 0), Vector3.ZERO, 1.0)
	body.collision_layer = 1
	body.collision_mask = 1
	body.can_sleep = true
	await wait_physics_frames(180)
	assert_true(body.sleeping)


func test_every_body_gets_a_real_size_and_the_right_things_float() -> void:
	var person: RigidBody3D = autofree(load("res://player/player.tscn").instantiate())
	var entry := _measured(person)
	assert_between(2.0 * entry.drag_area, 0.5, 0.8, "a person shows about 0.6 m2 averaged over all sides")
	assert_almost_eq(entry.volume, 80.0 / 985.0, 0.001, "a person is about as dense as water")
	for path: String in ["res://weapons/pistol/pistol.tscn", "res://weapons/ar/ar.tscn"]:
		var gun: Node = autofree(load(path).instantiate())
		var frame: RigidBody3D = gun.get_node("Frame")
		assert_gt(frame.mass / _measured(frame).volume, WATER.density, path + " sinks")
		assert_between(2.0 * _measured(frame).drag_area, 0.003, 0.05, path + " shows about as much as a real one")
	for path: String in ["res://weapons/parts/magazine_9mm.tscn", "res://weapons/parts/magazine_556.tscn"]:
		var magazine: RigidBody3D = autofree(load(path).instantiate())
		assert_gt(magazine.mass / _measured(magazine).volume, WATER.density, path + " sinks")
	var casing: RigidBody3D = autofree(load("res://ballistics/casing.tscn").instantiate())
	assert_gt(casing.mass / _measured(casing).volume, WATER.density, "brass sinks")


func test_a_convex_shape_measures_by_its_bounding_box() -> void:
	var body := _box(1.0, 0.1, Vector3(0, 100, 0))
	var convex := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for corner: int in 8:
		points.append(Vector3(corner & 1, corner >> 1 & 1, corner >> 2 & 1) - Vector3.ONE * 0.5)
	convex.points = points
	(body.get_child(0) as CollisionShape3D).shape = convex
	var entry := _measured(body)
	assert_almost_eq(entry.volume, 1.0, 0.01)
	assert_almost_eq(entry.drag_area, 0.75, 0.01)


func test_moving_gun_parts_are_left_to_the_frame() -> void:
	var open := _box(1.0, CUBE, Vector3(0, 100, 0), Vector3(20, 0, 0))
	var shrouded := RigidBody3D.new()
	shrouded.collision_layer = FluidDrag.MOVING_GUN_PART
	shrouded.collision_mask = 0
	shrouded.gravity_scale = 0.0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * CUBE
	collider.shape = box
	shrouded.add_child(collider)
	add_child_autofree(shrouded)
	shrouded.global_position = Vector3(0, 110, 0)
	shrouded.linear_velocity = Vector3(20, 0, 0)
	await wait_physics_frames(10)
	assert_lt(open.linear_velocity.x, 19.5)
	assert_almost_eq(shrouded.linear_velocity.x, 20.0, 0.001)


func test_a_bullet_slows_by_the_water_it_crosses_between_ticks() -> void:
	# Over 10 m a tick, so most of the time no tick starts or ends in this box.
	_volume(WATER, Vector3(0, 500, -25), Vector3(4, 4, 1))
	var from := Vector3(0, 500, 0)
	var bullet := Ballistics.pool.fire_bullet(RIFLE, from, Vector3(0, 0, -900))
	await wait_physics_frames(6)
	assert_lt(bullet.global_position.z, -26.0, "it comes out the far side")
	var factor := 0.5 * RIFLE.drag_coefficient * RIFLE.bore_area() / RIFLE.bullet_mass
	var through_air := Medium.ambient.density * from.distance_to(bullet._last_position)
	var left := 900.0 * exp(-factor * (through_air + (WATER.density - Medium.ambient.density) * 1.0))
	assert_almost_eq(bullet.linear_velocity.length(), left, 1.0)
	assert_lt(left, 400.0, "1 m of water takes more than 100 m of air would")


func test_water_stops_a_bullet_in_a_few_meters() -> void:
	_volume(WATER, Vector3(60, 500, 0), Vector3(40, 40, 40))
	var bullet := Ballistics.pool.fire_bullet(NINE, Vector3(60, 500, 0), Vector3(0, 0, -360))
	await wait_physics_frames(45)
	var factor := 0.5 * NINE.drag_coefficient * NINE.bore_area() / NINE.bullet_mass
	# Down to walking pace, and after that it only sinks, at about sqrt(g / k).
	assert_lt(bullet.linear_velocity.length(), 2.0 * sqrt(9.8 / (factor * WATER.density)))
	assert_between(-bullet.global_position.z, 2.0, 6.0)
