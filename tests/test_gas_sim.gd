extends GutTest
## Interior ballistics against published cartridge numbers.

const NINE: CartridgeSpec = preload("res://weapons/parts/cartridge_9x19.tres")
const RIFLE: CartridgeSpec = preload("res://weapons/parts/cartridge_556x45.tres")
const PISTOL_BARREL := 0.114
const AR_BARREL := 0.368
const CARRIER_MASS := 0.395

var _shot: GasSim.Shot


func before_each() -> void:
	_shot = GasSim.Shot.new()


func test_9mm_matches_published_numbers() -> void:
	GasSim.simulate(NINE, PISTOL_BARREL, _shot)
	# 115 gr from a 4.5 in barrel: about 350 to 380 m/s, SAAMI maximum 235 MPa.
	assert_between(_shot.muzzle_velocity, 340.0, 390.0)
	assert_between(_shot.peak_pressure, 170.0e6, 240.0e6)
	# Barrel time under 1 ms, much shorter than a tick.
	assert_between(_shot.barrel_time, 0.3e-3, 1.0e-3)


func test_556_matches_published_numbers() -> void:
	GasSim.simulate(RIFLE, AR_BARREL, _shot, GasPortSpec.new(), CARRIER_MASS)
	# M855 from a 14.5 in barrel: about 880 to 900 m/s, about 380 to 430 MPa.
	assert_between(_shot.muzzle_velocity, 850.0, 930.0)
	assert_between(_shot.peak_pressure, 350.0e6, 440.0e6)
	# Free recoil of an M4 is about 6 N s.
	assert_between(_shot.breech_impulse, 5.5, 7.0)


func test_pressure_curve_rises_peaks_and_decays() -> void:
	_shot.record_curve = true
	GasSim.simulate(NINE, PISTOL_BARREL, _shot)
	var peak_index := 0
	for i: int in _shot.curve.size():
		if _shot.curve[i].y > _shot.curve[peak_index].y:
			peak_index = i
	var peak_time := _shot.curve[peak_index].x
	assert_between(peak_time, 0.02e-3, _shot.barrel_time, "peak is inside the barrel")
	assert_lt(_shot.curve[0].y, _shot.curve[peak_index].y * 0.2, "starts low")
	assert_lt(_shot.curve[_shot.curve.size() - 1].y, 1.0e6, "blows down to near atmospheric")


func test_longer_barrel_is_faster() -> void:
	GasSim.simulate(NINE, PISTOL_BARREL, _shot)
	var short := _shot.muzzle_velocity
	GasSim.simulate(NINE, PISTOL_BARREL * 2.0, _shot)
	assert_gt(_shot.muzzle_velocity, short)


func test_bigger_charge_is_faster_and_harder() -> void:
	GasSim.simulate(NINE, PISTOL_BARREL, _shot)
	var velocity := _shot.muzzle_velocity
	var pressure := _shot.peak_pressure
	GasSim.simulate(NINE, PISTOL_BARREL, _shot, null, 0.0, 1.1)
	assert_gt(_shot.muzzle_velocity, velocity)
	assert_gt(_shot.peak_pressure, pressure)


func test_breech_impulse_equals_bullet_and_gas_momentum() -> void:
	for spec: CartridgeSpec in [NINE, RIFLE]:
		GasSim.simulate(spec, PISTOL_BARREL if spec == NINE else AR_BARREL, _shot)
		var forward := _shot.bullet_momentum + _shot.gas_momentum
		assert_almost_eq(_shot.breech_impulse, forward, forward * 0.001)


func test_gas_port_drives_the_carrier_at_a_real_speed() -> void:
	var gun: Gun = preload("res://weapons/ar/ar.tscn").instantiate()
	GasSim.simulate(RIFLE, AR_BARREL, _shot, gun.gas_port, CARRIER_MASS)
	gun.free()
	# Bolt carrier group speed on an M4 is about 5 to 6 m/s.
	assert_between(_shot.carrier_impulse / CARRIER_MASS, 4.5, 6.5)
	assert_lt(_shot.carrier_impulse, _shot.breech_impulse)


func test_no_port_gives_no_carrier_impulse() -> void:
	GasSim.simulate(NINE, PISTOL_BARREL, _shot)
	assert_eq(_shot.carrier_impulse, 0.0)
