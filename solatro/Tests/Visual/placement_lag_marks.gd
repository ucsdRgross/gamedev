extends RefCounted

# The per-frame cost sink the placement lag probe reads. Temporary brackets in product code add to
# it; the saver thread adds too, so every write goes through the one lock.

static var _lock := Mutex.new()
static var _by_frame : Dictionary[int, Dictionary] = {}
static var _thread_events : Array[String] = []

static func add(label: StringName, since_usec: int) -> void:
	var cost := Time.get_ticks_usec() - since_usec
	var frame := int(Engine.get_process_frames())
	_lock.lock()
	var row : Dictionary = _by_frame.get_or_add(frame, {})
	var count_key := StringName(String(label) + "#n")
	var so_far : int = row.get(label, 0)
	var calls : int = row.get(count_key, 0)
	row[label] = so_far + cost
	row[count_key] = calls + 1
	_lock.unlock()

static func thread_event(line: String) -> void:
	_lock.lock()
	_thread_events.append("%d %s" % [Time.get_ticks_usec(), line])
	_lock.unlock()

static func take(frame: int) -> Dictionary:
	_lock.lock()
	var row : Dictionary = _by_frame.get(frame, {})
	_by_frame.erase(frame)
	_lock.unlock()
	return row

static func take_thread_events() -> Array[String]:
	_lock.lock()
	var out := _thread_events.duplicate()
	_thread_events.clear()
	_lock.unlock()
	return out
