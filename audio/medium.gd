class_name Medium
extends Resource
## What fills a space, in real values.

## What's everywhere there's no MediumVolume. Set at startup by Sounds, since a script can't preload a resource made
## from itself.
static var ambient: Medium

## kg/m3.
@export var density := 1.204
## m/s. It doesn't change with pressure in a gas, only with what the gas is and how warm.
@export var sound_speed := 343.0
## What it takes off the high frequencies, in dB per meter at 8 kHz.
@export var absorption := 0.117
## Splashes when something goes in.
@export var is_liquid := false


## How hard it is to set moving, in rayl. Sound crosses between two media according to how close these are.
func impedance() -> float:
	return density * sound_speed


## The share of sound power that gets across a flat boundary between two impedances, head on.
static func transmission(a: float, b: float) -> float:
	return 4.0 * a * b / ((a + b) * (a + b)) if a + b > 0.0 else 0.0
