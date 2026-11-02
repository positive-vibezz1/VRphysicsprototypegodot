class_name Player
extends CharacterBody3D
## XR rig. The capsule follows the head, the sticks move and turn smoothly, the hands chase the controllers.
## Buttons are read as game actions: openxr_action_map.tres binds them natively for each kind of controller.

## The kind of controller in use changed. The profile is an OpenXR interaction profile path.
signal controllers_changed(profile: String)

const KNOWN_REFRESH_RATES: Array[int] = [72, 80, 90, 120, 144]
## How often to re-measure the refresh rate on a runtime that doesn't report it.
const RATE_CHECK_INTERVAL := 3.0
## Hand fit mode: hold its button on an empty left hand this long to enter or leave it.
const FIT_HOLD_TIME := 1.0
const FIT_MOVE_SPEED := 0.04
const FIT_TILT_SPEED := 30.0

## A brisk walk, and a run with the left stick clicked in.
@export var move_speed := 4.0
@export var sprint_speed := 6.5
@export var turn_speed := 2.2
@export var stick_deadzone := 0.15
## Take-off speed: 3.2 m/s lifts the feet about 50 cm, a good standing jump.
@export var jump_speed := 3.2
## Shoulder position relative to the head, for bracing a stock.
@export var shoulder_offset := Vector3(0.17, -0.2, 0.06)

## Where the hand fit is kept, so it only has to be set once.
var fit_path := "user://hand_fit.cfg"
var controller_profile := ""

var _xr: OpenXRInterface
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _fall_speed := 0.0
var _was_menu := false
var _was_jump := false
var _measure_rate := false
var _rate_check_time := 0.0
var _fit_mode := false
var _fit_hold := 0.0
var _fit_offset := Vector3.ZERO
var _fit_tilt := 0.0

@onready var _origin: XROrigin3D = $XROrigin3D
@onready var _camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _left_controller: XRController3D = $XROrigin3D/LeftController
@onready var _right_controller: XRController3D = $XROrigin3D/RightController
@onready var _left_aim: XRController3D = $XROrigin3D/LeftAim
@onready var _right_aim: XRController3D = $XROrigin3D/RightAim
@onready var _left_hand: PhysicsHand = $LeftHand
@onready var _right_hand: PhysicsHand = $RightHand
@onready var _left_shoulder: AnimatableBody3D = $LeftShoulder
@onready var _right_shoulder: AnimatableBody3D = $RightShoulder
@onready var _fit_label: Label3D = $LeftHand/FitLabel


func _ready() -> void:
	_left_hand.other_hand = _right_hand
	_right_hand.other_hand = _left_hand
	_left_hand.controller = _left_controller
	_right_hand.controller = _right_controller
	var tracker: XRControllerTracker = XRServer.get_tracker(&"right_hand")
	if tracker:
		tracker.profile_changed.connect(_on_profile_changed.bind(tracker))
		controller_profile = tracker.profile
	_load_fit()
	_start_xr()


func _physics_process(delta: float) -> void:
	if _measure_rate:
		_rate_check_time += delta
		if _rate_check_time >= RATE_CHECK_INTERVAL:
			_rate_check_time = 0.0
			set_tick_rate(_nearest_refresh_rate(Engine.get_frames_per_second()))
	_update_fit(delta)
	_locomote(delta)
	_update_hand(_left_hand, _left_controller, _left_aim)
	_update_hand(_right_hand, _right_controller, _right_aim)

	var forward := -_camera.global_basis.z
	var yaw := Basis(Vector3.UP, atan2(-forward.x, -forward.z))
	_right_shoulder.global_position = _camera.global_position + yaw * shoulder_offset
	_left_shoulder.global_position = _camera.global_position + yaw * Vector3(-shoulder_offset.x, shoulder_offset.y, shoulder_offset.z)

	var reset := _left_controller.is_button_pressed(&"reset") or _right_controller.is_button_pressed(&"reset")
	if reset and not _was_menu:
		get_tree().reload_current_scene.call_deferred()
	_was_menu = reset


func _locomote(delta: float) -> void:
	var turn := _stick(_right_controller).x
	rotate_y(-turn * turn_speed * delta)

	var stick := _stick(_left_controller)
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var speed := sprint_speed if _left_controller.is_button_pressed(&"sprint") else move_speed
	var walk := (right * stick.x + forward * stick.y) * speed

	# The capsule follows the head as far as it can, and the view stays put. A blocked capsule just leaves the
	# head leaning past it, which is what lets you lean over the table.
	var head_offset := _camera.global_position - global_position
	head_offset.y = 0.0
	var before := global_position
	velocity = head_offset / delta
	move_and_slide()
	var followed := global_position - before
	followed.y = 0.0
	_origin.global_position -= followed

	# Jump with its button, or by flicking the right stick up.
	var jump := not _fit_mode and (_right_controller.is_button_pressed(&"jump") or _right_controller.get_vector2(&"primary").y > 0.8)
	if is_on_floor():
		_fall_speed = jump_speed if jump and not _was_jump else 0.0
	else:
		_fall_speed -= _gravity * delta
	_was_jump = jump
	velocity = walk + Vector3.UP * _fall_speed
	move_and_slide()


func _update_hand(hand: PhysicsHand, controller: XRController3D, aim: XRController3D) -> void:
	if not controller.get_has_tracking_data():
		return
	hand.set_target(controller.global_transform)
	hand.aim_direction = -aim.global_basis.z if aim.get_has_tracking_data() else Vector3.ZERO
	hand.input_grip = controller.get_float(&"grip")
	hand.input_trigger = controller.get_float(&"trigger")
	hand.input_mag_release = controller.is_button_pressed(&"mag_release")
	hand.input_bolt_release = controller.is_button_pressed(&"bolt_release")
	hand.input_fire_mode = controller.is_button_pressed(&"fire_mode")


## Hand fit mode takes the sticks away from walking and turning.
func _stick(controller: XRController3D) -> Vector2:
	return Vector2.ZERO if _fit_mode else _deadzoned(controller)


func _deadzoned(controller: XRController3D) -> Vector2:
	# Rescaled so speed starts from zero at the edge of the deadzone, not with a jump.
	var stick := controller.get_vector2(&"primary")
	var length := stick.length()
	if length <= stick_deadzone:
		return Vector2.ZERO
	return stick / length * minf((length - stick_deadzone) / (1.0 - stick_deadzone), 1.0)


## Controller poses differ between runtimes and headsets, and only the person wearing it can see how far off the
## hands are, so the fit is set in the headset. Left stick: side and forward. Right stick: up and tilt.
func _update_fit(delta: float) -> void:
	if not _left_controller.is_button_pressed(&"hand_fit") or _left_hand.held:
		_fit_hold = 0.0
	elif _fit_hold >= 0.0:
		_fit_hold += delta
		if _fit_hold >= FIT_HOLD_TIME:
			# Negative until the buttons come up, so one long press only toggles once.
			_fit_hold = -1.0
			_fit_mode = not _fit_mode
			_fit_label.visible = _fit_mode
			if not _fit_mode:
				_save_fit()
	if _fit_mode:
		var left := _deadzoned(_left_controller)
		var right := _deadzoned(_right_controller)
		_fit_offset += Vector3(left.x, -left.y, -right.y) * FIT_MOVE_SPEED * delta
		_fit_tilt += right.x * FIT_TILT_SPEED * delta
		_apply_fit()
		_fit_label.text = "HAND FIT\nLeft stick: side, forward\nRight stick: up, tilt\nHold the same button: save\n%.3f, %.3f, %.3f   tilt %.0f" % [
			_fit_offset.x, _fit_offset.y, _fit_offset.z, _fit_tilt
		]


## Mirrored side to side, so the same fit suits both hands.
func _apply_fit() -> void:
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(_fit_tilt))
	_right_hand.set_fit(Transform3D(tilt, _fit_offset))
	_left_hand.set_fit(Transform3D(tilt, _fit_offset * Vector3(-1.0, 1.0, 1.0)))


## Each kind of controller reports its pose differently, so each keeps its own fit.
func _load_fit() -> void:
	var config := ConfigFile.new()
	config.load(fit_path)
	_fit_offset = config.get_value(_fit_section(), "offset", Vector3.ZERO)
	_fit_tilt = config.get_value(_fit_section(), "tilt", 0.0)
	_apply_fit()


func _fit_section() -> String:
	return controller_profile if controller_profile != "" else "default"


func _save_fit() -> void:
	var config := ConfigFile.new()
	config.load(fit_path)
	config.set_value(_fit_section(), "offset", _fit_offset)
	config.set_value(_fit_section(), "tilt", _fit_tilt)
	config.save(fit_path)
	print("Hand fit saved for ", _fit_section(), ": offset ", _fit_offset, " tilt ", _fit_tilt)


func _on_profile_changed(_role: String, tracker: XRControllerTracker) -> void:
	controller_profile = tracker.profile
	print("Controllers: ", controller_profile)
	_load_fit()
	controllers_changed.emit(controller_profile)


func _start_xr() -> void:
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null or not _xr.is_initialized():
		push_warning("OpenXR is not running. This project is VR only: start SteamVR and run it again.")
		return
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not _xr.session_begun.is_connected(_on_session_begun):
		_xr.session_begun.connect(_on_session_begun)


func _on_session_begun() -> void:
	var rate := roundi(_xr.display_refresh_rate)
	if rate > 0:
		set_tick_rate(rate)
	else:
		# SteamVR does not report a refresh rate, so measure it. Keep measuring: the first few seconds run slow
		# while everything loads, and a tick rate out of step with the display makes all movement judder.
		_measure_rate = true


func set_tick_rate(rate: int) -> void:
	if rate != Engine.physics_ticks_per_second:
		Engine.physics_ticks_per_second = rate
		print("Physics tick rate set to ", rate, " Hz")


static func _nearest_refresh_rate(measured: float) -> int:
	var best := KNOWN_REFRESH_RATES[0]
	for rate: int in KNOWN_REFRESH_RATES:
		if absf(rate - measured) < absf(best - measured):
			best = rate
	return best
