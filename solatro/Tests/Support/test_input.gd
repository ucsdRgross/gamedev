class_name TestInput
extends Node
## DEVICE INPUT THE PLATFORM'S OWN WAY -- `Viewport.push_input`, so the whole pipeline runs.

#Mouse emulation, hover and focus routing all happen on the way in, which is what makes a broken
#signal connection or a wrong mouse filter fail here exactly as it fails a player.

#A SubViewport is NOT on the OS input path, so `Input.parse_input_event` never reaches the one the
#game picture is hosted in and a suite has to deliver to that viewport itself. A frame is awaited
#after every event, which is what lets a hover land before the click that reads it.
static func driving(parent: Node, viewport: Viewport) -> TestInput:
	var driver := TestInput.new()
	driver._viewport = viewport
	parent.add_child(driver)
	return driver

var _viewport : Viewport

func send(event: InputEvent) -> void:
	_viewport.push_input(event)
	await get_tree().process_frame

## Move the pointer, which is what leaves behind the HOVER a card selection reads.
func move_to(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await send(motion)

## A press and a release over `at`, hovered first because selection reads the hovered control.
func click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await move_to(at)
	await send(_mouse_button(at, button, true))
	await send(_mouse_button(at, button, false))

## A key pressed and released, routed to whatever holds focus.
func key_tap(keycode: Key) -> void:
	await key_press(keycode)
	await key_release(keycode)

## A key held DOWN -- the half of a tap that a held action reads on its own.
func key_press(keycode: Key) -> void:
	await send(_key(keycode, true))

## Letting that key go, which is the other half of what a held action reads.
func key_release(keycode: Key) -> void:
	await send(_key(keycode, false))

## A controller button pressed and released, routed to whatever holds focus.
func joy_tap(button: JoyButton) -> void:
	await joy_press(button)
	await joy_release(button)

## A controller button held DOWN.
func joy_press(button: JoyButton) -> void:
	await send(_joy_button(button, true))

## Letting that controller button go.
func joy_release(button: JoyButton) -> void:
	await send(_joy_button(button, false))

func _mouse_button(at: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event

func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event

func _joy_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event
