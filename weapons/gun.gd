class_name Gun
extends Node3D
## One firearm: frame, bolt (the slide on a pistol), optional charging handle, fire control and magazine.
## The root node does not move. Frame, Bolt and the rest are sibling rigid bodies held together by joints.
##
## Recoil: the primer fires, GasSim integrates the shot, and its breech impulse goes into the bolt and the
## frame. Everything else that kicks the shooter's hand comes out of Jolt: the spring, the stops and the joints.

signal shot_fired(shot: GasSim.Shot, strike_energy: float)
signal misfired(strike_energy: float)
## The bolt slammed into a stop, with this impulse in N s.
signal bolt_stopped(impulse: float)
## The frame touched something, at this speed in m/s.
signal surface_hit(speed: float)

enum Chamber { EMPTY, LIVE, SPENT }

## Bolt counts as locked in battery within this distance of its rest position.
const BATTERY_TOLERANCE := 0.0015
## A bolt stop below this is too soft to feel or hear.
const FELT_STOP_IMPULSE := 0.15

@export var cartridge: CartridgeSpec
@export var start_chambered := true
@export var start_magazine: Magazine
## How a shot comes through the controller: a pistol is a short sharp snap, a rifle a longer deeper shove.
@export var haptic_duration := 0.03
@export var haptic_frequency := 180.0

@export_group("Barrel")
@export var barrel_length := 0.114
## Short recoil only: barrel mass locked to the slide for its first 3 mm, about 0.4 ms. It is part of the
## frame's mass at rest and stops against the frame well within one tick, so its share of the impulse goes
## straight to the frame.
@export var barrel_mass := 0.09
## Gas system. Without one the gun is short recoil and the whole breech impulse drives the bolt.
@export var gas_port: GasPortSpec

@export_group("Bolt")
@export var bolt_travel := 0.065
## Recoil spring: about 40 N in battery and 75 N at the rear for a 17 lb service pistol spring.
@export var spring_preload := 40.0
@export var spring_rate := 540.0
@export var eject_travel := 0.04
@export var feed_travel := 0.045
## Bolt catch position, a bit short of the rear stop.
@export var catch_travel := 0.058
## Energy spent stripping a round from the magazine.
@export var feed_work := 0.15
## Case ejection speed for a given bolt speed.
@export var eject_speed_factor := 0.7
## Shot to shot spread of the powder charge (relative standard deviation).
@export var charge_spread := 0.007

var finger_force := 0.0
var chamber := Chamber.EMPTY
var catch_engaged := false

@onready var frame: RigidBody3D = $Frame
@onready var bolt: RigidBody3D = $Bolt
@onready var charging_handle: RigidBody3D = get_node_or_null("ChargingHandle")
@onready var fire_control: FireControl = $FireControl
@onready var mag_well: MagWell = $Frame/MagWell
@onready var muzzle: Node3D = $Frame/Muzzle
@onready var ejection_port: Node3D = $Bolt/EjectionPort
@onready var grip: GrabPoint = $Frame/Grip
@onready var _flash: Node3D = $Frame/Muzzle/Flash

var _rail: Rail
var _handle_rail: Rail
var _shot := GasSim.Shot.new()
var _rng := RandomNumberGenerator.new()
var _past_eject := false
var _past_feed := false
var _short_of_catch := true
var _support_points: Array[GrabPoint] = []


func _ready() -> void:
	_rng.randomize()
	_rail = Rail.new(frame, bolt, $Rail, bolt_travel, spring_preload, spring_rate)
	if charging_handle:
		# Just enough spring to bring the handle home. The joint to the bolt does the rest.
		_handle_rail = Rail.new(frame, charging_handle, $HandleRail, bolt_travel, 4.0, 10.0)
	for body: RigidBody3D in [frame, bolt, charging_handle]:
		if body:
			for child: Node in body.get_children():
				if child is GrabPoint and child != grip:
					_support_points.append(child)
					child.enabled = false
	frame.contact_monitor = true
	frame.max_contacts_reported = 2
	frame.body_entered.connect(_on_frame_touched)
	if start_magazine:
		mag_well.seat(start_magazine)
	if start_chambered:
		chamber = Chamber.LIVE
		fire_control.cock_now()


func _physics_process(delta: float) -> void:
	if frame.sleeping and bolt.sleeping:
		return
	_flash.visible = false
	mag_well.tick()
	_rail.frame_mass = _supported_mass()
	_rail.update()
	_update_cycle()

	var in_battery := _rail.travel < BATTERY_TOLERANCE
	var strike := fire_control.tick(delta, finger_force, 0.0 if in_battery else _rail.travel, in_battery)
	_rail.take_energy(fire_control.cock_work)
	if strike >= 0.0:
		_strike(strike)

	_rail.apply(delta)
	if _rail.last_stop_impulse > FELT_STOP_IMPULSE:
		bolt_stopped.emit(_rail.last_stop_impulse)
		Ballistics.pool.play_click(frame.global_position)
	if _handle_rail:
		_handle_rail.apply(delta)


func release_magazine() -> void:
	mag_well.release()


## The B/Y button: sends a locked back bolt home, otherwise moves the selector.
func press_bolt_button() -> void:
	if catch_engaged:
		release_bolt()
	elif fire_control.selector_modes.size() > 1:
		fire_control.cycle_selector()
	else:
		return
	Ballistics.pool.play_click(frame.global_position)


func release_bolt() -> void:
	catch_engaged = false
	_rail.set_front_stop(0.0)


## Moves every body of the gun together. Only for grabbing and resets.
func teleport(delta_transform: Transform3D) -> void:
	for body: RigidBody3D in [frame, bolt, charging_handle, mag_well.magazine]:
		if body:
			body.global_transform = delta_transform * body.global_transform
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = false


func held_mass() -> float:
	var total := frame.mass + bolt.mass
	if charging_handle:
		total += charging_handle.mass
	if mag_well.magazine:
		total += mag_well.magazine.mass
	return total


## Called when a hand takes or lets go of a grab point.
func grab_changed() -> void:
	var held := grip.holder != null
	for point: GrabPoint in _support_points:
		point.enabled = held
	if not held:
		finger_force = 0.0


## All bodies of the gun, for tests and tools.
func bodies() -> Array[RigidBody3D]:
	var list: Array[RigidBody3D] = [frame, bolt]
	if charging_handle:
		list.append(charging_handle)
	if mag_well.magazine:
		list.append(mag_well.magazine)
	return list


## What the rail's stops push against: the frame, a seated magazine and the hand on the grip.
func _supported_mass() -> float:
	var total := frame.mass
	if mag_well.latched:
		total += mag_well.magazine.mass
	if grip.holder:
		total += grip.holder.mass
	return total


func _update_cycle() -> void:
	var travel := _rail.travel
	var magazine := mag_well.magazine if mag_well.latched else null

	# Extract on the way back, once the ejector reaches the case.
	if travel >= eject_travel:
		if not _past_eject:
			_past_eject = true
			if chamber != Chamber.EMPTY:
				_eject()
	else:
		_past_eject = false

	# Strip the next round on the way forward.
	if travel >= feed_travel:
		_past_feed = true
	elif _past_feed:
		_past_feed = false
		if chamber == Chamber.EMPTY and magazine and magazine.take_round():
			chamber = Chamber.LIVE
			_rail.take_energy(feed_work)

	# The follower of an empty magazine lifts the catch into the bolt's path.
	if magazine and magazine.count == 0 and travel >= catch_travel and _short_of_catch:
		catch_engaged = true
	elif catch_engaged and travel > catch_travel + 0.003 and not (magazine and magazine.count == 0):
		catch_engaged = false
	_short_of_catch = travel < catch_travel
	_rail.set_front_stop(catch_travel if catch_engaged else 0.0)


func _strike(energy: float) -> void:
	if chamber != Chamber.LIVE or not cartridge.primer_fires(energy, _rng):
		misfired.emit(energy)
		Ballistics.pool.play_click(frame.global_position)
		return
	chamber = Chamber.SPENT

	var charge_scale := 1.0 + _rng.randfn(0.0, charge_spread)
	GasSim.simulate(cartridge, barrel_length, _shot, gas_port, bolt.mass, charge_scale)

	var rear := frame.global_basis.z
	var bore_offset := muzzle.global_position - frame.global_position
	var muzzle_velocity := PhysicsServer3D.body_get_direct_state(frame.get_rid()).get_velocity_at_local_position(bore_offset)
	if gas_port:
		# While locked to the barrel the bolt shares the frame's recoil, then the gas pushes the carrier back
		# and the locked bolt forward, so the carrier gets its gas impulse on top and the frame the rest.
		var carrier_share := bolt.mass / (bolt.mass + _supported_mass())
		var carrier := _shot.carrier_impulse + _shot.breech_impulse * carrier_share
		bolt.apply_central_impulse(rear * carrier)
		frame.apply_impulse(rear * (_shot.breech_impulse - carrier), bore_offset)
	else:
		var slide_share := bolt.mass / (bolt.mass + barrel_mass)
		bolt.apply_central_impulse(rear * _shot.breech_impulse * slide_share)
		frame.apply_impulse(rear * _shot.breech_impulse * (1.0 - slide_share), bore_offset)

	Ballistics.pool.fire_bullet(cartridge, muzzle.global_position, muzzle_velocity - rear * _shot.muzzle_velocity)
	Ballistics.pool.play_shot(muzzle.global_position, _shot)
	# The muzzle blast grows with the pressure still behind the bullet when it leaves.
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.03 * sqrt(_shot.muzzle_pressure / 3.0e7)
	shot_fired.emit(_shot, energy)


func _on_frame_touched(_body: Node) -> void:
	surface_hit.emit(frame.linear_velocity.length())


func _eject() -> void:
	var live := chamber == Chamber.LIVE
	chamber = Chamber.EMPTY
	var offset := ejection_port.global_position - frame.global_position
	var state := PhysicsServer3D.body_get_direct_state(frame.get_rid())
	# Thrown to the right, a bit up and back, in proportion to how hard the ejector hits the case.
	var direction := (frame.global_basis * Vector3(0.8, 0.5, 0.3)).normalized()
	var speed := absf(_rail.velocity) * eject_speed_factor
	var velocity := state.get_velocity_at_local_position(offset) + direction * speed
	var spin := frame.global_basis.y * speed * 12.0
	Ballistics.pool.eject_casing(cartridge, ejection_port.global_position, frame.global_basis, velocity, spin, live)
