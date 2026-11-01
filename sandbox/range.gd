extends Node3D
## Test range. Shows the numbers of the last shot on the table, since those can't be felt directly.

@onready var _readout: Label3D = $Table/Readout


func _ready() -> void:
	Ballistics.pool.clear()
	for gun: Gun in [$Pistol as Gun, $AR as Gun]:
		gun.shot_fired.connect(_on_shot_fired.bind(gun))
		gun.misfired.connect(_on_misfired.bind(gun))


func _on_shot_fired(shot: GasSim.Shot, strike_energy: float, gun: Gun) -> void:
	_readout.text = "%s\n%.0f m/s   %.0f MPa peak   %.1f ms in bore\nrecoil %.2f N s   pin %.2f J" % [
		gun.name, shot.muzzle_velocity, shot.peak_pressure / 1.0e6, shot.barrel_time * 1000.0,
		shot.breech_impulse, strike_energy
	]


func _on_misfired(strike_energy: float, gun: Gun) -> void:
	_readout.text = "%s\nclick: no fire, pin %.2f J\nrack it to clear" % [gun.name, strike_energy]
