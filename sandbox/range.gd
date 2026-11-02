extends Node3D
## Test range. Shows the controls for the controller in use, and the numbers of the last shot, since those can't
## be felt directly.

const FRAME_PROFILE := "/interaction_profiles/valve/frame_controller_valve"
const COMMON_CONTROLS := """Grip: grab. Point at a gun or mag up to 1.5 m away, then grip, to pull it to you.
Trigger: fire. Free hand on the slide or charging handle: rack.
Grip a ladder, pipe, red ledge or crevice: climb. Jump on a ledge: mantle.
Trigger on an empty hand, at the dot: grapple. Pull your arm back to haul.
"""
const FRAME_CONTROLS := COMMON_CONTROLS + """A or D-pad down: drop mag. B or D-pad right: fire mode. X or D-pad left: bolt release.
Left stick: move, L3 or L1 toggles run. Right stick: turn, R3 or R1 or flick up to jump.
Menu: reset. Hold View with an empty left hand: adjust where your hands sit."""
const TOUCH_CONTROLS := COMMON_CONTROLS + """A or X: drop mag. B or Y: fire mode, or bolt release when locked back.
Left stick: move, click toggles run. Right stick: turn, click or flick up to jump.
Menu: reset. Hold Y with an empty left hand: adjust where your hands sit."""

@onready var _readout: Label3D = $Table/Readout
@onready var _controls: Label3D = $Table/Controls


func _ready() -> void:
	Ballistics.pool.clear()
	for gun: Gun in [$Pistol as Gun, $AR as Gun]:
		gun.shot_fired.connect(_on_shot_fired.bind(gun))
		gun.misfired.connect(_on_misfired.bind(gun))
	var player: Player = $Player
	player.controllers_changed.connect(_show_controls)
	_show_controls(player.controller_profile)


func _show_controls(profile: String) -> void:
	_controls.text = FRAME_CONTROLS if profile == FRAME_PROFILE else TOUCH_CONTROLS


func _on_shot_fired(shot: GasSim.Shot, strike_energy: float, gun: Gun) -> void:
	_readout.text = "%s\n%.0f m/s   %.0f MPa peak   %.1f ms in bore\nrecoil %.2f N s   pin %.2f J" % [
		gun.name, shot.muzzle_velocity, shot.peak_pressure / 1.0e6, shot.barrel_time * 1000.0,
		shot.breech_impulse, strike_energy
	]


func _on_misfired(strike_energy: float, gun: Gun) -> void:
	_readout.text = "%s\nclick: no fire, pin %.2f J\nrack it to clear" % [gun.name, strike_energy]
