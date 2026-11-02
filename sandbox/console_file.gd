class_name ConsoleFile
extends Logger
## Writes everything the console shows to a file of its own as it happens, so the file is whole however the game ends:
## a process that gets killed never reaches any code that could save it on the way out. May be called from any thread.

var _file: FileAccess
var _lock := Mutex.new()


## Starts with what the console already showed before the game's scripts could run.
func _init(path: String, earlier: String) -> void:
	_file = FileAccess.open(path, FileAccess.WRITE)
	_write(earlier)


func _log_message(message: String, _error: bool) -> void:
	_write(message)


func _log_error(
	function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var kind := "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR"
	_write("%s: %s\n   at: %s (%s:%d)\n" % [kind, rationale if rationale != "" else code, function, file, line])


func _write(text: String) -> void:
	_lock.lock()
	if _file:
		_file.store_string(text)
		_file.flush()
	_lock.unlock()
