class_name Player
extends CharacterBody3D
## XR rig. The capsule follows the head, the sticks move and turn smoothly, the hands chase the controllers.

const KNOWN_REFRESH_RATES: Array[int] = [72, 80, 90, 120, 144]
## How often to re-measure the refresh rate on a runtime that doesn't report it.
const RATE_CHECK_INTERVAL := 3.0

## A brisk walk, and a run with the left stick clicked in.
@export var move_speed := 4.0
@export var sprint_speed := 6.5
@export var turn_speed := 2.2
@export var stick_deadzone := 0.15
## Take-off speed: 3.2 m/s lifts the feet about 50 cm, a good standing jump.
@export var jump_speed := 3.2
## Shoulder position relative to the head, for bracing a stock.
@export var shoulder_offset := Vector3(0.17, -0.2, 0.06)

var _xr: OpenXRInterface
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _fall_speed := 0.0
var _was_menu := false
var _was_jump := false
var _measure_rate := false
var _rate_check_time := 0.0

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


func _ready() -> void:
	_left_hand.other_hand = _right_hand
	_right_hand.other_hand = _left_hand
	_left_hand.controller = _left_controller
	_right_hand.controller = _right_controller
	_start_xr()


func _physics_process(delta: float) -> void:
	if _measure_rate:
		_rate_check_time += delta
		if _rate_check_time >= RATE_CHECK_INTERVAL:
			_rate_check_time = 0.0
			set_tick_rate(_nearest_refresh_rate(Engine.get_frames_per_second()))
	_locomote(delta)
	_update_hand(_left_hand, _left_controller, _left_aim)
	_update_hand(_right_hand, _right_controller, _right_aim)

	var forward := -_camera.global_basis.z
	var yaw := Basis(Vector3.UP, atan2(-forward.x, -forward.z))
	_right_shoulder.global_position = _camera.global_position + yaw * shoulder_offset
	_left_shoulder.global_position = _camera.global_position + yaw * Vector3(-shoulder_offset.x, shoulder_offset.y, shoulder_offset.z)

	var menu := _left_controller.is_button_pressed(&"menu_button") or _right_controller.is_button_pressed(&"menu_button")
	if menu and not _was_menu:
		get_tree().reload_current_scene.call_deferred()
	_was_menu = menu


func _locomote(delta: float) -> void:
	var turn := _stick(_right_controller).x
	rotate_y(-turn * turn_speed * delta)

	var stick := _stick(_left_controller)
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var speed := sprint_speed if _left_controller.is_button_pressed(&"primary_click") else move_speed
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

	# Jump with the right stick: click it, or flick it up.
	var jump := _right_controller.is_button_pressed(&"primary_click") or _right_controller.get_vector2(&"primary").y > 0.8
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
	hand.input_mag_release = controller.is_button_pressed(&"ax_button")
	hand.input_bolt_button = controller.is_button_pressed(&"by_button")


func _stick(controller: XRController3D) -> Vector2:
	# Rescaled so speed starts from zero at the edge of the deadzone, not with a jump.
	var stick := controller.get_vector2(&"primary")
	var length := stick.length()
	if length <= stick_deadzone:
		return Vector2.ZERO
	return stick / length * minf((length - stick_deadzone) / (1.0 - stick_deadzone), 1.0)


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
