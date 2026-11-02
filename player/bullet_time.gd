class_name BulletTime
extends Node
## Slows the world with Engine.time_scale. Godot keeps ticking at the same real rate and hands everything a shorter
## delta, so motion stays as smooth as ever, the physics gets finer, and every equation still runs on its own time
## step: a bullet still leaves at full speed and a slide still takes its full 80 ms to cycle, only seen from further
## inside it. The head is the headset's own and PhysicsHand keeps the hands on the controllers, in real time.

## 9 mm at 36 m/s and 5.56 mm at 90 m/s: slow enough to see one cross the range, about 14 frames over 7 m from a pistol.
@export_range(0.05, 1.0, 0.01) var slow_scale := 0.1
## Real seconds to reach full slow and to come back from it.
@export var ramp_time := 0.25
## Real seconds of slow time in a full meter, and to fill one from empty.
@export var capacity := 6.0
@export var recharge_time := 24.0
## A meter below this won't start, so tapping an empty one doesn't stutter time.
@export_range(0.0, 1.0, 0.01) var least_charge := 0.15
## Sound slows with the world down to this speed. Any lower and a shot is a rumble too deep to place.
@export_range(0.05, 1.0, 0.01) var slowest_sound := 0.3
## Shows the meter by scaling along its local Y, so its origin goes at the end of the bar that stays put.
@export var meter: Node3D

var active := false
## 0 to 1.
var charge := 1.0

var _was_pressed := false
## 0 at normal speed, 1 at full slow. time_scale follows it exponentially, so the slowdown looks even all the way down.
var _depth := 0.0


func _ready() -> void:
	if meter:
		meter.visible = false


func _exit_tree() -> void:
	_set_time_scale(1.0)


## Advances by one tick of real time. Returns whether the press did something, so the caller can thump the controller.
func update(pressed: bool, tick: float) -> bool:
	var changed := false
	if pressed and not _was_pressed and (active or charge >= least_charge):
		_set_active(not active)
		changed = true
	_was_pressed = pressed
	if active:
		charge = maxf(charge - tick / capacity, 0.0)
		if charge == 0.0:
			_set_active(false)
			changed = true
	else:
		charge = minf(charge + tick / recharge_time, 1.0)
	var depth := move_toward(_depth, 1.0 if active else 0.0, tick / ramp_time)
	if depth != _depth:
		_depth = depth
		_set_time_scale(pow(slow_scale, _depth))
	if meter:
		meter.visible = charge < 1.0
		meter.scale.y = maxf(charge, 0.001)
	return changed


func _set_active(on: bool) -> void:
	active = on
	DebugLog.event("time", "bullet time %s, %.1f s of charge left" % ["on" if on else "off", charge * capacity])


func _set_time_scale(scale: float) -> void:
	Engine.time_scale = scale
	AudioServer.playback_speed_scale = maxf(scale, slowest_sound)
