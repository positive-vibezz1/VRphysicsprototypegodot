class_name GasPortSpec
extends Resource
## Direct impingement gas system: gas tapped from the bore pushes the bolt carrier through the carrier key.

## Distance from the chamber to the gas port.
@export var port_distance := 0.188
## Share of bore pressure that gets through the small port and tube to the carrier key.
@export var pressure_ratio := 0.15
## First order lag of gas filling the tube and key.
@export var tube_lag := 0.0005
## Area the gas pushes on: the bolt tail, about 9 mm across on an AR.
@export var piston_area := 6.3e-5
## Carrier travel at which the gas rings uncover the vents and the push ends.
@export var vent_travel := 0.0045
