class_name Player
extends RigidBody3D
## XR rig. A rigid body with a person's mass that only ever gets pushed around by capped forces from the legs,
## arms and grapple, so it takes time to get going and keeps going until something stops it. The body is a torso on
## a pair of legs: the legs are a spring that feels for the ground, with a short capsule to stop it on anything too
## tall to step onto, and they tuck up out of the way when hanging so the torso can get over a ledge. The capsule
## follows the head, the sticks move and turn smoothly, the hands chase the controllers.
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
## How long after leaving the ground a jump still works, so running off an edge doesn't eat one.
const JUMP_GRACE := 0.1
## How far above standing height the legs still reach the ground.
const GROUND_REACH := 0.1
## A body rising faster than this over the ground has left it, however close it still is: legs don't straighten this
## fast, so it jumped or got launched, and the feet have no more say in where it goes.
const LEFT_THE_GROUND := 2.0
## A landing below this speed isn't worth a thump.
const SOFT_LANDING := 1.5
## The legs brake when the stick asks for less than this share of the body's speed. It's about cos(45 degrees), so a
## gentle turn keeps its momentum and a hard one sheds it.
const BRAKE_BELOW := 0.7
## Hands rising slower than this are just reaching for something, not swinging.
const SLOWEST_ARM_SWING := 1.0
## Hands "rising" faster than this are the tracking jumping, not an arm.
const FASTEST_ARM_SWING := 10.0
## How quickly a swing is forgotten: one at a normal 3 m/s still counts for 0.3 s, so it can come before the button.
const ARM_SWING_DECAY := 10.0
## How long after the button a swing still adds to the jump, so it can come after the button too.
const ARM_SWING_WINDOW := 0.15
## How far past a hold to look for somewhere to stand when mantling, nearest first.
const MANTLE_REACHES: Array[float] = [0.35, 0.5, 0.65, 0.8]
## How far above and below a hold the top of a ledge can be. A ladder's top rung is 20 cm under the top of its tower.
const MANTLE_ABOVE := 0.4
const MANTLE_BELOW := 0.3
## How far the bottom of the torso clears the ledge on the way over it.
const MANTLE_CLEARANCE := 0.12
## How fast the body's speed closes on what the mantle wants, per second.
const MANTLE_RESPONSE := 15.0
## A hand comes off its hold this far from where it took it, while it's still close enough to rejoin the controller.
const MANTLE_HAND_REACH := 0.45
## Gives up after this long, in case something moved into the way.
const MANTLE_TIME_LIMIT := 2.0

## A brisk walk, and a run with the left stick clicked in.
@export var move_speed := 4.0
@export var sprint_speed := 6.5
@export var turn_speed := 2.2
## How fast the turn rate changes. Quick, because easing a turn in and out is what makes people sick.
@export var turn_acceleration := 14.0
@export var stick_deadzone := 0.15
## Most the legs can push along the ground: 7 m/s2 on 80 kg, about a hard sprint start. Speeding up and steering come
## from this.
@export var leg_force := 560.0
## Most the legs can brake with: 15 m/s2 on 80 kg, which stops a walk in about 50 cm and a run in about 1.4 m. Planted
## feet stop a body much harder than they can start it.
@export var brake_force := 1200.0
## Most the legs can push up: 5 times body weight, about what a hard landing takes.
@export var leg_lift := 4000.0
## How fast the legs take up a difference from standing height, in rad/s. A critically damped spring: a jump's landing
## dips the view a few centimeters, and a higher value lands harder.
@export var stand_response := 14.0
## How fast the legs straighten when there's far to go, such as standing up after hauling onto a ledge.
@export var stand_up_speed := 1.5
## Steering in the air, about 1 m/s2. Enough to adjust a jump, not to change your mind about it.
@export var air_force := 80.0
## Ground steeper than this is no use to the legs, so the body slides off it.
@export_range(0.0, 90.0, 1.0, "radians_as_degrees") var floor_max_angle := deg_to_rad(46.0)
## Most one arm can pull: 1.4 times body weight, so it can hang on and only just haul up. Two arms pull up easily.
@export var arm_force := 1100.0
## How fast the arms close the gap to the hold, in rad/s. A critically damped spring: higher is stiffer.
@export var arm_response := 20.0
## Most a mantle can pull with: arms and a leg together, about 2.5 times body weight.
@export var mantle_force := 2000.0
## How fast a mantle moves the body, and the view with it.
@export var mantle_speed := 2.5
## Take-off speed: 3.2 m/s lifts the feet about 50 cm, a good standing jump.
@export var jump_speed := 3.2
## Take-off speed added per m/s of the hands swinging up. A real arm swing adds about 20% to a jump, but nothing pushes
## back on the real body here, so this is well past that to make it read: a hard 4 m/s swing nearly doubles the height.
@export var arm_swing_jump := 0.5
## The most a swing can add. 5.2 m/s lifts the feet about 1.4 m.
@export var max_arm_swing_jump := 2.0
## Shoulder position relative to the head, for bracing a stock.
@export var shoulder_offset := Vector3(0.17, -0.2, 0.06)

## Where the hand fit is kept, so it only has to be set once.
var fit_path := "user://hand_fit.cfg"
var controller_profile := ""

var _xr: OpenXRInterface
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _turn_rate := 0.0
var _grounded := false
## Of the body above where it stands on the ground under it.
var _height := 0.0
## How fast the body is coming up off the ground under it.
var _rising := 0.0
var _air_time := 0.0
var _fall_speed := 0.0
var _floor_normal := Vector3.UP
var _floor_velocity := Vector3.ZERO
var _floor_point := Vector3.ZERO
## What's underfoot if it can move, so it gets the push back from the feet.
var _floor_body: RigidBody3D
var _legs_bottom := 0.0
var _torso_bottom := 0.0
var _sweep := PhysicsTestMotionParameters3D.new()
var _sweep_result := PhysicsTestMotionResult3D.new()
var _sprinting := false
var _was_sprint := false
var _was_moving := false
var _hands_height := 0.0
var _arm_swing := 0.0
var _take_off_time := 0.0
var _swing_used := 0.0
var _mantling := false
var _mantle_spot := Vector3.ZERO
var _mantle_time := 0.0
var _was_menu := false
var _was_jump := false
var _motion_state := &""
var _measure_rate := false
var _rate_check_time := 0.0
var _fit_mode := false
var _fit_hold := 0.0
var _fit_offset := Vector3.ZERO
var _fit_tilt := 0.0

@onready var _legs: CollisionShape3D = $Legs
@onready var _feet: RayCast3D = $Feet
@onready var _origin: XROrigin3D = $XROrigin3D
@onready var _camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _left_controller: XRController3D = $XROrigin3D/LeftController
@onready var _right_controller: XRController3D = $XROrigin3D/RightController
@onready var _left_aim: XRController3D = $XROrigin3D/LeftAim
@onready var _right_aim: XRController3D = $XROrigin3D/RightAim
@onready var _left_hand: PhysicsHand = $LeftHand
@onready var _right_hand: PhysicsHand = $RightHand
@onready var _left_grapple: Grapple = $LeftGrapple
@onready var _right_grapple: Grapple = $RightGrapple
@onready var _left_shoulder: AnimatableBody3D = $LeftShoulder
@onready var _right_shoulder: AnimatableBody3D = $RightShoulder
@onready var _fit_label: Label3D = $LeftHand/FitLabel
@onready var _bullet_time: BulletTime = $BulletTime


func _ready() -> void:
	_legs_bottom = _bottom_of(_legs)
	_torso_bottom = _bottom_of($Torso)
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
	# delta is world time, which bullet time slows. What the person does themselves goes by real time.
	var tick := 1.0 / Engine.physics_ticks_per_second
	if _measure_rate:
		_rate_check_time += delta
		if _rate_check_time >= RATE_CHECK_INTERVAL:
			_rate_check_time = 0.0
			set_tick_rate(_nearest_refresh_rate(Engine.get_frames_per_second()))
	_update_fit(tick)
	_feel_ground(delta)
	_turn(tick)
	_follow_head()
	_update_hand(_left_hand, _left_controller, _left_aim, delta)
	_update_hand(_right_hand, _right_controller, _right_aim, delta)
	_left_grapple.update(_left_hand, self, delta)
	_right_grapple.update(_right_hand, self, delta)
	var hands_on := int(_left_hand.climbing) + int(_right_hand.climbing)
	_tuck_legs(_mantling or hands_on > 0 or _left_grapple.attached or _right_grapple.attached)
	if _mantling:
		_mantle(delta)
	else:
		_stand(hands_on)
		if hands_on > 0:
			_hang(_left_hand, hands_on)
			_hang(_right_hand, hands_on)
		else:
			_walk(delta)
	_measure_arm_swing(tick)
	_jump(tick)
	_report_motion(hands_on)

	var forward := -_camera.global_basis.z
	var yaw := Basis(Vector3.UP, atan2(-forward.x, -forward.z))
	_right_shoulder.global_position = _camera.global_position + yaw * shoulder_offset
	_left_shoulder.global_position = _camera.global_position + yaw * Vector3(-shoulder_offset.x, shoulder_offset.y, shoulder_offset.z)

	var slow := not _fit_mode and (_left_controller.is_button_pressed(&"bullet_time") or _right_controller.is_button_pressed(&"bullet_time"))
	if _bullet_time.update(slow, tick):
		_left_controller.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.08, 0.0)
		_right_controller.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.08, 0.0)

	var reset := _left_controller.is_button_pressed(&"reset") or _right_controller.is_button_pressed(&"reset")
	if reset and not _was_menu:
		DebugLog.event("game", "range reset")
		get_tree().reload_current_scene.call_deferred()
	_was_menu = reset


## Feels straight down from the bottom of the body for what the legs stand on. Only a surface flat enough to stand on
## counts: anything steeper is left to the capsules, which have no friction, so the body slides off it.
func _feel_ground(delta: float) -> void:
	var start := (_torso_bottom if _legs.disabled else _legs_bottom) + 0.1
	_feet.position.y = start
	_feet.target_position.y = -start - GROUND_REACH
	_feet.force_raycast_update()
	_grounded = _feet.is_colliding() and _feet.get_collision_normal().y > cos(floor_max_angle)
	_floor_body = null
	if _grounded:
		_floor_normal = _feet.get_collision_normal()
		var under := _feet.get_collider() as RigidBody3D
		_floor_velocity = under.linear_velocity if under else Vector3.ZERO
		_rising = (linear_velocity - _floor_velocity).dot(_floor_normal) / _floor_normal.y
		_grounded = _rising < LEFT_THE_GROUND
	if _grounded:
		_floor_point = _feet.get_collision_point()
		_floor_body = _feet.get_collider() as RigidBody3D
		_height = global_position.y - _floor_point.y
		# Nothing pushes back on the real body, so a hard landing has to come through the controllers.
		if _air_time > 0.0 and _fall_speed > SOFT_LANDING:
			DebugLog.event("player", "landed at %.1f m/s after %.2f s in the air" % [_fall_speed, _air_time])
			var thump := minf(_fall_speed / 8.0, 1.0)
			_left_controller.trigger_haptic_pulse(&"haptic", 0.0, thump, 0.06, 0.0)
			_right_controller.trigger_haptic_pulse(&"haptic", 0.0, thump, 0.06, 0.0)
		_air_time = 0.0
	else:
		_air_time += delta
	_fall_speed = -linear_velocity.y


## Legs come back out only once there's room for them under the torso, or they would appear inside a ledge.
func _tuck_legs(tucked: bool) -> void:
	if tucked:
		_legs.disabled = true
	elif _legs.disabled and (not _grounded or _height >= -_legs_bottom):
		_legs.disabled = false


## The legs carry the body's weight, unless the arms are, and push to keep it at standing height over the ground.
## They can only push: a body going up leaves them behind.
func _stand(hands_on: int) -> void:
	if not _grounded:
		return
	var goal := minf(-_height * stand_response * 0.5, stand_up_speed)
	var weight := _gravity if hands_on == 0 else 0.0
	var force := Vector3.UP * clampf(mass * (weight + 2.0 * stand_response * (goal - _rising)), 0.0, leg_lift)
	apply_central_force(force)
	if _floor_body:
		_floor_body.apply_force(-force, _floor_point - _floor_body.global_position)


## Turns the view around the head, so turning never moves it. The capsule is round and has no need to turn.
func _turn(delta: float) -> void:
	_turn_rate = move_toward(_turn_rate, -_stick(_right_controller).x * turn_speed, turn_acceleration * delta)
	var head := _camera.global_position
	_origin.rotate_y(_turn_rate * delta)
	_origin.global_position += head - _camera.global_position


## The capsule follows the head as far as it can, and the view stays put. A blocked capsule just leaves the head
## leaning past it, which is what lets you lean over the table. This is the person's own steps catching the capsule
## up, not simulated motion, so it moves the body directly and gives it no momentum.
func _follow_head() -> void:
	var offset := _camera.global_position - global_position
	offset.y = 0.0
	if offset.is_zero_approx():
		return
	_sweep.from = global_transform
	_sweep.motion = offset
	var followed := Vector3.ZERO
	# The second pass slides along whatever stopped the first. Travel also includes being pushed out of contacts,
	# which would let a body held against a wall carry the view through it, so only count the motion asked for.
	for i: int in 2:
		var blocked := PhysicsServer3D.body_test_motion(get_rid(), _sweep, _sweep_result)
		var moved := _sweep.motion - _sweep_result.get_remainder()
		followed += moved
		if not blocked:
			break
		_sweep.from = _sweep.from.translated(moved)
		_sweep.motion = _sweep_result.get_remainder().slide(_sweep_result.get_collision_normal())
	followed.y = 0.0
	global_position += followed
	_origin.global_position -= followed


## Hanging on a hold: the arm pulls the body to bring the controller back to where it took hold, and carries its
## share of the weight, up to what an arm can do. Letting go leaves the body with the speed it has.
func _hang(hand: PhysicsHand, hands_on: int) -> void:
	if hand.climbing:
		var gap := hand.climb_point - hand.target.origin
		var acceleration := arm_response * arm_response * gap - 2.0 * arm_response * hand.controller_velocity
		apply_central_force((mass * (acceleration + Vector3.UP * _gravity / hands_on)).limit_length(arm_force))


## The legs push to bring the body up to the stick's speed along the ground, up to what legs can do. Anything
## underfoot that can move gets pushed the other way.
func _walk(delta: float) -> void:
	var stick := _stick(_left_controller)
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var wish := Vector3(-forward.z, 0.0, forward.x) * stick.x + forward * stick.y
	# Clicking toggles the run, and it ends with the walk. It can be clicked before setting off, with the stick centered.
	var moving := stick != Vector2.ZERO
	var sprint := _left_controller.is_button_pressed(&"sprint")
	if sprint and not _was_sprint:
		_sprinting = not _sprinting
	elif _was_moving and not moving:
		_sprinting = false
	_was_sprint = sprint
	_was_moving = moving
	var speed := sprint_speed if _sprinting else move_speed
	if not _grounded:
		# Only ever adds speed up to the stick's: steering doesn't brake a body that's flying faster than that.
		if wish != Vector3.ZERO and linear_velocity.dot(wish.normalized()) < speed:
			apply_central_force(wish * air_force)
		return
	var goal := wish.slide(_floor_normal).normalized() * wish.length() * speed
	var relative := linear_velocity - _floor_velocity
	relative.y = 0.0
	var error := goal - relative
	error.y = 0.0
	var limit := brake_force if goal.dot(relative) < BRAKE_BELOW * relative.length_squared() else leg_force
	var push := (mass * error / delta).limit_length(limit)
	apply_central_force(push)
	if _floor_body:
		_floor_body.apply_force(-push, _floor_point - _floor_body.global_position)


## How fast both hands are rising on average relative to the body, holding on to the peak for a moment.
func _measure_arm_swing(delta: float) -> void:
	var height := _left_controller.position.y + _right_controller.position.y
	var swing := (height - _hands_height) * 0.5 / delta
	_hands_height = height
	_arm_swing = maxf(swing if swing < FASTEST_ARM_SWING else 0.0, _arm_swing - ARM_SWING_DECAY * delta)


## Jump with its button, or by flicking the right stick up, and swing the arms up to jump higher.
func _jump(delta: float) -> void:
	var jump := not _fit_mode and (_right_controller.is_button_pressed(&"jump") or _right_controller.get_vector2(&"primary").y > 0.8)
	if jump and not _was_jump and not _mantling and not _start_mantle(_left_hand) and not _start_mantle(_right_hand) and _air_time < JUMP_GRACE:
		_air_time = JUMP_GRACE
		_take_off_time = ARM_SWING_WINDOW
		_swing_used = 0.0
		_push_off(jump_speed)
	_was_jump = jump
	if _take_off_time > 0.0:
		_take_off_time -= delta
		var boost := clampf((_arm_swing - SLOWEST_ARM_SWING) * arm_swing_jump, 0.0, max_arm_swing_jump)
		if boost > _swing_used:
			_push_off(boost - _swing_used)
			_swing_used = boost
		if _take_off_time <= 0.0:
			DebugLog.event("player", "jumped at %.1f m/s up, %.1f of it from the arms" % [linear_velocity.y, _swing_used])


## A line when what the body is doing changes, and its speed once a second while it's moving.
func _report_motion(hands_on: int) -> void:
	if not DebugLog.enabled:
		return
	var state := &"airborne"
	if _mantling:
		state = &"mantling"
	elif hands_on > 0:
		state = &"climbing"
	elif _left_grapple.attached or _right_grapple.attached:
		state = &"on the grapple"
	elif _grounded:
		state = &"on the ground"
	var flat := Vector2(linear_velocity.x, linear_velocity.z).length()
	if state != _motion_state:
		DebugLog.event("player", "%s at %.1f m/s across, %.1f up" % [state, flat, linear_velocity.y])
		_motion_state = state
	elif linear_velocity.length() > 0.5 and DebugLog.due(&"player_speed", 1.0):
		DebugLog.event("player", "%.1f m/s across, %.1f up, %s%s" % [flat, linear_velocity.y, state, ", running" if _sprinting else ""])


## Looks for somewhere to stand on top of what this hand is holding, past it the way the head faces, or else past it
## as seen from the head. Only a ledge has one: partway up a wall the search starts inside the wall and finds nothing.
## Runs on a button press, so it may allocate.
func _start_mantle(hand: PhysicsHand) -> bool:
	if not hand.climbing:
		return false
	var hold := hand.global_position
	var to_hold := hold - _camera.global_position
	to_hold.y = 0.0
	var facing := -_camera.global_basis.z
	facing.y = 0.0
	var space := get_world_3d().direct_space_state
	var room := CapsuleShape3D.new()
	room.radius = 0.2
	room.height = 1.4
	var room_query := PhysicsShapeQueryParameters3D.new()
	room_query.shape = room
	room_query.collision_mask = collision_mask
	for away: Vector3 in [facing.normalized() if facing.dot(to_hold) > 0.0 else Vector3.ZERO, to_hold.normalized()]:
		if away.is_zero_approx():
			continue
		for reach: float in MANTLE_REACHES:
			var over := _camera.global_position + away * (to_hold.dot(away) + reach)
			over.y = hold.y
			var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(over + Vector3.UP * MANTLE_ABOVE, over + Vector3.DOWN * MANTLE_BELOW, 1))
			if top.is_empty() or (top["normal"] as Vector3).y < cos(floor_max_angle):
				continue
			var spot: Vector3 = top["position"]
			room_query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * (_legs_bottom + room.height * 0.5))
			if space.intersect_shape(room_query, 1).is_empty():
				_mantling = true
				_mantle_spot = spot
				_mantle_time = 0.0
				hand.controller.trigger_haptic_pulse(&"haptic", 0.0, 0.5, 0.05, 0.0)
				return true
	return false


## Hauls the body up until the torso clears the ledge and then over it, with the legs tucked. It's still a capped force
## on the body, so anything in the way stops it. Once the feet are over the ledge, the legs stand the body up.
func _mantle(delta: float) -> void:
	_mantle_time += delta
	var to_spot := _mantle_spot - global_position
	var across := Vector3(to_spot.x, 0.0, to_spot.z)
	if across.length() < 0.1 or _mantle_time > MANTLE_TIME_LIMIT:
		_mantling = false
		_left_hand.let_go_of_hold()
		_right_hand.let_go_of_hold()
		return
	_release_stretched_hand(_left_hand)
	_release_stretched_hand(_right_hand)
	var to_clear := to_spot.y - _torso_bottom + MANTLE_CLEARANCE
	# Starts over just before clearing it, since the bottom of the torso is round.
	var over := clampf(1.0 - to_clear / 0.15, 0.0, 1.0)
	var goal := across.normalized() * minf(across.length() * MANTLE_RESPONSE, mantle_speed) * over
	goal.y = clampf(to_clear * MANTLE_RESPONSE, -mantle_speed, mantle_speed)
	apply_central_force((mass * ((goal - linear_velocity) * MANTLE_RESPONSE + Vector3.UP * _gravity)).limit_length(mantle_force))


func _release_stretched_hand(hand: PhysicsHand) -> void:
	if hand.climbing and hand.target.origin.distance_to(hand.climb_point) > MANTLE_HAND_REACH:
		hand.let_go_of_hold()


## Adds take-off speed, pushing back on whatever's underfoot.
func _push_off(speed: float) -> void:
	var impulse := Vector3.UP * mass * speed
	apply_central_impulse(impulse)
	if _floor_body:
		_floor_body.apply_impulse(-impulse, _floor_point - _floor_body.global_position)


func _update_hand(hand: PhysicsHand, controller: XRController3D, aim: XRController3D, delta: float) -> void:
	if not controller.get_has_tracking_data():
		hand.let_go_of_hold()
		return
	var before := hand.target.origin
	hand.set_target(controller.global_transform)
	hand.controller_velocity = (hand.target.origin - before) / delta
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


static func _bottom_of(capsule: CollisionShape3D) -> float:
	return capsule.position.y - (capsule.shape as CapsuleShape3D).height * 0.5


static func _nearest_refresh_rate(measured: float) -> int:
	var best := KNOWN_REFRESH_RATES[0]
	for rate: int in KNOWN_REFRESH_RATES:
		if absf(rate - measured) < absf(best - measured):
			best = rate
	return best
