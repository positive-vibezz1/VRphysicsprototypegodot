class_name CartridgeSpec
extends Resource
## Real data for one cartridge, in SI units. Used by GasSim, FireControl and the bullet and casing pools.

@export_group("Bullet")
@export var bullet_mass := 0.0075
@export var bore_diameter := 0.00902
## Constant drag coefficient over the speeds a sandbox range sees, fitted to published velocity tables.
@export var drag_coefficient := 0.3

@export_group("Propellant")
@export var charge_mass := 0.00036
## Case volume behind the seated bullet.
@export var chamber_volume := 6.0e-7
## Powder force (impetus), R * T of the burnt gas. Real powders are about 1.0 MJ/kg before heat loss.
@export var powder_force := 1.0e6
@export var powder_density := 1600.0
## Noble-Abel co-volume, about 1 cm3/g for propellant gas.
@export var covolume := 1.0e-3
@export var gas_gamma := 1.24
## Vieille burn law: dz/dt = (p / GasSim.REFERENCE_PRESSURE) ^ burn_exponent / burn_time.
@export var burn_time := 0.0005
@export var burn_exponent := 0.9
## Pressure the primer flash gives the chamber before the powder burns.
@export var primer_pressure := 1.0e7
## Pressure needed to push the bullet into the rifling.
@export var engrave_pressure := 2.0e7
## Bore friction once the bullet is moving, as a pressure.
@export var friction_pressure := 5.0e6

@export_group("Primer")
## Ball-drop sensitivity data: below no_fire nothing ignites, above all_fire everything does.
@export var no_fire_energy := 0.05
@export var all_fire_energy := 0.35
## Chance a well struck primer is a dud anyway.
@export var dud_chance := 0.002

@export_group("Case")
@export var casing_mass := 0.0042
@export var round_mass := 0.012
@export var casing_length := 0.019
@export var casing_radius := 0.0049


func bore_area() -> float:
	return PI * 0.25 * bore_diameter * bore_diameter


## Between no_fire and all_fire the ignition chance grows linearly, like a ball-drop sensitivity curve.
func primer_fires(energy: float, rng: RandomNumberGenerator) -> bool:
	var chance := clampf(inverse_lerp(no_fire_energy, all_fire_energy, energy), 0.0, 1.0)
	return rng.randf() < chance and rng.randf() >= dud_chance
