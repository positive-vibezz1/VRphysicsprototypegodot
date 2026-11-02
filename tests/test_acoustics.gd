extends GutTest
## Sound on its way to the ear: the equations, then the same through real rays, boxes and voices.

## Two times around the room: the first sweep can end on rays from before the walls went up.
const SWEEP := 30

var _camera: Camera3D


func before_each() -> void:
	_silence()
	_camera = Camera3D.new()
	_camera.current = true
	add_child_autofree(_camera)


func after_each() -> void:
	_silence()


func _silence() -> void:
	Sounds.pool.hush()
	Sounds.pool._quiet_until = 0


func _listen_from(point: Vector3) -> void:
	_camera.global_position = point
	await wait_physics_frames(2)


func _volume(medium_path: String, center: Vector3, size: Vector3) -> MediumVolume:
	var volume := MediumVolume.new()
	volume.medium = load(medium_path)
	volume.size = size
	volume.position = center
	add_child_autofree(volume)
	return volume


func _wall(center: Vector3, size: Vector3, surface := Sounds.Surface.CONCRETE) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = center
	wall.set_meta(&"surface", surface)
	add_child_autofree(wall)
	return wall


func test_sound_crossing_air_and_water_loses_what_impedances_say() -> void:
	var air: Medium = load("res://audio/air_medium.tres")
	var water: Medium = load("res://audio/water_medium.tres")
	assert_almost_eq(Medium.transmission(air.impedance(), water.impedance()), 0.0011, 0.0001, "the famous 30 dB")
	assert_almost_eq(Medium.transmission(air.impedance(), air.impedance()), 1.0, 0.0001)
	assert_eq(Medium.transmission(air.impedance(), 0.0), 0.0, "nothing crosses into a vacuum")
	assert_eq(Medium.transmission(0.0, 0.0), 0.0)


func test_the_mass_law_matches_a_concrete_wall() -> void:
	# 20 cm of concrete, 480 kg/m2, is about 60 dB at 500 Hz, and each doubling of frequency adds 6 dB.
	assert_almost_eq(Acoustics.mass_law(500.0, 480.0), 60.6, 0.5)
	assert_almost_eq(Acoustics.mass_law(1000.0, 480.0) - Acoustics.mass_law(500.0, 480.0), 6.0, 0.05)
	assert_eq(Acoustics.mass_law(500.0, 0.01), 0.0, "foil stops nothing")


func test_a_barrier_loses_more_with_a_longer_detour_and_at_higher_frequencies() -> void:
	# Maekawa's chart: Fresnel number 1 is about 13 dB.
	var one := 343.0 / 500.0 / 2.0
	assert_almost_eq(Acoustics.barrier_loss(500.0, one, 343.0), 13.8, 0.5)
	assert_lt(Acoustics.barrier_loss(500.0, 0.2, 343.0), Acoustics.barrier_loss(500.0, 1.0, 343.0))
	assert_lt(Acoustics.barrier_loss(500.0, 0.2, 343.0), Acoustics.barrier_loss(4000.0, 0.2, 343.0))
	assert_eq(Acoustics.barrier_loss(4000.0, 100.0, 343.0), Acoustics.MOST_BARRIER_LOSS)


func test_reverberation_time_follows_the_room() -> void:
	# A room with 4 m between surfaces of 10% absorption, about 1.5 s. Sabine would say 1.6.
	assert_almost_eq(Acoustics.reverberation(4.0, 0.1, 343.0), 1.53, 0.05)
	assert_gt(Acoustics.reverberation(8.0, 0.1, 343.0), Acoustics.reverberation(4.0, 0.1, 343.0), "bigger rings longer")
	assert_gt(Acoustics.reverberation(4.0, 0.1, 343.0), Acoustics.reverberation(4.0, 0.5, 343.0), "softer rings shorter")
	assert_gt(Acoustics.reverberation(4.0, 0.1, 343.0), Acoustics.reverberation(4.0, 0.1, 1482.0), "faster sound dies sooner")
	assert_eq(Acoustics.room_size(0.2), 0.0, "shorter than the reverb can go")
	assert_gt(Acoustics.room_size(3.0), Acoustics.room_size(1.0))


func test_a_far_sound_arrives_late_and_loses_its_highs() -> void:
	await _listen_from(Vector3(0, 100, 0))
	var acoustics := Sounds.pool.acoustics
	acoustics.trace(Vector3(343, 100, 0))
	assert_almost_eq(acoustics.delay, 1.0, 0.001, "343 m at 343 m/s")
	assert_almost_eq(acoustics.shelf, -343.0 * 0.117, 0.01)
	assert_almost_eq(acoustics.gain, 1.0, 0.001, "the ear is in the same air")


func test_sound_in_a_box_goes_by_what_is_in_the_box() -> void:
	_volume("res://audio/water_medium.tres", Vector3(50, 0, 0), Vector3(10, 10, 10))
	_volume("res://audio/thin_air_medium.tres", Vector3(-50, 0, 0), Vector3(10, 10, 10))
	var acoustics := Sounds.pool.acoustics
	var air_gain: Dictionary[String, float] = {}

	await _listen_from(Vector3(0, 0, 0))
	acoustics.trace(Vector3(1, 0, 0))
	air_gain["air to air"] = acoustics.gain
	acoustics.trace(Vector3(50, 0, 0))
	air_gain["water to air"] = acoustics.gain
	assert_almost_eq(acoustics.delay, 45.0 / 343.0 + 5.0 / 1482.0, 0.001, "faster through the water")
	acoustics.trace(Vector3(-50, 0, 0))
	air_gain["thin to air"] = acoustics.gain

	await _listen_from(Vector3(50, 0, 0))
	assert_true(acoustics.ear_medium.is_liquid)
	assert_lt(acoustics.panning, 0.3, "too fast down there to tell left from right")
	acoustics.trace(Vector3(51, 0, 0))
	air_gain["water to water"] = acoustics.gain
	assert_lt(acoustics.shelf, -Acoustics.SKULL_LOSS + 0.1)
	acoustics.trace(Vector3(60, 10, 0))
	air_gain["air to water"] = acoustics.gain

	await _listen_from(Vector3(-50, 0, 0))
	acoustics.trace(Vector3(-51, 0, 0))
	air_gain["thin to thin"] = acoustics.gain
	assert_lt(acoustics.shelf, -2.0, "thin air takes the highs fast")

	assert_almost_eq(air_gain["air to air"], 1.0, 0.001)
	assert_lt(air_gain["thin to thin"], 0.2, "thin air carries little")
	assert_lt(air_gain["thin to air"], air_gain["air to air"], "and starts out quiet")
	assert_lt(air_gain["water to air"], 0.25, "a boundary stops most of it")
	assert_lt(air_gain["air to water"], 0.01, "and more with an ear full of air under water")
	assert_gt(air_gain["water to water"], air_gain["air to water"] * 10.0, "hits under water carry to an ear under water")


func test_a_vacuum_carries_nothing() -> void:
	var nothing := Medium.new()
	nothing.density = 0.0
	var volume := _volume("res://audio/thin_air_medium.tres", Vector3(50, 0, 0), Vector3(10, 10, 10))
	volume.medium = nothing
	await _listen_from(Vector3(0, 0, 0))
	var stream := Sounds.pool.stream_of(Sounds.Surface.METAL, true, 0)
	assert_false(Sounds.pool.play(stream, Vector3(50, 0, 0), 1.0), "no sound in space")


func test_a_box_in_the_way_costs_two_boundaries() -> void:
	_volume("res://audio/thin_air_medium.tres", Vector3(10, 0, 0), Vector3(4, 4, 4))
	await _listen_from(Vector3(0, 0, 0))
	var acoustics := Sounds.pool.acoustics
	acoustics.trace(Vector3(20, 0, 0))
	var through := acoustics.gain
	assert_lt(through, 0.5)
	assert_gt(through, 0.1)
	assert_lt(acoustics.shelf, -4.0 * 2.34, "and it dulls more than air alone")


func test_a_wall_muffles_what_is_behind_it() -> void:
	var acoustics := Sounds.pool.acoustics
	await _listen_from(Vector3(0, 1, 0))
	acoustics.trace(Vector3(0, 1, -10))
	var open_gain := acoustics.gain
	var open_shelf := acoustics.shelf
	_wall(Vector3(0, 1, -5), Vector3(3, 3, 0.2))
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	assert_lt(acoustics.gain, open_gain * 0.5, "quieter")
	assert_gt(acoustics.gain, open_gain * 0.05, "but it comes around a wall that small")
	assert_lt(acoustics.shelf, open_shelf - 3.0, "and the highs lose the most")
	assert_almost_eq(acoustics.open_gain, open_gain, 0.001, "an echo needn't come through it")


func test_a_bigger_wall_muffles_more_and_a_shut_room_far_more() -> void:
	var acoustics := Sounds.pool.acoustics
	await _listen_from(Vector3(0, 1, 0))
	var small := _wall(Vector3(0, 1, -5), Vector3(1, 1, 0.2))
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	var around_small := acoustics.gain
	small.free()
	var big := _wall(Vector3(0, 1, -5), Vector3(14, 14, 0.2))
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	var around_big := acoustics.gain
	assert_lt(around_big, around_small, "a longer way around")
	big.free()
	# A sealed concrete box around the source: only through the walls is left, and that's next to nothing.
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var size := Vector3.ONE * 2.2 - side.abs() * 2.0
		_wall(Vector3(0, 1, -10) + side, size)
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	assert_lt(acoustics.gain, around_big * 0.2, "sealed in")


func test_a_light_wall_lets_more_through_than_a_heavy_one() -> void:
	var acoustics := Sounds.pool.acoustics
	await _listen_from(Vector3(0, 1, 0))
	# Too big to get around, so only what it's made of matters.
	var wood := _wall(Vector3(0, 1, -5), Vector3(60, 60, 0.02), Sounds.Surface.WOOD)
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	var through_wood := acoustics.gain
	wood.free()
	_wall(Vector3(0, 1, -5), Vector3(60, 60, 0.2))
	await wait_physics_frames(2)
	acoustics.trace(Vector3(0, 1, -10))
	assert_gt(through_wood, acoustics.gain)


func test_a_sound_waits_for_its_way_here_and_then_gets_a_voice() -> void:
	await _listen_from(Vector3(0, 100, 0))
	var stream := Sounds.pool.stream_of(Sounds.Surface.METAL, true, 0)
	assert_true(Sounds.pool.play(stream, Vector3(34.3, 100, 0), 1.0), "0.1 s away")
	assert_eq(Sounds.pool.waiting_count(), 1)
	var started := func() -> bool:
		for voice: Node in Sounds.pool.get_children():
			if voice is AudioStreamPlayer3D and (voice as AudioStreamPlayer3D).playing:
				return true
		return false
	assert_false(started.call(), "not yet")
	await wait_physics_frames(4)
	assert_false(started.call(), "still on its way after 44 ms")
	await wait_physics_frames(7)
	assert_eq(Sounds.pool.waiting_count(), 0)
	assert_true(started.call(), "there after 100 ms")


func test_a_near_sound_starts_at_once() -> void:
	await _listen_from(Vector3(0, 100, 0))
	Sounds.pool.play(Sounds.pool.stream_of(Sounds.Surface.METAL, true, 0), Vector3(1, 100, 0), 1.0)
	assert_eq(Sounds.pool.waiting_count(), 0)


func test_a_big_wall_throws_a_sound_back_from_its_mirror_image() -> void:
	_wall(Vector3(0, 10, -30), Vector3(80, 40, 1))
	await _listen_from(Vector3(0, 1.6, 0))
	await wait_physics_frames(SWEEP)
	var acoustics := Sounds.pool.acoustics
	assert_eq(acoustics.find_echoes(Vector3(0, 1.6, 0)), 1)
	# The wall's near face is at z = -29.5, so the way there and back is 59 m.
	assert_almost_eq(acoustics.echo_positions[0].z, -59.0, 0.2)
	assert_almost_eq(acoustics.echo_delays[0], 59.0 / 343.0, 0.002)
	assert_almost_eq(acoustics.echo_levels[0], sqrt(0.98), 0.001, "concrete takes 2% of the power")
	assert_lt(acoustics.echo_shelves[0], -5.0, "air has taken the highs off the long way")


func test_no_echo_in_the_open_or_off_a_near_wall_or_with_something_in_the_way() -> void:
	await _listen_from(Vector3(0, 1.6, 0))
	await wait_physics_frames(SWEEP)
	var acoustics := Sounds.pool.acoustics
	assert_eq(acoustics.find_echoes(Vector3(0, 1.6, 0)), 0, "nothing to bounce off")
	var near := _wall(Vector3(0, 10, -5), Vector3(80, 40, 1))
	await wait_physics_frames(SWEEP)
	assert_eq(acoustics.find_echoes(Vector3(0, 1.6, 0)), 0, "too close to hear apart")
	near.free()
	_wall(Vector3(0, 10, -30), Vector3(80, 40, 1))
	await wait_physics_frames(SWEEP)
	assert_eq(acoustics.find_echoes(Vector3(0, 1.6, 0)), 1)
	# Right up against the source, on the side toward the far wall.
	_wall(Vector3(0, 1.6, -11), Vector3(4, 4, 0.2))
	assert_eq(acoustics.find_echoes(Vector3(0, 1.6, -10)), 0, "the sound can't reach the wall")


func test_the_open_has_little_reverb_and_a_room_has_plenty() -> void:
	var acoustics := Sounds.pool.acoustics
	await _listen_from(Vector3(0, 1.6, 0))
	_wall(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	await wait_physics_frames(SWEEP)
	assert_lt(acoustics.wet, 0.02, "a floor alone gives nothing back to speak of")
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0)]:
		var size := Vector3(12, 8, 12) * (Vector3.ONE - side.abs()) + side.abs() * 0.4
		_wall(Vector3(0, 1.6, 0) + side * Vector3(5, 3, 5), size)
	await wait_physics_frames(SWEEP)
	assert_gt(acoustics.wet, 0.3)
	assert_gt(acoustics.reverb_seconds, 1.0, "bare concrete rings")


func test_soft_walls_ring_less_than_hard_ones() -> void:
	var acoustics := Sounds.pool.acoustics
	await _listen_from(Vector3(0, 1.6, 0))
	var walls: Array[StaticBody3D] = []
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		var size := Vector3(12, 8, 12) * (Vector3.ONE - side.abs()) + side.abs() * 0.4
		walls.append(_wall(Vector3(0, 1.6, 0) + side * Vector3(5, 3, 5), size))
	await wait_physics_frames(SWEEP)
	var hard := acoustics.reverb_seconds
	for wall: StaticBody3D in walls:
		wall.set_meta(&"surface", Sounds.Surface.SOFT)
	await wait_physics_frames(SWEEP)
	assert_lt(acoustics.reverb_seconds, hard * 0.2)


func test_contact_time_follows_stiffness_mass_and_speed() -> void:
	var metal := Sounds.pool.sound_of(Sounds.Surface.METAL)
	var concrete := Sounds.pool.sound_of(Sounds.Surface.CONCRETE)
	var soft := Sounds.pool.sound_of(Sounds.Surface.SOFT)
	var wood := Sounds.pool.sound_of(Sounds.Surface.WOOD)
	# 1 kg of steel on concrete at 4 m/s.
	assert_almost_eq(SurfaceSound.contact_time(metal, concrete, 1.0, 4.0), 0.00037, 0.00005)
	assert_lt(SurfaceSound.contact_time(metal, concrete, 1.0, 4.0), SurfaceSound.contact_time(metal, wood, 1.0, 4.0), "wood gives more")
	assert_lt(SurfaceSound.contact_time(metal, wood, 1.0, 4.0), SurfaceSound.contact_time(metal, soft, 1.0, 4.0) * 0.2, "and a hand far more")
	assert_lt(SurfaceSound.contact_time(metal, concrete, 0.1, 4.0), SurfaceSound.contact_time(metal, concrete, 1.0, 4.0), "lighter is shorter")
	assert_lt(SurfaceSound.contact_time(metal, concrete, 1.0, 8.0), SurfaceSound.contact_time(metal, concrete, 1.0, 1.0), "faster is shorter")


func test_the_same_gun_sounds_duller_on_a_softer_surface() -> void:
	var metal := Sounds.pool.sound_of(Sounds.Surface.METAL)
	var on_concrete := SurfaceSound.contact_time(metal, Sounds.pool.sound_of(Sounds.Surface.CONCRETE), 0.3, 4.0)
	var on_soft := SurfaceSound.contact_time(metal, Sounds.pool.sound_of(Sounds.Surface.SOFT), 0.3, 4.0)
	assert_true(metal.is_hard(on_concrete), "the bright take on concrete")
	assert_false(metal.is_hard(on_soft), "the dull take on something soft")
	assert_gt(metal.dulling(on_soft, Acoustics.HIGH_BAND), metal.dulling(on_concrete, Acoustics.HIGH_BAND))
	assert_eq(metal.dulling(metal.hard_contact * 0.5, Acoustics.HIGH_BAND), 0.0, "a take can't get brighter than it was baked")


func test_a_body_rings_lower_under_water_by_how_light_it_is() -> void:
	var water: Medium = load("res://audio/water_medium.tres")
	var air: Medium = load("res://audio/air_medium.tres")
	var metal := Sounds.pool.sound_of(Sounds.Surface.METAL)
	var wood := Sounds.pool.sound_of(Sounds.Surface.WOOD)
	assert_almost_eq(metal.pitch_for(1.0, air.density), 1.0, 0.001, "air weighs nothing next to it")
	assert_almost_eq(metal.pitch_for(1.0, water.density), 0.94, 0.01)
	assert_lt(wood.pitch_for(4.0, water.density), 0.7, "wood weighs less than the water it moves")


func test_a_dropped_body_splashes() -> void:
	var box := _volume("res://audio/water_medium.tres", Vector3(0, 100, 0), Vector3(4, 4, 4))
	await _listen_from(Vector3(0, 103, 3))
	var splashes: Array[float] = []
	var listener := func(surface: Sounds.Surface, energy: float, _volume_out: float, _pitch: float) -> void:
		if surface == Sounds.Surface.WATER:
			splashes.append(energy)
	Sounds.pool.played.connect(listener)
	var body := RigidBody3D.new()
	body.mass = 1.0
	body.collision_layer = 32
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.05
	shape.shape = sphere
	body.add_child(shape)
	body.position = Vector3(0, 103, 0)
	add_child_autofree(body)
	var free_fall := sqrt(2.0 * 9.8 * 1.0)
	await wait_physics_frames(60)
	Sounds.pool.played.disconnect(listener)
	assert_eq(splashes.size(), 1, "a splash on the way in")
	if not splashes.is_empty():
		# Water has taken some of it by the tick the box notices the body.
		assert_between(splashes[0], 5.0, 0.5 * free_fall * free_fall + 1.0, "with about the energy it fell with")
	assert_true(box.contains(body.global_position))


func test_a_bullet_splashes_once_even_if_it_could_cross_between_ticks() -> void:
	_volume("res://audio/water_medium.tres", Vector3(0, 100, -11.5), Vector3(4, 4, 1))
	await _listen_from(Vector3(0, 100, -8))
	var cartridge: CartridgeSpec = load("res://weapons/parts/cartridge_556x45.tres")
	var splashes: Array[float] = []
	var listener := func(surface: Sounds.Surface, energy: float, _volume_out: float, _pitch: float) -> void:
		if surface == Sounds.Surface.WATER:
			splashes.append(energy)
	Sounds.pool.played.connect(listener)
	var bullet := Ballistics.pool.fire_bullet(cartridge, Vector3(0, 100, 0), Vector3(0, 0, -1000))
	await wait_physics_frames(6)
	Sounds.pool.played.disconnect(listener)
	bullet.park()
	assert_eq(splashes.size(), 1, str(splashes))


func test_the_range_has_water_and_thin_air_to_listen_in_and_clear_of_the_lanes() -> void:
	var scene: Node3D = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(scene)
	var water: MediumVolume = scene.get_node("Water")
	var thin: MediumVolume = scene.get_node("ThinAir")
	assert_true(water.medium.is_liquid)
	assert_lt(thin.medium.density, 0.2)
	assert_eq(MediumVolume.medium_at(water.global_position), water.medium)
	assert_eq(MediumVolume.medium_at(Vector3(0, 1, 3)), Medium.ambient)
	assert_true(water.contains(water.global_position + Vector3(0, 1.0, 0)), "deep enough to get a head under")
	assert_lt(water.global_position.y - water.size.y * 0.5, 0.01, "and it reaches the floor")
	# From the table to the farthest target on that side.
	var lane_from := Vector3(0, 1.3, -0.85)
	for target: String in ["Steel5m", "Steel10m", "Steel25m", "Steel50m", "Dummy"]:
		var to := (scene.get_node(target) as Node3D).global_position + Vector3(0, 1.2, 0)
		assert_eq(water.path_length(lane_from, to), 0.0, target)
		assert_eq(thin.path_length(lane_from, to), 0.0, target)
