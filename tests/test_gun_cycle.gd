extends GutTest
## Full guns in the real physics server, floating free so nothing but the gun's own forces act on them.

const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _shots: Array[float] = []
var _last_shot_impulse := 0.0
var _last_bullet_momentum := 0.0
var _last_gas_momentum := 0.0
var _hand: PhysicsHand
var _watched: Gun
var _furthest := 0.0


## A dud stops a gun until it is racked, which would fail these tests at random. test_fire_control covers duds.
func before_all() -> void:
	(load("res://weapons/parts/cartridge_9x19.tres") as CartridgeSpec).dud_chance = 0.0
	(load("res://weapons/parts/cartridge_556x45.tres") as CartridgeSpec).dud_chance = 0.0


func before_each() -> void:
	_shots.clear()
	Ballistics.pool.clear()
	_furthest = 0.0
	_hand = null


func after_each() -> void:
	if get_tree().physics_frame.is_connected(_on_physics_frame):
		get_tree().physics_frame.disconnect(_on_physics_frame)
	_watched = null


## Records the furthest bolt travel on every tick.
func _watch(gun: Gun) -> void:
	_watched = gun
	get_tree().physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if is_instance_valid(_watched):
		_furthest = maxf(_furthest, _travel(_watched))


func _spawn(scene: PackedScene) -> Gun:
	var gun: Gun = scene.instantiate()
	add_child_autofree(gun)
	for body: RigidBody3D in gun.bodies():
		body.gravity_scale = 0.0
		body.can_sleep = false
	gun.shot_fired.connect(_on_shot)
	return gun


## A gun in a firm hand: a free floating pistol frame is too light to work against, which is limp wristing.
func _spawn_held(scene: PackedScene) -> Gun:
	var gun: Gun = scene.instantiate()
	gun.position = Vector3(0, 100, 0)
	add_child_autofree(gun)
	gun.shot_fired.connect(_on_shot)
	_hand = HAND_SCENE.instantiate()
	add_child_autofree(_hand)
	_hand.set_target(Transform3D(LEVEL_GRIP, Vector3(0, 100, 0)))
	await wait_physics_frames(1)
	_hand.input_grip = 1.0
	_hand.grab(gun.grip)
	await wait_physics_frames(10)
	return gun


## Pulls or lets go of the trigger, through the hand if one holds the gun.
func _trigger(gun: Gun, pulled: bool) -> void:
	if _hand:
		_hand.input_trigger = 1.0 if pulled else 0.0
	else:
		gun.finger_force = gun.fire_control.break_force + 20.0 if pulled else 0.0


func _on_shot(shot: GasSim.Shot, _energy: float) -> void:
	_shots.append(shot.muzzle_velocity)
	_last_shot_impulse = shot.breech_impulse
	_last_bullet_momentum = shot.bullet_momentum
	_last_gas_momentum = shot.gas_momentum


func _momentum(gun: Gun) -> Vector3:
	var total := Vector3.ZERO
	for body: RigidBody3D in gun.bodies():
		total += body.linear_velocity * body.mass
	return total


func _travel(gun: Gun) -> float:
	return (gun.frame.global_transform.affine_inverse() * gun.bolt.global_position).z - gun._rail._rest_z


func test_pistol_stays_in_battery_at_rest() -> void:
	var gun := _spawn(PISTOL_SCENE)
	await wait_physics_frames(30)
	assert_almost_eq(_travel(gun), 0.0, 0.001)
	assert_lt(gun.frame.linear_velocity.length(), 0.01, "spring and stop cancel out")


func test_pistol_fires_and_cycles() -> void:
	var gun := await _spawn_held(PISTOL_SCENE)
	await wait_physics_frames(3)
	var before := gun.mag_well.magazine.count
	_watch(gun)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	assert_eq(_shots.size(), 1, "one shot")
	await wait_physics_frames(30)
	assert_gt(_furthest, gun.eject_travel, "slide went past the ejector")
	assert_lt(_furthest, gun.bolt_travel + 0.02, "slide stayed on its rails, give or take a tick")
	assert_almost_eq(_travel(gun), 0.0, 0.002, "back in battery")
	assert_eq(gun.chamber, Gun.Chamber.LIVE, "chambered the next round")
	assert_eq(gun.mag_well.magazine.count, before - 1)
	assert_eq(gun.fire_control.hammer_state, FireControl.Hammer.SEAR, "hammer recocked")


func test_slide_does_not_twitch_after_a_shot() -> void:
	var gun := await _spawn_held(PISTOL_SCENE)
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(25)
	var furthest_forward := 0.0
	for i: int in 180:
		await wait_physics_frames(1)
		furthest_forward = minf(furthest_forward, _travel(gun))
	assert_gt(furthest_forward, -0.003, "the spring never throws it past the stop at rest")


func test_pistol_momentum_goes_where_the_gas_says() -> void:
	var gun := _spawn(PISTOL_SCENE)
	await wait_physics_frames(3)
	var before := _momentum(gun)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(2)
	assert_eq(_shots.size(), 1)
	var gained := (_momentum(gun) - before).length()
	assert_almost_eq(gained, _last_bullet_momentum + _last_gas_momentum, 0.03 * _last_shot_impulse)


func test_ar_momentum_goes_where_the_gas_says() -> void:
	var gun := _spawn(AR_SCENE)
	await wait_physics_frames(3)
	var before := _momentum(gun)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(2)
	assert_eq(_shots.size(), 1)
	var gained := (_momentum(gun) - before).length()
	assert_almost_eq(gained, _last_bullet_momentum + _last_gas_momentum, 0.03 * _last_shot_impulse)


func test_ar_semi_fires_once_per_pull() -> void:
	var gun := await _spawn_held(AR_SCENE)
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(40)
	assert_eq(_shots.size(), 1, "one shot on a held trigger")
	_trigger(gun, false)
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(3)
	assert_eq(_shots.size(), 2, "reset and pull fires again")


func test_ar_auto_cycles_at_a_real_rate() -> void:
	var gun := await _spawn_held(AR_SCENE)
	gun.fire_control.selector = FireControl.Selector.AUTO
	await wait_physics_frames(3)
	var start := gun.mag_well.magazine.count
	_trigger(gun, true)
	await wait_physics_frames(90)
	_trigger(gun, false)
	# One second of fire. An M4 cycles about 700 to 950 rounds a minute, 12 to 16 a second.
	assert_between(_shots.size(), 9, 18, "shots per second")
	assert_between(gun.mag_well.magazine.count, start - _shots.size(), start - _shots.size() + 1, "one fed per shot")


## At 120 Hz the carrier could reach battery still moving forward fast, and firing then took its speed off the shot's,
## so the next stroke fell short of the ejector and the hammer hit the spent case.
func test_ar_auto_empties_a_magazine_at_every_refresh_rate() -> void:
	for rate: int in Player.KNOWN_REFRESH_RATES:
		Engine.physics_ticks_per_second = rate
		_shots.clear()
		var clicks: Array[float] = []
		var gun := await _spawn_held(AR_SCENE)
		gun.misfired.connect(clicks.append)
		gun.fire_control.selector = FireControl.Selector.AUTO
		_trigger(gun, true)
		await wait_physics_frames(rate * 4)
		_trigger(gun, false)
		assert_eq(_shots.size(), 31, "%d Hz: the chambered round and all 30 in the magazine" % rate)
		assert_eq(clicks.size(), 0, "%d Hz: no clicks on a spent case" % rate)
		gun.free()
		_hand.free()
	Engine.physics_ticks_per_second = 90


func test_ar_burst_fires_three_per_pull() -> void:
	var gun := await _spawn_held(AR_SCENE)
	gun.fire_control.selector = FireControl.Selector.BURST
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(60)
	assert_eq(_shots.size(), 3, "three on a held trigger")
	_trigger(gun, false)
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(60)
	assert_eq(_shots.size(), 6, "three more after a reset")


func test_fire_mode_steps_and_shows_on_the_gun() -> void:
	var gun := await _spawn_held(AR_SCENE)
	var label: Label3D = gun.frame.get_node("SelectorLabel")
	assert_eq(label.text, "SEMI")
	assert_true(gun.cycle_fire_mode())
	assert_eq(gun.fire_control.selector, FireControl.Selector.BURST)
	assert_eq(label.text, "BURST", "the gun shows what it is set to")


func test_a_shared_button_releases_a_locked_bolt_instead_of_changing_fire_mode() -> void:
	var gun := await _spawn_held(AR_SCENE)
	gun.catch_engaged = true
	_hand.input_bolt_release = true
	_hand.input_fire_mode = true
	await wait_physics_frames(2)
	_hand.input_bolt_release = false
	_hand.input_fire_mode = false
	assert_false(gun.catch_engaged, "bolt released")
	assert_eq(gun.fire_control.selector, FireControl.Selector.SEMI, "fire mode left alone")
	await wait_physics_frames(2)
	_hand.input_bolt_release = true
	_hand.input_fire_mode = true
	await wait_physics_frames(2)
	_hand.input_bolt_release = false
	_hand.input_fire_mode = false
	assert_eq(gun.fire_control.selector, FireControl.Selector.BURST, "with no locked bolt it changes the fire mode")


func test_pistol_has_no_selector_to_change() -> void:
	var gun := await _spawn_held(PISTOL_SCENE)
	assert_false(gun.cycle_fire_mode())
	assert_eq(gun.fire_control.selector, FireControl.Selector.SEMI)


func test_a_shot_reports_the_bolt_hitting_its_stops() -> void:
	var gun := await _spawn_held(AR_SCENE)
	watch_signals(gun)
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(30)
	assert_signal_emitted(gun, "bolt_stopped")


func test_magazine_runs_dry_and_the_bolt_locks_back() -> void:
	var gun := await _spawn_held(PISTOL_SCENE)
	gun.mag_well.magazine.count = 1
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(40)
	assert_eq(gun.chamber, Gun.Chamber.LIVE, "last round chambered")
	assert_eq(gun.mag_well.magazine.count, 0)
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(40)
	assert_eq(_shots.size(), 2)
	assert_true(gun.catch_engaged, "bolt catch up on an empty magazine")
	assert_almost_eq(_travel(gun), gun.catch_travel, 0.004, "held open")
	assert_eq(gun.chamber, Gun.Chamber.EMPTY)
	gun.release_bolt()
	await wait_physics_frames(40)
	assert_almost_eq(_travel(gun), 0.0, 0.002, "release sends it home")


func test_empty_chamber_clicks_nothing_and_racking_loads() -> void:
	var gun := _spawn(PISTOL_SCENE)
	gun.chamber = Gun.Chamber.EMPTY
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(3)
	_trigger(gun, false)
	assert_eq(_shots.size(), 0, "no round no bang")
	assert_eq(gun.fire_control.hammer_state, FireControl.Hammer.DOWN, "hammer fell on nothing")
	# Pull the slide back like a hand would and let it go.
	for i: int in 25:
		gun.bolt.apply_central_force(gun.frame.global_basis.z * 200.0)
		gun.frame.apply_central_force(-gun.frame.global_basis.z * 200.0)
		await wait_physics_frames(1)
	assert_gt(_travel(gun), gun.feed_travel, "slide came back")
	await wait_physics_frames(40)
	assert_eq(gun.chamber, Gun.Chamber.LIVE, "spring chambered a round")
	assert_almost_eq(_travel(gun), 0.0, 0.002)
	assert_eq(gun.fire_control.hammer_state, FireControl.Hammer.SEAR)
	_trigger(gun, true)
	await wait_physics_frames(2)
	assert_eq(_shots.size(), 1, "and it fires")


func test_magazine_drops_and_reseats() -> void:
	var gun := _spawn(PISTOL_SCENE)
	await wait_physics_frames(3)
	var mag := gun.mag_well.magazine
	mag.gravity_scale = 1.0
	# Gun held upright: gravity on the magazine alone is enough once the latch lets go.
	gun.release_magazine()
	await wait_physics_frames(40)
	assert_null(gun.mag_well.magazine, "fell clear of the rails")
	assert_gt(gun.mag_well._depth_of(mag), gun.mag_well.engage_length)
	# Offered back from below in line with the well, and pushed in.
	mag.gravity_scale = 0.0
	mag.linear_velocity = Vector3.ZERO
	mag.angular_velocity = Vector3.ZERO
	mag.global_transform = gun.mag_well.global_transform.translated(-gun.mag_well.global_basis.y * 0.05)
	await wait_physics_frames(3)
	assert_eq(gun.mag_well.magazine, mag, "captured by the well")
	for i: int in 20:
		mag.apply_central_force(gun.mag_well.global_basis.y * 10.0)
		await wait_physics_frames(1)
	assert_true(gun.mag_well.latched, "latched when seated")
	assert_almost_eq(gun.mag_well._depth_of(mag), 0.0, 0.006)


func test_seated_magazine_stays_put_through_a_shot() -> void:
	var gun := await _spawn_held(PISTOL_SCENE)
	await wait_physics_frames(3)
	var mag := gun.mag_well.magazine
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	var worst := 0.0
	for i: int in 30:
		await wait_physics_frames(1)
		worst = maxf(worst, absf(gun.mag_well._depth_of(mag)))
	assert_lt(worst, 0.003, "latched magazine does not move on its rails")


func test_ar_charging_handle_pulls_the_carrier_and_stays_when_it_fires() -> void:
	var gun := await _spawn_held(AR_SCENE)
	await wait_physics_frames(3)
	var rear := gun.frame.global_basis.z
	for i: int in 40:
		gun.charging_handle.apply_central_force(rear * 120.0)
		gun.frame.apply_central_force(-rear * 120.0)
		await wait_physics_frames(1)
	assert_gt(_travel(gun), 0.05, "handle dragged the carrier back")
	await wait_physics_frames(60)
	assert_almost_eq(_travel(gun), 0.0, 0.003, "spring sent the carrier home")
	var handle_z := (gun.frame.global_transform.affine_inverse() * gun.charging_handle.global_position).z
	_trigger(gun, true)
	await wait_physics_frames(2)
	_trigger(gun, false)
	await wait_physics_frames(2)
	var handle_after := (gun.frame.global_transform.affine_inverse() * gun.charging_handle.global_position).z
	assert_almost_eq(handle_after, handle_z, 0.01, "handle does not ride along when the carrier cycles")
	assert_gt(_shots.size(), 0, "fired")


func test_gun_stays_stable_for_a_long_string_of_fire() -> void:
	var gun := await _spawn_held(AR_SCENE)
	gun.fire_control.selector = FireControl.Selector.AUTO
	await wait_physics_frames(3)
	_trigger(gun, true)
	await wait_physics_frames(120)
	_trigger(gun, false)
	await wait_physics_frames(30)
	var offset := gun.bolt.global_position - gun.frame.global_position
	assert_lt(offset.length(), 0.3, "parts did not fly apart")
	assert_gt(_shots.size(), 8)
