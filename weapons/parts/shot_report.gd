class_name ShotReport
extends RefCounted
## Watches a gun after it fires and puts what the recoil did on the debug log, in one line once the gun has settled.

## Long enough for the muzzle to come back down. Another shot before then starts it over, so a burst gets one line.
const WATCH_TIME := 0.35

var _left := 0.0
var _shots := 0
var _aim := Vector3.ZERO
var _elapsed := 0.0
var _cycle_time := 0.0
var _was_out := false
var _bolt_speed := 0.0
var _travel := 0.0
var _stop := 0.0
var _flip := 0.0
var _kick := 0.0
var _hand_off := 0.0


func watching() -> bool:
	return _left > 0.0


func shot(frame: RigidBody3D) -> void:
	if not DebugLog.enabled:
		return
	if not watching():
		_shots = 0
		_aim = -frame.global_basis.z
		_bolt_speed = 0.0
		_travel = 0.0
		_stop = 0.0
		_flip = 0.0
		_kick = 0.0
		_hand_off = 0.0
	_shots += 1
	_left = WATCH_TIME
	_elapsed = 0.0
	_was_out = false


func tick(delta: float, gun: Gun, rail: Rail) -> void:
	_left -= delta
	_elapsed += delta
	_bolt_speed = maxf(_bolt_speed, absf(rail.velocity))
	_travel = maxf(_travel, rail.travel)
	_stop = maxf(_stop, rail.last_stop_impulse)
	if rail.travel > Gun.BATTERY_TOLERANCE:
		_was_out = true
	elif _was_out:
		_was_out = false
		_cycle_time = _elapsed
	_flip = maxf(_flip, rad_to_deg(_aim.angle_to(-gun.frame.global_basis.z)))
	_kick = maxf(_kick, gun.frame.linear_velocity.length())
	var hand := gun.grip.holder
	if hand:
		_hand_off = maxf(_hand_off, hand.global_position.distance_to(hand.target.origin))
	if _left <= 0.0:
		DebugLog.event("recoil", "%s after %d shot%s: cycle %.0f ms, bolt %.1f m/s over %.0f mm, stop %.2f N s, muzzle flip %.1f deg, frame %.2f m/s, hand %.1f cm off controller" % [
			gun.name, _shots, "" if _shots == 1 else "s", _cycle_time * 1000.0, _bolt_speed, _travel * 1000.0, _stop, _flip,
			_kick, _hand_off * 100.0
		])
