class_name TimeTrial
extends Node3D
## A timed run through every way the player can move, a section each: sprint, slalom, steps, jumps, swing jump, ladder
## and bars, rock wall, grapple swing, grapple haul, drop and wade. Leaving the start box starts the clock, the
## checkpoint at the end of each section has to be passed in order, and walking back into the start box calls a run off
## and gets ready for the next. Times are world time, so bullet time costs nothing on the clock.
##
## Each split goes to the log with how the body got through that section, and a finished run adds a csv line, so runs
## from before and after a change to the movement numbers can be compared. A run starts by logging the numbers in use.

const CHANNEL := "trial"
## Real seconds a split stays on the wrist in place of the clock, and the final time.
const SHOW_SPLIT := 3.0
const SHOW_FINISH := 15.0

@export var player: Player
## Where the best times are kept between sessions.
@export var best_path := "user://time_trial.cfg"

var running := false
var runs := 0
## World seconds since the start of this run.
var time := 0.0
## World seconds each section took on this run, and the best each has taken, 0 for none yet.
var splits: Array[float] = []
var best_splits: Array[float] = []
var best_time := 0.0

var _gates: Array[TrialGate] = []
## The gate to go for next. The start, until the player is standing in it.
var _next := 0
var _ready_to_go := false
var _section := Section.new()
var _real_time := 0.0
var _last_position := Vector3.ZERO
var _hands: Array[PhysicsHand] = []
var _grapples: Array[Grapple] = []
var _holding: Array[bool] = [false, false]
var _hooked: Array[bool] = [false, false]
var _bullet_time: BulletTime
## On the left wrist: the clock, or for a while after a checkpoint, its split.
var _wrist := Label3D.new()
var _shown_tenths := -1
var _message_time := 0.0

@onready var _board: Label3D = $Board


func _ready() -> void:
	for child: Node in $Gates.get_children():
		var gate := child as TrialGate
		gate.body_entered.connect(_on_entered.bind(_gates.size()))
		gate.body_exited.connect(_on_exited.bind(_gates.size()))
		_gates.append(gate)
	best_splits.resize(_gates.size() - 1)
	best_splits.fill(0.0)
	_load_best()
	_hands = [player.get_node("LeftHand") as PhysicsHand, player.get_node("RightHand") as PhysicsHand]
	_grapples = [player.get_node("LeftGrapple") as Grapple, player.get_node("RightGrapple") as Grapple]
	_bullet_time = player.get_node("BulletTime")
	_wrist.position = Vector3(0, 0.07, 0.03)
	_wrist.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_wrist.no_depth_test = true
	_wrist.pixel_size = 0.0005
	_wrist.font_size = 32
	_wrist.outline_size = 8
	_wrist.visible = false
	_hands[0].add_child(_wrist)
	_light_gates()
	_show_board()
	var titles := PackedStringArray()
	for gate: TrialGate in _gates.slice(1):
		titles.append(gate.title)
	DebugLog.event(CHANNEL, "csv run,time,%s" % ",".join(titles))


func _physics_process(delta: float) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	if _message_time > 0.0:
		_message_time -= tick
		if _message_time <= 0.0:
			_wrist.visible = running
			_shown_tenths = -1
	if not running:
		return
	time += delta
	_real_time += tick
	_section.time += delta
	_section.real_time += tick
	var at := player.global_position
	_section.distance += at.distance_to(_last_position)
	_last_position = at
	_section.top_speed = maxf(_section.top_speed, Vector2(player.linear_velocity.x, player.linear_velocity.z).length())
	for i: int in 2:
		var holding := _hands[i].climbing
		_section.holds += int(holding and not _holding[i])
		_holding[i] = holding
		var hooked := _grapples[i].attached
		_section.grapples += int(hooked and not _hooked[i])
		_hooked[i] = hooked
	if _holding[0] or _holding[1]:
		_section.climbing += delta
	if _hooked[0] or _hooked[1]:
		_section.grappling += delta
	if _bullet_time.active:
		_section.slowed += tick
	var tenths := int(time * 10.0)
	if _message_time <= 0.0 and tenths != _shown_tenths:
		_shown_tenths = tenths
		_wrist.text = "%.1f\nnext: %s" % [time, _gates[_next].title]


func _on_entered(body: Node3D, index: int) -> void:
	if body != player:
		return
	if index == 0:
		_get_ready()
	elif running and index == _next:
		_pass()
	elif running and index > _next and DebugLog.due(&"trial_skipped", 2.0):
		DebugLog.event(CHANNEL, "%s doesn't count yet, %s is next" % [_gates[index].title, _gates[_next].title])


func _on_exited(body: Node3D, index: int) -> void:
	if body == player and index == 0 and _ready_to_go:
		_start()


## Calls off any run in progress.
func _get_ready() -> void:
	if running:
		running = false
		DebugLog.event(CHANNEL, "run %d called off on the way to %s, after %.2f s" % [runs, _gates[_next].title, time])
	_ready_to_go = true
	_next = 1
	_message_time = 0.0
	_wrist.visible = false
	_light_gates()


func _start() -> void:
	_ready_to_go = false
	running = true
	runs += 1
	time = 0.0
	_real_time = 0.0
	splits.clear()
	_section = Section.new()
	_last_position = player.global_position
	for i: int in 2:
		_holding[i] = _hands[i].climbing
		_hooked[i] = _grapples[i].attached
	_shown_tenths = -1
	_wrist.visible = true
	DebugLog.event(CHANNEL, "run %d started. %s" % [runs, _tuning()])


func _pass() -> void:
	var title := _gates[_next].title
	var split := _section.time
	var best := best_splits[_next - 1]
	splits.append(split)
	var against := _against(split, best)
	DebugLog.event(CHANNEL, "%s at %.2f s, took %.2f s%s. %s" % [title, time, split, against, _section.describe()])
	_show_on_wrist("%s %.2f\n%s" % [title, split, against.trim_prefix(", ")], SHOW_SPLIT)
	if best == 0.0 or split < best:
		best_splits[_next - 1] = split
	_section = Section.new()
	_next += 1
	if _next == _gates.size():
		_finish()
	_save_best()
	_light_gates()
	_show_board()


func _finish() -> void:
	running = false
	var against := _against(time, best_time)
	DebugLog.event(CHANNEL, "run %d finished in %.2f s%s, %.2f s real" % [runs, time, against, _real_time])
	var row := PackedStringArray([str(runs), "%.2f" % time])
	for split: float in splits:
		row.append("%.2f" % split)
	DebugLog.event(CHANNEL, "csv " + ",".join(row))
	_show_on_wrist("FINISH %.2f\n%s" % [time, against.trim_prefix(", ")], SHOW_FINISH)
	if best_time == 0.0 or time < best_time:
		best_time = time


func _show_on_wrist(text: String, seconds: float) -> void:
	_wrist.text = text
	_wrist.visible = true
	_message_time = seconds


func _light_gates() -> void:
	for i: int in _gates.size():
		var state := TrialGate.State.WAITING
		if i == _next:
			state = TrialGate.State.NEXT
		elif i > 0 and i < _next:
			state = TrialGate.State.PASSED
		_gates[i].set_state(state)


func _show_board() -> void:
	var lines := PackedStringArray(["TIME TRIAL", "Best run %s" % _seconds(best_time), ""])
	for i: int in best_splits.size():
		var last := _seconds(splits[i]) if i < splits.size() else "-"
		lines.append("%s  %s   best %s" % [_gates[i + 1].title, last, _seconds(best_splits[i])])
	_board.text = "\n".join(lines)


## The numbers the run was made with, so the log says what each time was measured against.
func _tuning() -> String:
	var grapple := _grapples[1]
	return (
		"walk %.1f m/s, run %.1f, legs %.0f N, brakes %.0f N, air %.0f N, jump %.1f m/s + %.2f per m/s of arm swing up to "
		+ "%.1f, arms %.0f N, mantle %.0f N, grapple %.0f N with haul gain %.1f, bullet time x%.2f"
	) % [
		player.move_speed, player.sprint_speed, player.leg_force, player.brake_force, player.air_force, player.jump_speed,
		player.arm_swing_jump, player.max_arm_swing_jump, player.arm_force, player.mantle_force, grapple.max_tension,
		grapple.haul_gain, _bullet_time.slow_scale,
	]


func _load_best() -> void:
	var config := ConfigFile.new()
	config.load(best_path)
	best_time = config.get_value("best", "time", 0.0)
	for i: int in best_splits.size():
		best_splits[i] = config.get_value("best", _gates[i + 1].title, 0.0)


func _save_best() -> void:
	var config := ConfigFile.new()
	config.set_value("best", "time", best_time)
	for i: int in best_splits.size():
		config.set_value("best", _gates[i + 1].title, best_splits[i])
	config.save(best_path)


static func _against(seconds: float, best: float) -> String:
	return ", first time" if best == 0.0 else ", %+.2f on the best of %.2f" % [seconds - best, best]


static func _seconds(seconds: float) -> String:
	return "%.2f" % seconds if seconds > 0.0 else "-"


## How the body got through one section.
class Section:
	var time := 0.0
	var real_time := 0.0
	var distance := 0.0
	var top_speed := 0.0
	var climbing := 0.0
	var holds := 0
	var grappling := 0.0
	var grapples := 0
	## Real seconds of bullet time.
	var slowed := 0.0

	func describe() -> String:
		return (
			"%.1f m at %.1f m/s, top %.1f m/s across, climbing %.1f s on %d holds, grapple %.1f s from %d catches, "
			+ "bullet time %.1f s, %.2f s real"
		) % [distance, distance / maxf(time, 0.001), top_speed, climbing, holds, grappling, grapples, slowed, real_time]
