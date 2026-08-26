@tool
class_name CardOutline
## THE OUTLINE CONVENTION, in one place: the padded UV mapping `Shaders/outline.gdshader` needs, and
## the material every outlined polygon wears.
##
## `@tool` for the same reason every modifier here is: the FX editor and the outline atlas stand up a
## REAL card, and nothing in this file needs a running game.
##
## ── THE RULE ──────────────────────────────────────────────────────────────────────────────────────
## **The source frame maps to the polygon's INNER rect, and the polygon extends `WIDTH` art units past
## it on all four sides.** 8x8 art in a 10x10 polygon, 32x32 in 34x34, and the card's face 38x52 in a
## 40x54 polygon. One rule, five clients, one shader.
##
## ⚠ **THIS IS A VARIANT OF `CardModifier.update_polygon_uv_frame`, NOT A REPLACEMENT FOR IT.** That
## function is the project's one definition of sheet geometry and it is SHARED with prop art through
## `PropVisual._draw_frame`. Props deliberately get no outline (design D3 — they are temporary, so they
## do not need the same readability), so they need no padding, and editing the shared function to add
## some would have moved every prop in the game. Both funnel into `CardModifier.frame_rect`, so there
## is still exactly one definition of where a frame lives in a sheet.
##
## ⚠ **The padded window overlaps four neighbouring frames**, because the sheets carry no transparent
## gutter. Nothing here prevents that bleed — `u_frame_uv` and the shader's clamp do. That was the
## trade: padded sheets would have made the bleed impossible by construction but pinned the rim at one
## pixel forever, and a wider rim is exactly what the GLARE alert wants.

## Rim thickness in ART UNITS, which on a card is also SOURCE TEXELS (`test_fx_pixel_is_the_games_pixel`
## pins the 1:1). THE constant: the polygon padding below, `CardVisual.CARD_SIZE`'s definition and the
## shader's `u_outline_width` are all derived from it, so they cannot drift apart.
const WIDTH : float = 1.0

const SHADER : Shader = preload("res://Shaders/outline.gdshader")

## THE SHIPPED TUNING — ink, width and both alert kinds — and the reason `tools/outline_atlas.tscn`
## changes the GAME rather than only its own preview. A card uses this unless its TYPE names another
## (`CardModifierType.outline_style`).
##
## ⚠ It lives here rather than on `OutlineStyle` because a `.tres` cannot be preloaded as a typed const
## inside the very class that scripts it — see that file's note.
const STYLE : OutlineStyle = preload("res://Shaders/Styles/outline_default.tres")

## How a body texel is coloured. Not a style choice — see the shader's own note: `suit_pips.png`,
## `stamp_pips.png` and `card_types.png` are AUTHORED in the palette and already carry their own
## shading, so flattening them to one entry would destroy it. The rank pip and the card art are
## suit-agnostic silhouettes shared by every suit, so they MUST be flattened to the suit's role.
enum Fill {TEXTURE = 0, PALETTE = 1}

## The alert modes, mirroring the shader's constants. A status names one of these; it never names a
## colour for GLARE, because what makes an alert an alert is that it MOVES (design D6).
enum Alert {NONE = 0, GLARE = 1, THROB = 2}

## The material this polygon draws through, created on first use and REUSED afterwards.
##
## ⚠ **NO POLYGON ON A CARD MAY BE LEFT MATERIAL-LESS.** `PipSuit.set_texture` and
## `CardModifier.set_material` used to assign `null` here, deliberately: these polygons are POOLED and
## reused across cards, so a stale ShaderMaterial from a previous binding would otherwise survive a
## rebind. Now that every element is an outline client, the answer to a stale material is to OVERWRITE
## its uniforms rather than to clear it — every former `= null` site calls into this file instead.
## Missing one is a pip that silently loses its outline on some cards and not others, depending on what
## happened to be bound there before.
##
## ⚠ **Reused, not rebuilt, and that is a cost decision.** The old `set_material` built a fresh
## `ShaderMaterial.new()` on every bind. The deck viewer is the densest screen in the game — 50+ cards
## x 5 polygons — and pooled controls re-derive their card's state on every `_bind_slot`, so rebinds
## are frequent. Retuning uniforms on the live material is what keeps that off the frame budget.
static func material_of(poly : Polygon2D) -> ShaderMaterial:
	var mat := poly.material as ShaderMaterial
	if not (mat and mat.shader == SHADER):
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		# ⚠ SCENE-LOCAL, so a material that ends up SAVED into a scene is still copied per instance.
		# Without it every card sharing that scene shares one material, and each card's own
		# `u_frame_uv` / `u_fill_mode` write lands on all of them — last writer wins, board-wide.
		mat.resource_local_to_scene = true
		poly.material = mat
	# ⚠ **SEEDED ON EVERY CALL, NOT ONLY ON CREATION.** These three used to be set once, inside the
	# construction branch, with an existing outline material returned untouched. That is exactly what
	# an editor-saved material defeats: `poly.material = mat` above is a scene mutation, so a `@tool`
	# host persists it, and every later call then short-circuited and left whatever uniform state the
	# editor happened to capture. Re-seeding is idempotent and cheap next to a rebind.
	# The palette IMAGE and its width both come from PaletteDB, never from a shader default: the
	# VisualShader this pattern replaced had the palette baked into itself, so swapping palettes
	# recoloured nothing (ARCHITECTURE_REVIEW §4h, proved by the 16_palette_swap snapshot).
	mat.set_shader_parameter(&"u_palette", PaletteDB.PALETTE.texture)
	mat.set_shader_parameter(&"u_num_colors", PaletteDB.width())
	mat.set_shader_parameter(&"u_outline_width", int(WIDTH))
	return mat

## UV this polygon so its frame lands on the polygon's inner rect, leaving `WIDTH` units of margin for
## the rim, and tell the shader where that frame ends.
##
## ⚠ **The 1 art unit = 1 source texel invariant is what this function ESTABLISHES, and it holds only
## if the polygon is exactly `frame + 2 * WIDTH` across.** Give it a polygon that is still the size of
## its frame and the art is simply stretched over the padding — no outline, everything 25 % too big on
## a pip. Nothing here can detect that (a polygon has no opinion about how big it ought to be), so it
## is asserted from the outside, by `test_pixels`.
static func frame_polygon(poly : Polygon2D, sheet : Texture2D, h_frames : int, v_frames : int,
		target_frame : int) -> void:
	if not poly or poly.polygon.is_empty(): return
	if poly.texture != sheet: poly.texture = sheet

	var src := CardModifier.frame_rect(sheet, h_frames, v_frames, target_frame)
	var pad := Vector2(WIDTH, WIDTH)
	# The window the polygon's bounding box maps onto: the frame grown by the rim on all four sides.
	var win_pos := src.position - pad
	var win_size := src.size + pad * 2.0

	var pts := poly.polygon
	var min_p := pts[0]
	var max_p := pts[0]
	for i : int in range(1, pts.size()):
		var p := pts[i]
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var span := max_p - min_p
	if span.x == 0.0: span.x = 1.0
	if span.y == 0.0: span.y = 1.0

	var uvs := PackedVector2Array()
	uvs.resize(pts.size())
	for i : int in pts.size():
		var norm := (pts[i] - min_p) / span
		uvs[i] = win_pos + norm * win_size
	poly.uv = uvs

	# THE CLAMP the shader tests every tap against, in normalized sheet UV. Derived from the same
	# `frame_rect` the UVs were, so the two cannot describe different windows.
	var sheet_size := sheet.get_size()
	var mat := material_of(poly)
	mat.set_shader_parameter(&"u_frame_uv", Vector4(
			src.position.x / sheet_size.x, src.position.y / sheet_size.y,
			(src.position.x + src.size.x) / sheet_size.x,
			(src.position.y + src.size.y) / sheet_size.y))
	# The polygon's own centre in card space, which is exactly its node position — pushed rather than
	# written down, so the coordinate the alert sweeps cannot disagree with where the polygon is.
	mat.set_shader_parameter(&"u_card_offset", poly.position)

## Override where this polygon sits IN CARD SPACE, for a host whose node position is not its card
## position.
##
## ⚠ **`frame_polygon` already pushes `poly.position`, which is correct for a real card and WRONG for
## any tool that lays elements out on a grid.** The alert band sweeps card space and exists only within
## the card's own extent (±20 in x), so an atlas that leaves its layout coordinates in there sees the
## band on the handful of frames whose grid position happens to fall inside ±20 and on nothing else.
## Measured on `outline_atlas` 2026-08-06: exactly three frames glowed — the first pip of the rank, suit
## and stamp rows, each at x≈15 — and every other frame in the game appeared not to support the alert
## at all. A tool laying frames out must say which element each frame IS.
static func set_card_offset(poly : Polygon2D, card_offset : Vector2) -> void:
	material_of(poly).set_shader_parameter(&"u_card_offset", card_offset)

## Draw this element's body in the sheet's own colours.
static func fill_texture(poly : Polygon2D) -> void:
	material_of(poly).set_shader_parameter(&"u_fill_mode", Fill.TEXTURE)

## Flatten this element's body to one palette entry (the suit's role, for the rank pip and the card art).
static func fill_palette(poly : Polygon2D, palette_index : int) -> void:
	var mat := material_of(poly)
	mat.set_shader_parameter(&"u_fill_mode", Fill.PALETTE)
	mat.set_shader_parameter(&"u_fill_index", palette_index)

## THE CARD'S RIM — its ink and its width — plus the card extent the alert sweeps. Pushed from
## `CardVisual.update_visual` to all five polygons at once: resolving it inside each modifier would
## derive the same fact five times and leave nowhere for a per-type override to land.
##
## ⚠ `style.width` above `WIDTH` CLIPS at the polygon edge, because the polygons were baked with exactly
## `WIDTH` of margin. That is not enforced here — see `OutlineStyle.width` for why a silent clamp would
## be worse than a visible clip.
static func set_rim(poly : Polygon2D, style : OutlineStyle, card_extent : Vector2) -> void:
	var mat := material_of(poly)
	mat.set_shader_parameter(&"u_outline_index", style.outline_index)
	mat.set_shader_parameter(&"u_outline_width", style.width)
	mat.set_shader_parameter(&"u_card_extent", card_extent)

## Put this polygon's rim into (or out of) an alert. `null` is the resting state.
##
## Takes the whole `CardAlert` rather than its fields one by one: the alert grew a fourth knob (the
## side buffer) and a fifth is plausible, and a widening argument list is a widening list of call sites
## that have to be found and updated in step.
static func set_alert(poly : Polygon2D, alert : CardAlert, style : OutlineStyle) -> void:
	var mat := material_of(poly)
	if not alert:
		mat.set_shader_parameter(&"u_alert_kind", Alert.NONE)
		return
	# RESOLVED HERE, not at construction: a status builds its request without knowing which card will
	# read it, so anything it left unset must fall through to THAT card's style rather than to the
	# shipped one. See `CardAlert`'s three layers.
	mat.set_shader_parameter(&"u_alert_kind", alert.kind)
	mat.set_shader_parameter(&"u_alert_color", alert.resolved_color(style))
	mat.set_shader_parameter(&"u_alert_thickness", alert.resolved_thickness(style))
	mat.set_shader_parameter(&"u_alert_buffer", alert.resolved_buffer(style))

## Advance this polygon's alert phase. Written every frame while an alert is live and never otherwise —
## a resting board must pay nothing for a feature it is not using.
static func set_clock(poly : Polygon2D, phase : float) -> void:
	material_of(poly).set_shader_parameter(&"u_alert_clock", phase)
