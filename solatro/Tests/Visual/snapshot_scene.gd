class_name SnapshotScene
extends Node2D
# res://Tests/Visual/snapshot_scene.gd
# ==============================================================================
# The plumbing every visual-snapshot scene needs, in ONE place: the backdrop, the layout space, the
# captions, and the capture-and-write. Subclasses (fx_snapshot.gd, prop_art_snapshot.gd) contribute
# only their shots.
#
# It exists because the two harnesses had drifted into two copies of this, and one of the copies is
# the CANVAS-UNITS rule below — a trap that already cost a debugging pass once. It is not the kind of
# thing that should live in two files.
#
# These scenes are deliberately NOT in all_tests.tscn: they need a window and a GPU, so they stay
# separate, explicit runs rather than something that breaks headless invocations. They are
# diagnostics, so their strings are deliberately literal rather than localized.
# ==============================================================================

## Seeded so two runs of unchanged code produce identical images and a diff means a real change.
const RNG_SEED := 20260727

## A dark backdrop: the effects are transparent overlays, and on the default clear colour the darkest
## bands of a ramp are invisible.
const BACKDROP := Color(0.09, 0.09, 0.12)

## Where this scene's PNGs go, and the window it shoots at — set by the subclass in _ready before it
## calls begin().
var out_dir : String = "user://snapshots"

## Refuse to run without a renderer, LOUDLY and immediately.
##
## Under `--headless` the dummy renderer never fires `RenderingServer.frame_post_draw`, so a snapshot
## scene does not fail there — it HANGS FOREVER, writes nothing, and reports no reason (measured
## 2026-07-27: a headless run sat past a two-minute timeout having produced zero PNGs, while stale
## PNGs from an earlier windowed run sat on disk looking like output). Better to die in one line.
## Returns false when the caller must stop; it has already quit the tree.
func require_renderer() -> bool:
	if DisplayServer.get_name() != "headless": return true
	push_error("%s needs a REAL renderer: --headless never compiles a shader and never fires "
			% get_script().resource_path
			+ "frame_post_draw, so this scene would hang forever instead of writing snapshots. "
			+ "Re-run it WITHOUT --headless.")
	get_tree().quit(1)
	return false

## Prepare the RNG, the window, the output folder and the backdrop. Subclasses call this first, and
## stop if it returns false (no renderer — see require_renderer).
func begin(dir: String, window: Vector2i) -> bool:
	if not require_renderer(): return false
	out_dir = dir
	seed(RNG_SEED)
	DisplayServer.window_set_size(window)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	return true

## THE layout space — and NOT the window size. `window/stretch/mode` is `canvas_items`, so the canvas
## has its own resolution and the captured image is that canvas scaled to the window. Laying out
## against window pixels puts the last column off the right edge; reading pixels back needs
## `img.get_width() / canvas().x` as the conversion (see to_image_scale).
func canvas() -> Vector2:
	return get_viewport_rect().size

## Canvas units -> captured-image pixels, the ratio every measurement of a capture goes through.
func to_image_scale(img: Image) -> float:
	return float(img.get_width()) / canvas().x

## Caption the shot, wait for the frame to actually reach the screen, then capture and write it.
## Returns the Image so a caller that MEASURES its own capture does not have to re-read the file.
func capture(file_name: String, caption: String) -> Image:
	label(self, "%s — %s" % [file_name, caption], Vector2(canvas().x * 0.5, 30.0))
	# Two frames: one to apply the uniforms/state written above, one to be sure it has been drawn.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, file_name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
	# The caption is parented to self (it must not vanish with a shot's holder), so clear it here.
	for child in get_children():
		if child is Label: child.queue_free()
	return img

## Centred caption.
func label(parent: Node, text: String, at: Vector2) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(400, 20)
	lab.position = at - Vector2(200, 10)
	parent.add_child(lab)
