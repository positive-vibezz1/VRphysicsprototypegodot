class_name DebugLog
extends RefCounted
## Numbers for tuning feel, on the console and in Godot's log file. One line per event and nothing per tick: a shot, a
## grab, a landing. On in a debug build with a window. F9 in the game window flips it, and `-- --no-log` on the command
## line starts it off. Check `enabled` or `due` before building a line in per-tick code, so it allocates nothing when off.

static var enabled := OS.is_debug_build() and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-log")

static var _next_time: Dictionary[StringName, int] = {}


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
