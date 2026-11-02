class_name DebugLog
extends RefCounted
## Numbers for tuning feel, on the console. One line per event and nothing per tick: a shot, a grab, a landing. On in a
## debug build with a window. F9 in the game window flips it, and `-- --no-log` on the command line starts it off. Check
## `enabled` or `due` before building a line in per-tick code, so it allocates nothing when off.
##
## A game run also saves its whole console to a file in the log folder, so a session can be read after it's over.
## Godot's own log can't do this: it keeps 5 and every test run and import takes a slot.

static var enabled := is_game_run()

static var _next_time: Dictionary[StringName, int] = {}
static var _console_file: ConsoleFile


## Not a test run, an import or a tool, which have nothing to say about how the game feels.
static func is_game_run() -> bool:
	return OS.is_debug_build() and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-log")


## Starts saving the console, the first time it's called. An exported game can't write to res://.
static func save_console() -> void:
	if _console_file or not is_game_run():
		return
	var folder := "res://logs" if OS.has_feature("editor") else "user://session_logs"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("session_%s.log" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_"))
	_console_file = ConsoleFile.new(path, FileAccess.get_file_as_string("user://logs/godot.log"))
	OS.add_logger(_console_file)
	print("Saving this console to ", ProjectSettings.globalize_path(path))


static func event(channel: String, text: String) -> void:
	if enabled:
		print(line(channel, text))


## Whether a line that can repeat quickly, such as a hand rubbing along a table, may print again yet.
static func due(key: StringName, interval: float) -> bool:
	if not enabled:
		return false
	var now := Time.get_ticks_msec()
	if now < _next_time.get(key, 0):
		return false
	_next_time[key] = now + int(interval * 1000.0)
	return true


## Real seconds since startup, the channel, and how slowed the world is when it is.
static func line(channel: String, text: String) -> String:
	var slowed := "" if Engine.time_scale == 1.0 else "x%.2f " % Engine.time_scale
	return "%8.2f %-7s %s%s" % [Time.get_ticks_msec() / 1000.0, channel, slowed, text]
