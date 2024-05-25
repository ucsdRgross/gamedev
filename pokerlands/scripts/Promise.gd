class_name Promise
extends RefCounted

signal completed(args)
signal update(args)
enum MODE {ANY, ALL}
var mode: int = MODE.ANY
var signals: Dictionary = {}

func _init(_signals: Array, mode: int) -> void:
	for connection in _signals:
		if connection is Signal:
			connection.connect(_on_signal.bind({&'signal':connection, &'data':false}))
			signals[connection] = {&'emitted':false, &'data':false}
		elif connection is Promise:
			connection.completed.connect(_on_signal.bind({&'signal':connection.completed, &'data':false}))
			connection.update.connect(_on_update)
			signals[connection.completed] = {&'emitted':false, &'data':false}
	self.mode = mode

func _on_signal(arg1 := {}, arg2 := {}) -> void:
	var _signal : Signal = arg1[&'signal']
	signals[_signal][&'emitted'] = true
	signals[_signal][&'data'] = arg1[&'data']
	_check_completion()

func _on_update(s : Signal, data : Array) -> void:
	signals[s][&'data'] = data

func _check_completion():
	if mode == MODE.ANY:
		_check_any_completion()
	elif mode == MODE.ALL:
		_check_all_completion()

func _check_any_completion() -> void:
	var complete := false
	var return_data: Array = []
	for _signal in signals:
		if signals[_signal][&'data'] is bool:
			signals[_signal][&'data'] = signals[_signal][&'emitted']
		return_data.append(signals[_signal][&'data'])
		if signals[_signal][&'emitted']:
			complete = true
	update.emit(completed, return_data)
	if complete:
		completed.emit({&'signal':completed, &'data':return_data})

func _check_all_completion() -> void:
	var complete := true
	var return_data: Array = []
	for _signal in signals:
		if signals[_signal][&'data'] is bool:
			signals[_signal][&'data'] = signals[_signal][&'emitted']
		return_data.append(signals[_signal][&'data'])
		if not signals[_signal][&'emitted']:
			complete = false
	update.emit(completed, return_data)
	if complete:
		completed.emit({&'signal':completed, &'data':return_data})
	
