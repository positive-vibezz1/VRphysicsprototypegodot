extends GutTest
## The tuning log, and everything that writes to it running with it switched on, since a bad format string only shows
## up when the line is built.

const DT := 1.0 / 90.0

var _was_enabled := false


func before_each() -> void:
	_was_enabled = DebugLog.enabled
	Ballistics.pool.clear()


func after_each() -> void:
	DebugLog.enabled = _was_enabled
	Engine.time_scale = 1.0


func test_a_line_has_the_time_and_channel_and_says_when_time_is_slowed() -> void:
	var line := DebugLog.line("gun", "fired")
	assert_string_contains(line, "gun")
	assert_string_ends_with(line, "fired")
	assert_false(line.contains("x0"))
	Engine.time_scale = 0.1
	assert_string_contains(DebugLog.line("gun", "fired"), "x0.10 fired")


func test_due_only_lets_a_repeating_line_through_once_per_interval() -> void:
	DebugLog.enabled = true
	assert_true(DebugLog.due(&"test_due", 60.0))
	assert_false(DebugLog.due(&"test_due", 60.0))
	assert_true(DebugLog.due(&"test_due_other", 60.0), "each key has its own")


func test_nothing_is_due_when_it_is_off() -> void:
	DebugLog.enabled = false
	assert_false(DebugLog.due(&"test_off", 0.0))


func test_the_console_file_gets_what_the_console_shows_right_away() -> void:
	var path := "user://test_console_file.log"
	var logger := ConsoleFile.new(path, "from before
")
	OS.add_logger(logger)
	print("a line for the file")
	push_warning("a warning for the file")
	# Read back while it's still open: a killed game never gets to close it.
	var saved := FileAccess.get_file_as_string(path)
	OS.remove_logger(logger)
	DirAccess.remove_absolute(path)
	assert_string_starts_with(saved, "from before
")
	assert_string_contains(saved, "a line for the file
")
	assert_string_contains(saved, "WARNING: a warning for the file")


func test_only_a_game_run_saves_its_console() -> void:
	DebugLog.save_console()
	assert_false(DebugLog.is_game_run(), "this is a headless run")
	assert_null(DebugLog._console_file)


func test_every_event_can_build_its_line() -> void:
	DebugLog.enabled = true
	var shots := [0]
	var gun: Gun = (load("res://weapons/pistol/pistol.tscn") as PackedScene).instantiate()
	gun.position = Vector3(0, 100, 0)
	add_child_autofree(gun)
	gun.shot_fired.connect(func(_s: GasSim.Shot, _e: float) -> void: shots[0] += 1)
	var hand: PhysicsHand = (load("res://player/physics_hand.tscn") as PackedScene).instantiate()
	add_child_autofree(hand)
	hand.set_target(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 100, 0)))
	await wait_physics_frames(2)
	hand.input_grip = 1.0
	hand.grab(gun.grip)
	await wait_physics_frames(10)
	hand.input_trigger = 1.0
	await wait_physics_frames(2)
	hand.input_trigger = 0.0
	# Past the end of the shot's report.
	await wait_physics_frames(roundi(ShotReport.WATCH_TIME / DT) + 2)
	assert_eq(shots[0], 1, "fired, with the log on")
	assert_false(gun.get("_report").watching(), "and the report finished")
	gun.release_magazine()
	await wait_physics_frames(30)
	assert_null(gun.mag_well.magazine, "the magazine fell out")
	hand.release()
	assert_null(hand.held)
