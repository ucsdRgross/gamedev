class_name WallOverlay
extends CanvasLayer
## The persistent overlay: Back, Forward and Wall in the TOP-LEFT — never the bottom, which would
## sit over start_menu's Profile/Options and the map's Deck button — plus the top-right Info
## toggle. Its own CanvasLayer so it never rides the wall camera, mounted at `%Overlay` inside
## wall.tscn. Owns no navigation state: it reports presses and reflects a `FocusStack` back out
## through `refresh()`.

## Emitted when the corresponding control is pressed. `Main` consumes all four.
signal back_pressed
signal forward_pressed
signal wall_pressed
## `active` is the Info toggle's new pressed state.
signal info_toggled(active: bool)

@onready var _back_button : Button = %BackButton
@onready var _forward_button : Button = %ForwardButton
@onready var _wall_button : Button = %WallButton
@onready var _info_button : Button = %InfoButton

## Localises every label (never a literal string) and wires each control to its signal.
func _ready() -> void:
	_back_button.text = TRANSLATION.find('WALL_BACK')
	_forward_button.text = TRANSLATION.find('WALL_FORWARD')
	_wall_button.text = TRANSLATION.find('WALL_OVERVIEW')
	# A magnifying glass, not the word. The localised string stays as the TOOLTIP, so the control
	# is still named for a screen reader and still translatable.
	_info_button.icon = magnifier_icon()
	_info_button.tooltip_text = TRANSLATION.find('WALL_INFO')
	_back_button.pressed.connect(_on_back_pressed)
	_forward_button.pressed.connect(_on_forward_pressed)
	_wall_button.pressed.connect(_on_wall_pressed)
	_info_button.toggled.connect(_on_info_toggled)
	_apply_touch_targets()

## Grows every overlay control to at least `WallInput.touch_target_px()` on both axes.
##
## GROWS the authored layout rather than replacing it: each button keeps its authored top-left and
## the row keeps its authored GAP, both read back off the scene rather than re-typed here, so they
## cannot drift from it. The Info button is anchored RIGHT, so it grows leftward from its authored
## right edge and stays in the corner.
##
## ⚠ `custom_minimum_size` alone does NOT resize a manually-positioned Control until Godot's
## deferred layout pass — see `InfoCard._resize_to_content()` — so `size` is set explicitly too,
## and a caller reading `size` straight after `_ready()` sees the real one.
func _apply_touch_targets() -> void:
	var target := WallInput.touch_target_px(DisplayServer.screen_get_dpi(),
			WallPicture.settings())
	var row : Array[Button] = [_back_button, _forward_button, _wall_button]
	var gap := row[1].position.x - (row[0].position.x + row[0].size.x)
	var x := row[0].position.x
	for button : Button in row:
		_grow_to(button, target)
		button.position.x = x
		x += button.size.x + gap
	var info_right := _info_button.position.x + _info_button.size.x
	_grow_to(_info_button, target)
	_info_button.position.x = info_right - _info_button.size.x

func _grow_to(button: Button, target: float) -> void:
	button.size = Vector2(maxf(button.size.x, target), maxf(button.size.y, target))
	button.custom_minimum_size = button.size

## Reflects `stack` back onto the controls. Call whenever focus changes; the scene's defaults
## already match a fresh stack, so this is only needed on CHANGE.
##
## Back and Forward VISIBLY disable (`Button.disabled`) rather than silently doing nothing. The
## Wall button HIDES outright while `picture_count` is 1 or fewer — nothing to overview with one
## picture.
##
## ⚠ `in_wall_view` changes what "can go back" MEANS. `can_back()` asks whether anything sits
## below the current picture, which is the right question only while a picture is focused. In wall
## view Back returns to the picture just left — the stack's top — so it is live whenever the stack
## has ANY entry. Without this the button greys out on cold launch -> Escape while the Escape key
## and joypad Back, which share this handler, still work.
func refresh(stack: FocusStack, picture_count: int = 2, in_wall_view: bool = false) -> void:
	_back_button.disabled = not (stack.current() != &"" if in_wall_view else stack.can_back())
	_forward_button.disabled = not stack.can_forward()
	_wall_button.visible = picture_count > 1

## The `wall_info` key's way in. Flips the REAL toggle button rather than writing
## `wall_info_mode` from a second place, so the mode and what the button shows cannot disagree:
## setting `button_pressed` fires `toggled`, making key and mouse the same path.
func toggle_info() -> void:
	_info_button.button_pressed = not _info_button.button_pressed

## The Info button's magnifying glass. Built procedurally, the same idiom as
## `WallPicture.shared_frame_texture()`: the project's font is a bitmap face with no magnifier
## glyph, and a one-icon PNG is a dependency this does not need.
##
## Drawn WHITE so `Button.icon`'s theme tinting colours it, and cached statically — one texture
## however many overlays exist.
const _ICON_SIZE := 64
const _ICON_LENS_CENTRE := Vector2(25.0, 25.0)
const _ICON_LENS_RADIUS := 16.0
const _ICON_STROKE := 5.0
const _ICON_HANDLE_FROM := Vector2(36.0, 36.0)
const _ICON_HANDLE_TO := Vector2(57.0, 57.0)

static var _magnifier_icon : ImageTexture = null

static func magnifier_icon() -> ImageTexture:
	if _magnifier_icon: return _magnifier_icon
	# `Image.create()` zero-fills, so this is already fully transparent — no explicit fill, and
	# so no colour literal on a line that is not a colour choice.
	var img := Image.create(_ICON_SIZE, _ICON_SIZE, false, Image.FORMAT_RGBA8)
	var half_stroke := _ICON_STROKE * 0.5
	for y : int in _ICON_SIZE:
		for x : int in _ICON_SIZE:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			# The lens is a RING: inside the annulus of half-stroke either side of the radius.
			var on_lens := absf(p.distance_to(_ICON_LENS_CENTRE) - _ICON_LENS_RADIUS) <= half_stroke
			var on_handle := _distance_to_segment(p, _ICON_HANDLE_FROM, _ICON_HANDLE_TO) 					<= half_stroke + 0.5
			if on_lens or on_handle:
				img.set_pixel(x, y, Color.WHITE)
	_magnifier_icon = ImageTexture.create_from_image(img)
	return _magnifier_icon

## Shortest distance from `p` to the segment `a`-`b`, so the handle is a capsule of even width
## rather than a stack of per-row pixels that thins out on the diagonal.
static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0: return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _on_back_pressed() -> void:
	back_pressed.emit()

func _on_forward_pressed() -> void:
	forward_pressed.emit()

func _on_wall_pressed() -> void:
	wall_pressed.emit()

func _on_info_toggled(active: bool) -> void:
	info_toggled.emit(active)
