class_name GestureMetrics
extends RefCounted
## The one unit model for gestures and overlay controls: a fraction of the thing being touched.

# ⚠ NO SCREEN-DENSITY READING ANYWHERE, AND NO MILLIMETRES: the density a screen reports is
# unreliable on multi-monitor Windows, which gives the primary screen's for all of them, and on
# Android.

## How far a press must travel before its RELEASE places instead of its click grabbing.
static func drag_threshold_px(card_size: Vector2, settings: PlayerSettings) -> float:
	return card_size.x * settings.card_drag_threshold

## The minimum size of any overlay control, uncapped -- the window fraction IS the clamp.
static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float:
	return minf(window.x, window.y) * settings.touch_target_fraction
