class_name GasSim
extends RefCounted
## Interior ballistics of one shot, integrated in sub-steps much shorter than a physics tick.
##
## In the bore: powder burns by Vieille's law, Resal's energy balance with the Noble-Abel equation of state
## gives the mean gas pressure, and the Lagrange gradient splits it into base and breech pressure.
## After the bullet leaves: isentropic blowdown through the muzzle with choked flow.
## The reaction on the breech is what becomes recoil.

## Reference pressure of the burn law.
const REFERENCE_PRESSURE := 2.0e8
## Sub-steps: the pressure rise takes about 100 us, the blowdown about 1 ms.
const BORE_STEP := 5.0e-6
const BLOWDOWN_STEP := 2.0e-5
## Thrust coefficient: 1.25 for an ideal sonic exit, lowered to 1.0 because the gas cools on the bore walls. Fits M4 free recoil of about 6 N s.
const THRUST_COEFFICIENT := 1.0
const DISCHARGE_COEFFICIENT := 0.9
## Blowdown counts as finished at about 2 atm.
const END_PRESSURE := 2.0e5
## A bullet still in the bore after this is stuck (squib).
const MAX_TIME := 0.012


class Shot:
	var muzzle_velocity := 0.0
	var peak_pressure := 0.0
	var muzzle_pressure := 0.0
	var barrel_time := 0.0
	## Total rearward impulse on the breech, in the bore plus blowdown.
	var breech_impulse := 0.0
	## Forward momentum of bullet and gas, which breech_impulse has to balance.
	var bullet_momentum := 0.0
	var gas_momentum := 0.0
	## Rearward impulse on the bolt carrier from the gas port (and the same forward on the frame).
	var carrier_impulse := 0.0
	var record_curve := false
	## (time, breech pressure) samples when record_curve is set.
	var curve := PackedVector2Array()


static func simulate(
	c: CartridgeSpec, barrel_length: float, shot: Shot, port: GasPortSpec = null,
	carrier_mass := 0.0, charge_scale := 1.0
) -> void:
	var area := c.bore_area()
	var m_b := c.bullet_mass
	var m_c := c.charge_mass * charge_scale
	var m_lagrange := m_b + m_c / 3.0
	var f_mc := c.powder_force * m_c
	var kinetic_term := 0.5 * (c.gas_gamma - 1.0) * m_lagrange
	var unburnt_volume := m_c / c.powder_density
	var burnt_volume := c.covolume * m_c
	var burn_factor := 1.0 / c.burn_time
	var engrave_force := area * c.engrave_pressure
	var friction_force := area * c.friction_pressure

	var z := c.primer_pressure * (c.chamber_volume - unburnt_volume) / f_mc
	var x := 0.0
	var v := 0.0
	var t := 0.0
	var p := c.primer_pressure
	var breech_impulse := 0.0
	var peak := 0.0
	var in_bore := true

	# Blowdown state, set when the bullet leaves.
	var gas_mass := m_c
	var bore_volume := 0.0
	var exit_density := 0.0
	var exit_pressure := 0.0
	var muzzle_impulse := 0.0
	var choke := pow(2.0 / (c.gas_gamma + 1.0), (c.gas_gamma + 1.0) / (2.0 * (c.gas_gamma - 1.0)))

	# Gas port state.
	var key_pressure := 0.0
	var carrier_x := 0.0
	var carrier_v := 0.0
	var carrier_active := port != null

	shot.muzzle_velocity = 0.0
	shot.muzzle_pressure = 0.0
	shot.barrel_time = 0.0
	shot.curve.clear()
	while t < MAX_TIME:
		var h := BORE_STEP if in_bore else BLOWDOWN_STEP
		if in_bore:
			# Heun step of burn fraction z, travel x, velocity v.
			var free_1 := c.chamber_volume + area * x - unburnt_volume * (1.0 - z) - burnt_volume * z
			var p_1 := (f_mc * z - kinetic_term * v * v) / free_1
			var a_1 := _acceleration(area * p_1, v, engrave_force, friction_force) / m_lagrange
			var dz_1 := burn_factor * pow(p_1 / REFERENCE_PRESSURE, c.burn_exponent) if z < 1.0 else 0.0

			var z_2 := minf(z + h * dz_1, 1.0)
			var x_2 := x + h * v
			var v_2 := maxf(v + h * a_1, 0.0)
			var free_2 := c.chamber_volume + area * x_2 - unburnt_volume * (1.0 - z_2) - burnt_volume * z_2
			var p_2 := (f_mc * z_2 - kinetic_term * v_2 * v_2) / free_2
			var a_2 := _acceleration(area * p_2, v_2, engrave_force, friction_force) / m_lagrange
			var dz_2 := burn_factor * pow(p_2 / REFERENCE_PRESSURE, c.burn_exponent) if z_2 < 1.0 else 0.0

			var v_before := v
			z = minf(z + 0.5 * h * (dz_1 + dz_2), 1.0)
			x += 0.5 * h * (v + v_2)
			v = maxf(v + 0.5 * h * (a_1 + a_2), 0.0)
			p = 0.5 * (p_1 + p_2)

			# Lagrange gradient: the gas column moves too, so the breech pressure is above base pressure.
			# Bore friction drags the barrel forward, so the frame only feels the momentum gained.
			var dv := v - v_before
			breech_impulse += (m_b + 0.5 * m_c) * dv
			var a := dv / h
			var resist := friction_force if v > 0.0 else 0.0
			var breech_pressure := (m_b * a + resist + 0.5 * m_c * a) / area if v > 0.0 else p
			peak = maxf(peak, breech_pressure)
			if shot.record_curve:
				shot.curve.append(Vector2(t, breech_pressure))

			if x >= barrel_length:
				in_bore = false
				shot.barrel_time = t
				shot.muzzle_velocity = v
				bore_volume = c.chamber_volume + area * barrel_length
				exit_density = gas_mass / bore_volume
				exit_pressure = p
				shot.muzzle_pressure = p
		else:
			# Isentropic blowdown: choked mass flow out of the muzzle, thrust on the breech.
			var density := gas_mass / bore_volume
			var mass_flow := DISCHARGE_COEFFICIENT * area * sqrt(c.gas_gamma * p * density) * choke
			muzzle_impulse += h * THRUST_COEFFICIENT * area * p
			gas_mass = maxf(gas_mass - h * mass_flow, 0.0)
			p = exit_pressure * pow(gas_mass / bore_volume / exit_density, c.gas_gamma)
			if shot.record_curve:
				shot.curve.append(Vector2(t, p))

		if carrier_active:
			var source := p if x >= port.port_distance else 0.0
			key_pressure += h * (port.pressure_ratio * source - key_pressure) / port.tube_lag
			carrier_v += h * key_pressure * port.piston_area / carrier_mass
			carrier_x += h * carrier_v
			carrier_active = carrier_x < port.vent_travel

		t += h
		if not in_bore and p < END_PRESSURE and not carrier_active:
			break

	shot.peak_pressure = peak
	shot.bullet_momentum = m_b * shot.muzzle_velocity
	shot.gas_momentum = 0.5 * m_c * shot.muzzle_velocity + muzzle_impulse
	shot.breech_impulse = breech_impulse + muzzle_impulse
	shot.carrier_impulse = carrier_mass * carrier_v


## Net force on the bullet: it stays put until the gas overcomes engraving, then only bore friction resists.
static func _acceleration(gas_force: float, v: float, engrave_force: float, friction_force: float) -> float:
	if v > 0.0:
		return gas_force - friction_force
	return maxf(gas_force - engrave_force, 0.0)
