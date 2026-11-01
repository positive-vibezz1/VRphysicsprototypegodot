extends GutTest
## Trigger, sear, hammer, firing pin and primer without any physics bodies.

const DT := 1.0 / 90.0
const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")

var _fc: FireControl
var _rng: RandomNumberGenerator


func before_each() -> void:
	_fc = FireControl.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 1234


func after_each() -> void:
	_fc.free()


func _run(ticks: int, finger: float, bolt_travel := 0.0, in_battery := true) -> float:
	var strike := -1.0
	for i: int in ticks:
		strike = maxf(strike, _fc.tick(DT, finger, bolt_travel, in_battery))
	return strike


func test_mainspring_energy_is_the_integral_of_its_torque() -> void:
	var angle := 1.0
	var expected := _fc.mainspring_preload * angle + 0.5 * _fc.mainspring_rate * angle * angle
	assert_almost_eq(_fc.spring_energy(angle), expected, 1.0e-9)


func test_hammer_speed_matches_spring_energy() -> void:
	_fc.cock_now()
	var energy := _fc.spring_energy(_fc.cocked_angle)
	var strike := _fc.tick(DT, _fc.break_force, 0.0, true)
	var expected_speed := sqrt(2.0 * energy / _fc.hammer_inertia)
	var expected_strike := _fc.strike_energy(expected_speed)
	assert_almost_eq(strike, expected_strike, expected_strike * 0.03)


func test_light_trigger_pressure_does_not_fire() -> void:
	_fc.cock_now()
	assert_eq(_run(10, _fc.break_force - 1.0), -1.0)
	assert_eq(_fc.hammer_state, FireControl.Hammer.SEAR)


func test_break_force_drops_the_hammer_onto_the_pin() -> void:
	_fc.cock_now()
	var strike := _run(2, _fc.break_force)
	assert_gt(strike, 0.0)
	assert_eq(_fc.hammer_state, FireControl.Hammer.DOWN)


func test_strike_happens_within_one_tick() -> void:
	_fc.cock_now()
	assert_gt(_fc.tick(DT, _fc.break_force, 0.0, true), 0.0)


func test_hammer_down_gives_a_dead_trigger() -> void:
	assert_eq(_run(10, 45.0), -1.0)


func test_safety_blocks_the_sear() -> void:
	_fc.cock_now()
	_fc.selector = FireControl.Selector.SAFE
	assert_eq(_run(10, 45.0), -1.0)
	assert_eq(_fc.hammer_state, FireControl.Hammer.SEAR)


func test_bolt_cocks_the_hammer_and_spends_energy() -> void:
	_fc.tick(DT, 0.0, _fc.cock_travel, true)
	assert_almost_eq(_fc.hammer_angle, _fc.cocked_angle, 1.0e-6)
	assert_almost_eq(_fc.cock_work, _fc.spring_energy(_fc.cocked_angle), 1.0e-6)
	assert_eq(_fc.hammer_state, FireControl.Hammer.SEAR)


func test_semi_needs_a_trigger_reset() -> void:
	_fc.cock_now()
	_run(2, 45.0)
	# Trigger still held while the bolt cycles: the disconnector catches the hammer.
	_fc.tick(DT, 45.0, _fc.cock_travel, false)
	assert_eq(_fc.hammer_state, FireControl.Hammer.DISCONNECTOR)
	assert_eq(_run(5, 45.0), -1.0, "held trigger does not fire again")
	_run(1, 0.0)
	assert_eq(_fc.hammer_state, FireControl.Hammer.SEAR, "reset hands the hammer to the sear")
	assert_gt(_run(2, _fc.break_force), 0.0, "second pull fires")


func test_auto_fires_when_the_bolt_returns() -> void:
	_fc.has_auto = true
	_fc.selector = FireControl.Selector.AUTO
	_fc.cock_now()
	_run(2, 45.0)
	_fc.tick(DT, 45.0, _fc.cock_travel, false)
	assert_eq(_fc.hammer_state, FireControl.Hammer.AUTO_SEAR)
	assert_eq(_fc.tick(DT, 45.0, 0.02, false), -1.0, "bolt still out of battery")
	assert_gt(_run(2, 45.0), 0.0, "fires in battery")


func test_out_of_battery_does_not_strike() -> void:
	_fc.cock_now()
	assert_eq(_run(2, _fc.break_force, 0.01, false), -1.0)


func test_weak_mainspring_gives_a_light_strike() -> void:
	_fc.mainspring_preload = 0.1
	_fc.mainspring_rate = 0.05
	_fc.cock_now()
	var strike := _run(5, _fc.break_force)
	assert_lt(strike, NINE.all_fire_energy, "too weak for a reliable ignition")


func test_service_mainspring_is_above_the_all_fire_energy() -> void:
	_fc.cock_now()
	assert_gt(_run(2, _fc.break_force), NINE.all_fire_energy)


func test_primer_below_threshold_never_fires() -> void:
	for i: int in 100:
		assert_false(NINE.primer_fires(NINE.no_fire_energy * 0.9, _rng))


func test_primer_above_threshold_fires_except_for_duds() -> void:
	var fired := 0
	for i: int in 2000:
		if NINE.primer_fires(NINE.all_fire_energy * 1.1, _rng):
			fired += 1
	var expected := 2000.0 * (1.0 - NINE.dud_chance)
	assert_almost_eq(float(fired), expected, 15.0)


func test_primer_between_thresholds_sometimes_fires() -> void:
	var fired := 0
	var energy := 0.5 * (NINE.no_fire_energy + NINE.all_fire_energy)
	for i: int in 1000:
		if NINE.primer_fires(energy, _rng):
			fired += 1
	assert_between(fired, 400, 600)
