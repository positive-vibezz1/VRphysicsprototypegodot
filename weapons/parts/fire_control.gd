class_name FireControl
extends Node
## Trigger, sear, hammer and firing pin of one gun. Gun steps this once per physics tick.
##
## These parts weigh grams and move in about a millisecond: at 90 Hz a sprung hammer as a Jolt body would
## cross its whole arc in one tick (omega * dt well above 2), so they are integrated here in sub-steps with
## the real spring torque, and the pin strike is the elastic collision of the hammer and the pin.

enum Selector { SAFE, SEMI, AUTO }
enum Hammer { DOWN, SEAR, DISCONNECTOR, AUTO_SEAR, FALLING }

## 50 us: the hammer falls in about 2 to 4 ms, so about 60 steps per fall.
const SUB_STEP := 5.0e-5

@export var hammer_visual: Node3D
@export var trigger_visual: Node3D
@export var selector_visual: Node3D

@export_group("Trigger")
## Finger force below this does not move the trigger.
@export var trigger_preload := 4.0
@export var trigger_rate := 1200.0
## Free travel up to the sear wall.
@export var take_up_travel := 0.004
@export var total_travel := 0.007
## The trigger resets when it comes back this close to rest.
@export var reset_travel := 0.0025
## Pull weight at the sear: 25 N is about 5.5 lb.
@export var break_force := 25.0
@export var has_auto := false

@export_group("Hammer")
## About 20 g at 18 mm from the pivot.
@export var hammer_inertia := 6.5e-6
## Mainspring torque with the hammer down, and its rate. Stores about 1 J when cocked, like a service pistol.
@export var mainspring_preload := 0.8
@export var mainspring_rate := 0.4
@export var cocked_angle := 1.0
## Distance from the hammer pivot to the firing pin.
@export var strike_radius := 0.018
## Bolt travel that pushes the hammer fully back.
@export var cock_travel := 0.03

@export_group("Firing pin")
@export var pin_mass := 0.008
@export var pin_restitution := 0.8
## Pin flight to the primer and its return spring.
@export var pin_gap := 0.0015
@export var pin_return_force := 8.0

var selector := Selector.SEMI
var hammer_state := Hammer.DOWN
var hammer_angle := 0.0
var hammer_speed := 0.0
var trigger_travel := 0.0
var trigger_pulled := false
## Energy the bolt spent pushing the hammer back during the last tick.
var cock_work := 0.0


## Advances one tick. Returns the pin energy at the primer if the pin struck this tick, otherwise -1.
func tick(delta: float, finger_force: float, bolt_travel: float, in_battery: bool) -> float:
	_cock(bolt_travel)
	_update_trigger(finger_force, in_battery)
	var strike := -1.0
	if hammer_state == Hammer.FALLING:
		strike = _fall(delta, bolt_travel, in_battery)
	if hammer_visual:
		hammer_visual.rotation.x = hammer_angle
	if trigger_visual:
		trigger_visual.rotation.x = -trigger_travel / 0.02
	return strike


func cock_now() -> void:
	hammer_angle = cocked_angle
	hammer_speed = 0.0
	hammer_state = Hammer.SEAR


func cycle_selector() -> void:
	match selector:
		Selector.SAFE:
			selector = Selector.SEMI
		Selector.SEMI:
			selector = Selector.AUTO if has_auto else Selector.SAFE
		Selector.AUTO:
			selector = Selector.SAFE
	if selector_visual:
		selector_visual.rotation.x = deg_to_rad(float(selector) * 60.0)


## Energy stored in the mainspring at a hammer angle, above the hammer down position.
func spring_energy(angle: float) -> float:
	return mainspring_preload * angle + 0.5 * mainspring_rate * angle * angle


## Pin energy reaching the primer for a hammer falling at this angular speed.
func strike_energy(angular_speed: float) -> float:
	var hammer_mass := hammer_inertia / (strike_radius * strike_radius)
	var hammer_v := angular_speed * strike_radius
	var pin_v := (1.0 + pin_restitution) * hammer_mass * hammer_v / (hammer_mass + pin_mass)
	return maxf(0.5 * pin_mass * pin_v * pin_v - pin_return_force * pin_gap, 0.0)


func _cock(bolt_travel: float) -> void:
	cock_work = 0.0
	var cam := clampf(bolt_travel / cock_travel, 0.0, 1.0) * cocked_angle
	if cam > hammer_angle:
		cock_work = spring_energy(cam) - spring_energy(hammer_angle)
		hammer_angle = cam
		hammer_speed = 0.0
	if hammer_state == Hammer.DOWN or hammer_state == Hammer.FALLING:
		if cam >= cocked_angle:
			if not trigger_pulled:
				hammer_state = Hammer.SEAR
			elif selector == Selector.AUTO:
				hammer_state = Hammer.AUTO_SEAR
			else:
				hammer_state = Hammer.DISCONNECTOR
		elif hammer_state == Hammer.DOWN:
			# Not latched: the hammer rides the bolt back down without building speed.
			hammer_angle = cam


func _update_trigger(finger_force: float, in_battery: bool) -> void:
	var safe := selector == Selector.SAFE
	var at_wall := safe or hammer_state == Hammer.SEAR
	var travel_limit := take_up_travel if at_wall else total_travel
	var travel := clampf((finger_force - trigger_preload) / trigger_rate, 0.0, travel_limit)
	if not safe and hammer_state == Hammer.SEAR and finger_force >= break_force:
		hammer_state = Hammer.FALLING
		travel = total_travel
	trigger_travel = travel
	if travel > take_up_travel:
		trigger_pulled = true
	elif travel < reset_travel:
		trigger_pulled = false

	match hammer_state:
		Hammer.DISCONNECTOR:
			if not trigger_pulled:
				hammer_state = Hammer.SEAR
		Hammer.AUTO_SEAR:
			if not trigger_pulled:
				hammer_state = Hammer.SEAR
			elif in_battery:
				hammer_state = Hammer.FALLING


func _fall(delta: float, bolt_travel: float, in_battery: bool) -> float:
	var cam := clampf(bolt_travel / cock_travel, 0.0, 1.0) * cocked_angle
	var elapsed := 0.0
	while elapsed < delta:
		var torque := mainspring_preload + mainspring_rate * hammer_angle
		hammer_speed += SUB_STEP * torque / hammer_inertia
		hammer_angle -= SUB_STEP * hammer_speed
		elapsed += SUB_STEP
		if hammer_angle <= cam:
			var speed := hammer_speed
			hammer_angle = cam
			hammer_speed = 0.0
			hammer_state = Hammer.DOWN
			return strike_energy(speed) if in_battery and cam <= 0.0 else -1.0
	return -1.0
