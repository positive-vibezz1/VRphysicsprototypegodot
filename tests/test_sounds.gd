extends GutTest
## Sounds from real Jolt contacts: how the energy of a hit becomes a voice, and what stays silent.

const BOX_SIZE := 0.2

var _heard: Array[Dictionary] = []


func before_each() -> void:
	_heard.clear()
	Sounds.pool.played.connect(_on_played)
	_silence()


func after_each() -> void:
	Sounds.pool.played.disconnect(_on_played)
	_silence()


func _on_played(surface: Sounds.Surface, energy: float, volume: float, pitch: float) -> void:
	_heard.append({"surface": surface, "energy": energy, "volume": volume, "pitch": pitch})


## Frees the voices and lifts the hush, whatever an earlier test left.
func _silence() -> void:
	Sounds.pool.hush()
	Sounds.pool._quiet_until = 0


func _floor(surface := Sounds.Surface.CONCRETE) -> StaticBody3D:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	ground.set_meta(&"surface", surface)
	add_child_autofree(ground)
	return ground


## A body with its underside this high over the top of the floor.
func _box(mass: float, height: float, surface := Sounds.Surface.METAL) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * BOX_SIZE
	shape.shape = box
	body.add_child(shape)
	var ring := ImpactSound.new()
	ring.surface = surface
	body.add_child(ring)
	body.position = Vector3(0, height + BOX_SIZE * 0.5, 0)
	add_child_autofree(body)
	return body


func _first(surface: Sounds.Surface) -> Dictionary:
	for sound: Dictionary in _heard:
		if sound["surface"] == surface:
			return sound
	return {}


func _samples(stream: AudioStreamWAV) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(stream.data.size() / 2)
	for i: int in samples.size():
		samples[i] = stream.data.decode_s16(i * 2) / 32768.0
	return samples


func _level(samples: PackedFloat32Array, from: int, to: int) -> float:
	var total := 0.0
	for i: int in range(from, to):
		total += samples[i] * samples[i]
	return sqrt(total / (to - from))


func test_every_take_rings_and_dies_away_without_clipping() -> void:
	for surface: int in Sounds.SURFACE_PATHS.size():
		for take: int in Sounds.TAKES:
			for hard: bool in [false, true]:
				var samples := _samples(Sounds.pool.stream_of(surface, hard, take))
				var tenth := samples.size() / 10
				assert_gt(tenth, 0)
				var head := _level(samples, 0, tenth)
				assert_gt(head, 0.02, "surface %d has a sound in it" % surface)
				assert_lt(_level(samples, samples.size() - tenth, samples.size()), head * 0.05, "and it dies away")
				var peak := 0.0
				for sample: float in samples:
					peak = maxf(peak, absf(sample))
				assert_lt(peak, 0.95)


func test_takes_differ() -> void:
	var first := Sounds.pool.stream_of(Sounds.Surface.METAL, true, 0).data
	assert_ne(first, Sounds.pool.stream_of(Sounds.Surface.METAL, true, 1).data)


func test_a_short_contact_rings_brighter_than_a_long_one() -> void:
	for surface: int in Sounds.SURFACE_PATHS.size():
		var brightness: Array[float] = []
		for hard: bool in [false, true]:
			# The more of it is in high frequencies, the more it changes from one sample to the next.
			var samples := _samples(Sounds.pool.stream_of(surface, hard, 0))
			var change := 0.0
			var total := 0.0
			for i: int in range(1, samples.size()):
				change += pow(samples[i] - samples[i - 1], 2.0)
				total += samples[i] * samples[i]
			brightness.append(change / total)
		assert_gt(brightness[1], brightness[0], "surface %d" % surface)


func test_loudness_rises_with_energy_and_tops_out() -> void:
	assert_eq(Sounds.loudness(0.0), 0.0)
	assert_eq(Sounds.loudness(-1.0), 0.0, "a bullet can come out of a contact faster than it went in")
	assert_lt(Sounds.loudness(0.04), Sounds.loudness(1.0))
	assert_lt(Sounds.loudness(1.0), Sounds.loudness(10.0))
	assert_eq(Sounds.loudness(Sounds.FULL_ENERGY), 1.0)
	assert_eq(Sounds.loudness(1000.0), 1.0)


func test_a_lighter_body_rings_higher_and_a_static_one_at_its_own_pitch() -> void:
	var metal := Sounds.pool.sound_of(Sounds.Surface.METAL)
	assert_almost_eq(metal.pitch_for(metal.reference_mass), 1.0, 0.001)
	assert_almost_eq(metal.pitch_for(metal.reference_mass / 8.0), 2.0, 0.001, "half the size, twice the pitch")
	assert_eq(metal.pitch_for(0.0), 1.0)
	assert_eq(metal.pitch_for(1.0e-6), SurfaceSound.HIGHEST_PITCH)
	assert_eq(metal.pitch_for(1.0e6), SurfaceSound.LOWEST_PITCH)


func test_a_drop_rings_with_the_energy_it_fell_with() -> void:
	_floor(Sounds.Surface.WOOD)
	_box(1.0, 1.0)
	await wait_physics_frames(60)
	var body := _first(Sounds.Surface.METAL)
	var ground := _first(Sounds.Surface.WOOD)
	assert_false(body.is_empty(), "the metal rings")
	assert_false(ground.is_empty(), "and the table it hit")
	if body.is_empty() or ground.is_empty():
		return
	# m g h.
	assert_almost_eq(body["energy"] as float, 9.8, 1.5)
	# A 1 kg box against a table's 4 kg.
	assert_almost_eq(ground["energy"] as float, 9.8 / 5.0, 0.3)


func test_a_longer_drop_is_louder() -> void:
	_floor()
	var low := _box(1.0, 0.1)
	await wait_physics_frames(45)
	assert_false(_heard.is_empty())
	var near := _first(Sounds.Surface.METAL)
	low.free()
	_heard.clear()
	_silence()
	_box(1.0, 1.0)
	await wait_physics_frames(60)
	assert_gt(_first(Sounds.Surface.METAL)["volume"] as float, near["volume"] as float)


func test_a_body_at_rest_is_silent() -> void:
	_floor()
	_box(1.0, 0.1)
	await wait_physics_frames(60)
	_heard.clear()
	await wait_physics_frames(60)
	assert_eq(_heard.size(), 0, str(_heard))


func test_pressing_hard_into_a_surface_is_silent() -> void:
	_floor()
	# As hard as a hand can press, and it never sleeps.
	var body := _box(0.8, 0.0)
	body.can_sleep = false
	await wait_physics_frames(10)
	_heard.clear()
	for i: int in 60:
		body.apply_central_force(Vector3.DOWN * 350.0)
		await wait_physics_frames(1)
	assert_eq(_heard.size(), 0, str(_heard))


func test_bounces_are_throttled() -> void:
	_floor()
	var body := _box(1.0, 0.5)
	var bouncy := PhysicsMaterial.new()
	bouncy.bounce = 0.8
	body.physics_material_override = bouncy
	await wait_physics_frames(120)
	var rings := 0
	for sound: Dictionary in _heard:
		rings += 1 if sound["surface"] == Sounds.Surface.METAL else 0
	assert_gt(rings, 1, "it rings on the way down each time")
	assert_lt(rings, 12, "but no faster than the gap between hits")


func test_a_light_body_hitting_a_heavy_one_mostly_rings_itself() -> void:
	_floor()
	var heavy := _box(40.0, 0.0, Sounds.Surface.WOOD)
	await wait_physics_frames(30)
	_heard.clear()
	var light := _box(0.1, 1.0)
	light.position.y += BOX_SIZE
	await wait_physics_frames(60)
	assert_gt(_first(Sounds.Surface.METAL)["volume"] as float, 0.0)
	var knock := _first(Sounds.Surface.WOOD)
	if not knock.is_empty():
		assert_lt(knock["energy"] as float, _first(Sounds.Surface.METAL)["energy"] as float * 0.1, "the crate hardly notices")
	assert_gt(heavy.mass, light.mass)


func test_a_casing_tinks_and_hardly_shakes_the_floor() -> void:
	_floor()
	var cartridge: CartridgeSpec = load("res://weapons/parts/cartridge_9x19.tres")
	var casing := Ballistics.pool.eject_casing(cartridge, Vector3(0, 1, 0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, false)
	await wait_physics_frames(60)
	var tink := _first(Sounds.Surface.BRASS)
	assert_false(tink.is_empty(), "brass rings")
	if not tink.is_empty():
		# m g h on 4 g, less for the bit of the fall Jolt's speculative contact takes out.
		assert_almost_eq(tink["energy"] as float, casing.mass * 9.8 * 1.0, 0.03)
		assert_gt(tink["pitch"] as float, 0.8)
		var floor_sound := _first(Sounds.Surface.CONCRETE)
		if not floor_sound.is_empty():
			assert_lt(floor_sound["volume"] as float, tink["volume"] as float * 0.5)
	casing.park()


func test_a_bullet_rings_steel_and_a_cover_differently() -> void:
	var target: Node3D = (load("res://sandbox/steel_target.tscn") as PackedScene).instantiate()
	add_child_autofree(target)
	var plate: RigidBody3D = target.get_node("Plate")
	var cartridge: CartridgeSpec = load("res://weapons/parts/cartridge_9x19.tres")
	await wait_physics_frames(2)
	Ballistics.pool.fire_bullet(cartridge, plate.global_position + Vector3(0, 0, 2), Vector3(0, 0, -300))
	await wait_physics_frames(10)
	var ring := _first(Sounds.Surface.METAL)
	assert_false(ring.is_empty(), "steel rings")
	if not ring.is_empty():
		assert_lt(ring["pitch"] as float, 1.0, "a 2.9 kg plate rings lower than a 1 kg gun")
		assert_gt(ring["volume"] as float, 0.2)
	_heard.clear()
	var cover := _floor(Sounds.Surface.WOOD)
	cover.position = Vector3(5, -0.5, 0)
	await wait_physics_frames(2)
	Ballistics.pool.fire_bullet(cartridge, Vector3(5, 2, 0), Vector3(0, -300, 0))
	await wait_physics_frames(10)
	assert_false(_first(Sounds.Surface.WOOD).is_empty(), "a bullet knocks on wood")
	assert_true(_first(Sounds.Surface.METAL).is_empty(), "and doesn't ring on it")


func test_the_quietest_voice_gives_way_and_the_quietest_sound_gets_none() -> void:
	var stream := Sounds.pool.stream_of(Sounds.Surface.METAL, false, 0)
	for i: int in Sounds.VOICE_COUNT:
		assert_true(Sounds.pool.play(stream, Vector3.ZERO, 0.5 if i > 0 else 0.3), "voice %d is free" % i)
	assert_false(Sounds.pool.play(stream, Vector3.ZERO, 0.2), "quieter than all of them")
	assert_true(Sounds.pool.play(stream, Vector3.ZERO, 1.0), "a shot takes the quietest")
	assert_false(Sounds.pool.play(stream, Vector3.ZERO, 0.4), "and nothing that quiet is left to take")


func test_a_hit_too_faint_to_hear_takes_no_voice() -> void:
	var stream := Sounds.pool.stream_of(Sounds.Surface.METAL, false, 0)
	assert_false(Sounds.pool.play(stream, Vector3.ZERO, Sounds.FAINTEST * 0.5))


func test_one_surface_cant_flood_the_voices() -> void:
	for i: int in 10:
		Sounds.pool.impact(Vector3.ZERO, Sounds.Surface.BRASS, 0.04, 3.0, 0.004)
	assert_eq(_heard.size(), 1, "the same hit in one tick is one sound")
	Sounds.pool.impact(Vector3.ZERO, Sounds.Surface.BRASS, 10.0, 3.0, 0.004)
	assert_eq(_heard.size(), 2, "unless it's louder")


func test_a_reload_settles_quietly() -> void:
	_floor()
	Ballistics.pool.clear()
	_box(1.0, 0.05)
	await wait_physics_frames(30)
	assert_eq(_heard.size(), 0, "within the hush")
	_box(1.0, 0.5).position.x = 2.0
	await wait_physics_frames(60)
	assert_gt(_heard.size(), 0, "and heard once it's over")


func test_a_gun_is_a_knock_and_a_steel_plate_is_a_ring() -> void:
	var gun := Sounds.pool.sound_of(Sounds.Surface.GUN)
	var steel := Sounds.pool.sound_of(Sounds.Surface.METAL)
	var gun_samples := _samples(Sounds.pool.stream_of(Sounds.Surface.GUN, true, 0))
	var steel_samples := _samples(Sounds.pool.stream_of(Sounds.Surface.METAL, true, 0))
	assert_lt(gun_samples.size() / float(SurfaceSound.MIX_RATE), 0.15, "over in a moment")
	assert_gt(steel_samples.size() / float(SurfaceSound.MIX_RATE), 0.3, "where a plate rings on")
	assert_gt(gun.modes.size() * 3, steel.modes.size() * 3, "and it has far more going on")
	assert_gt(gun.rattles, 0, "with its parts knocking together")


func test_a_rifle_blast_is_bigger_and_lower_than_a_pistols() -> void:
	var pistol: Gun = (load("res://weapons/pistol/pistol.tscn") as PackedScene).instantiate()
	var ar: Gun = (load("res://weapons/ar/ar.tscn") as PackedScene).instantiate()
	add_child_autofree(pistol)
	add_child_autofree(ar)
	var small := GunshotSound.of(pistol.cartridge, pistol.barrel_length, pistol.gas_port, pistol.bolt.mass)
	var big := GunshotSound.of(ar.cartridge, ar.barrel_length, ar.gas_port, ar.bolt.mass)
	# 25 MPa over 7.3 cm3 of bore, and 106 MPa over 9.4 cm3, with a gamma of about 1.24.
	assert_almost_eq(small.energy, 775.0, 80.0)
	assert_almost_eq(big.energy, 4170.0, 400.0)
	assert_almost_eq(small.blast_radius, 0.2, 0.01)
	assert_almost_eq(big.blast_radius, 0.345, 0.015)
	assert_lt(small.level, big.level)
	assert_gt(small.level, 0.4, "a pistol is no quiet thing")
	assert_true(GunshotSound.of(ar.cartridge, ar.barrel_length, ar.gas_port, ar.bolt.mass) == big, "baked only once")
	assert_lt(big.crack_time, small.crack_time, "and the faster, thinner bullet cracks sharper")
	assert_between(big.crack_time, 0.00005, 0.0002)
	assert_eq(GunshotSound.crack_duration(300.0, 0.009), 0.0, "a subsonic bullet has no crack")


func test_a_shot_starts_with_a_shock_and_has_weight_under_it() -> void:
	var ar: Gun = (load("res://weapons/ar/ar.tscn") as PackedScene).instantiate()
	add_child_autofree(ar)
	var shot := GunshotSound.of(ar.cartridge, ar.barrel_length, ar.gas_port, ar.bolt.mass)
	for take: AudioStreamWAV in shot.takes:
		var samples := _samples(take)
		var first_ms := 0.0
		for i: int in GunshotSound.MIX_RATE / 1000:
			first_ms = maxf(first_ms, absf(samples[i]))
		assert_gt(first_ms, 0.5, "the pressure jumps all at once")
		# The share of its energy that a low-pass at 500 Hz keeps.
		var low := 0.0
		var total := 0.0
		var filtered := 0.0
		var filter := 1.0 - exp(-TAU * 500.0 / GunshotSound.MIX_RATE)
		for sample: float in samples:
			filtered += (sample - filtered) * filter
			low += filtered * filtered
			total += sample * sample
		assert_gt(low / total, 0.3, "and plenty of it down low")
		assert_lt(_level(samples, samples.size() - 800, samples.size()), _level(samples, 0, 800) * 0.05, "it dies away")


func test_a_bolt_stop_stays_well_under_the_shot() -> void:
	var at := Vector3(90, 100, 0)
	var ar: Gun = (load("res://weapons/ar/ar.tscn") as PackedScene).instantiate()
	ar.position = at
	add_child_autofree(ar)
	var hand: PhysicsHand = (load("res://player/physics_hand.tscn") as PackedScene).instantiate()
	add_child_autofree(hand)
	hand.set_target(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), at))
	(load("res://weapons/parts/cartridge_556x45.tres") as CartridgeSpec).dud_chance = 0.0
	await wait_physics_frames(2)
	hand.input_grip = 1.0
	hand.grab(ar.grip)
	await wait_physics_frames(2)
	_heard.clear()
	hand.input_trigger = 1.0
	await wait_physics_frames(45)
	var stops := 0
	for sound: Dictionary in _heard:
		if sound["surface"] == Sounds.Surface.GUN:
			stops += 1
			assert_lt(sound["volume"] as float, 0.2, "a bolt on its stop is nothing next to the shot")
			assert_lt(sound["pitch"] as float, 0.8, "and rings at the pitch of the whole rifle")
	assert_gt(stops, 0)


func test_a_long_contact_hardly_sets_steel_ringing_and_a_short_one_does() -> void:
	var metal := Sounds.pool.sound_of(Sounds.Surface.METAL)
	assert_lt(metal.excitation(0.007), 0.1, "a hand on steel")
	assert_eq(metal.excitation(0.00005), 1.0, "a bullet on steel")
	assert_eq(metal.excitation(metal.hard_contact), 1.0, "a contact like the one it was baked for")

