extends Control
class_name PlayArea

signal data_selected(data : CardData)
## A card was CLICKED while Info mode is on. Carries the card's own `InfoEntry` for the wall's one
## info card; `data_selected` is deliberately NOT emitted for the same press.
signal info_requested(entry: InfoEntry)
## Emitted once a rebuild's CardVisuals are all in-tree and _ready. CardVisuals add_child via
## call_deferred, so right after set_card_zones they're mapped in data_card but not yet ready;
## a deferred emit queued after those adds (FIFO) fires only once they've entered the tree.
## Lets callers that must animate a freshly built board (e.g. a resumed show) await instead
## of poll. Pair with visuals_ready() for the already-ready case (check-then-await).
signal board_visuals_ready

## OVERVIEW ONLY: the view should rest on grid `grid_index`. The horizontal aim is dead range in
## the overview (the container is picture-wide), so the CAMERA is the single horizontal authority
## there; whoever owns the wall camera listens and drives it from `WallPicture.grid_state()`.
signal overview_pan_requested(grid_index: int)

## OVERVIEW ONLY: a pan was attempted past the first or last grid. `step` carries the direction
## (`pan_by_grids`'s own sign) so the listener can push the camera the same way and spring it back.
signal overview_bounce_requested(step: int)

## The board has exactly TWO view modes and nothing in between: OVERVIEW shows every grid for
## orientation, FOCUSED shows the one grid the player is acting on. Switching is a transition —
## there is no intermediate zoom to sit at.
enum ViewMode { OVERVIEW, FOCUSED }

## No grid is focused. ⚠ Never 0 — grid 0 is a real grid.
const NO_GRID := -1

## The width the HUD's rectangle takes on the LEFT, published by `GameView`. The board lays out in
## what is left of the screen and CENTRES THERE, not on the screen (owner ruling). Zero for any host
## that mounts a bare `PlayArea` with no HUD around it.
##
## ⚠ **THE BOARD'S WINDOW IS WHAT MOVES, NOT THE CONTENT.** Insetting the scroller's own left edge
## makes every centring the board already does -- the focused aim, the resting position, the
## removal re-centre -- land in the post-HUD space for free. Offsetting the content instead would
## leave each of those to re-discover the inset separately.
var board_inset_left : float = 0.0:
	set(value):
		if is_equal_approx(board_inset_left, value): return
		board_inset_left = maxf(value, 0.0)
		if not is_instance_valid(scroll_container): return
		# ⚠ **THE RESERVE ARRIVES AFTER THE SHOW HAS ALREADY OPENED.** `GameView` reads the HUD's
		# authored offsets at the END of its own `_ready()`, by which time the deal has built the
		# board and `open_show_view()` has already fitted a focused grid against an inset of zero.
		# Re-fitting here is what makes the arriving reserve reach the zoom; without it the board
		# keeps the width it chose when it thought it had the whole screen.
		# ⚠ **THE RECT FIRST, UNCONDITIONALLY.** `_zoom_board_to()` early-returns when the zoom is
		# unchanged, and a reserve that arrives without moving the zoom is exactly that case — the
		# scroller would keep the offsets it took when it thought it had the whole screen, and the
		# board would centre on the SCREEN rather than on what the HUD leaves.
		_apply_entrance_strip_height()
		if view_mode == ViewMode.FOCUSED and focused_grid != NO_GRID:
			focus_grid(focused_grid)

## The view mode changed. Carries the mode and the grid it focuses (`NO_GRID` in the overview).
signal view_mode_changed(mode: ViewMode, grid: int)

## ⚠ **THE OVERVIEW IS ORIENTATION ONLY: A CLICK ON A GRID THERE FOCUSES IT AND PLACES NOTHING.**
## Placement only ever happens focused. Set through `open_zoomed_out` / `focus_grid`, never by hand.
## ⚠ **THE RESTING DEFAULT IS THE ACTING MODE.** The overview is a state a show is explicitly
## OPENED into (`open_zoomed_out`), so a show that never opens it reads as one that opens focused
## rather than silently matching a default.
var view_mode : ViewMode = ViewMode.FOCUSED
var focused_grid : int = 0

var focused_control : Control = null
var moused_hovered_control : Control = null
var selected_cards : Array[CardData] = []

## The board's inter-card gap in ART units, before `card_scale`. One number, so the board and the
## picture that has to hold it cannot disagree about the pitch.
const BOARD_SEPARATION := 4

var separation : int = BOARD_SEPARATION: 
	set(value):
		separation = value
		set_separation()
	get():
		return separation * PlayArea.settings().card_scale

## Which `PlayerSettings` the BOARD reads. ⚠ **THE SAME ACCESSOR THE WALL USES, AND THAT IS THE
## POINT.** `Tools/wall_editor.tscn` hosts a real `GameView` on its game picture, and the one
## override it sets is `WallPicture.editor_settings` -- so a board that went straight to
## `SettingsManager` ignored every knob the tool's own panel edits, and `board_edge_pad_rows` or
## `hud_width_fraction` tuned there changed nothing on the board being previewed.
## In the shipped game nothing sets that override and this resolves to `SettingsManager.settings`.
static func settings() -> PlayerSettings:
	return WallPicture.settings()

## **S16 — THE REVEAL. Which board rows are held open, and how far.** Value
## is the eased 0..1 this row is through its opening. A row at 0 is absent from the map entirely, so
## an un-revealed board carries no state and `slot_center_global` costs what it always did.
##
## ⚠ **A COLUMN OPENS EVERY ROW IT PASSES THROUGH**, not none — the reveal set is every board row
## that must expand to make each member of the spotlight set fully visible, and the consequence is
## stated outright: *"Column scoring on the longest column expands nearly every row at
## once"*. This is keyed by ROW for exactly that reason.
## ⚠ **THE KEY IS `(grid, h)`, WITH THE ENTRANCE ON A RESERVED GRID INDEX** (`REVEAL_ENTRANCE_GRID`)
## — one key shape for the whole board, the Entrance just another row. `h` is a DEPTH within a
## stack, not a screen row: on the Entrance a level of a fanned column, on a grid a height layer
## across every cell. Build every key with `_reveal_key`, never by hand.
var _row_open : Dictionary[Vector2i, float] = {}
## The rows that WANT to be open. Separate from `_row_open` because a row that has just left the set
## still has to ease back down, and a map that only held the current set would snap it.
var _row_open_wanted : Dictionary[Vector2i, bool] = {}

## The Entrance's reserved slot in the reveal key's grid axis. Real grids index from 0, so -1 is
## free, and it can never collide with `coord.grid` — the Entrance carries the index of whichever
## grid it is attached to, which is a REAL grid.
const REVEAL_ENTRANCE_GRID := -1

## The `_row_open` key for a board coordinate.
func _reveal_key(coord: BoardCoord) -> Vector2i:
	return Vector2i(REVEAL_ENTRANCE_GRID if coord.is_entrance() else coord.grid, coord.h)

## Each grid panel's resolved global origin, keyed by its index among `GameData.grids`. A panel's
## own rect is a LAYOUT RESULT (bottom/center-shrink flags inside an HBoxContainer of siblings), so
## the panel publishes its origin here whenever its rect changes; `slot_center_global` reads only
## this cache and never the panel's rect, keeping the every-frame prop-anchor path free of
## control-tree reads. Grids are only appended or truncated from the end (`set_grid_zones`), so a
## panel's index is stable for its whole lifetime and is a safe cache key.
## ⚠ Empty for any grid whose panel has not yet reported a `resized` at all (the very first frame
## before layout has run once) — a lookup then falls back to `Vector2.ZERO`, the same silent-until-
## seen failure mode the cache accepts by design.
var _grid_panel_origin : Dictionary[int, Vector2] = {}

## The board's floor: the screen line every grid panel is bottom-aligned against. See
## `_publish_board_floor` for why this, and not a panel's own rect, is what the row geometry reads.
var _board_floor_y := 0.0

## Each grid's CELL BLOCK — where the columns actually start, and where its rows actually bottom
## out. Distinct from the panel once the panel carries score gutters. See `_publish_cell_rects`.
var _grid_cells_origin : Dictionary[int, Vector2] = {}
var _grid_cells_bottom : Dictionary[int, float] = {}



## How tall a revealed row's strip becomes, in screen pixels — the only place either formula is
## written.
##
## ⚠ **NEITHER FORMULA MAY LOOK AT ANY CARD'S POSITION.** Sizing the opening from the lowest card
## that had to be seen breaks on a FLUSH, where every card in the row is lit and jumps — that card
## is then the lowest on the board, and the opening lifts rows *"that arent part of actual scored
## set"*.
func _row_open_height() -> float:
	return row_open_height(PlayArea.settings(), float(separation))

## The two modes, STATIC so the tuning tool reads the same formula instead of a hand copy
## (its copy ignored the mode and kept the overshoot bug fixed below — the exact drift the tool
## exists to rule out). `separation_px` is the SCALED inter-row gap (`PlayArea.separation`'s
## getter applies `card_scale`; a caller without the node applies it itself).
static func row_open_height(settings_res: PlayerSettings, separation_px: float) -> float:
	var full := CardVisual.card_size_play.y
	if settings_res.spotlight_separation_mode == PlayerSettings.SeparationMode.JUMP_ADJUSTED:
		# The jumping cards clear the row while a card that does NOT jump stays slightly covered —
		# which is the whole point of this mode, not a rounding artefact.
 # ⚠ **`separation` COMES OFF THIS MODE TOO** (owner: *"jump adjusted needs to be
		# card height - separation - jump height then"*). `CARD_HEIGHT` opens to a pitch of exactly one
		# card; this opens to a card LESS the inter-row gap and the jump rise, so a card that does not
		# jump stays covered by that much. Both branches return a TOTAL pitch — `row_open_span`
		# takes the container's `separation` off again to get the strip — so this is the distance you
		# actually measure between two rows.
		return full - separation_px - CardVisual.card_jump_rise_play
	return full

## The strip-level EXTRA a fully open row adds over the stacked layout — the mode's total pitch
## minus the separation the container already provides and the stacked strip itself.
static func row_open_span(settings_res: PlayerSettings, separation_px: float) -> float:
	return maxf(row_open_height(settings_res, separation_px) - separation_px \
			- float(CardVisual.card_separation_play_custom), 0.0)

## The board's inter-card gap in SCREEN pixels. Static so anything that has to size the board
## WITHOUT one on screen -- the picture that hosts it -- reads the same number the board lays out
## with, rather than a copy that can drift.
static func board_separation_px(settings_res: PlayerSettings) -> float:
	return float(BOARD_SEPARATION) * settings_res.card_scale

## One grid's CELL BLOCK in board pixels: `grid_width` cards across and `grid_height` down with the
## board separation between them. ⚠ The score gutters are deliberately NOT in it -- they sit
## inside the buffer between grids, which is what `_apply_grid_buffer()` enforces on screen.
static func grid_block_size_px(settings_res: PlayerSettings, grid: GridData) -> Vector2:
	var sep := board_separation_px(settings_res)
	var card := CardVisual.CARD_SIZE * settings_res.card_scale
	var w := float(maxi(grid.grid_width, 1))
	var h := float(maxi(grid.grid_height, 1))
	return Vector2(w * card.x + (w - 1.0) * sep, h * card.y + (h - 1.0) * sep)

## The clear band kept ABOVE the board and BELOW the Entrance so neither hugs the window's edge
## (owner ruling: *"add 1 row full card height buffer to top and bottom of the play area so it
## doesnt hug screen edge so tightly"*). One whole card, in BOARD units, so it scales with the
## board exactly as a row does -- an unscaled band would read as half a card once focused.
static func board_edge_pad_px(settings_res: PlayerSettings) -> float:
	return CardVisual.CARD_SIZE.y * settings_res.card_scale * settings_res.board_edge_pad_rows

## The Entrance strip's height, in screen pixels, at a given zoom. `zoom = 1.0` for the two
## static picture-sizing sites (the render-target picture is fixed and zoom-independent);
## the live strip passes `board_zoom` so it tracks the same scale the grid renders at.
static func entrance_strip_height_px(settings_res: PlayerSettings, zoom: float) -> float:
	return CardVisual.CARD_SIZE.y * settings_res.card_scale * settings_res.entrance_visible_rows * zoom

## Everything `focused_board_zoom()` divides the board's window by, in board units -- the cell
## block, the Entrance strip and the two card-row edge buffers.
##
## ⚠ **THE BUFFER DERIVATION MUST SOLVE FOR THE ZOOM THE BOARD REALLY USES.** It solved for
## `picture.y / (block.y + strip)` while the live fit had grown two card rows of edge buffer in its
## denominator -- 108 of 475 units unmodelled -- so the buffer it produced isolated nothing.
## ⚠ **STILL AN UNDER-COUNT, AND DELIBERATELY.** The live fit also carries the panel's column-label
## gutter and the scroller's reserved band, both of which come from a FONT and a THEME and cannot be
## known before a board exists, while this sizes the picture before one does. The remainder is ~35
## units of ~510; the two card-row buffers were the term worth closing.
## The two terms the fit carries that no SETTING describes: the panel's column-label row and the
## band the scroller reserves for its horizontal bar. Both come from the FONT and the THEME.
##
## ⚠ **ASKED OF THE ENGINE, NOT GUESSED AT.** They were left out because "they cannot be known
## before a board exists" -- but they are not properties of a BOARD, they are properties of a Label
## and an HScrollBar, and either will state its own minimum height without being in a tree. That is
## a theme query, not a stand-in for the real thing.
## ⚠ **CACHED, BECAUSE THE PICTURE IS ONE SIZE FOR A RUN.** A font or theme swap mid-run would have
## to invalidate this, and nothing in this game does one.
static var _furniture_h := -1.0
static func board_furniture_height_px(settings_res: PlayerSettings) -> float:
	if _furniture_h < 0.0:
		var label := Label.new()
		var bar := HScrollBar.new()
		_furniture_h = label.get_combined_minimum_size().y + bar.get_combined_minimum_size().y
		label.free()
		bar.free()
	return _furniture_h + board_separation_px(settings_res)

static func focused_content_height_px(settings_res: PlayerSettings) -> float:
	return grid_block_size_px(settings_res, GridData.new()).y 			+ entrance_strip_height_px(settings_res, 1.0) 			+ 2.0 * board_edge_pad_px(settings_res) 			+ board_furniture_height_px(settings_res)

## What the picture's width is divided by to get the half-width a neighbour must clear.
##
## ⚠ **THE BOARD'S OWN AREA IS THE VIEW ISOLATION IS MEASURED IN, NOT THE CAMERA'S WHOLE RECT**
## (owner: *"the center should be on halfway through the 0.75 section... pretend 0.75 area is the
## entire camera view, so its truly centered"*). The HUD takes `hud_width_fraction` off the left, so
## the board's own view is the remaining share and a neighbour is out of view once it clears THAT.
##
## ⚠ **THIS IS WHY THE CONDITION IS SYMMETRIC AGAIN.** The board centres in its own area, so both
## neighbours sit the same distance from its edges -- the one-sided HUD offset that made the LEFT
## neighbour cost more than the right cancels out the moment the board's area is the frame of
## reference. It also asks LESS than the old `wall_overfill_margin` did: `0.375 W` against `0.49 W`.
##
## ⚠ **SYMMETRIC IN THE BOARD'S AREA IS NOT SYMMETRIC ON THE SCREEN, AND THAT IS EXPECTED.** With
## the HUD on the left the board's area is offset right, so a left-hand grid really does sit nearer
## the screen's edge than a right-hand one. Isolation does not care -- it is measured in the board's
## area -- but anything that reasons about DISTANCE TO THE SCREEN EDGE must not assume the two sides
## match.
## ⚠ **THIS DIVISOR IS HORIZONTAL, AND IT ASSUMES THE HUD IS A LEFT COLUMN.** A HUD on TOP takes
## nothing off the width, so the horizontal divisor is 1 and the share comes off the HEIGHT instead
## -- and then neither side is nearer the screen's edge. Whoever moves the HUD moves this with it.
static func board_view_divisor(settings_res: PlayerSettings) -> float:
	return 1.0 / maxf(1.0 - settings_res.hud_width_fraction, 0.0001)

## The buffer between two grid panels, DERIVED so a FOCUSED grid isolates its neighbours: at the
## isolation check's own scale, the neighbour panel's near edge must clear the OVERVIEW picture's
## own resting half-width, which is what the wall camera actually shows at rest since it always fits
## the whole picture whole.
## ⚠ **MEASURED, NOT INFERRED: `wall_overfill_margin` DOES apply here.** The picture's height is
## rounded to a whole pixel (`game_picture_design_size()`), which breaks the exact aspect match with
## the window by a hair -- `WallPicture.focused_scale()`'s axis ratios then differ enough that
## `is_equal_approx` reads them as unequal, so the margin branch fires. Confirmed by reading
## `focused_scale()`'s own return against the live design size rather than assumed from the intent
## behind the rounding.
## ⚠ **THE ZOOM MUST BE `focused_board_zoom()`'s OWN FIXED POINT, NOT A FLAT SUBTRACTION.** A flat
## `(picture.y - strip_h) / block.y` is a DIFFERENT, smaller quantity than the real
## `picture.y / (block.y + strip_h)` the board actually focuses to -- confirmed by evaluating both
## against a live picture (2.340 modelled vs 2.044 real), and the smaller real zoom is exactly why a
## buffer solved against the flat model still left a neighbour in frame.
## ⚠ **CLOSED FORM, NOT A SEARCH.** `grid_position_size_px()`'s width and (per the aspect minimum
## dominating `block.y` at every buffer this game ships) height are both AFFINE in the buffer, so
## the isolation inequality `neighbour_near_edge(buffer) >= visible_half(buffer)` expands to exactly
## `a*buffer^2 + b*buffer + c >= 0`; sampling the real function at buffer 0 and 1 reads its two
## affine coefficients exactly, with no formula of this function's own to drift from
## `grid_position_size_px()`. With one grid there is no neighbour to isolate.
static func isolating_grid_buffer_px(settings_res: PlayerSettings) -> float:
	var count := maxi(settings_res.grid_max_count, 1)
	if count <= 1: return 0.0
	var block := grid_block_size_px(settings_res, GridData.new())
	var strip_h := focused_content_height_px(settings_res)
	var by := maxf(strip_h, 0.0001)
	var wom := board_view_divisor(settings_res)
	var p0 := grid_position_size_px(settings_res, 0.0)
	var p1 := grid_position_size_px(settings_res, 1.0)
	var height_slope := p1.y - p0.y
	var width_slope := p1.x - p0.x
	var a := height_slope / by
	var b := p0.y / by + height_slope * block.x / (2.0 * by) - width_slope / (2.0 * wom)
	var c := p0.y * block.x / (2.0 * by) - p0.x / (2.0 * wom)
	if c >= 0.0: return 0.0
	if is_zero_approx(a):
		return maxf(-c / b, 0.0) if not is_zero_approx(b) else 0.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0: return 0.0
	var sq := sqrt(disc)
	var root_lo := minf((-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a))
	var root_hi := maxf((-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a))
	return maxf(root_hi, 0.0) if a > 0.0 else (root_lo if root_lo > 0.0 else 0.0)

## Does buffer `buffer` isolate a FOCUSED grid's neighbours? Reads `grid_position_size_px()` at the
## candidate buffer for the picture's own width/height, so this can never disagree with the thing
## it is certifying -- the only math left here is the isolation check itself, which exists nowhere
## else to duplicate. The zoom is `focused_board_zoom()`'s own fixed-point shape, not a flat
## subtraction -- see `isolating_grid_buffer_px()`.
static func _isolates_at_buffer(settings_res: PlayerSettings, buffer: float) -> bool:
	var block := grid_block_size_px(settings_res, GridData.new())
	var picture := grid_position_size_px(settings_res, buffer)
	var z := picture.y / maxf(focused_content_height_px(settings_res), 0.0001)
	if z <= 0.0: return false
	var visible_half := picture.x / (2.0 * board_view_divisor(settings_res))
	var neighbour_near_edge := z * (buffer + block.x * 0.5)
	# The closed-form root sits exactly ON this boundary -- an exact equality two different
	# arithmetic paths (this and the solver's quadratic formula) can round to either side of.
	return neighbour_near_edge >= visible_half or is_equal_approx(neighbour_near_edge, visible_half)

## THE WHOLE PICTURE'S span: `grid_max_count` grids of the DEFAULT shape side by side, spaced by
## `isolating_grid_buffer_px()` (a RAW pixel quantity, like the card and cell sizes it sits
## between), with that SAME buffer again as margin on each side against the picture's own edge
## (owner ruling: the edge gap and the inter-grid gap read as the same thing, so they ARE the same
## quantity), at the height the window aspect needs. The OVERVIEW camera rests on this whole span --
## every grid the picture holds fits inside it at once, which is what lets zooming out show them
## all. FOCUSED reuses the same span too: isolation comes from the buffer, not from a second camera
## box.
## `buffer_override` lets a candidate buffer be tried without re-entering the derivation that
## produces the real one -- pass a value `>= 0.0` to use it as-is; the default (`-1.0`) resolves
## through `isolating_grid_buffer_px()` as every non-solving caller wants.
static func grid_position_size_px(settings_res: PlayerSettings, buffer_override: float = -1.0) -> Vector2:
	var block := grid_block_size_px(settings_res, GridData.new())
	var count := float(maxi(settings_res.grid_max_count, 1))
	var buffer := buffer_override if buffer_override >= 0.0 else isolating_grid_buffer_px(settings_res)
	var span := count * block.x + (count - 1.0) * buffer
	var width := span + 2.0 * buffer
	# The reference aspect is the project's own window shape, read from it rather than restated.
	var ref_w : float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var ref_h : float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	var aspect_minimum := width * ref_h / ref_w if ref_w > 0.0 and ref_h > 0.0 else 0.0
	return Vector2(width, maxf(block.y, aspect_minimum))

## The size the game picture is laid out at: `grid_max_count` grids side by side, exactly the span
## `grid_position_size_px()` already computes -- three cell blocks, two isolating buffers between
## them, that same buffer again on each edge, height the larger of the board's own height or the
## window-aspect minimum. The whole picture is therefore window-shaped and fits in frame at once.
##
## ⚠ **DERIVED FROM THE CAP AND THE DEFAULT GRID SHAPE, NEVER FROM THE GRIDS A RUN HAS.** The
## picture is one fixed size for every run: a deck that unlocks a second grid mid-show must not
## resize a render target, and a 1-grid run sits in a picture built for three.
static func game_picture_design_size(settings_res: PlayerSettings) -> Vector2i:
	var span := grid_position_size_px(settings_res)
	return Vector2i(roundi(span.x), roundi(span.y))

## The EXTRA height this row currently carries over a stacked strip. Zero for every row on a board
## with no reveal up, which is what keeps the unexpanded layout bit-for-bit what it was.
func row_open_extra(coord: BoardCoord) -> float:
	var t : float = _row_open.get(_reveal_key(coord), 0.0)
	if t <= 0.0: return 0.0
	# ⚠ **A ROW THAT COVERS NOTHING DOES NOT OPEN, AND LEAVING THIS OUT WAS A REAL BUG.** The opening
	# exists to lift a covering card off a buried one. On a board one card deep there is nothing
	# underneath, so growing the strip adds PURE EMPTY SPACE and the only visible result is the whole
	# zone below being shoved down — exactly the *"shifting in cards that arent part of actual scored
	# set"* the derived opening was retired for. It reads as *"lower zone input zone cards wiggle down
	# and up twice"* while nothing has actually been revealed.
	# ⚠ Decided per DEPTH LAYER, never per column or cell: every column's VBox (and every CellSlot)
	# must give that layer the same height or the rows stop lining up across the board.
	if not _row_covers_anything(coord): return 0.0
	# ⚠ **THE VBOX ALREADY PUTS `separation` BETWEEN ROWS — SUBTRACT IT OR THE OPENING OVERSHOOTS.**
	# `row_open_height` is the TOTAL distance the mode asks for (a full card, or a card minus the
	# jump), but the row-to-row pitch is `strip + separation`: the containers get
	# `add_theme_constant_override("separation", separation)` and `slot_center_global` adds the same
	# term. Sizing the STRIP to the full height therefore produced height + separation — an extra
	# `4 * card_scale` (10 px at the shipped scale), which the owner saw as *"an odd gap between the
	# rows, looks like an extra few pixels of separation"*. `row_open_span` supplies the remainder.
	return row_open_span(PlayArea.settings(), float(separation)) * t

## Does any stack in `coord`'s half of the board hold a card BELOW depth `coord.h` — i.e. is there
## anything for this layer to uncover? The deepest layer covers nothing and must stay put. The
## Entrance asks it of its fanned columns, a grid of its cells; the question is the same one.
## ⚠ Read from STATE, not the control tree: rebuilds are DEFERRED, so mid-mutation the child counts
## describe the previous board — and `slot_center_global` (pure math, prop-anchored every frame)
## routes through here, so a tree read made its geometry depend on rebuild timing after all.
func _row_covers_anything(coord: BoardCoord) -> bool:
	var game := CardEnvironment.get_current_game()
	if not game: return false
	for stack : ArrayCardData in _reveal_stacks(coord):
		if stack.datas.size() > coord.h + 1: return true
	return false

## The stacks a reveal layer spans: the Entrance's columns, or one grid's cells. Empty for a grid
## index no grid answers to.
func _reveal_stacks(coord: BoardCoord) -> Array[ArrayCardData]:
	var empty : Array[ArrayCardData] = []
	var game := CardEnvironment.get_current_game()
	if not game: return empty
	if coord.is_entrance(): return game.state.upper_zone
	var grids := game.state.grids
	if coord.grid < 0 or coord.grid >= grids.size(): return empty
	var grid : GridData = grids[coord.grid]
	return grid.cells if grid else empty

## Everything the layers ABOVE `coord.h` in the same half of the board have pushed down. ⚠ Above
## only: a layer's own opening grows the gap BELOW it, so it does not move its own card.
## How much taller the reveal is currently making an Entrance column -- exactly what the hbox has
## grown BY, so a floor taken from its bottom edge can be corrected back to its resting line.
func _entrance_open_total() -> float:
	var sum := 0.0
	for key : Vector2i in _row_open:
		if key.x != REVEAL_ENTRANCE_GRID: continue
		sum += row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, key.y))
	return sum

func _row_open_offset(coord: BoardCoord) -> float:
	var sum := 0.0
	var axis := _reveal_key(coord).x
	for key : Vector2i in _row_open:
		if key.x == axis and key.y < coord.h:
			sum += row_open_extra(BoardCoord.new(coord.grid, coord.x, coord.y, key.y))
	return sum

var ui_data : Dictionary[Control, CardData]
var data_ui : Dictionary[CardData, Control]
var data_card : Dictionary[CardData, CardVisual]
var new_data_card : Dictionary[CardData, CardVisual]

## ⚠ **`%UpperZone` (an `HSplitContainer`) IS DELIBERATELY NOT IN THIS LIST.** Its "separation"
## theme constant is the GUTTER RESERVED BETWEEN ITS TWO PANES, not a card-row spacing — matching
## it to the shared card `separation` pushed `UpperZoneRight` (and every Entrance column) that
## many pixels off its own left edge, out from under the grid's columns it must x-slave to
## (measured: 4 px, TP-80k). `UpperZoneLeft` is hidden (`setup_gui`), so the gutter has nothing to
## separate from and is zeroed there instead.
@onready var containers : Array[Control] = [%TopLevelVBox, %UpperZoneLeft, %UpperZoneRight]
@onready var top_level_vbox: VBoxContainer = %TopLevelVBox
@onready var upper_zone_left: VBoxContainer = %UpperZoneLeft
@onready var upper_zone_right: HBoxContainer = %UpperZoneRight
@onready var prop_layer: PropLayer = %PropLayer   ## Phase 4 prop-animation surface
## CardVisual host INSIDE the scroll content (a Node2D the containers ignore, like PropLayer):
## the scroll transform carries cards, controls, and props together. Parented to the PlayArea
## root, cards chased their anchors' scrolled globals through the _process ease and visibly
## lagged every scroll (owner report).
## S20b -- the grid board's root. One child per entry in `GameData.grids`, left to right.
## ⚠ Typed `HBoxContainer` and NAMED `GridContainer`: the name is the registry's, the type is
## what puts the panels side by side. The 5x5 of cells INSIDE each panel is the real
## `GridContainer`, built per panel in `_create_grid_panel`.
## ⚠ **IT CLIPS.** A grid outside the board's window is OUT OF VIEW, not merely out of
## position: unclipped, a non-focused grid painted across the Deck button and the score column
## while its geometry was already correct. The Entrance is a SIBLING of this container, so a
## card being placed crosses the clip edge -- measured, it spends one frame outside the picture
## entirely and every later frame inside the window, so the clip takes nothing off the flight.
@onready var scroll_container: ScrollContainer = $SmoothScrollContainer
@onready var grid_container: HBoxContainer = %GridContainer
@onready var card_layer: Node2D = %CardLayer
## Always-on-top surface (last sibling of TopLevelVBox): the focus inspector panel and score
## popups live here so they render above every card and prop by TREE ORDER — no z_index needed.
@onready var overlay_layer: Node2D = %OverlayLayer

## **THE PINNED ENTRANCE.** A sibling of `SmoothScrollContainer`, outside the board's scroll, so
## it never scrolls away vertically -- the board's own scrollbar is the ONLY one on screen, since
## `EntranceVScroll`'s own bar is hidden (nothing left for it to reveal -- see below) and
## `EntranceStrip` no longer clips: `EntranceStrip` is the fixed visible window; `EntranceHTrack` is
## the wide (board-content-width) track slid in X to mirror the board's own horizontal scroll
## (`_sync_entrance_x`); `EntranceVScroll` does not resize or clip -- a stack deeper than the
## configured strip simply draws past the window rather than being cropped or needing a second bar
## to reach it (resizing the strip itself was tried and rejected: it re-lays out everything anchored
## inside it, drifting a prop off its own slot mid-cycle); `EntranceCardLayer` is its OWN card
## layer — a card layer INSIDE the board's scroll cannot pin, because its cards would scroll away
## from their own pinned controls.
@onready var entrance_strip: Control = %EntranceStrip
@onready var entrance_h_track: Control = %EntranceHTrack
@onready var entrance_v_scroll: ScrollContainer = %EntranceVScroll
@onready var entrance_card_layer: Node2D = %EntranceCardLayer

func _ready() -> void:
	SettingsManager.settings_changed.connect(update_gui)
	# ⚠ **NEITHER SCROLLBAR MAY ADVERTISE WHICH MECHANISM IS MOVING THE VIEW** (owner): a camera step
	# in the overview and a scroll in focused mode must read as the same motion, and *"no scrollbar
	# should be visible"* when a focused grid opens.
	# ⚠ **SIZING THE BOARD TO CLEAR THE BAR IS NOT ENOUGH.** Measured: the vertical bar shows at
	# EXACT equality of content and page — hidden at a 1152x648 window, shown at 1147x649 with the
	# identical 313 == 313 — so any fit lands on a coin toss between two widths five pixels apart.
	# ⚠ `SCROLL_MODE_SHOW_NEVER` hides a bar and KEEPS ITS BAND; `_scroller_frame_h()` is what pays
	# for the horizontal one, so the board still clears the space the container reserves.
	# Scrolling itself is untouched — the zoom, the pan actions, the touch drag and a deep stack all
	# still move the board.
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	# Pay every FX shader's first-use compile here, on invisible one-pixel quads, rather than on
	# the first card that catches fire mid-act.
	FxAttachment.warm(overlay_layer)
	setup_gui()
	# THE SHOW OPENS ON ITS OPENING VIEW. A show is one PlayArea, so this is that view -- and with
	# no grids built yet it is the all-grids view, which the first rebuild that has one revisits.
	open_show_view()
	_show_view_opened = grid_container.get_child_count() > 0
	set_process(false)  # _process only pins the focus inspector — enabled while it is visible
	# X-SLAVING RUNS EVERY PHYSICS FRAME, UNCONDITIONALLY (never toggled off like `_process`
	# above): a board scroll can happen at any time regardless of whether the focus inspector or
	# a reveal is live, and a ScrollContainer's `scroll_horizontal` can be written directly
	# (tests, and any future scroll-to code) without reliably firing its scrollbar's
	# `value_changed` — the same "recompute live, never trust a signal alone" rule every other
	# per-frame board anchor in this file already follows (`slot_center_global`'s callers).
	set_physics_process(true)

func setup_gui() -> void:
	set_separation()
	set_card_zones()
	# THE ENTRANCE LINES UP WITH THE GRID'S COLUMNS, which is what makes it read as the row below
	# the board rather than a separate strip that happens to be nearby. Two things were pushing it
	# out of line: its row-score gutter, which is a leftover of the retired upper zone (row scores
	# belong to a grid's own panel now, so the Entrance has none), and its row being left-aligned
	# while the grid centres itself in the same width.
	upper_zone_left.visible = false
	upper_zone_right.alignment = BoxContainer.ALIGNMENT_CENTER
	# ⚠ **A BOARD NARROWER THAN THE WINDOW SITS CENTRED, NOT PARKED AT THE LEFT EDGE.** A
	# ScrollContainer hands its content exactly the content's own minimum width unless the content
	# asks to expand — the scroll range then collapses to nothing with the board still hard left
	# (measured: one grid centred at 555 in a window centred at 782). Asking to expand gives the
	# spare width to the content, where `GridContainer`'s centre alignment spends it, so the clamp
	# collapsing to centre on an axis that already fits is the LAYOUT's answer and not arithmetic
	# written here. Content wider than the window keeps its own minimum, so an overflowing board is
	# untouched.
	top_level_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The split gutter has nothing to separate now the left pane is hidden -- zero it so
	# `UpperZoneRight` starts flush with `UpperZone`'s own left edge (see the `containers` note).
	(%UpperZone as Control).add_theme_constant_override("separation", 0)
	# The board grows UPWARD out of the Entrance, so the Entrance is the part the player acts on
	# and it is the bottom of the picture. Anchor the scroll there ON ENTRY -- deferred, because
	# the containers have not been sized yet at this point and the maximum is still 0.
	# ⚠ **THE SCROLLER MUST NOT CHASE KEYBOARD FOCUS.** A card control grabs focus on
	# `mouse_entered`, and a `ScrollContainer` with `follow_focus` scrolls whatever just took focus
	# into view -- so simply moving the mouse across the board scrolled it. Measured: the gap
	# between the cell block and the Entrance wandered between 44.2 and 25.3 px with nothing
	# placed or removed, because `scroll_vertical` was being written by the hover. The board's own
	# `pan_to_grid`/`_recentre_board` are the only things allowed to aim it.
	if is_instance_valid(scroll_container): scroll_container.follow_focus = false
	# ⚠ **THE BOARD DOES NOT CLIP, AND THAT IS A RULING, NOT AN OVERSIGHT.** `%CardLayer` lives
	# inside this scroller, so a clip here CULLS card visuals outright -- and props and animations
	# are authored to leave the board's edges on purpose, so it was cutting effects that are
	# supposed to overflow. Owner: *"clipping content cant work because i see it clipping stuff
	# like props and animations which specifically go outside edges of board visually."*
	# Hiding a neighbouring grid is the CAMERA's job and only the camera's.
	if is_instance_valid(scroll_container): scroll_container.clip_contents = false
	_last_scroll_max = -1.0
	_scroll_growth_carry = 0.0
	_anchor_scroll_to_bottom.call_deferred()
	update_score_controls()
	_apply_entrance_strip_height()
	# The floor is measured against THIS control's height, so re-measure it whenever the window
	# changes — otherwise the board keeps growing off a stale floor.
	if not resized.is_connected(_apply_entrance_strip_height):
		resized.connect(_apply_entrance_strip_height)
	_sync_entrance_x()

func _physics_process(_delta: float) -> void:
	_apply_grid_buffer()
	_follow_board_growth()
	_sync_row_label_heights()
	_sync_score_label_font()
	_sync_entrance_x()
	# ⚠ ONE control's rect, on the tick `_sync_entrance_x` already reads on. `resized` alone left
	# this 8 px stale (562 against a real 554) because the content's POSITION can settle without
	# its size changing, and a stale floor moves every row on the board at once.
	# ⚠ This is safe where the per-PANEL version was not: that one read the rects the floor code
	# WRITES to, every frame, and the board never settled. `TopLevelVBox` is written only from
	# `_give_the_board_a_floor`, which runs on a window resize — not on this tick.
	_publish_board_floor()
	_sync_cell_score_labels()

## **E17 / `Q309`=a — a stack's height score sits ABOVE its topmost card, and rises as the stack
## grows.** One label per cell that has ever scored; `scores_cell` is already keyed per cell.
##
## ⚠ **POSITIONED BY ARITHMETIC IN ITS OWN LAYER, NOT PARENTED INTO THE CELL.** A label inside the
## `CellSlot` would add its own height to the cell, and `_measure_grid_row_height` — the arithmetic
## every card and prop on the board is placed by — would have to know about it. Riding
## `slot_center_global` instead means the label follows the stack through a growth ease, a spring
## and a reveal for free, and the row geometry never learns it exists.
##
## ⚠ **`at` IS A MEASURED GLOBAL, ALREADY SCALED BY `board_zoom`; THE CARD AND LABEL SIZES ARE
## NOT.** Both live in `card_layer`, scaled with the board through `scroll_container`, so their
## local magnitudes must be taken into screen pixels by `board_zoom` before being subtracted from
## `at` — the same convention `_grid_slot_center_global` and `_apply_grid_buffer` already follow.
func _sync_cell_score_labels() -> void:
	if not is_inside_tree() or not is_instance_valid(card_layer): return
	var game := CardEnvironment.get_current_game()
	if not game:
		for key : Vector3i in _cell_score_labels:
			if is_instance_valid(_cell_score_labels[key]): _cell_score_labels[key].queue_free()
		_cell_score_labels.clear()
		return
	var state := game.state
	var live : Dictionary[Vector3i, bool] = {}
	for key : Vector3i in state.scores_cell:
		if key.x < 0 or key.x >= state.grids.size(): continue
		var grid : GridData = state.grids[key.x]
		if not grid: continue
		var idx := grid.cell_index(key.y, key.z)
		if idx < 0 or idx >= grid.cells.size(): continue
		var depth : int = grid.cells[idx].datas.size()
		if depth <= 0: continue   # nothing to sit above yet
		live[key] = true
		var label : BigNumberLabel = _cell_score_labels.get(key)
		if not label or not is_instance_valid(label):
			label = BigNumberLabel.new()
			label.name = "CellScore_%d_%d_%d" % [key.x, key.y, key.z]
			# A height score stands over its own column of cards, so it is centred like the
			# column gutter is.
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_layer.add_child(label)
			_cell_score_labels[key] = label
		label.current_num = state.scores_cell[key]
		# ABOVE the topmost card: its centre, less half a card, less the label's own height.
		var top := BoardCoord.new(key.x, key.y, key.z, depth - 1)
		var at := slot_center_global(top)
		label.global_position = Vector2(at.x - label.size.x * board_zoom * 0.5,
				at.y - CardVisual.card_size_play.y * board_zoom * 0.5 - label.size.y * board_zoom)
	for key : Vector3i in _cell_score_labels.keys():
		if live.has(key): continue
		var doomed : BigNumberLabel = _cell_score_labels[key]
		if is_instance_valid(doomed): doomed.queue_free()
		_cell_score_labels.erase(key)

## One height-score label per cell that has scored, keyed the same way `scores_cell` is.
var _cell_score_labels : Dictionary[Vector3i, BigNumberLabel] = {}

## X SLAVED TO THE COLUMNS OF THE GRID THE VIEW IS ON (owner spec): the Entrance never scrolls on
## its own in X, it sits under the grid the player is looking at, so its slots stay under that
## grid's columns.
##
## ⚠ **THERE IS EXACTLY ONE ENTRANCE, AND IT FOLLOWS THE VIEW** -- the owner's rule is that it
## behaves like a player's hand. The grids stand one per grid position, a whole position apart, so
## an Entrance parked on the first grid would sit a position away from the grid being played.
##
## ⚠ **THE TRACK TAKES THE GRID'S OWN CELL BLOCK, NOT A WIDTH SHARED WITH THE WHOLE BOARD.**
## Both halves are read off the cells' live rect rather than reconstructed from the scroll offset:
## the scrolled content carries a constant margin of its own (measured: 4 px) that arithmetic from
## the raw scroll delta cannot see, and the cells -- not the panel -- are where the columns start,
## since a row-label gutter sits between the two (measured: 20 px, the gutter's width).
func _sync_entrance_x() -> void:
	if not is_instance_valid(entrance_h_track) or not is_instance_valid(scroll_container): return
	# ⚠ **THE BOARD'S CONTENT STAYS AT LEAST AS WIDE AS THE ENTRANCE, OR AN ENTRANCE WIDER THAN
	# THE WINDOW CANNOT BE REACHED.** The Entrance rides the board's horizontal scroll, so the scroll
	# needs the reach even on a board with no grid of its own to supply it. The Entrance's own
	# minimum is read, never the container's own width, which would fold in last call's answer and
	# could then only ever grow.
	grid_container.custom_minimum_size.x = upper_zone_right.get_combined_minimum_size().x
	var columns_x := grid_container.global_position.x
	var columns_w := grid_container.size.x
	var cells := _view_grid_cells()
	if cells:
		columns_x = cells.global_position.x
		columns_w = cells.size.x * maxf(board_zoom, 0.0001)
	entrance_h_track.position.x = columns_x - entrance_strip.global_position.x
	entrance_h_track.size.x = columns_w
	_apply_entrance_zoom_rect()

## **THE SCALE MUST LIVE ON THE SCROLL CONTAINER, NOT ITS CONTENT** (same rule
## `_apply_board_zoom_rect` follows) — `%EntranceVScroll` carries `board_zoom` so the Entrance's
## cards scale with the grid's, and its rect is divided by the zoom first so the
## visible, on-screen window stays exactly `entrance_h_track`'s own rect.
##
## ⚠ Height is RECOMPUTED, never read off `entrance_h_track.size.y`: a strip resize (`offset_top`)
## has not necessarily reached this Control's own rect yet (a layout pass lags an offset write,
## same trap `_board_window_local` avoids), and this runs both right after that write and every
## physics frame. Width is safe to read live -- `_sync_entrance_x` writes it explicitly, above.
func _apply_entrance_zoom_rect() -> void:
	if not is_instance_valid(entrance_v_scroll) or not is_instance_valid(entrance_h_track): return
	var z := maxf(board_zoom, 0.0001)
	var window := Vector2(entrance_h_track.size.x,
			entrance_strip_height_px(PlayArea.settings(), z))
	var local := window / z
	entrance_v_scroll.scale = Vector2.ONE * z
	entrance_v_scroll.offset_right = local.x - window.x
	entrance_v_scroll.offset_bottom = local.y - window.y

## The Entrance's REAL depth, past the configured visible strip -- what the board's floor must
## clear so a deep Entrance never covers a grid card. Distinct from the visible strip on purpose:
## the strip itself must stay fixed (see `_apply_entrance_strip_height`), or resizing it re-lays
## out everything anchored inside it and a prop or slot drifts off its own anchor mid-cycle
## (measured: 4 px).
func _entrance_strip_full_height() -> float:
	return maxf(entrance_strip_height_px(PlayArea.settings(), board_zoom), _entrance_row_height())

## The picture x the board's current pan puts under the LEFT edge of the grid the view is
## centred on -- the same value the Entrance aligns to (`_sync_entrance_x`'s `columns_x`).
## Exposed so anything OUTSIDE the scroll (the rest of the HUD) can ride the identical pan
## rather than a second, independent measure of where the view currently rests. The board's
## scroll window spans the whole picture, so this is a LIVE layout position -- the grid
## positions sit side by side in the wide picture rather than one scrolling past a narrow window.
func pan_window_left_x() -> float:
	var cells := _view_grid_cells()
	return cells.global_position.x if cells else grid_container.global_position.x

## The cell block of the grid the view is centred on, or null when the board has no grids.
func _view_grid_cells() -> Control:
	if not is_instance_valid(grid_container): return null
	var last := grid_container.get_child_count() - 1
	if last < 0: return null
	return _cells_root(grid_container.get_child(clampi(pan_grid, 0, last)) as Control)

## The strip's FIXED visible height, and the matching reservation carved out of the board's own
## scroll so the two never overlap on screen. A multiple of one card's height
## (`entrance_visible_rows`) — re-applied on every settings change since `card_scale` resizes the
## card the multiple is measured against. Stays fixed even when the Entrance stacks deeper: the
## strip is a player setting, and resizing it re-lays out everything anchored inside it (see
## `_entrance_strip_full_height`). The board's floor is what clears the real depth instead.
func _apply_entrance_strip_height() -> void:
	if not is_instance_valid(entrance_strip) or not is_instance_valid(scroll_container): return
	var h := entrance_strip_height_px(PlayArea.settings(), board_zoom)
	var pad := board_edge_pad_px(PlayArea.settings()) * board_zoom
	entrance_strip.offset_top = -h - pad
	entrance_strip.offset_bottom = -pad
	entrance_strip.offset_left = hud_reserve_px()
	_apply_board_zoom_rect(h)
	_apply_entrance_zoom_rect()
	_give_the_board_a_floor(_entrance_strip_full_height())

## Put the board's window back where it was after the zoom made it bigger.
##
## ⚠ **THE ZOOM SCALES THE SCROLL CONTAINER, AND ITS RECT IS DIVIDED BY THE ZOOM TO COMPENSATE.**
## The scale cannot go on the CONTENT: a `Container` rewrites its children's scale on every sort
## (measured -- the scale was back at 1 the next frame), so the scroller's own child is the one node
## on the board that cannot carry it. The scroller itself is a child of this plain `Control`, which
## rewrites nothing. Dividing the rect by the same factor leaves the window exactly the pixels it
## occupied unzoomed, so the side panels keep their room and only the BOARD grows.
func _apply_board_zoom_rect(strip_h: float) -> void:
	if not is_instance_valid(scroll_container): return
	_board_strip_h = strip_h
	var local := _board_window_local()
	var pad := board_edge_pad_px(PlayArea.settings()) * board_zoom
	scroll_container.scale = Vector2.ONE * board_zoom
	scroll_container.offset_top = pad
	var inset := hud_reserve_px()
	scroll_container.offset_left = inset
	scroll_container.offset_right = inset + local.x - size.x
	scroll_container.offset_bottom = pad + local.y - size.y

## The strip the board's window is currently giving up to the Entrance, kept so the window can be
## recomputed without waiting for a layout pass.
var _board_strip_h := 0.0

## The board's window in the SCROLLER'S OWN units: what it occupies on screen, divided by the zoom.
##
## ⚠ **COMPUTED, NEVER READ BACK OFF `scroll_container.size`.** A container's size only catches up
## with the offsets on the next sort, so anything that measures it on the tick the zoom changed is
## reading the PREVIOUS mode's window -- which is a whole grid's worth of aim, and a board floor
## left where the unzoomed board had it.
func _board_window_local() -> Vector2:
	var pad := board_edge_pad_px(PlayArea.settings()) * board_zoom
	return Vector2(maxf(size.x - hud_reserve_px(), 0.0),
			maxf(size.y - _board_strip_h - 2.0 * pad, 0.0)) / maxf(board_zoom, 0.0001)

## `board_inset_left`, capped so the board is never starved of the room for a grid.
##
## ⚠ **THE HUD IS AUTHORED AGAINST A 1152-WIDE CANVAS AND DOES NOT SHRINK WITH THE SCREEN.** On a
## 412 px phone its 402 px rectangle leaves the board TEN PIXELS -- measured, with the whole grid
## off screen. The board yielding the room the HUD asks for is the owner's ruling; yielding room it
## does not have is a different thing, and a grid that does not fit is not a layout.
## ⚠ Derived from the panel the board must show, never a fraction or an authored floor: the rule is
## "a grid still fits", and that is exactly what it says.
## ⚠ The real fix is `GAP-038` -- the HUD either scales with the screen or moves off the board. This
## keeps the board legible until that is answered; it does not stop the HUD overlapping it.
func hud_reserve_px() -> float:
	var panel := _panel_width(resting_grid())
	if panel <= 0.0: return board_inset_left
	return minf(board_inset_left, maxf(size.x - panel, 0.0))

## ⚠ **THE ENTRANCE IS ROW −1, AND ITS OWN HEIGHT PUSHES THE BOARD UP** (`Q313`=a, owner: *"if
## entrance/input cards are somehow stacked with multiple cards as well increasing in height, then
## it raises everything above it up as well so as to not cover any card in the grid"*). Same
## arithmetic a grid row uses — a whole card plus a fanned strip for every card under the top one —
## so the Entrance participates in the board's geometry rather than being a fixed reservation the
## board happens to sit above. The configured `entrance_visible_rows` stays the FLOOR of that: a
## shallow Entrance still shows the strip the player expects.
func _entrance_row_height() -> float:
	var full := CardVisual.card_size_play.y * board_zoom
	var game := CardEnvironment.get_current_game()
	if not game: return full
	var deepest := 0
	for col : ArrayCardData in game.state.upper_zone:
		deepest = maxi(deepest, col.datas.size())
	if deepest == 0: return full
	var depth_pitch := (float(CardVisual.card_separation_play_custom) + float(separation)) * board_zoom
	return float(separation) * board_zoom + full + float(deepest - 1) * depth_pitch

## ⚠ **THE BOARD NEEDS A FLOOR TO GROW UP OFF, AND A SCROLL CONTAINER DOES NOT GIVE IT ONE.**
## `TopLevelVBox` hugs its own content, so without this the grid block starts at the top of the
## scrolled content and every deepened stack pushes the rows BELOW it down — the opposite of the
## board growing upward out of the Entrance.
## ⚠ **`alignment`, NOT `size_flags_vertical`.** A vertical size flag aligns a child inside its OWN
## allotted slot, and a `VBoxContainer` allots each child exactly its minimum height — so
## `SIZE_SHRINK_END` on the grid block moved it by nothing at all (measured: the rows below a
## deepened one still slid down the full 40 px it gained). `ALIGNMENT_END` packs the container's
## children against its end, which is what actually pins the floor.
func _give_the_board_a_floor(strip_h: float) -> void:
	if not is_instance_valid(top_level_vbox) or not is_instance_valid(grid_container): return
	# ⚠ Divided by the zoom, and by NOTHING ELSE: `size.y - strip_h` is the floor in SCREEN pixels
	# while the content is laid out in the scroller's own, smaller ones. ⚠ It must not be taken from
	# the scroller's window either -- that window is carved out by the Entrance's RESERVATION while
	# this floor clears its ACTUAL height, and the two differ exactly when the Entrance stacks.
	var pad := board_edge_pad_px(PlayArea.settings()) * board_zoom
	top_level_vbox.custom_minimum_size.y = maxf(
			maxf(size.y - strip_h - 2.0 * pad, 0.0) / maxf(board_zoom, 0.0001)
			- _scroller_frame_h(), 0.0)
	top_level_vbox.alignment = BoxContainer.ALIGNMENT_END
	_publish_board_floor()
	if not top_level_vbox.resized.is_connected(_publish_board_floor):
		top_level_vbox.resized.connect(_publish_board_floor)

## ⚠ **THE FLOOR COMES FROM THE SCROLL CONTENT, NOT FROM A PANEL'S RECT.** Every grid panel is
## bottom-aligned against this same line, so it is the one number the row geometry needs — and
## unlike a panel it does NOT move when a stack deepens, which is exactly why caching it is safe.
## Caching the PANEL's rect was not: its origin lagged a whole depth pitch behind (measured: 264
## against a real 244), and a board's rows then appeared to slide by that much whenever a card
## landed. `resized` is enough here because this control only changes with the WINDOW.
func _publish_board_floor() -> void:
	if not is_instance_valid(top_level_vbox): return
	_board_floor_y = top_level_vbox.global_position.y + top_level_vbox.size.y * board_zoom
	_publish_cell_rects()

## ⚠ **THE ARITHMETIC FOLLOWS THE CELLS, NOT THE PANEL.** Once the panel carries score gutters the
## two are no longer the same rect: the row-label column pushes the cells right and the column-label
## row lifts their bottom. Reading the panel instead put every card a gutter's width off its cell
## (measured: 20 px sideways, 27 px vertically) — and the Entrance, which x-slaves to the columns,
## went with it.
## Refreshed on this same tick, and safe for the same reason: nothing writes these rects per frame.
func _publish_cell_rects() -> void:
	if not is_instance_valid(grid_container): return
	for i : int in grid_container.get_child_count():
		var panel := grid_container.get_child(i) as Control
		if not panel or panel.is_queued_for_deletion(): continue
		var cells := _cells_root(panel)
		if not cells: continue
		_grid_cells_origin[i] = cells.global_position
		# ⚠ A GLOBAL origin plus a LOCAL size is not a global edge once the board is zoomed --
		# `global_position` carries the zoom and `size` never does.
		_grid_cells_bottom[i] = cells.global_position.y + cells.size.y * board_zoom

## The scroll range the board last had. -1 until a tick has seen one, so a rebuild re-baselines
## rather than treating the whole range as fresh growth.
var _last_scroll_max := -1.0
## The sub-pixel part of the growth not yet handed to `scroll_vertical`, which is an INT. Carried
## rather than rounded away: rounding each step independently drifts by up to half a unit per card,
## measured at 5.1 px of accumulated slip over six placements.
var _scroll_growth_carry := 0.0

## Keep the board's BOTTOM line where it is as the board gets taller.
##
## ⚠ **THE BOARD GROWS UPWARD, AND THAT MEANS ITS BOTTOM DOES NOT MOVE.** A deepening stack makes
## the scroll content taller; with the offset left alone every new pixel appears BELOW the window,
## so the board reads as sinking out of its own frame and under the Entrance. Measured on a single
## column: at depth 3 the cell block already hung 14.7 px past the window's bottom edge, and at
## depth 6, 112.8 px. Adding the growth to the offset puts the new height at the TOP, where the
## stack actually grew.
##
## ⚠ **THIS IS NOT `_anchor_scroll_to_bottom()`.** That one SNAPS to the bottom and runs on entry
## only, because a rebuild that snapped would yank the view away from a player who had scrolled
## somewhere else. Following the growth keeps whatever offset the player chose, measured from the
## bottom instead of from the top.
func _follow_board_growth() -> void:
	if not is_instance_valid(scroll_container): return
	var bar := scroll_container.get_v_scroll_bar()
	if not bar: return
	var now := bar.max_value
	if _last_scroll_max < 0.0:
		_last_scroll_max = now
		return
	var grown := now - _last_scroll_max
	_last_scroll_max = now
	if grown <= 0.0: return
	_scroll_growth_carry += grown
	var whole := int(floorf(_scroll_growth_carry))
	if whole <= 0: return
	_scroll_growth_carry -= float(whole)
	scroll_container.scroll_vertical += whole

## Wait for `card`'s visual to reach the cell it was just placed in.
##
## ⚠ **TWO FRAMES BEFORE THE FIRST POLL, AND THEY ARE NOT OPTIONAL.** The rebuild that starts the
## card's flight is deferred, so on the frame the placement commits there is no `move_tween` yet --
## polling immediately reads "not moving" and returns before the card has begun to travel.
## ⚠ Bounded by the act clock: a visual that never settles must not stall the show.
func await_card_settled(card: CardData) -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	await get_tree().process_frame
	var visual : CardVisual = data_card.get(card)
	if not visual or not is_instance_valid(visual): return
	var game := CardEnvironment.get_current_game()
	var limit : float = game.get_delay() if game else PlayArea.settings().base_delay
	var waited := 0.0
	while waited < maxf(limit, 0.05):
		if not is_instance_valid(visual): return
		if not (visual.move_tween and visual.move_tween.is_running()): return
		await get_tree().process_frame
		waited += get_process_delta_time()

## Scroll to the bottom of the board. ⚠ ON ENTRY ONLY -- a rebuild that re-anchored would yank
## the view out from under a player who had scrolled somewhere else.
## ⚠ WAITS FOR THE SCROLL RANGE TO STOP CHANGING before aiming -- panel positions, the shared
## width and the scroll range all settle separately over several frames, so reading `max_value`
## after a single frame clamps the aim against a range that is still growing. Re-read `max_value`
## every frame rather than latching a copy, which would freeze at the same stale value. The wait
## is capped at the pan clock so a board that never settles still gets an aim.
func _anchor_scroll_to_bottom() -> void:
	if not is_instance_valid(scroll_container): return
	var bar := scroll_container.get_v_scroll_bar()
	if not bar: return
	var last := INF
	var waited := 0.0
	while waited < PlayArea.settings().grid_pan_duration:
		await get_tree().process_frame
		if not is_instance_valid(scroll_container) or not is_instance_valid(bar): return
		waited += get_process_delta_time()
		if is_equal_approx(bar.max_value, last): break
		last = bar.max_value
	scroll_container.scroll_vertical = int(bar.max_value)

func update_gui() -> void:
	set_separation()
	set_card_zones_visuals()
	update_score_controls()
	_apply_entrance_strip_height()
	_sync_entrance_x()

# ==============================================================================
# THE TWO VIEW MODES
#
# The show opens on the all-grids view; a click on a grid focuses that grid. The overview is
# orientation, so a click there costs the player nothing: it moves the view and never the board.
# ==============================================================================

## The show's OPENING view: the all-grids view, or the single grid FOCUSED when that is all there
## is. The overview is orientation BETWEEN grids, so with exactly one it frames what focused mode
## already frames and the click that leaves it buys the player nothing (owner ruling). One grid is
## the DEFAULT and not an edge case -- a deck of 52 or fewer unlocks exactly one.
func open_show_view() -> void:
	if grid_container.get_child_count() == 1:
		focus_grid(0)
		return
	open_zoomed_out()

## True once the opening view has been settled against the grids that actually EXIST.
## ⚠ **THERE ARE NO GRIDS AT `_ready()`.** The rules deck builds them during the deal, so the
## opening view cannot be chosen until the first rebuild that has one -- and it must be chosen
## exactly ONCE, or a player who zoomed out is yanked back on the next placement.
var _show_view_opened := false

func _open_show_view_once() -> void:
	if _show_view_opened or grid_container.get_child_count() == 0: return
	_show_view_opened = true
	open_show_view()

## Open the all-grids view with nothing focused.
func open_zoomed_out() -> void:
	_set_view(ViewMode.OVERVIEW, NO_GRID)
	_zoom_board_to(OVERVIEW_BOARD_ZOOM)
	rest_board()

## The grid the board RESTS centred on, per view mode. `NO_GRID` while there is no grid to rest on.
##
## ⚠ **A RESTING BOARD IS A POSITIONED BOARD.** Nothing used to place the board horizontally, so it
## sat at scroll zero — hard left — while the view claimed to be centred on a grid.
## FOCUSED: the grid being acted on, and it is the ONLY grid the "no cut-off grid" rule speaks about
## — a neighbour sliced by the window edge is not a defect.
## OVERVIEW: the MIDDLE grid, which is what puts the whole board in the middle of the window.
func resting_grid() -> int:
	var last := grid_container.get_child_count() - 1
	if last < 0: return NO_GRID
	if view_mode == ViewMode.FOCUSED and focused_grid != NO_GRID:
		return clampi(focused_grid, 0, last)
	return last / 2

## Bring the board to its resting position. Reuses the removal re-centre, so opening the board and
## losing a grid move it the same way — including its wait for the panels to stop moving, which is
## what makes this safe to call before the layout has ever run.
func rest_board() -> void:
	var gi := resting_grid()
	if gi == NO_GRID: return
	pan_grid = gi
	_recentre_board()

## Focus one grid — what a click on a grid in the overview does. Placement happens focused.
## Focusing also CENTRES the view on that grid: the grid being acted on is the grid in the middle,
## in both modes, so `pan_grid` can never disagree with `focused_grid` about where the view is.
func focus_grid(gi: int) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
	_set_view(ViewMode.FOCUSED, gi)
	_zoom_board_to(focused_board_zoom(gi))
	pan_to_grid(gi)
	# ⚠ **AIM AGAIN ONCE THE ZOOM'S RELAYOUT HAS LANDED.** The aim above is exact horizontally --
	# the content's own columns do not move when the board zooms -- but the FLOOR does, and a grid's
	# vertical position is measured from it, so the vertical half of that aim is taken against the
	# previous mode's floor. This is the same re-aim a removal uses, for the same reason.
	_recentre_board()

# ------------------------------------------------------------------------------
# THE ZOOM — what makes the two modes different on screen and not merely in state
# ------------------------------------------------------------------------------

## The overview's zoom: the board at the scale it is laid out at. The overview shows as many grids
## as fit at ONE fixed readable zoom and pans to reach the rest, so it never scales.
const OVERVIEW_BOARD_ZOOM := 1.0

## The scale the board is CURRENTLY being taken to. The live scale lags it through the transition;
## every aim is computed at this one, so a pan and a zoom started together land together.
var board_zoom : float = OVERVIEW_BOARD_ZOOM

## The focused view's scale: **grid `gi`'s CELL BLOCK made exactly as tall as the board's window.**
## Derived from the grid's own shape and the window, never authored -- a taller grid zooms less.
## ⚠ The block, not the grid's live height: a stack growing upward must not re-scale the board
## under the player's hand.
##
## ⚠ **SOLVED IN CLOSED FORM, NOT READ OFF `_board_strip_h`.** The window and the Entrance strip
## both scale with THIS zoom, so "the block exactly fills the window" is
## `block_h * z == size.y - base_strip * z` with `base_strip` the zoom-independent strip height --
## a fixed point in `z`, not a value `_board_strip_h` (last zoom's strip) can supply. Solving it
## directly (`z = size.y / (block_h + base_strip)`) is the only value that does not depend on which
## zoom was live when this was called -- reading the previous zoom's strip made the first focus and
## a later step land at different scales for the identical grid.
func focused_board_zoom(gi: int) -> float:
	if not is_instance_valid(scroll_container): return OVERVIEW_BOARD_ZOOM
	var grid : GridData = _bound_grids[gi] if gi >= 0 and gi < _bound_grids.size() else GridData.new()
	var block_h := grid_block_size_px(PlayArea.settings(), grid).y
	var base_strip := entrance_strip_height_px(PlayArea.settings(), 1.0)
	var pad := board_edge_pad_px(PlayArea.settings())
	if block_h <= 0.0 or size.y <= 0.0 or size.x <= 0.0: return OVERVIEW_BOARD_ZOOM
	var tall := size.y / (block_h + _panel_gutter_h(gi) + base_strip + 2.0 * pad
			+ _scroller_frame_h())
	var wide := _panel_width(gi)
	return tall if wide <= 0.0 else minf(tall, maxf(size.x - hud_reserve_px(), 1.0) / wide)

## The band the scroller keeps for its HORIZONTAL bar, which it reserves whether or not that bar is
## on screen -- `SCROLL_MODE_SHOW_NEVER` hides the bar and keeps the band.
##
## ⚠ **`page` IS WHAT DECIDES WHETHER THE VERTICAL BAR SHOWS**, not the scroller's rect, and `page`
## is the rect LESS this. A board fitted to the rect overflows the page by exactly this much, and
## the player gets a scrollbar on a board they have not touched. Measured: a content of 313 against
## a page of 305.
func _scroller_frame_h() -> float:
	if not is_instance_valid(scroll_container): return 0.0
	var h_bar := scroll_container.get_h_scroll_bar()
	return h_bar.get_combined_minimum_size().y if h_bar else 0.0

## The whole panel's width — the row-label gutter, the cells and the special-meld label — as one
## MINIMUM-size query, for the same reasons `_panel_gutter_h()` gives.
func _panel_width(gi: int) -> float:
	if gi < 0 or gi >= grid_container.get_child_count(): return 0.0
	var panel := grid_container.get_child(gi) as Control
	return panel.get_combined_minimum_size().x if panel else 0.0

## The score furniture a grid panel carries BELOW its cells: the column-label row and the gap above
## it. Part of what the board's window must hold, or the panel overflows it and the scroller shows a
## bar on a board the player has not even touched.
##
## ⚠ **MEASURED FROM THE PANEL, AND IT HAS TO BE.** The label's height comes from the FONT (23 px at
## the shipped one), so there is no constant to derive it from.
## ⚠ **THE DIFFERENCE OF TWO MINIMUM SIZES, NOT OF TWO RECTS.** A container answers
## `get_combined_minimum_size()` from its children on demand rather than from the last layout pass,
## so this cannot serve a stale rect the way a `size` read would -- and subtracting the cells' own
## minimum takes the stacks' DEPTH back out, which is what keeps a deepening stack from re-scaling
## the board under the player's hand.
func _panel_gutter_h(gi: int) -> float:
	if gi < 0 or gi >= grid_container.get_child_count(): return 0.0
	var panel := grid_container.get_child(gi) as Control
	if not panel: return 0.0
	var cells := _cells_root(panel)
	if not cells: return 0.0
	return maxf(panel.get_combined_minimum_size().y - cells.get_combined_minimum_size().y, 0.0)

## Take the board to scale `z` over the pan clock -- the same clock a grid pan and the removal
## re-centre use, so a mode change is one motion and not two.
##
## ⚠ **THE SCALE IS NOT ANIMATED, AND THAT IS THE RULE, NOT A SHORTCUT.** There are exactly two
## view modes and NO INTERMEDIATE ZOOM EXISTS: the transition the player sees is the board sliding
## to the grid, over the pan clock, at the mode's own scale. An eased scale would also fight the
## aim it is issued with -- the scroller clamps every aim against the reach it can see at that
## instant, so a target set for the zoomed board is destroyed by the next unzoomed frame.
##
## The whole board is re-measured here rather than on the next layout pass, because `pan_to_grid`
## runs immediately after and reads the window and the floor this writes.
func _zoom_board_to(z: float) -> void:
	if not is_instance_valid(scroll_container): return
	if is_equal_approx(board_zoom, maxf(z, 0.0001)): return
	board_zoom = maxf(z, 0.0001)
	_apply_entrance_strip_height()
	_publish_board_floor()

## Where the scroller puts the content at `pos` zero: the margin offset it centres with, measured
## rather than restated, so an aim is expressed in the same units the scroller stores.
func _board_content_origin() -> Vector2:
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return Vector2.ZERO
	var z := maxf(scroll_container.scale.x, 0.0001)
	return (top_level_vbox.global_position - scroll_container.global_position) / z - smooth.pos


## The grid the view is CENTRED on. Distinct from `focused_grid`, which is `NO_GRID` in the
## overview: the view is centred on some grid in both modes.
var pan_grid : int = 0

## The grid Back zoomed out of, so Forward can return to the same view. `NO_GRID` until Back has
## zoomed out of a focused grid — Forward then has nothing to return to.
var _zoom_out_grid : int = NO_GRID

## ⚠ **THE BOARD IS ONE LEVEL OF A STACK THAT CONTINUES PAST IT** — one grid, then every grid, then
## the wall. Back steps OUT one level and Forward steps back IN, and both FALL THROUGH once this
## screen has no level left to give: Back in the all-grids view must reach the wall, or the wall
## becomes unreachable from inside a show. Panning has its own actions and never touches these.
## True when this screen consumed the event.
func _consume_as_view_action(event: InputEvent) -> bool:
	# The overview's arrow keys pick a GRID, not a cell. Read here as well as on a focused cell's
	# own `gui_input` so the arrows still work when nothing on the board holds focus.
	if _consume_as_grid_select(event):
		return true
	if event.is_action_pressed(&"grid_pan_left"):
		pan_by_grids(-1)
		return true
	if event.is_action_pressed(&"grid_pan_right"):
		pan_by_grids(1)
		return true
	if event.is_action_pressed(&"wall_back"):
		if view_mode != ViewMode.FOCUSED: return false
		_zoom_out_grid = focused_grid
		open_zoomed_out()
		return true
	if event.is_action_pressed(&"wall_forward"):
		if view_mode != ViewMode.OVERVIEW or _zoom_out_grid == NO_GRID: return false
		focus_grid(_zoom_out_grid)
		return true
	return false

## Pan `step` grids from whichever grid the view is centred on. There is nothing to centre past the
## outermost grid, so the board bounces there instead of moving.
func pan_by_grids(step: int) -> void:
	var last := grid_container.get_child_count() - 1
	if last < 0: return
	var target := pan_grid + step
	if target < 0 or target > last:
		_bounce_board(step)
		return
	pan_to_grid(target)

## Centre the view on grid `gi`.
##
## ⚠ **THE CLAMP IS THE SCROLL CONTAINER'S OWN, NOT ARITHMETIC WRITTEN HERE.** `scroll_x_to` clamps
## the request to the content's real range, and that range collapses to nothing on an axis the
## content already fits — so an edge grid rests against the edge with no bare background beside it,
## and a board narrower than the window stays centred by the layout instead of being panned.
func pan_to_grid(gi: int) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
	pan_grid = gi
	# ⚠ **OVERVIEW: THE CAMERA IS THE SINGLE HORIZONTAL AUTHORITY.** The scroller's horizontal aim
	# is dead range there — retired rather than left as a second writer.
	if view_mode == ViewMode.OVERVIEW:
		overview_pan_requested.emit(gi)
		return
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	var cells := _cells_root(grid_container.get_child(gi) as Control)
	if not cells: return
	var dur : float = PlayArea.settings().grid_pan_duration
	var origin := _board_content_origin()
	var local := _board_local_rect(cells)
	# ⚠ **EVERY TERM HERE IS IN THE SCROLLER'S OWN LOCAL SPACE, WHICH THE ZOOM DOES NOT TOUCH.**
	# The zoom scales the scroller and divides its rect, so inside it the content keeps its authored
	# size and the WINDOW is what shrinks -- `size` already carries the zoom, and multiplying a
	# board length by it again aims the board off its own edge (measured: a whole grid out).
	var window := _board_window_local()
	smooth.scroll_x_to(window.x * 0.5
			- (local.position.x + local.size.x * 0.5) - origin.x, dur)
	# ⚠ **THE VERTICAL AIM IS THE FOCUSED VIEW'S ALONE.** Zoomed in, the grid is taller than the
	# window unless it is framed, and the edge to frame it by is the FLOOR every grid grows up out
	# of. In the overview the board is at rest vertically and a pan must not yank a player who has
	# scrolled up to read a stack.
	smooth.scroll_y_to(window.y - (local.position.y + local.size.y) - origin.y, dur)

## A board control's rect in the CONTENT's own unzoomed space. ⚠ `global_position` already carries
## the zoom while `size` never does, so the two cannot be mixed: everything an aim is built from is
## divided back out here, and the target zoom is applied once, at the end.
func _board_local_rect(c: Control) -> Rect2:
	var z := maxf(scroll_container.scale.x, 0.0001)
	return Rect2((c.global_position - top_level_vbox.global_position) / z, c.size)

## The edge push-back. FOCUSED keeps the scroll container's OWN overdrag, which supplies the
## counterforce and carries the board back to rest — reused rather than hand-tweened so the board's
## edge feels like every other overscroll in the game, and so nothing here can park the board off
## its own edge. OVERVIEW has no scroller range to spend a kick into (that
## panning to the camera), so it asks the camera's owner to bounce instead.
func _bounce_board(step: int) -> void:
	if view_mode == ViewMode.OVERVIEW:
		overview_bounce_requested.emit(step)
		return
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	smooth.scroll_horizontally(float(step) * PlayArea.settings().grid_bounce_velocity_px)

## How far `velocity_px` carries a scroller under `damper`'s OWN physics before it settles —
## simulated frame by frame through `ScrollDamper.slide()`, the same public call the scroller's own
## `_process()` makes, so a camera bounce reaches exactly as far as the scroller's kick would.
## `grid_bounce_velocity_px` already lives in the same design-pixel space `grid_position_size_px()`
## does (both native SubViewport pixels; OVERVIEW's `board_zoom` is `OVERVIEW_BOARD_ZOOM == 1.0`),
## which is the same space `WallPicture.grid_state()` writes straight into `camera.position` with no
## rescale — so the returned peak is added to a camera position the same way, unscaled.
static func bounce_peak_px(damper: ScrollDamper, velocity_px: float) -> float:
	if not damper or is_zero_approx(velocity_px): return 0.0
	var velocity := velocity_px
	var offset := 0.0
	var peak := 0.0
	var dt := 1.0 / 60.0
	var steps := 0
	while absf(velocity) > 0.5 and steps < 600:
		var result := damper.slide(velocity, dt)
		velocity = result[0]
		offset += result[1]
		peak = maxf(peak, absf(offset))
		steps += 1
	return peak

## The single write path for the view mode; announces only real changes.
func _set_view(mode: ViewMode, gi: int) -> void:
	if view_mode == mode and focused_grid == gi: return
	view_mode = mode
	focused_grid = gi
	view_mode_changed.emit(mode, gi)

## Which grid a board control belongs to, or `NO_GRID` for anything that is not on a grid — the
## Entrance included, so grabbing a card from the Entrance still works in the overview.
func _grid_index_of(c: Control) -> int:
	if not is_instance_valid(c): return NO_GRID
	var node : Node = c
	while is_instance_valid(node):
		var parent := node.get_parent()
		if parent == grid_container: return node.get_index()
		node = parent
	return NO_GRID

## In the overview, a click on a grid focuses that grid INSTEAD of acting on the card. True when
## it consumed the press. Info mode is not placement, so it is asked first and passes through.
func _consume_as_focus_click(c: Control) -> bool:
	if view_mode != ViewMode.OVERVIEW: return false
	var gi := _grid_index_of(c)
	if gi == NO_GRID: return false
	focus_grid(gi)
	return true

# ==============================================================================
# MOVING THE SELECTION — ARROWS, AND THE ONE-FINGER SWIPE
#
# The arrows mean two different things, and which one depends on the view mode: focused, they move
# the SELECTED CELL along the board's lattice and cross into the next grid; in the overview they
# select a whole GRID, which Enter then focuses. Same key, two granularities.
# ==============================================================================

## The overview's cursor: which grid the arrows have selected, and the one Enter focuses. Kept in
## step with the board focus (`on_control_focus_entered`), so a grid picked with the mouse and a
## grid picked with the arrows are the same fact.
var selected_grid : int = 0

## Which way an arrow (or d-pad) press points, `ZERO` for anything else. ⚠ `y` grows DOWNWARD: row
## 0 is a grid's TOP row, so Up is -1.
func _arrow_delta(event: InputEvent) -> Vector2i:
	if event.is_action_pressed(&"ui_left"): return Vector2i.LEFT
	if event.is_action_pressed(&"ui_right"): return Vector2i.RIGHT
	if event.is_action_pressed(&"ui_up"): return Vector2i.UP
	if event.is_action_pressed(&"ui_down"): return Vector2i.DOWN
	return Vector2i.ZERO

## Every grid's own bounding width, left to right — the lattice `BoardCoord.step` moves over.
func _grid_widths() -> Array[int]:
	var widths : Array[int] = []
	var game := CardEnvironment.get_current_game()
	if not game: return widths
	for grid : GridData in game.state.grids:
		widths.append(grid.grid_width if grid else 0)
	return widths

## The board coordinate a bound control names, or `NOWHERE`. An EMPTY cell presents its own zone
## card, which names the cell rather than a card in it — so both are asked.
func _coord_of_control(c: Control) -> BoardCoord:
	if not is_instance_valid(c) or c not in ui_data: return BoardCoord.NOWHERE
	var game := CardEnvironment.get_current_game()
	if not game: return BoardCoord.NOWHERE
	var data : CardData = ui_data[c]
	var coord : BoardCoord = game.state.grid_position_of(data)
	if not coord.is_nowhere(): return coord
	return game.state.cell_type_coord(data)

## The control the selection sits on for a cell: its slot's FIRST child, which is the topmost card
## of the stack, or the cell's own zone card while it is empty. Null when no cell is built there.
func _cell_focus_control(coord: BoardCoord) -> Control:
	var game := CardEnvironment.get_current_game()
	if not game: return null
	if coord.grid < 0 or coord.grid >= grid_container.get_child_count(): return null
	if coord.grid >= game.state.grids.size(): return null
	var grid : GridData = game.state.grids[coord.grid]
	if not grid: return null
	var slot := _cell_slot(grid_container.get_child(coord.grid) as Control, grid,
			grid.cell_index(coord.x, coord.y))
	if not slot or slot.get_child_count() == 0: return null
	return slot.get_child(0) as Control

## Arrow movement of the selected CELL, focused mode only. True when it consumed the press.
##
## ⚠ **THE MOVEMENT IS `BoardCoord.step` OVER THE UNBOUNDED LATTICE, NEVER ARITHMETIC WRITTEN
## HERE.** Stepping off a grid's edge simply lands in the next grid's block; whether a cell EXISTS
## at the landing is a separate question asked here, at landing. A landing on nothing consumes the
## press and moves nothing, so the board's outer edge stops the selection instead of wrapping.
## ⚠ **CROSSING CARRIES THE VIEW WITH IT**, or the selection would walk off screen: the landing
## grid is focused, which also centres it.
func _consume_as_cell_move(event: InputEvent, control: Control) -> bool:
	if view_mode != ViewMode.FOCUSED: return false
	var d := _arrow_delta(event)
	if d == Vector2i.ZERO: return false
	var from := _coord_of_control(control)
	if from.is_nowhere() or from.is_entrance(): return false
	var game := CardEnvironment.get_current_game()
	if not game: return false
	var to := from.step(d.x, d.y, _grid_widths())
	if not game.state.has_cell(to): return true
	var target := _cell_focus_control(to)
	if not target: return true
	target.grab_focus()
	if to.grid != from.grid: focus_grid(to.grid)
	return true

## Arrow selection of a whole GRID, overview only — a different granularity from the focused
## mode's cell movement, matching the wall's own overview. The view follows the selection and the
## board focus moves onto the newly selected grid, so Enter and the mouse agree about which grid is
## chosen. Up/Down mean nothing here and fall through.
##
## ⚠ **THE PAN IS THE LAST WRITER, ALWAYS — GRAB THE FOCUS FIRST.** The scroll container follows
## focus: a focus change kills the in-flight pan and re-aims to put the control just inside the
## window edge, which leaves the selected grid on screen but NOT centred (measured: 227 px off).
## Same order as the focused mode's cell move, for the same reason.
func _consume_as_grid_select(event: InputEvent) -> bool:
	if view_mode != ViewMode.OVERVIEW: return false
	var d := _arrow_delta(event)
	if d.x == 0: return false
	var last := grid_container.get_child_count() - 1
	if last < 0: return false
	selected_grid = clampi(selected_grid + d.x, 0, last)
	var target := _cell_focus_control(BoardCoord.new(selected_grid, 0, 0, 0))
	if target: target.grab_focus()
	pan_to_grid(selected_grid)
	return true

## Key input on a FOCUSED board cell.
##
## ⚠ **THIS IS THE ONLY PLACE THE BOARD CAN HEAR AN ARROW KEY.** The viewport's own focus-neighbour
## search runs in the GUI pass and consumes any arrow that finds a neighbour, so an arrow read from
## `_unhandled_input` would never arrive while a cell holds focus — the selection would drift by
## SCREEN GEOMETRY instead of along the board's lattice, and nothing would pan to follow it.
## `accept_event` is what stops that search from also running.
func _on_cell_gui_input(event: InputEvent, control: Control) -> void:
	if _arrow_delta(event) == Vector2i.ZERO: return
	if _consume_as_cell_move(event, control) or _consume_as_grid_select(event):
		control.accept_event()

## Does a BOARD control genuinely hold the focus right now? `focused_control` is a last-known
## value and goes stale as soon as focus moves to other UI, so the viewport is asked too.
func _board_control_has_focus() -> bool:
	return (is_instance_valid(focused_control) and focused_control in ui_data
			and get_viewport().gui_get_focus_owner() == focused_control)

## Where the live one-finger drag began, in screen pixels.
var _swipe_origin := Vector2.ZERO
## Armed only by a touch that began on BARE BOARD. A drag that begins on a card is a placement —
## the same distinction the wall draws between a press on a picture and a press on bare wall.
var _swipe_armed := false
## ONE GRID PER SWIPE: latched the moment the threshold is crossed, and not re-armed until the
## finger lifts.
var _swipe_fired := false

## How far a finger must travel before the drag is a pan, in px: the millimetre knob converted at
## the screen's DPI, clamped to the SWIPE's own millimetre bounds converted the same way.
##
## ⚠ **THE CLAMP GUARDS THE DPI READING, NOT THE GESTURE'S SIZE.** A DPI reading is unreliable on
## multi-monitor Windows (which reports the primary screen's for all of them) and on Android, so an
## unclamped conversion can produce any number at all -- that much stands. But the bounds used to be
## the TOUCH-TARGET ones, and a distance to travel is not a thing to hit: their floor of 32 px is
## ~8.5 mm at 96 DPI, which is roughly three times the paging slop Android uses for this very
## gesture, and it sat ABOVE the knob's own default so turning the knob down did nothing.
## Both bounds are millimetres now, so the whole clamp survives a DPI change together.
func _swipe_threshold_px() -> float:
	var s := PlayArea.settings()
	var dpi := DisplayServer.screen_get_dpi()
	return clampf(WallInput.mm_to_px(s.grid_swipe_threshold_mm, dpi),
			WallInput.mm_to_px(s.grid_swipe_threshold_min_mm, dpi),
			WallInput.mm_to_px(s.grid_swipe_threshold_max_mm, dpi))

## The bound board control under a point, or null for bare board. The zone card an EMPTY cell
## presents counts as a card: it is the cell's drop target, so a drag begun on it is a placement.
func _card_control_at(at: Vector2) -> Control:
	for c : Control in ui_data:
		if not is_instance_valid(c) or not c.is_visible_in_tree(): continue
		if c.get_global_rect().has_point(at): return c
	return null

## The one-finger swipe. True only when a pan actually fired.
##
## ⚠ **READ FROM `InputEventScreenDrag` AND NOTHING ELSE.** With `emulate_mouse_from_touch` at its
## default of true, one finger arrives as BOTH a screen drag and a synthesised
## `InputEventMouseMotion`; a reader that accepted either form pans TWICE per swipe. The project
## setting stays on — the wall's own one-finger pan reads the mouse form.
## ⚠ **`device == -1` MARKS THE ENGINE'S OWN SYNTHESIS** (a mouse emulating touch), so filtering it
## keeps a real mouse drag from panning the board.
## ⚠ A press only ARMS: it consumes nothing, and moves nothing until the finger does.
## ⚠ **DRIVEN FROM `_input`, NEVER `_unhandled_input`** — see the routing note there.
func _consume_as_swipe(event: InputEvent) -> bool:
	if event.device == -1: return false
	var touch := event as InputEventScreenTouch
	if touch:
		_swipe_fired = false
		_swipe_armed = false
		if touch.pressed:
			flush_rebuild()   # reads ui_data
			_swipe_origin = touch.position
			_swipe_armed = _card_control_at(touch.position) == null
		return false
	var drag := event as InputEventScreenDrag
	if not drag or not _swipe_armed or _swipe_fired: return false
	var travel := drag.position.x - _swipe_origin.x
	if absf(travel) < _swipe_threshold_px(): return false
	_swipe_fired = true
	# The board follows the finger: dragging RIGHT brings the grid on the left into view.
	pan_by_grids(-1 if travel > 0.0 else 1)
	return true

func _on_gui_input(event: InputEvent) -> void:
	flush_rebuild() #reads ui_data
	# Mouse ONLY: key/joypad events never reach this root handler — Godot 4 delivers them to
	# the FOCUSED control alone (no ancestor bubbling), so keyboard/controller accept+cancel
	# live in _unhandled_input below (caught by the interaction suite 2026-07-13: Enter/A on
	# a focused card silently did nothing).
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		# left click
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			# is_instance_valid guard: a board rebuild (e.g. submit clearing the board)
			# can free the control this still points at, and `freed in typed_dict` errors.
			if (is_instance_valid(focused_control)
					and focused_control == moused_hovered_control
					and focused_control in ui_data):
					#and not focused_control.is_in_group("CardVisualZoneControl")):
				if _info_mode():
					info_requested.emit(card_info(ui_data[focused_control]))
				elif not _consume_as_focus_click(focused_control):
					data_selected.emit(ui_data[focused_control])

## Keyboard/controller accept + cancel. Key events go ONLY to the focused control (a plain
## card control consumes nothing), then fall through the focus-navigation pass to unhandled
## input — this is the first place the board can hear them. Buttons (Submit/Continue/…)
## consume their own ui_accept before this runs, so a focused button never double-acts.
func _unhandled_input(event: InputEvent) -> void:
	# THE VIEW GETS FIRST REFUSAL, and gives the event straight back when it has no level left to
	# step out of — see `_consume_as_view_action`.
	if _consume_as_view_action(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		# IN THE OVERVIEW, ENTER FOCUSES THE SELECTED GRID even when nothing on the board holds
		# focus — an arrow selection must be committable on its own. With a board control focused
		# the pass below already does it through `_consume_as_focus_click`, and the two agree
		# because the cursor tracks the focus; leaving that case alone is what keeps a focused
		# ENTRANCE card (which belongs to no grid) selectable in the overview.
		if view_mode == ViewMode.OVERVIEW and not _board_control_has_focus():
			focus_grid(selected_grid)
			get_viewport().set_input_as_handled()
			return
		flush_rebuild() #reads ui_data
		# Act only when a BOARD control genuinely holds focus RIGHT NOW (focused_control is
		# our last-known card control; it can go stale when focus moves to other UI, and it
		# must stay inert while the game-over overlay has the board focus-locked).
		if _board_control_has_focus():
			if _info_mode():
				info_requested.emit(card_info(ui_data[focused_control]))
			elif not _consume_as_focus_click(focused_control):
				data_selected.emit(ui_data[focused_control])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if selected_cards:
			ungrab_cards()
			get_viewport().set_input_as_handled()
		else:
			hide_focus_info() # nothing held: just dismiss the inspector, leave the event be

# since clicks outside of play area can happen
##
## ⚠ **THE ONE-FINGER PAN IS READ HERE, AND CANNOT BE READ FROM `_unhandled_input`.** Godot routes
## `InputEventScreenTouch`/`InputEventScreenDrag` through the same viewport GUI pass as the mouse,
## and the first `MOUSE_FILTER_STOP` control under the finger — the board's own scroll container —
## marks them handled, so unhandled input never sees a finger on the board at all. `_input` runs
## BEFORE that pass, which is the only place the board can hear one. (Measured: the swipe reader was
## unreachable in the product while its tests, which called the handler directly, were green.)
func _input(event: InputEvent) -> void:
	if _consume_as_swipe(event):
		get_viewport().set_input_as_handled()
		return
	# Mouse
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		# right click / cancel
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			ungrab_cards()
			
func grab_cards(datas:Array[CardData]) -> void:
	flush_rebuild() #reads data_card / data_ui
	ungrab_cards()
	selected_cards = datas
	set_card_zones_visuals()
	for index in selected_cards.size():
		var data := selected_cards[index]
		if data in data_card:
			var card_visual := data_card[data]
			card_visual.held = index + 1
			# Held cards ride ABOVE all resting cards, still below PropLayer (a later sibling of
			# CardLayer). move_child to the end of the card's OWN layer (Entrance or grid) — no
			# z_index (structural order, LAYERING.md). ungrab_cards -> rebuild restores row-major
			# order.
			var vis_layer := card_visual.get_parent()
			if vis_layer == card_layer or vis_layer == entrance_card_layer:
				(vis_layer as Node2D).move_child(card_visual, -1)
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func ungrab_cards() -> void:
	flush_rebuild() #reads data_card / data_ui
	hide_focus_info() #ui_cancel/right-click also dismisses the focus inspector
	for data in selected_cards:
		if data in data_card: 
			var card_visual := data_card[data]
			card_visual.held = 0
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_PASS
	selected_cards = []
	set_card_zones_visuals()

## Game over: the outcome overlay covers the board and blocks the mouse, but keyboard/
## controller focus could still walk onto the covered cards — drop it, and KEEP it dropped
## through rebuilds: the final Submit's discard queues a deferred rebuild that lands AFTER
## the overlay went up and would otherwise hand the focus modes right back.
var board_focus_locked := false

func disable_board_focus() -> void:
	board_focus_locked = true
	for control : Control in ui_data:
		control.focus_mode = Control.FOCUS_NONE

## Outcome dismissed (undo): unlock and restore card focus. The dismissal's full rebuild
## follows immediately and re-derives the header focus exceptions, so a blanket FOCUS_ALL
## here is safe (reused pooled controls never re-run create_card_control's defaults).
func enable_board_focus() -> void:
	board_focus_locked = false
	for control : Control in ui_data:
		control.focus_mode = Control.FOCUS_ALL

#No per-frame processing: Game relays GameData.board_changed (emitted by every
#revision bump, i.e. every board mutation) to queue_rebuild(). Focus/selection
#changes don't touch the board and call set_card_zones_visuals() directly.

#Any number of rebuild requests within one frame collapse into a single
#set_card_zones() at end of frame (call_deferred). A direct synchronous
#set_card_zones() (setup_gui/undo) clears the pending request instead.
var _rebuild_queued := false

func queue_rebuild() -> void:
	if _rebuild_queued: return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()

func _deferred_rebuild() -> void:
	if not _rebuild_queued: return #a direct rebuild already happened this frame
	set_card_zones()

#GUARD RULE: ui_data / data_ui / data_card and the control tree are only valid for
#the CURRENT revision. Anything that reads them must flush the queued rebuild first,
#or it operates on a stale layout (out-of-bounds crashes, missing visuals).
## True once every current card visual is in-tree and _ready — i.e. its @onready nodes
## exist. CardVisuals add_child via call_deferred, so right after a rebuild they're mapped in
## data_card but not yet ready; callers that animate visuals immediately (e.g. a resumed
## show replaying its scoring) wait on this first.
func visuals_ready() -> bool:
	for visual: CardVisual in data_card.values():
		if not is_instance_valid(visual) or not visual.is_node_ready():
			return false
	return true

func flush_rebuild() -> void:
	if _rebuild_queued:
		# A board rebuild is the single most disruptive thing the visual layer does — every pooled
		# slot control is rebound, so any card position read before it is stale after it. Logged
		# because "the beam was in the wrong place" and "the board moved under the beam" look
		# identical on screen and are one line apart in the log.
		EventLog.event(EventLog.CH_BOARD, "rebuild", "cards=%d" % data_card.size())
		set_card_zones()

## The board Control at a slot coord (z == -1 header, z >= 0 row card), or null if the layout
## has no control there (empty slot past the built rows). Focus/input helpers use this;
## slot GEOMETRY does not — slot_center_global below is pure math (owner spec).
func control_for_coord(v: Vector3i) -> Control:
	var hbox : HBoxContainer = upper_zone_right
	if v.y < 0 or v.y >= hbox.get_child_count(): return null
	var vbox := hbox.get_child(v.y)
	var idx := v.z + 1   # child 0 = the zone/type header (z == -1)
	if idx < 0 or idx >= vbox.get_child_count(): return null
	return vbox.get_child(idx) as Control

## Global-space center of the CARD at any board coord — PURE MATH, no control-rect reads on the
## hot path (owner spec 2026-07-15): geometry is deterministic and independent of container
## relayout timing, and the one formula covers occupied, empty, and off-board slots alike, for
## both branches below. Every prop anchors through this every frame.
func slot_center_global(coord: BoardCoord) -> Vector2:
	if coord.y == BoardCoord.ENTRANCE_ROW:
		return _entrance_slot_center_global(coord)
	return _grid_slot_center_global(coord)

## Which `CardVisual` layer a BOARD COORD's card draws in — `PropLayer`'s split-prop bracketing
## (`_apply_split`/`_row_bounds`) needs this to move/query the right layer now the Entrance and
## the grids no longer share one `CardLayer`.
func card_layer_for(coord: BoardCoord) -> Node2D:
	return entrance_card_layer if coord.y == BoardCoord.ENTRANCE_ROW else card_layer

## The Entrance: still backed by `upper_zone`, and still mirrors the container build in
## `set_card_zone` / `update_card_zone_visuals` — the Entrance hbox is a direct child of one VBox
## at a known, stable offset, so reading its own global position here (unlike a grid panel's) does
## not depend on relayout timing in practice.
##   column x = entrance hbox left + column * (card width + separation) + half card width
##   slot top = entrance hbox top + header height (0) + separation + slot * row pitch
##     with row pitch = card strip height (card_separation_play_custom) + separation
##   card anchor = slot top + half a card — stacked row strips are thin while the card art hangs a
##     full card below its control top.
## **THE ONE PLACE THE BOARD'S STACKING GEOMETRY LIVES.** A card at height `h` sits `h` depth
## pitches ABOVE the line its stack rests on, and its centre is half a card above its own bottom
## edge; column `column` is that many card-and-separation steps right of `origin_x`.
##
## ⚠ **A GRID CELL AND AN ENTRANCE COLUMN ARE THE SAME STACK** (owner: *"all stacking should use
## same code. no duplication"*). They differ only in which line they rest on and where their columns
## start — so that is all either caller supplies. Two copies of this arithmetic is exactly how the
## Entrance came to fan downward while the grid stacked up.
##
## ⚠ **EVERY LENGTH HERE IS A BOARD LENGTH AND THE ORIGIN IS A SCREEN POINT.** The board draws at
## `board_zoom`, so each is taken into screen pixels before it is added to a measured global.
func _stack_slot_center(origin_x: float, floor_y: float, column: int, h: int) -> Vector2:
	var width := CardVisual.card_size_play.x * board_zoom
	var sep := float(separation) * board_zoom
	var x := origin_x + float(column) * (width + sep) + width * 0.5
	var y := floor_y - _depth_pitch_px() * board_zoom * float(h) 			- CardVisual.card_size_play.y * board_zoom * 0.5
	return Vector2(x, y)

## **THE ONE PLACE A STACK'S CONTROLS ARE SIZED.** The slot's own zone card is the LAST child and
## collapses once a card covers it; the newest card takes the FIRST control and shows whole; every
## card under it shows one depth pitch — the strip a covered card reveals, which is where its pips
## are.
##
## ⚠ **NO SEPARATION; EACH CARD CARRIES ITS OWN GAP.** A zero-height child still takes a separation
## from a `VBoxContainer`, so with one the row grew the moment its FIRST card landed. A stack of one
## is exactly one card tall.
func _size_stack_slot(slot: Control) -> void:
	slot.add_theme_constant_override("separation", 0)
	var occupied := slot.get_child_count() > 1
	var zone_control : Control = slot.get_child(-1)
	zone_control.custom_minimum_size = CardVisual.card_size_play if not occupied 			else Vector2(CardVisual.card_size_play.x, 0)
	zone_control.focus_mode = Control.FOCUS_NONE if occupied else Control.FOCUS_ALL
	for j : int in slot.get_child_count() - 1:
		(slot.get_child(j) as Control).custom_minimum_size = Vector2(
				CardVisual.card_size_play.x, _depth_pitch_px())
	if occupied:
		(slot.get_child(0) as Control).custom_minimum_size = CardVisual.card_size_play

## **THE ONE PLACE A STACK'S CONTROL ORDER IS DECIDED.** A `VBoxContainer` lays its children out top
## to bottom and a card hangs from its control's BOTTOM edge, so the card at the greatest height
## takes the FIRST control and the slot's own zone card the very last one.
##
## ⚠ Leaving the zone card FIRST draws it a full card ABOVE an occupied slot: its control collapses
## to zero height once a card covers it, so bottom-anchoring puts it off the top of the slot.
func _bind_stack(slot: Control, stack: Array[CardData], zone_card: CardData) -> void:
	_fit_children(slot, stack.size() + 1, create_card_control)
	var depth := stack.size()
	for j : int in depth:
		_bind_slot(slot.get_child(j) as Control, stack[depth - 1 - j])
	_bind_slot(slot.get_child(depth) as Control, zone_card)

func _entrance_slot_center_global(coord: BoardCoord) -> Vector2:
	# ⚠ **THE CONTAINER'S OWN `global_position` STOPS MIRRORING ITS CHILDREN THE MOMENT IT IS
	# CENTRED** (`ALIGNMENT_CENTER`, set in `setup_gui` so the Entrance lines up with the grid): the
	# columns start at an offset INSIDE the hbox and the two disagree by half the slack (measured:
	# 20 px). The first column's own position already carries that offset, so read it directly.
	var origin := upper_zone_right.global_position
	if upper_zone_right.get_child_count() > 0:
		origin = (upper_zone_right.get_child(0) as Control).global_position
	# ⚠ **THE FLOOR IS THE LINE THE COLUMNS REST ON WITH NOTHING OPEN.** `upper_zone_right`'s own
	# bottom edge is CONTENT-driven: a reveal makes a column taller and the hbox grows with it, so a
	# floor read straight off it moves by exactly the opening and CANCELS the opening the reveal
	# term then subtracts -- measured, a revealed row appeared not to move at all and a prop
	# anchored across the expansion drifted 34 px. The growth is knowable, so it is taken back out.
	# ⚠ Reading the STRIP instead is not the answer either: its height comes from
	# `entrance_visible_rows`, so it stops being the columns' line the moment they outgrow it.
	# ⚠ **THE RESTING LINE IS COMPUTED, NOT READ.** `upper_zone_right`'s bottom edge is
	# CONTENT-driven: a reveal makes a column taller and the hbox grows DOWNWARD from its fixed top,
	# so a floor read off that edge moves by the opening and cancels the opening the reveal term
	# then subtracts. Subtracting the growth back off works at rest but LAGS mid-ease -- a control
	# rect is a frame behind the eased numbers, which is the very thing every other comment here
	# warns about, and it drifted a prop 34 px during the animation. The column's resting height is
	# a function of the DATA, so it is derived: one whole card plus a pitch for every card above it.
	var deepest := 0
	var game := CardEnvironment.get_current_game()
	if game:
		for col : ArrayCardData in game.state.upper_zone:
			deepest = maxi(deepest, col.datas.size())
	var resting_h := CardVisual.card_size_play.y 			+ float(maxi(deepest - 1, 0)) * _depth_pitch_px()
	var floor_y := upper_zone_right.global_position.y + resting_h * board_zoom
	var at := _stack_slot_center(origin.x, floor_y, coord.x, coord.h)
	# ⚠ **THE UNIFORM PITCH IS NOT THE WHOLE STORY, AND EVERY PROP ANCHORS TO THIS.** The reveal
	# grows one layer's strip, lifting every layer above it by an amount the pitch does not
	# describe. Still pure math: the offset comes from the same eased numbers that size the
	# controls, so geometry stays independent of relayout timing.
	at.y -= _row_open_offset(coord) * board_zoom
	return at

## A grid cell: column and row come from the DATA (`coord.x`, `coord.y`), height from the cell's
## own stack (`coord.h`). The panel's origin is a cached publish (`_grid_panel_origin`), never a
## live rect read, because a grid panel's position is a layout result (bottom/center-shrink flags
## inside an HBoxContainer of siblings).
##
## ⚠ **STACKS GROW UPWARD FROM A SHARED BOTTOM EDGE.** Every card in a row bottoms out on that
## row's bottom line; height `h` lifts a card by one depth pitch, so a covered card shows its
## bottom strip — which is where the pips are. The centre is measured UP from the row's bottom,
## never down from the panel's top.
##
## ⚠ **ROW HEIGHTS ARE NOT UNIFORM, AND THAT IS THE POINT.** A row is as tall as its deepest cell,
## and a tall stack pushes every row ABOVE it up. Still pure arithmetic: the heights come from the
## DATA (`_grid_row_height` counts cards), never from a control rect, so geometry stays independent
## of relayout timing.
func _grid_slot_center_global(coord: BoardCoord) -> Vector2:
	var origin : Vector2 = _grid_cells_origin.get(coord.grid,
			_grid_panel_origin.get(coord.grid, Vector2.ZERO))
	# ⚠ **EVERY LENGTH HERE IS A BOARD LENGTH AND THE ORIGIN IS A SCREEN POINT.** The board is
	# drawn at `board_zoom`, so each of them is taken into screen pixels before it is added to a
	# measured global origin; leaving one unscaled puts the card a growing fraction of a cell off.
	var width := CardVisual.card_size_play.x * board_zoom
	var full := CardVisual.card_size_play.y * board_zoom
	var sep := float(separation) * board_zoom
	var depth_pitch := (float(CardVisual.card_separation_play_custom) + float(separation)) * board_zoom
	var x := origin.x + float(coord.x) * (width + sep) + width * 0.5
	# ⚠ **THE ROW BOTTOMS ARE MEASURED FROM THE BOARD'S FLOOR, NOT FROM THIS PANEL.** Every panel is
	# bottom-aligned against that one line, and it does not move when a stack deepens — so nothing
	# here lags the way a per-panel rect cache did. Do NOT refresh a rect cache from
	# `_physics_process` instead: reading panel rects every frame feeds the relayout the floor code
	# writes into, and the board never settles.
	var bottom : float = _grid_cells_bottom.get(coord.grid, _board_floor_y)
	for r : int in range(coord.y + 1, _grid_rows(coord.grid)):
		bottom -= (_grid_row_height(coord.grid, r) + float(separation)) * board_zoom
	# ⚠ **THE STACK STARTS ON THE ROW'S BOTTOM LINE, NOT ONE SEPARATION ABOVE IT.** A covered cell
	# frame is HIDDEN rather than flattened, so it takes no separation under the stack any more —
	# the height-0 card's bottom edge IS the row's bottom line, exactly where the frame's was.
	var y := bottom - depth_pitch * float(coord.h) - full * 0.5
	return Vector2(x, y)

## ⚠ **MEMOISED ON THE STATE'S REVISION, AND IT HAS TO BE.** `slot_center_global` runs for every
## card and every prop EVERY FRAME, and the row heights it needs are an O(rows x cols) scan of the
## cells. Computing them per call collapsed the frame rate far enough that awaited placement
## animations stopped finishing — which presents as a HANG with no error, not as slowness: the
## suite died before its banner, and the visual harness never reached its own second card.
## `revision` is the same key `GameData._ensure_pos_index` rebuilds on, and it bumps on every board
## mutation, so a stale entry cannot outlive a change to the cells it measured.
var _row_height_cache : Dictionary[Vector2i, float] = {}
var _row_height_revision := -1
var _row_height_aligned := false

func _row_heights_for(g: int) -> void:
	var game := CardEnvironment.get_current_game()
	var rev : int = game.state.revision if game else -1
	# ⚠ **THE ALIGNMENT SETTING IS PART OF THE KEY.** It changes every row height on the board
	# without touching the state, so a memo keyed on `revision` alone kept serving the pre-toggle
	# answer — measured: a shallow grid stayed at its own 58 where the shared maximum was 98.
	var aligned : bool = PlayArea.settings().grid_align_rows_globally
	if rev == _row_height_revision and aligned == _row_height_aligned: return
	_row_height_cache.clear()
	_row_height_revision = rev
	_row_height_aligned = aligned

## A panel's whole height, from the DATA: every row, plus the gap the panel puts between them.
func _grid_panel_height(g: int) -> float:
	var rows := _grid_rows(g)
	if rows <= 0: return 0.0
	var total := float(separation) * float(rows - 1)
	for r : int in rows:
		total += _grid_row_height(g, r)
	return total

## How many rows grid `g` has, from the DATA. Zero for a grid index nothing answers to.
func _grid_rows(g: int) -> int:
	var game := CardEnvironment.get_current_game()
	if not game: return 0
	var grids := game.state.grids
	if g < 0 or g >= grids.size(): return 0
	var grid : GridData = grids[g]
	return grid.grid_height if grid else 0

## How tall row `r` of grid `g` stands: its deepest cell decides, because a `GridContainer` row is
## as tall as its tallest child. An EMPTY cell is a whole card (that is what an empty cell shows);
## a stack of `d` is the top card whole plus a strip for every card under it, and the cell's own
## zone-card child adds one `separation` once it has collapsed to nothing.
## Reads the DATA, never a rect — `slot_center_global` is on the every-frame prop-anchor path.
func _grid_row_height(g: int, r: int) -> float:
	# ⚠ While anything is EASING the height is a function of time, not of the revision, so the memo
	# would freeze the animation on its first frame. An idle board — which is nearly every frame —
	# still takes the cached path.
	if not _row_open.is_empty() or not _layer_grown.is_empty():
		return _measure_grid_row_height(g, r)
	_row_heights_for(g)
	var key := Vector2i(g, r)
	if _row_height_cache.has(key): return _row_height_cache[key]
	var h := _measure_grid_row_height(g, r)
	_row_height_cache[key] = h
	return h

## ⚠ **CROSS-GRID ALIGNMENT LIVES HERE, AND NOWHERE ELSE** (§1.14, `Q245`=b). With the setting on,
## row `r` takes a SHARED maximum across every grid, so the boards read as one ruled sheet; with it
## off, each grid sizes its own rows. Putting it in the one function every row's height comes from
## is what keeps it PURELY VISUAL — scoring never reads a row height, so the same board scores
## identically either way (`Q251`=b).
func _measure_grid_row_height(g: int, r: int) -> float:
	if not PlayArea.settings().grid_align_rows_globally:
		return _own_grid_row_height(g, r)
	var game := CardEnvironment.get_current_game()
	if not game: return _own_grid_row_height(g, r)
	var tallest := 0.0
	for gi : int in game.state.grids.size():
		tallest = maxf(tallest, _own_grid_row_height(gi, r))
	return tallest

## One grid's OWN height for row `r`, before any cross-grid alignment.
func _own_grid_row_height(g: int, r: int) -> float:
	var full := CardVisual.card_size_play.y
	var game := CardEnvironment.get_current_game()
	if not game: return full
	var grids := game.state.grids
	if g < 0 or g >= grids.size(): return full
	var grid : GridData = grids[g]
	if not grid or r < 0 or r >= grid.grid_height: return full
	var deepest := 0
	for x : int in grid.grid_width:
		var idx := grid.cell_index(x, r)
		if idx >= 0 and idx < grid.cells.size():
			deepest = maxi(deepest, grid.cells[idx].datas.size())
	if deepest == 0: return full
	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(separation)
	# ⚠ **EACH DEPTH LAYER CONTRIBUTES ITS PITCH THROUGH THE EASE, NOT ALL AT ONCE** — the row
	# GROWS into its new height instead of snapping there, reusing the very clock the reveal
	# already runs on. A layer with no entry in `_row_open` has finished arriving and counts whole.
	var grown := 0.0
	for h : int in range(1, deepest):
		grown += depth_pitch * _layer_arrival(g, h)
	# ⚠ **NOTHING IS ADDED FOR THE FIRST CARD.** A stack of one is exactly one card tall -- there
	# is no gap inside it -- and every layer above brings its own pitch, which already carries the
	# separation its own gap needs.
	return full + grown

## How far depth layer `h` of grid `g` is through arriving, 0..1. ⚠ **THE GUARD IS ABOUT THE STACK,
## NOT ABOUT WHAT IS ABOVE IT** (`Q77`=b, re-derived for the flipped direction): the old reveal
## refused to open a row with nothing beneath it because that added pure empty space, and the
## re-derivation asks the same question of the stack — a layer only contributes height if the stack
## really reaches it. Guarding on whether a row has anything ABOVE it is the misreading, and a row
## with nothing above it still pushes.
func _layer_arrival(g: int, h: int) -> float:
	var key := Vector2i(g, h)
	if not _layer_grown.has(key): return 1.0
	return clampf(_layer_grown[key], 0.0, 1.0)

## How far each newly-landed depth layer is through arriving. ⚠ **SEPARATE FROM `_row_open`, ON
## PURPOSE.** They share the key shape and the clock, but not the semantics: a reveal OPENS and
## then CLOSES again, and `set_reveal_cards` REPLACES its wanted-set every section — a growth entry
## living in there would be closed by the next section and the row would shrink back under a card
## that is still sitting on it. Height that has arrived is permanent, so an entry is erased once it
## reaches 1 and an absent key reads as fully arrived.
var _layer_grown : Dictionary[Vector2i, float] = {}
## The deepest stack each grid had at the last rebuild, so a DEEPER one can be told apart from a
## board that simply already looked like this.
var _known_depth : Dictionary[int, int] = {}

## Seed the arrival of any depth layer that appeared since the last rebuild, so the row eases into
## its new height instead of snapping (`Q75`=a).
## ⚠ A grid seen for the FIRST time animates nothing: a dealt or restored board is already the
## shape it should be, and easing it in would play a growth that never happened.
func _seed_new_layers(game_state: GameData) -> void:
	for gi : int in game_state.grids.size():
		var grid : GridData = game_state.grids[gi]
		if not grid: continue
		var deepest := 0
		for cell : ArrayCardData in grid.cells:
			deepest = maxi(deepest, cell.datas.size())
		var known : int = _known_depth.get(gi, deepest)
		for h : int in range(maxi(known, 1), deepest):
			if not _layer_grown.has(Vector2i(gi, h)):
				_layer_grown[Vector2i(gi, h)] = 0.0
				set_process(true)
		_known_depth[gi] = deepest

## Every CardVisual in `coord`'s BRACKET ROW — the set `PropLayer` brackets a split prop around.
##
## ⚠ **THE BRACKET ROW IS THE HEIGHT LAYER `h`, IN BOTH HALVES OF THE BOARD — NEVER THE CELL ROW
## `y`.** `_order_board_cards` is what decides this: `_append_grids_row_major` emits grid cards
## `for h: for every cell`, so ONE HEIGHT LAYER is contiguous in `card_layer` and a row `y` is
## scattered through it. `PropLayer._row_bounds` brackets `[first..last]` of whatever set it gets,
## so a non-contiguous set would swallow every card between its ends. The Entrance agrees by
## construction: its depth `h` is a level within a fanned column, not a screen row.
##
## Short columns and shallow cells simply have no card at that depth and are skipped, so an empty
## slot never pulls another layer's card into the set.
func row_card_visuals(coord: BoardCoord) -> Array[CardVisual]:
	var out : Array[CardVisual] = []
	if coord.h < 0: return out
	# ⚠ **READ FROM STATE, NOT FROM THE CONTROLS — BOTH HALVES OF THE BOARD.** Rebuilds are
	# DEFERRED, so mid-mutation the controls still describe the previous board. The Entrance used to
	# walk its controls at `h + 1`, hard-coding "child 0 is the header": when the Entrance was
	# turned around to stack upward that index silently named a DIFFERENT card, and every split
	# prop bracketed the wrong row. Which child holds which height is a layout detail; the stack
	# itself is the fact.
	var game := CardEnvironment.get_current_game()
	if not game: return out
	if coord.is_entrance():
		for col : ArrayCardData in game.state.upper_zone:
			if coord.h >= col.datas.size(): continue
			_append_row_visual(out, col.datas[coord.h])
		return out
	var grids := game.state.grids
	if coord.grid < 0 or coord.grid >= grids.size(): return out
	var grid : GridData = grids[coord.grid]
	if not grid: return out
	for cell : ArrayCardData in grid.cells:
		if coord.h >= cell.datas.size(): continue
		_append_row_visual(out, cell.datas[coord.h])
	return out

func _append_row_visual(out: Array[CardVisual], d: CardData) -> void:
	var vis : CardVisual = data_card.get(d) if d else null
	if vis and is_instance_valid(vis):
		out.append(vis)

func set_separation() -> void:
	for container : Control in containers:
		container.add_theme_constant_override("separation", separation)

func set_card_zones() -> void:
	_rebuild_queued = false #this rebuild satisfies any queued request
	hide_focus_info() #the control it anchored to may be about to move or free
	var game := CardEnvironment.get_current_game()
	if not game: return
	ui_data.clear()
	data_ui.clear()
	var game_state := game.state
	# Handles structural validation, instantiations, and dictionary mapping
	set_card_zone(upper_zone_right, game_state.upper_zone_type, game_state.upper_zone)
	set_grid_zones(game_state)
	data_card = new_data_card
	new_data_card = {}
	set_card_zones_visuals()
	# Game-over lock outlives rebuilds: re-strip whatever focus the passes above assigned.
	if board_focus_locked:
		for control : Control in ui_data:
			control.focus_mode = Control.FOCUS_NONE
	_open_show_view_once()
	# The CardVisuals just created queued their add_child via call_deferred; this deferred emit
	# is queued AFTER them (FIFO), so it fires once they're all in-tree and _ready.
	_emit_board_visuals_ready.call_deferred()

func _emit_board_visuals_ready() -> void:
	board_visuals_ready.emit()

func set_card_zones_visuals() -> void:
	#a queued rebuild means the control tree is STALE vs the state arrays — running
	#the visual pass against it can index out of bounds. Flush the rebuild instead
	#(set_card_zones ends with the visual pass anyway).
	if _rebuild_queued:
		flush_rebuild()
		return
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	# Sizing, style overrides, and focus logic per zone; then ONE structural ordering pass over
	# both zones (row-major — see _order_board_cards). Upper zone first, lower second, so
	# lower-zone cards draw over upper.
	update_card_zone_visuals(upper_zone_right, game_state.upper_zone_type, game_state.upper_zone)
	update_grid_zone_visuals(game_state)
	_seed_new_layers(game_state)
	# The Entrance is row -1: its depth is part of the board's geometry, so a rebuild that changed
	# it has to re-measure the floor. This moves the BOARD, never the strip.
	_apply_entrance_strip_height()
	_order_board_cards(game_state)

	# Re-sync now too (not just every physics frame): a caller that reads Entrance geometry
	# (`slot_center_global`) synchronously right after a rebuild, in the SAME frame, must not see
	# a stale track width from before this rebuild's grid changed size.
	_sync_entrance_x()

func set_card_zone(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	# ⚠ **AN ENTRANCE COLUMN *IS* A CELL SLOT** -- same constructor, so it cannot drift from one.
	_fit_children(hbox, type.size(), _create_cell_slot)

	# ⚠ ONE bind path for the whole board: `_bind_stack()` fits the controls, orders them and binds
	# them. A grid cell goes through the same call.
	for i in type.size():
		_bind_stack(hbox.get_child(i) as Control, datas[i].datas, type[i])

## Which `CardVisual` layer a slot control's card belongs in — the Entrance's own pinned layer
## if `c` lives under `upper_zone_right`, the board's otherwise. Walking `c`'s own ancestry (not
## a caller-supplied flag) means every call site stays exactly as it was (REUSE — no new params).
func _target_card_layer(c: Control) -> Node2D:
	var n : Node = c
	while n:
		if n == upper_zone_right: return entrance_card_layer
		n = n.get_parent()
	return card_layer

## Register one board control <-> CardData mapping and carry over (or create) its CardVisual.
func _bind_slot(c: Control, connected_data: CardData) -> void:
	ui_data[c] = connected_data
	data_ui[connected_data] = c
	# Interactivity is a FUNCTION OF THE CURRENT STATE, never a leftover. Board controls are
	# POOLED per slot and rebound to whatever card lands there, so the MOUSE_FILTER_IGNORE
	# grab_cards puts on a held card's control must be re-derived here — otherwise a rebuild
	# that happens while a grab is live (auto-Next folds a Next into try_place) leaves the
	# filter on a control that now belongs to a DIFFERENT card, which becomes permanently
	# uninteractable and survives undo (owner bug report).
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE if connected_data in selected_cards \
			else Control.MOUSE_FILTER_PASS
	var target_layer := _target_card_layer(c)
	# ⚠ **EVERY card on this board hangs from its control's BOTTOM edge**, the Entrance included:
	# the pips are on a card's bottom, so a stack that grew downward buried the very row the player
	# reads. Owner: *"entrance should stack upwards since downwards stacking hides pip row."*
	var bottom := true
	if connected_data in data_card and is_instance_valid(data_card[connected_data]):
		var vis := data_card[connected_data]
		vis.bottom_anchored = bottom
		new_data_card[connected_data] = vis
		vis.control_anchor = c
		# A CARD MOVED BETWEEN LAYERS (Entrance <-> grid — a placement or an undo of one): a
		# pooled visual does not follow its card between layers on its own, so reparent
		# it here. Guarded on a non-null parent: a visual created THIS rebuild is still awaiting
		# its own deferred add_child into its CREATION layer (CardVisual.add_child_card_visual) —
		# reparenting something with no parent yet is an ENGINE ERROR, not a no-op, and it will
		# land correctly in that layer already, so nothing to do until the NEXT rebuild.
		if vis.get_parent() != target_layer and vis.get_parent() != null:
			vis.reparent(target_layer)
	else:
		var fresh := CardVisual.add_child_card_visual(
			target_layer, connected_data, CardVisual.DisplayContext.PLAY_AREA, c)
		fresh.bottom_anchored = bottom
		new_data_card[connected_data] = fresh

## Structural draw order (no z_index anywhere, LAYERING.md), ROW-MAJOR across columns
## (owner spec): per zone, the type/zone headers first, then row 0 of every column,
## then row 1, and so on — upper zone before lower. Cards only overlap WITHIN a column, so this
## renders identically to the old column-major order for the cards themselves, but it makes each
## row CONTIGUOUS in CardLayer: a split prop (hoop) brackets a whole ROW — back half before the
## row's first card (behind every card in the row, above every earlier row), front half after
## its last (in front of the whole row, below the rows beneath). See PropLayer._apply_split.
##
## GUARDED and index-safe by construction: targets are assigned 0,1,2,… in ascending order and
## only to visuals verified IN CardLayer at this moment (each at most once — `seen` dedups in
## case a data ever appears twice), so `desired` < the number of verified children ≤ the child
## count and move_child can never go out of bounds (the old cross-checked counter once crashed
## with "Invalid new child index" during a settings change). Ascending processing also converges
## in ONE pass, and a still board does zero move_childs. Freshly created CardVisuals add_child
## via call_deferred, so they aren't in CardLayer yet — skipped; they append in creation order
## and the next rebuild slots them. Held/selected cards keep their lifted end-of-layer spot
## (grab_cards); prop half nodes drift toward the end and PropLayer re-fixes them next frame.
## ⚠ **TWO LAYERS, TWO INDEPENDENT ORDERINGS.** A `move_child` index only
## means anything inside the layer that holds the child. The Entrance now lives in its OWN
## `EntranceCardLayer`, pinned outside the board's scroll (`_bind_slot`), so its cards can never
## share one ordered list / `seen` set / `pending` flag with the grids' `CardLayer` — a visual
## that is (correctly) parented in the OTHER layer would read as a deferred add that never lands,
## and the reorder would requeue itself every frame until the stack overflowed. Measured, twice.
func _order_board_cards(game_state: GameData) -> void:
	var entrance_ordered : Array[CardVisual] = []
	var entrance_seen : Dictionary[CardVisual, bool] = {}
	var entrance_pending : Array[bool] = [false]
	_append_zone_row_major(entrance_ordered, entrance_seen, entrance_pending, entrance_card_layer,
			game_state.upper_zone_type, game_state.upper_zone)
	_apply_layer_order(entrance_card_layer, entrance_ordered)

	var grid_ordered : Array[CardVisual] = []
	var grid_seen : Dictionary[CardVisual, bool] = {}
	var grid_pending : Array[bool] = [false]
	_append_grids_row_major(grid_ordered, grid_seen, grid_pending, card_layer, game_state.grids)
	_apply_layer_order(card_layer, grid_ordered)

	# Freshly created CardVisuals enter the tree via call_deferred and were skipped above — but
	# their creation order is COLUMN-major, so without a follow-up pass a fresh board keeps the
	# wrong row order until some unrelated rebuild happens (which nothing guarantees: hoop halves
	# then bracketed scattered indices — back arcs behind the row above, owner report).
	# Queue exactly ONE re-order behind the pending add_childs (deferred FIFO: adds run first).
	if (entrance_pending[0] or grid_pending[0]) and not _reorder_queued:
		_reorder_queued = true
		_deferred_reorder.call_deferred()

## Apply one layer's ordering with `move_child` calls confined to THAT layer alone.
func _apply_layer_order(layer: Node2D, ordered: Array[CardVisual]) -> void:
	for i : int in ordered.size():
		var vis := ordered[i]
		if vis.get_index() != i:
			layer.move_child(vis, i)

var _reorder_queued := false

func _deferred_reorder() -> void:
	_reorder_queued = false
	var game := CardEnvironment.get_current_game()
	if game: _order_board_cards(game.state)

## Append one zone's CardVisuals in row-major order, scoped to `layer`: headers (row -1), then
## each row across all columns (ragged columns simply skip the rows they don't have). `pending[0]`
## flips true when a visual belongs in `layer` but is not yet parented there (deferred add still
## in flight) — the caller re-orders once it lands.
func _append_zone_row_major(out: Array[CardVisual], seen: Dictionary[CardVisual, bool],
		pending: Array[bool], layer: Node2D, type: Array[CardData],
		datas: Array[ArrayCardData]) -> void:
	var max_rows := 0
	for col : ArrayCardData in datas:
		max_rows = maxi(max_rows, col.datas.size())
	for data : CardData in type:
		_append_ordered_visual(out, seen, pending, layer, data)
	for z : int in max_rows:
		for i : int in datas.size():
			if z < datas[i].datas.size():
				_append_ordered_visual(out, seen, pending, layer, datas[i].datas[z])

## The grid half of the board's draw order, mirroring `_append_zone_row_major`, scoped to `layer`:
## a cell's zone card first, then the stacks height-major, so a card always draws OVER the cell it
## sits on and a whole height layer stays contiguous for PropLayer's brackets.
##
## ⚠ Without this, grid cards were never assigned an index at all -- they kept creation order, and
## a cell frame rebuilt after its card drew on top of it.
func _append_grids_row_major(out: Array[CardVisual], seen: Dictionary[CardVisual, bool],
		pending: Array[bool], layer: Node2D, grids: Array[GridData]) -> void:
	for grid : GridData in grids:
		if not grid: continue
		for data : CardData in grid.cell_types:
			_append_ordered_visual(out, seen, pending, layer, data)
		var max_h := 0
		for cell : ArrayCardData in grid.cells:
			max_h = maxi(max_h, cell.datas.size())
		for h : int in max_h:
			for ci : int in grid.cells.size():
				if h < grid.cells[ci].datas.size():
					_append_ordered_visual(out, seen, pending, layer, grid.cells[ci].datas[h])

func _append_ordered_visual(out: Array[CardVisual], seen: Dictionary[CardVisual, bool],
		pending: Array[bool], layer: Node2D, data: CardData) -> void:
	if data in selected_cards: return   # held cards stay lifted at the layer's end
	var vis : CardVisual = data_card.get(data)
	if vis == null or not is_instance_valid(vis): return
	if vis.get_parent() != layer:
		pending[0] = true   # deferred add still in flight; re-order once it lands
		return
	if vis in seen: return
	seen[vis] = true
	out.append(vis)

func update_card_zone_visuals(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	for i in type.size():
		_size_stack_slot(hbox.get_child(i) as Control)

	# ⚠ S16: the loop above resets every strip to its stacked height, so a rebuild that lands mid-act
	# would slam an open row shut. Re-push the live openings over the top of it.
	_apply_row_openings()

	# 3. Focus neighborhood linking
	for i in type.size() - 1:
		var left: Control = hbox.get_child(i).get_child(0)
		var right: Control = hbox.get_child(i+1).get_child(0)
		left.focus_neighbor_right = right.get_path()
		right.focus_neighbor_left = left.get_path()

	# ⚠ **THE BESPOKE HELD/SELECTED WIDENING IS GONE, BY OWNER RULING.** It reached into this
	# container by fixed child index (`get_child(0)` / `get_child(1)` / `get_child(-1)`), which the
	# reversal above inverts, and it was a second highlight mechanism beside the one every other
	# card on the board already uses. `on_control_focus_entered()`'s widening is now the only one.
	# ⚠ The look when picking a card up from the Entrance CHANGES; that is the ruling, not a bug.

# ==============================================================================
# S20b — THE GRID BOARD
#
# One `GridPanel` per grid, each holding a Godot `GridContainer` of `CellSlot`s. A cell slot is
# built exactly like a zone column: child 0 is the cell's own zone card, children 1..n are the
# cards stacked in it. That is deliberate — it is the same shape `set_card_zone` builds, so the
# binding, the pooling, the focus wiring and the `CardVisual` creation are all the existing ones.
#
# ⚠ THE CELLS ARE CONTROLS; THE CARDS ARE NOT. A Godot container overwrites its children's
# position and size, so a `CardVisual` can never live in one — it stays in `%CardLayer`,
# positioned by arithmetic. That is what lets a springing card overlap the row above without the
# board re-flowing, and it is why this mirrors the container rather than reading it.
# ==============================================================================

## Builds one panel per grid, in lockstep with the grid list, and one cell slot per cell.
func set_grid_zones(game_state: GameData) -> void:
	var wanted := game_state.grids.size()
	var removed := _removed_grid_index(game_state.grids)
	var diff := wanted - grid_container.get_child_count()
	if diff > 0:
		for _i : int in diff:
			grid_container.add_child(_create_grid_panel())
	elif diff < 0:
		for _i : int in absi(diff):
			var doomed : Node = grid_container.get_child(-1)
			grid_container.remove_child(doomed)
			doomed.queue_free()
	for gi : int in wanted:
		_bind_grid_panel(grid_container.get_child(gi) as Control, game_state.grids[gi])
	_bound_grids.assign(game_state.grids)
	if removed != NO_GRID: _on_grid_removed(removed)
	# ⚠ A GRID ARRIVING MOVES THE RESTING POSITION AS SURELY AS ONE LEAVING: the board is wider and
	# its middle is somewhere else, so a board left where it was is a board off its rest.
	elif diff > 0: rest_board()

## The grid list as it was at the last rebuild. The panels are bound by POSITION, so without this
## nothing can tell a grid that was REMOVED from one that merely shifted left into its place.
var _bound_grids : Array[GridData] = []

## Which bound grid is no longer on the board, or `NO_GRID`. Grids go one at a time, so the first
## one missing is the one that went.
func _removed_grid_index(grids: Array[GridData]) -> int:
	if grids.size() >= _bound_grids.size(): return NO_GRID
	for i : int in _bound_grids.size():
		var grid : GridData = _bound_grids[i]
		if grid and not grids.has(grid): return i
	return NO_GRID

## Where the view goes when the grid it was on is removed: the NEAREST survivor, the LEFT one when
## both neighbours are equally near. They always are — so this is the left neighbour, except when
## the board's first grid went and there is none.
func _nearest_surviving_grid(removed: int) -> int:
	return clampi(removed - 1, 0, grid_container.get_child_count() - 1)

## Keep the view honest on a board that just lost a grid: every index right of the hole shifts left,
## a view that was ON that grid moves to the nearest survivor, and the board re-centres either way.
## ⚠ **THE RE-CENTRE IS NOT CONDITIONAL ON THE REFOCUS** — a grid removed elsewhere on the board
## still leaves the remaining grids sitting off centre.
## ⚠ **EVERY INDEX THIS SCREEN REMEMBERS IS FIXED UP HERE, INCLUDING FORWARD'S.** They are indices,
## so a survivor slides into the hole and any one left alone silently names a DIFFERENT grid.
## The view and the arrow cursor both take the NEAREST SURVIVOR, preferring the one to the left, so
## the board cannot re-centre on one grid while the cursor sits on another (owner ruling).
## Forward's memory is the exception to that rule: the view it would return to no
## longer exists, so it is cleared and Forward falls through to the wall rather than returning to a
## grid the player never left.
func _on_grid_removed(removed: int) -> void:
	if grid_container.get_child_count() == 0: return
	if pan_grid > removed: pan_grid -= 1
	elif pan_grid == removed: pan_grid = _nearest_surviving_grid(removed)
	if _zoom_out_grid > removed: _zoom_out_grid -= 1
	elif _zoom_out_grid == removed: _zoom_out_grid = NO_GRID
	if selected_grid > removed: selected_grid -= 1
	elif selected_grid == removed: selected_grid = _nearest_surviving_grid(removed)
	if view_mode == ViewMode.FOCUSED and focused_grid != NO_GRID:
		if focused_grid == removed:
			focus_grid(_nearest_surviving_grid(removed))
		elif focused_grid > removed:
			_set_view(view_mode, focused_grid - 1)
	_recentre_board()

## True while a re-centre is waiting for the board to stop re-laying out, so a second removal in
## the same breath does not start a second wait.
var _recentre_waiting := false

## Re-centre on whichever grid the view is on, animated over the pan clock — the player's own pan,
## reused, so a removal moves the board exactly the way a pan key does.
##
## ⚠ **AIM ONLY ONCE THE PANELS HAVE STOPPED MOVING.** Losing a grid re-lays the board out over
## several frames — panel positions, the shared width and the scroll range all settle separately —
## and a pan aimed at where the grids WERE lands short of centre (measured: 118 px, half a grid).
## The wait is capped at the pan clock so a board that never settles still re-centres.
func _recentre_board() -> void:
	pan_grid = clampi(pan_grid, 0, grid_container.get_child_count() - 1)
	if _recentre_waiting: return
	_recentre_waiting = true
	var last := Vector3(INF, INF, INF)
	var waited := 0.0
	while waited < PlayArea.settings().grid_pan_duration:
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(grid_container):
			_recentre_waiting = false
			return
		waited += get_process_delta_time()
		var now := _recentre_probe()
		if now.is_equal_approx(last): break
		last = now
	_recentre_waiting = false
	pan_to_grid(pan_grid)
	# ⚠ **AIM TWICE: A BOARD SITTING AT SCROLL ZERO LIES ABOUT WHERE IT IS.** At exactly zero the
	# scroll container still holds the half-margin it centred the content with while the board fitted
	# (measured: 4 px), and it drops it the moment the scroll moves — so an aim taken from rest lands
	# 4 px short and stays there, no matter how long it waited for the layout. One frame in, the board
	# is on its true line and the second aim corrects the same motion, mid-flight, invisibly.
	await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(grid_container): pan_to_grid(pan_grid)

## What "the board has stopped moving" means to a re-centre: where the centred grid sits INSIDE the
## board, how wide the board is, and how far the view can scroll. ⚠ All three are read relative to
## the board, never in screen space — the scroll's own easing moves screen space every frame, so a
## probe that read it could never come to rest.
func _recentre_probe() -> Vector3:
	if pan_grid < 0 or pan_grid >= grid_container.get_child_count(): return Vector3.ZERO
	var cells := _cells_root(grid_container.get_child(pan_grid) as Control)
	if not cells: return Vector3.ZERO
	var bar := scroll_container.get_h_scroll_bar()
	var reach : float = bar.max_value if bar else 0.0
	return Vector3(cells.global_position.x - grid_container.global_position.x,
			grid_container.size.x, reach)

## **ONE GRID PER GRID POSITION: THE PITCH BETWEEN TWO CELL BLOCKS IS ONE BLOCK PLUS ONE BUFFER.**
## The picture holds `grid_max_count` grids side by side, each its own position, so spacing the
## panels at that pitch is what places them edge to edge with just the buffer between -- never the
## whole picture's width, which would scatter them across empty board. The buffer itself is
## `isolating_grid_buffer_px()`, DERIVED so a FOCUSED grid isolates its neighbours.
## Each panel carries score gutters either side of its cells (row labels left, the special-meld
## label right); those gutters sit INSIDE the buffer rather than adding to the board's width, so a
## wider label never widens the board. The container's own separation is therefore the buffer LESS
## the gutters it has to absorb. Where panels' gutters differ, the WIDEST pair sets it, so no two
## cell blocks are ever closer than the buffer.
##
## ⚠ THE SEPARATION IS RAW, NOT DIVIDED BY THE ZOOM: it grows on screen with `board_zoom`, the
## same as every other authored length on the board -- that growth IS the isolating mechanism
## `isolating_grid_buffer_px()` solves for, so dividing it back out would defeat the derivation.
##
## ⚠ Measured every frame, not once: a score label appearing changes a gutter's width, and grids
## laid out against a stale gutter sit at the wrong pitch. The override is written only when the
## value actually changes, so a settled board stops re-sorting. Safe against the feedback the
## per-panel floor code hit -- every quantity here is panel-RELATIVE, and the container's own
## separation does not move a panel's cells inside it.
## The widest score gutter on each side, in BOARD (design) px -- divided by the zoom, since the
## positions they are measured from are screen ones. `Vector2.ZERO` while no panel carries cells yet.
func _grid_gutters() -> Vector2:
	var left := 0.0
	var right := 0.0
	var z := maxf(board_zoom, 0.0001)
	for i : int in grid_container.get_child_count():
		var panel := grid_container.get_child(i) as Control
		if not panel: continue
		var cells := _cells_root(panel)
		if not cells: continue
		left = maxf(left, (cells.global_position.x - panel.global_position.x) / z)
		right = maxf(right, panel.global_position.x / z + panel.size.x
				- (cells.global_position.x / z + cells.size.x))
	return Vector2(left, right)

func _apply_grid_buffer() -> void:
	if not is_instance_valid(grid_container) or grid_container.get_child_count() == 0: return
	var gutters := _grid_gutters()
	var buffer := isolating_grid_buffer_px(PlayArea.settings())
	var wanted := roundi(maxf(buffer - gutters.x - gutters.y, 0.0))
	if grid_container.get_theme_constant(&"separation") == wanted: return
	grid_container.add_theme_constant_override("separation", wanted)

## The screen-independent distance from one grid panel's cell block centre to the next -- ONE BLOCK
## PLUS THE ACTUAL APPLIED BUFFER (the rounded container separation plus the gutters it absorbed),
## never `isolating_grid_buffer_px()`'s own unrounded value: the camera step this feeds has to land
## on the panel `_apply_grid_buffer()` actually placed, not the buffer it rounded away from.
func grid_pitch_px() -> float:
	var block := grid_block_size_px(PlayArea.settings(), GridData.new())
	if not is_instance_valid(grid_container) or grid_container.get_child_count() == 0:
		return block.x + isolating_grid_buffer_px(PlayArea.settings())
	var gutters := _grid_gutters()
	var wanted := float(grid_container.get_theme_constant(&"separation"))
	return block.x + wanted + gutters.x + gutters.y

## A panel: a positioning node that draws nothing, holding the cell grid.
func _create_grid_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "GridPanel"
	# Grids are aligned by their BOTTOM edges: every grid sits on the same floor and grows
	# upward independently, which is what the board growing up out of the Entrance means. With
	# cross-grid row alignment off (the default) the bottom edge is the ONLY thing that lines up.
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Stated for the same reason the cell slots state it: this board's fixed edge is the bottom.
	panel.alignment = BoxContainer.ALIGNMENT_END
	# ⚠ **ONE CONTAINER PER ROW, NOT ONE GRID FOR THE WHOLE PANEL** (owner spec). A `GridContainer`
	# gives every cell in a row the row's full height, so a cell has nothing to bottom-align
	# against and a deep stack bleeds into the row above. A row of its own is the same shape the
	# original play area used for a zone — an HBox of columns — just turned through 90 degrees:
	# each row is independent, each cell shrinks to its own stack, and every cell in a row is
	# bottom-aligned inside it, which is what keeps a row's zone cards on ONE y.
	panel.add_theme_constant_override("separation", separation)
	# ⚠ **THE SCORE GUTTERS LIVE IN THE PANEL AROUND THE CELLS.** Row labels LEFT (`Q107`=a),
	# column labels BELOW (`Q108`, which the flip inverted), and ONE special-meld label to the
	# RIGHT centred on the grid (`Q110`: *"a single label to the right of the grid aligned with
	# center of the grid, opposite side of row labels"*). Everything that walks ROWS goes through
	# `_cells_root`, so a lookup can never read a gutter as a row.
	var board := HBoxContainer.new()
	board.name = "Board"
	board.add_theme_constant_override("separation", separation)
	var row_labels := VBoxContainer.new()
	row_labels.name = "RowLabels"
	row_labels.add_theme_constant_override("separation", separation)
	row_labels.alignment = BoxContainer.ALIGNMENT_END
	# ⚠ Takes its OWN height at the top of the row, not the whole row's. Its stacks already mirror
	# the cell rows, so its own minimum IS the cell block's height and its bottom edge lands on the
	# cells' -- which stays true now that the column labels have made `Board` taller than `Cells`.
	row_labels.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	board.add_child(row_labels)
	# ⚠ **THE COLUMN LABELS ARE A SIBLING OF THE CELLS, IN THE CELLS' OWN COLUMN.** That is what
	# puts a column's label under that column: the container does it, and nothing measures or
	# maintains an indent. As a bare child of the panel they began at the PANEL's left edge, which
	# is the row gutter's edge, and every label sat most of a column left of the column it names.
	var cells_column := VBoxContainer.new()
	cells_column.name = "CellsColumn"
	cells_column.add_theme_constant_override("separation", separation)
	board.add_child(cells_column)
	var cells := VBoxContainer.new()
	cells.name = "Cells"
	cells.add_theme_constant_override("separation", separation)
	cells.alignment = BoxContainer.ALIGNMENT_END
	cells_column.add_child(cells)
	var special := BigNumberLabel.new()
	special.name = "SpecialLabel"
	special.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	board.add_child(special)
	panel.add_child(board)
	var col_labels := HBoxContainer.new()
	col_labels.name = "ColLabels"
	col_labels.add_theme_constant_override("separation", separation)
	cells_column.add_child(col_labels)
	# ⚠ **`resized` IS NOT ENOUGH, AND THE CLAIM THAT IT COVERS POSITION WAS FALSE.** `resized`
	# fires on SIZE changes only; a panel shoved up or sideways by a sibling — which is exactly
	# what happens to a bottom-aligned panel when the board grows — changes POSITION with no size
	# change at all, and the cache silently kept the old line. Measured: a cached bottom of 574
	# against a real 554, one whole depth pitch stale, which read as the board growing DOWNWARD.
	# `item_rect_changed` is the signal that covers both.
	panel.item_rect_changed.connect(_publish_grid_panel_origin.bind(panel))
	panel.sort_children.connect(_publish_grid_panel_origin.bind(panel))
	return panel

## One row of a grid: an HBox of cells, the same shape the original play area gave a zone.
func _create_grid_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "GridRow"
	row.add_theme_constant_override("separation", separation)
	# Rows keep their own width centred on the panel, like the panel does on the board.
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return row

## One cell: a VBox holding its stack. ⚠ **BOTTOM-ALIGNED INSIDE ITS ROW** — this is the whole
## reason a row is its own HBox. The row is as tall as its deepest cell, and every shallower cell
## shrinks to its own stack and sits on the row's bottom line, so a row's zone cards are ALWAYS on
## one y no matter how uneven the stacks are.
func _create_cell_slot() -> Control:
	var slot := VBoxContainer.new()
	slot.name = "CellSlot"
	# ⚠ **NO SEPARATION; EACH CARD CARRIES ITS OWN GAP** -- see `update_grid_zone_visuals()`, which
	# is where the reason lives. Set here as well so the authored value is not a different number
	# from the one the board actually runs on.
	slot.add_theme_constant_override("separation", 0)
	slot.size_flags_vertical = Control.SIZE_SHRINK_END
	# ⚠ **STATED, NOT LEFT TO THE DEFAULT.** The slot shrinks to its own stack today, so packing
	# from the top is invisible -- but a board that grows UPWARD wants the bottom edge to be the
	# fixed one, and a stack that ever gets surplus height must not drift off its row's line. The
	# label gutters had exactly this bug from exactly this default.
	slot.alignment = BoxContainer.ALIGNMENT_END
	return slot

## Grows or truncates `parent`'s children to exactly `wanted`, building new ones with `make`.
## The same add/remove-from-the-end shape `set_card_zone` uses for a zone's columns.
func _fit_children(parent: Node, wanted: int, make: Callable) -> void:
	var diff := wanted - parent.get_child_count()
	if diff > 0:
		for _i : int in diff:
			parent.add_child(make.call() as Node)
	elif diff < 0:
		for _i : int in absi(diff):
			var doomed : Node = parent.get_child(-1)
			parent.remove_child(doomed)
			doomed.queue_free()

## The slot for grid cell index `ci`, found through its row. Cells are row-major in the data, so
## the row is `ci / width` and the column `ci % width`.
## Fills a grid's score gutters from its buckets. ⚠ **EVERY (index, height) ENTRY GETS A LABEL**
## (GAP-015, owner: *"each will need to be tracked and displayed ... so row could display 10 scores
## if 5 rows each with 2 height cards at 0 and 1"*), and the heights **stack in the same order as
## the cards they describe**: a row's height-0 label beside its height-0 cards, height-1 above it.
##
## ⚠ That is why a row's labels are their own VBox built exactly like a `CellSlot` — bottom-aligned,
## `h` rising — rather than one label per row. Laying them out any other way would put a height-1
## score beside height-0 cards, which is the one thing the owner's wording pins down.
func _bind_grid_score_labels(panel: Control, grid: GridData) -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var gi := panel.get_index()
	var state := game.state
	var board := panel.get_node_or_null("Board") as Control
	if not board: return
	var col_levels := state.line_score_levels(state.scores_col, gi)

	var row_labels := board.get_node_or_null("RowLabels") as Control
	if row_labels:
		_fit_children(row_labels, grid.grid_height, _create_label_stack)
		for ry : int in grid.grid_height:
			_fill_label_stack(row_labels.get_child(ry) as VBoxContainer, state.scores_row,
					gi, ry, _row_score_levels(state.scores_row, gi, ry), true)
	var col_labels := panel.get_node_or_null("Board/CellsColumn/ColLabels") as Control
	if col_labels:
		_fit_children(col_labels, grid.grid_width, _create_label_stack)
		for cx : int in grid.grid_width:
			_fill_label_stack(col_labels.get_child(cx) as VBoxContainer, state.scores_col,
					gi, cx, col_levels, false)
	var special := board.get_node_or_null("SpecialLabel") as BigNumberLabel
	if special:
		# ⚠ **THE SPECIAL LABEL NEEDS A BOX OR IT IS NOT A SCORE LABEL.** With none it shrank to
		# whatever its own text measured and `AutosizeLabel` pinned its font at the minimum. It is
		# the row gutter's mirror on the far side of the cells, so it takes the row gutter's box.
		special.custom_minimum_size = Vector2(CardVisual.card_size_play.x, _depth_pitch_px())
		# ⚠ Right-aligned like the ROW gutter, NOT mirrored (owner, reversing an earlier call):
		# leaning it toward the cells made it read as belonging to whichever row it sat beside.
		special.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# ⚠ ONE label for every diagonal and every future non-directional meld — the owner's Q110
		# ruling, and the bucket really is one in the data too.
		var value : BigNumber = state.score_special[gi] if gi < state.score_special.size() else null
		if value: special.current_num = value
		else: special.text = ""

## One depth layer's pitch in BOARD units: the strip a covered card shows plus the gap above it.
## The ONE place a score gutter and the cells agree about how far apart two heights are.
func _depth_pitch_px() -> float:
	return float(CardVisual.card_separation_play_custom) + float(separation)

## Give every score label on a grid ONE font size: the smallest any of them would pick for its own
## box and its own text.
##
## ⚠ **EQUAL BOXES ARE NOT ENOUGH.** `AutosizeLabel` fits its font to its own TEXT as well as its
## box, so a four-digit row score and a two-digit column score in identical boxes still render at
## different sizes. The owner's rule is that the set reads as one set, which is a property of the
## GROUP and cannot be decided by any label alone.
##
## ⚠ **ASKING DOES NOT DEPEND ON THE ANSWER.** `best_font_size()` measures against
## `custom_minimum_size`, which the container hands back unchanged whatever font is applied, so
## this cannot oscillate. Written only on change, so a settled board stops re-sorting.
func _sync_score_label_font() -> void:
	if not is_instance_valid(grid_container): return
	for gi : int in grid_container.get_child_count():
		var panel := grid_container.get_child(gi) as Control
		if not panel: continue
		var labels := _score_labels_of(panel)
		if labels.is_empty(): continue
		var smallest := 0x7FFFFFFF
		for label : BigNumberLabel in labels:
			if label.text.is_empty(): continue
			smallest = mini(smallest, label.best_font_size())
		if smallest == 0x7FFFFFFF: continue
		for label : BigNumberLabel in labels:
			label.force_font_size(smallest)

## Every score label a grid panel carries: the row gutter, the column gutter and the one special
## label. NOT the per-cell height labels, which live in the card layer and are positioned by
## arithmetic rather than by this panel.
func _score_labels_of(panel: Control) -> Array[BigNumberLabel]:
	var out : Array[BigNumberLabel] = []
	var board := panel.get_node_or_null("Board") as Control
	if not board: return out
	for gutter_path : String in ["RowLabels", "CellsColumn/ColLabels"]:
		var gutter := board.get_node_or_null(gutter_path) as Control
		if not gutter: continue
		for stack : Node in gutter.get_children():
			for label : Node in stack.get_children():
				var l := label as BigNumberLabel
				if l: out.append(l)
	var special := board.get_node_or_null("SpecialLabel") as BigNumberLabel
	if special: out.append(special)
	return out

## Keep every row-label stack exactly as tall as the cell row it names.
##
## ⚠ **PER TICK, BECAUSE A ROW'S HEIGHT IS A FUNCTION OF TIME WHILE A LAYER IS ARRIVING.** The
## stacks take their height at bind time, and anything that binds mid-growth -- a score popping its
## own label, for one -- latched whatever fraction the ease had reached. The cells then finished
## growing and the gutter did not, leaving every row label sitting below the row it belongs to.
## Written only on change, so a settled board stops re-sorting.
func _sync_row_label_heights() -> void:
	if not is_instance_valid(grid_container): return
	for gi : int in grid_container.get_child_count():
		var panel := grid_container.get_child(gi) as Control
		if not panel: continue
		var board := panel.get_node_or_null("Board") as Control
		var row_labels := board.get_node_or_null("RowLabels") as Control if board else null
		if not row_labels: continue
		for ry : int in row_labels.get_child_count():
			var stack := row_labels.get_child(ry) as Control
			var wanted := _grid_row_height(gi, ry)
			if is_equal_approx(stack.custom_minimum_size.y, wanted): continue
			stack.custom_minimum_size = Vector2(CardVisual.card_size_play.x, wanted)

## Pop the ONE score label a grid line just banked into, the way a legacy gutter label pops.
##
## ⚠ **THE LABELS ARE RE-BOUND FIRST.** A line scoring at a height nothing has reached before has
## no label yet, and a pop on a label that does not exist is a silently dropped animation — which
## is what "the scores are not popping up" looked like from the outside.
func pop_grid_score_label(section: ScoringSection) -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var gi := section.grid
	if gi < 0 or gi >= grid_container.get_child_count() or gi >= game.state.grids.size(): return
	var grid : GridData = game.state.grids[gi]
	if not grid: return
	var panel := grid_container.get_child(gi) as Control
	_bind_grid_score_labels(panel, grid)
	_sync_cell_score_labels()
	var label := _grid_score_label(panel, section)
	if label: label.anim_pop()

## The score label a section banks into, or null when it has none yet.
func _grid_score_label(panel: Control, section: ScoringSection) -> BigNumberLabel:
	var board := panel.get_node_or_null("Board") as Control
	if not board: return null
	match section.kind:
		ScoringSection.LineKind.DIAG:
			return board.get_node_or_null("SpecialLabel") as BigNumberLabel
		ScoringSection.LineKind.ROW:
			return _label_in_stack(board.get_node_or_null("RowLabels") as Control,
					section.index, section.height)
		ScoringSection.LineKind.COL:
			return _label_in_stack(panel.get_node_or_null("Board/CellsColumn/ColLabels") as Control,
					section.index, section.height)
		ScoringSection.LineKind.HEIGHT_V:
			return _cell_score_labels.get(Vector3i(panel.get_index(), section.cell.x,
					section.cell.y))
	return null

## Height `h`'s label inside gutter stack `index`. ⚠ **A STACK IS BUILT HIGHEST FIRST**, so height
## 0 is the LAST child, not the first — the same order `_fill_label_stack` writes them in.
func _label_in_stack(gutter: Control, index: int, h: int) -> BigNumberLabel:
	if not gutter or index < 0 or index >= gutter.get_child_count(): return null
	var stack : Control = gutter.get_child(index)
	var i := stack.get_child_count() - 1 - h
	if i < 0 or i >= stack.get_child_count(): return null
	return stack.get_child(i) as BigNumberLabel

## THAT ROW's own score-level count, not the grid-wide max `state.line_score_levels` returns —
## a shallow row must never get surplus fixed-height children forcing it past `_grid_row_height`.
func _row_score_levels(bucket: Dictionary[Vector3i, BigNumber], gi: int, ry: int) -> int:
	var deepest := -1
	for key : Vector3i in bucket:
		if key.x == gi and key.y == ry: deepest = maxi(deepest, key.z)
	return deepest + 1

## One line's labels: a VBox of one label per height, built like a `CellSlot` so the stack reads
## in the same direction the cards do.
func _create_label_stack() -> Control:
	var stack := VBoxContainer.new()
	stack.name = "LabelStack"
	# ⚠ **NO SEPARATION; EACH LABEL CARRIES THE DEPTH PITCH ITSELF.** A stack's pitch has to equal
	# the CARD depth pitch exactly or the scores fan away from the cards they name -- measured, a
	# label 20 px tall plus a 4 px separation walked 6.5 px per level off a 32.7 px card pitch, so
	# height 2's score sat 14.7 px above its pip row while height 0's sat on it. The same shape the
	# cell slots use, for the same reason.
	stack.add_theme_constant_override("separation", 0)
	stack.size_flags_vertical = Control.SIZE_SHRINK_END
	# ⚠ **BOTTOM-ALIGNED, LIKE THE CARDS BESIDE IT.** `alignment` was simply left at its default of
	# BEGIN, so a stack as tall as its row packed its scores against the row's TOP edge -- the old
	# pre-grid position, and 37 px (60.5 at the focused zoom) above the pip row they name. The
	# label pitch already equals the card depth pitch, so aligning the group to the bottom lines
	# up EVERY height at once rather than only the first.
	stack.alignment = BoxContainer.ALIGNMENT_END
	return stack

## ⚠ **HIGHEST HEIGHT FIRST**, so the column reads bottom-up exactly like the cards beside it: the
## last child is height 0, level with the height-0 cards, and each earlier child is one level up.
## ⚠ **A ROW STACK'S OWN MINIMUM HEIGHT FOLLOWS `_grid_row_height`, THE CELLS' MEASURED HEIGHT** —
## the cell block is authoritative, so the label gutter's row `ry` is only ever as tall as cell row
## `ry` actually is (never a fixed per-level size), and it tracks an easing row through the ease the
## same way `_grid_row_height` already does for the cells. Column stacks stay levels-sized: a column's
## width never varies by data the way a row's height does.
## Row labels expand to fill the stack's already-authoritative height (never grow it) so their
## text has real room to sit at the bottom, level with the pip row on a card's bottom edge.
func _fill_label_stack(stack: VBoxContainer, bucket: Dictionary[Vector3i, BigNumber],
		gi: int, index: int, levels: int, is_row: bool) -> void:
	if not stack: return
	_fit_children(stack, maxi(levels, 1), _create_score_label)
	var game := CardEnvironment.get_current_game()
	if not game: return
	for i : int in stack.get_child_count():
		var h := stack.get_child_count() - 1 - i   # child 0 is the HIGHEST height
		var label : BigNumberLabel = stack.get_child(i)
		# ⚠ **ONE WIDTH FOR EVERY SCORE LABEL** (owner: *"all score labels should be same size as
		# each other"*). `AutosizeLabel` fits its font to its own box, so a 16 px row gutter and a
		# 40 px column gutter rendered the same number at 8 px and 14 px. The heights still differ
		# by kind: a row label's is the depth strip, because its stack's pitch has to match the
		# cards'.
		label.custom_minimum_size = Vector2(CardVisual.card_size_play.x, _depth_pitch_px())
		# ⚠ **EACH GUTTER LEANS TOWARD THE CELLS IT DESCRIBES** (owner). The row gutter sits LEFT of
		# the grid, so its numbers are right-aligned, hard against the cells; the column gutter sits
		# under its columns, so its numbers are centred on them.
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if is_row 				else HORIZONTAL_ALIGNMENT_CENTER
		var key := Vector3i(gi, index, h)
		if bucket.has(key): label.current_num = bucket[key]
		else: label.text = ""
	if is_row:
		stack.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
				_grid_row_height(gi, index))

func _create_score_label() -> Control:
	return BigNumberLabel.new()

## The node holding a grid's ROW containers. ⚠ Everything that walks rows goes through here: the
## panel also carries score gutters, and a lookup that indexed the panel directly would silently
## start reading a gutter as a row.
func _cells_root(panel: Control) -> Control:
	var board := panel.get_node_or_null("Board") as Control
	return board.get_node_or_null("CellsColumn/Cells") as Control if board else null

func _cell_slot(panel: Control, grid: GridData, ci: int) -> VBoxContainer:
	var w := maxi(grid.grid_width, 1)
	var ry := ci / w
	var cx := ci % w
	var cells := _cells_root(panel)
	if not cells or ry < 0 or ry >= cells.get_child_count(): return null
	var row : Control = cells.get_child(ry)
	if cx < 0 or cx >= row.get_child_count(): return null
	return row.get_child(cx) as VBoxContainer

## Caches one grid panel's resolved global origin, so `slot_center_global` can read it instead of
## the panel's rect. Keyed by the panel's CURRENT index (see `_grid_panel_origin`'s own comment for
## why that index is stable).
func _publish_grid_panel_origin(panel: Control) -> void:
	_grid_panel_origin[panel.get_index()] = panel.global_position


## Fills one panel with `grid_width * grid_height` cell slots and binds every card in them.
## The cell count comes from the DATA, never from a hard-coded 5.
func _bind_grid_panel(panel: Control, grid: GridData) -> void:
	if not grid: return
	var cells := _cells_root(panel)
	if not cells: return
	_fit_children(cells, grid.grid_height, _create_grid_row)
	_bind_grid_score_labels(panel, grid)
	for ry : int in grid.grid_height:
		var row : HBoxContainer = cells.get_child(ry)
		row.add_theme_constant_override("separation", separation)
		_fit_children(row, grid.grid_width, _create_cell_slot)
	var wanted := grid.cells.size()
	for ci : int in wanted:
		var slot : VBoxContainer = _cell_slot(panel, grid, ci)
		if not slot: continue
		_bind_stack(slot, grid.cells[ci].datas, grid.cell_types[ci])

## Sizes every cell slot. An EMPTY cell takes a FULL card's worth, so a grid is a complete block
## of card-sized slots from the moment it is built and never changes shape as it fills; a covered
## card shows exactly `CARD_SEPARATION` of itself and the top card of a stack shows whole.
func update_grid_zone_visuals(game_state: GameData) -> void:
	for gi : int in mini(game_state.grids.size(), grid_container.get_child_count()):
		var grid : GridData = game_state.grids[gi]
		if not grid: continue
		var panel : Control = grid_container.get_child(gi)
		panel.add_theme_constant_override("separation", separation)
		for ci : int in grid.cells.size():
			var slot : VBoxContainer = _cell_slot(panel, grid, ci)
			if slot: _size_stack_slot(slot)

func create_card_control() -> Control:
	var new_control := Control.new()
	new_control.add_to_group("CardVisualControl")
	new_control.focus_mode = Control.FOCUS_ALL
	new_control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	new_control.focus_entered.connect(func()->void:on_control_focus_entered(new_control))
	# ARROW KEYS ARE READ HERE, on the focused cell itself — see `_on_cell_gui_input` for why
	# `_unhandled_input` is too late.
	new_control.gui_input.connect(func(e: InputEvent)->void:_on_cell_gui_input(e, new_control))
	new_control.mouse_entered.connect(func()->void:
			new_control.grab_focus()
			moused_hovered_control = new_control)
	new_control.mouse_exited.connect(func()->void:
			if moused_hovered_control == new_control:
				moused_hovered_control = null
				# hover-driven inspector hides with the hover (keyboard re-focus re-shows it)
				if focused_control == new_control: hide_focus_info())
	return new_control

var focused_visual : CardVisual
func on_control_focus_entered(control:Control) -> void:
	flush_rebuild() #reads ui_data / data_card
	# ONE CURSOR FOR BOTH INPUT MODES: whatever moved the board focus onto a grid — mouse hover,
	# arrows, a click — is also what the overview's Enter will focus.
	var focus_grid_index := _grid_index_of(control)
	if focus_grid_index != NO_GRID: selected_grid = focus_grid_index
	if focused_visual: focused_visual.focused = false
	if ui_data.has(control) and data_card.has(ui_data[control]):
		focused_visual = data_card[ui_data[control]]
		focused_visual.focused = true
	# Card inspector for EVERY input mode (mouse hover grabs focus too, so focus is the one
	# unified hover signal). NOT Control.tooltip_text: the native tooltip is a popup Window
	# that sat under the cursor and blocked clicks — this panel is pure display (IGNORE).
	# ⚠ Two gates, and they are different questions. In Info mode this panel ALWAYS yields: the
	# wall's card is the one description system, and two panels describing the same card is what
	# having a single info card replaced. Outside Info mode `wall_screen_popups` decides whether a
	# description is available at all.
	if ui_data.has(control) and _popups_allowed():
		_show_focus_info(control, ui_data[control])
	else:
		hide_focus_info()

	# ⚠ **HOVER DOES NOT RESIZE THE STACK, AND ESPECIALLY NOT ITS ZONE CARD.** This used to hand-size
	# controls by fixed child index on every focus -- written when child 0 was the zone header and
	# child -1 the newest card. The board stacks upward now and that order is REVERSED, so
	# `get_child(-1)` names the ZONE card: hovering set it to a full card's height and the zone
	# visibly dipped DOWN under the card being hovered. Owner: *"stacking cards on a zone should not
	# cause the zone to move relative to grid."*
	# ⚠ It was also a second sizing mechanism beside `_size_stack_slot()`, which `set_card_zones_visuals()`
	# runs immediately below and which is the ONE place a stack's controls are sized.
	focused_control = control
	set_card_zones_visuals()

# ==============================================================================
# FOCUS CARD INSPECTOR — THE card-text surface for every input mode
# ([[solatro-multimodal-input]]): mouse hover grabs focus, so focus covers mouse, keyboard,
# and controller alike. Deliberately NOT Control.tooltip_text — the native tooltip is a
# popup Window that sat under the cursor and blocked board clicks; this panel is pure
# display (MOUSE_FILTER_IGNORE everywhere, focus NONE) and can never touch input. Text =
# localized ControlCard.describe_card. A PERMANENT child of the OverlayLayer (a Node2D in the
# scroll content, so scroll carries it), re-pinned beside its anchor control every frame
# (_position_focus_info) so container relayouts can't strand it — it was briefly reparented
# under the focused control for that, which is unnecessary now that the whole board (cards
# included) rides one scroll transform. Mouse-exit / ui_cancel / ungrab / rebuild dismisses it.
# ==============================================================================
const FOCUS_INFO_WIDTH := 260.0
const FOCUS_INFO_GAP := 4.0

var _focus_info : PanelContainer = null
var _focus_info_label : Label = null
var _focus_info_anchor : Control = null   ## the board control the panel is pinned beside

func _ensure_focus_info() -> void:
	if _focus_info and is_instance_valid(_focus_info): return
	_focus_info = PanelContainer.new()
	_focus_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_info.focus_mode = Control.FOCUS_NONE
	# No z_index: OverlayLayer is the last sibling of TopLevelVBox, so its children draw above
	# every card and prop by tree order (the structural layering scheme — see LAYERING.md).
	_focus_info_label = Label.new()
	_focus_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_focus_info_label.custom_minimum_size = Vector2(FOCUS_INFO_WIDTH, 0)
	_focus_info.add_child(_focus_info_label)
	# CRITICAL: SmoothScrollContainer force-rewrites every Control added under it to
	# MOUSE_FILTER_PASS (smooth_scroll_container.gd _on_node_added) — which turned this panel
	# into a mouse hit-target hovering over cards and BLOCKED board clicks. It skips nodes
	# already carrying its meta marker, so claim the marker BEFORE entering the tree.
	_focus_info.set_meta("_smooth_scroll_default_mouse_filter_set", true)
	_focus_info_label.set_meta("_smooth_scroll_default_mouse_filter_set", true)
	overlay_layer.add_child(_focus_info)
	_focus_info.hide()

## Show `data`'s description beside the focused control (right of it; flips left at the
## edge). Placement is re-pinned every frame while visible (_process) so focus-driven
## container relayouts — which move the anchor a frame later — never strand the panel.
## Whether the wall's Info mode is on. Read through `WallPicture.settings()` — the one accessor
## that answers "which PlayerSettings" — so a tool previewing the board sees its own knobs.
func _info_mode() -> bool:
	return WallPicture.settings().wall_info_mode

## Whether this screen's OWN description popup may show right now — never in Info mode, and outside
## it only when `wall_screen_popups` is on.
func _popups_allowed() -> bool:
	var settings := WallPicture.settings()
	return not settings.wall_info_mode and settings.wall_screen_popups

## A card's `InfoEntry` for the wall's info card. The TEXT is `ControlCard.describe_card()`, the
## same string the in-screen inspector shows, so the two can never drift; its first line is the
## card's name and the rest is the description. The VISUAL is a real preview card built through
## `CardsViewer`, the same listing `MapHoverPanel` uses for booster previews.
##
## ⚠ The caller takes ownership of `entry.visual` — `InfoCard.show_entry()` frees it on the next
## entry — so a fresh one is built per call rather than cached.
static func card_info(data: CardData) -> InfoEntry:
	var entry := InfoEntry.new()
	var text := ControlCard.describe_card(data)
	var split := text.split("\n", false, 1)
	entry.title = split[0] if split.size() > 0 else ""
	entry.body = split[1] if split.size() > 1 else ""
	var flow := FlowContainer.new()
	entry.visual = flow
	CardsViewer.new(flow).populate([data] as Array[CardData])
	return entry

func _show_focus_info(control: Control, data: CardData) -> void:
	_ensure_focus_info()
	_focus_info_anchor = control
	_focus_info_label.text = ControlCard.describe_card(data)
	_focus_info.show()
	_focus_info.reset_size()
	_position_focus_info()
	set_process(true)  # keep the panel pinned to its anchor while visible

## Pin the panel beside its anchor control; flip left / lift up when it would leave the area.
## Global placement is safe every frame: the panel and the anchor both live in the scroll
## content, so their globals move in lockstep under scrolling.
func _position_focus_info() -> void:
	if not _focus_info or not is_instance_valid(_focus_info) or not _focus_info.visible:
		return
	if not is_instance_valid(_focus_info_anchor) or not _focus_info_anchor.is_inside_tree():
		hide_focus_info()   # the control it anchored to was freed by a rebuild
		return
	var area := get_global_rect()
	var at := _focus_info_anchor.global_position \
			+ Vector2(_focus_info_anchor.size.x + FOCUS_INFO_GAP, 0.0)
	if at.x + _focus_info.size.x > area.end.x:
		at.x = _focus_info_anchor.global_position.x - _focus_info.size.x - FOCUS_INFO_GAP
	var overflow_y := at.y + _focus_info.size.y - area.end.y
	if overflow_y > 0.0:
		at.y -= overflow_y
	_focus_info.global_position = at

## **S16 — OPEN THE ROWS THESE CARDS SIT IN.** Called with the section being scored, or empty to close
## everything again. The set REPLACES: a row that has left the set eases shut rather than being
## dropped, which is why `_row_open` outlives `_row_open_wanted`.
func set_reveal_cards(cards: Array[CardData]) -> void:
	flush_rebuild()  # a hook may have just compacted the board
	var game := CardEnvironment.get_current_game()
	var wanted : Dictionary[Vector2i, bool] = {}
	if game:
		for data : CardData in cards:
			# ⚠ **ASK THE ENGINE WHERE THE CARD IS, don't walk the controls.** `grid_position_of`
			# already answers for the WHOLE board (grids and Entrance alike) off a revision-keyed
			# index; the control walk this replaced could only ever find an Entrance card, and was
			# a second, staler answer to a question the state already answers.
			var coord : BoardCoord = game.state.grid_position_of(data)
			if coord.is_nowhere(): continue
			wanted[_reveal_key(coord)] = true
	_row_open_wanted = wanted
	for key : Vector2i in wanted:
		if not _row_open.has(key): _row_open[key] = 0.0
	set_process(true)

## Push the current openings onto the row strips AND the row score gutters.
##
## ⚠ **K12 — THE GUTTER GROWS BY THE SAME AMOUNT OR THE SCORE NUMBERS DESYNC FROM THEIR ROWS.** The
## labels are a parallel column with no knowledge of the cards, so nothing else would keep them level;
## the design calls this out by name because it fails silently and looks like a labelling bug.
func _apply_row_openings() -> void:
	# ⚠ The GRID's opening needs no control pass: a grid row's height is a function of its cells'
	# depth (`_measure_grid_row_height`), which the containers already resolve on their own. Only
	# the Entrance's fanned strips and its score gutter have to be pushed by hand.
	var hbox : HBoxContainer = upper_zone_right
	if hbox:
		# ⚠ **THIS FOLLOWS THE ENTRANCE'S REVERSED ORDER, AND IT IS THE LAST WRITER OF THOSE
		# HEIGHTS.** Child 0 is the newest card and shows whole, each card under it shows one depth
		# pitch, and the slot's own zone card is the last child -- `update_card_zone_visuals()` owns
		# that one. Left on the old top-down build, this pass silently put the old sizes back every
		# frame and the controls stepped 16 px where the card arithmetic steps 20.
		for col : Node in hbox.get_children():
			var depth := col.get_child_count() - 1
			for j : int in depth:
				var c := col.get_child(j) as Control
				if not c: continue
				var base : float = CardVisual.card_size_play.y if j == 0 else _depth_pitch_px()
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
						base + row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW,
						depth - 1 - j)))
	var gutter : VBoxContainer = upper_zone_left
	if not gutter: return
	for i : int in gutter.get_child_count():
		var label := gutter.get_child(i) as Control
		if not label: continue
		label.custom_minimum_size = Vector2(CardVisual.card_separation_play,
				float(CardVisual.card_separation_play_custom)
				+ row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, i)))

## One frame of the reveal. Returns whether anything is still open or moving.
##
## ⚠ **A FRACTION OF `Game.get_delay()`, never wall clock** — the expansion compresses with
## the act speed-up exactly like the dim, the travel and the hold, so a long cascade cannot leave a
## row still opening while the next section has already started.
func _ease_row_openings(delta: float) -> bool:
	var growing := _ease_layer_arrivals(delta)
	if _row_open.is_empty(): return growing
	var game := CardEnvironment.get_current_game()
	var unit : float = game.get_delay() if game else PlayArea.settings().base_delay
	var span := maxf(unit * PlayArea.settings().spotlight_reveal_fraction, 0.0001)
	var shut : Array[Vector2i] = []
	var moved := false
	for key : Vector2i in _row_open:
		var target : float = 1.0 if _row_open_wanted.has(key) else 0.0
		var now : float = _row_open[key]
		# ⚠ Only an ENTRANCE key can make the control pass necessary — a grid row's height is a
		# function of its cells' depth and its containers resolve it themselves. Running the pass
		# for a grid key rewrites the Entrance's strip sizes for no reason, and the relayout that
		# provokes drifts anything anchored to an Entrance slot (measured: a prop 4 px off across a
		# reveal cycle, which is exactly what G31/G32 exist to catch).
		var is_entrance_key := key.x == REVEAL_ENTRANCE_GRID
		if is_equal_approx(now, target):
			# ⚠ A fully CLOSED row leaves the map, so an idle board holds no reveal state at all and
			# `_row_open_offset` stays free. A fully OPEN one must stay — it is still displacing.
			if target <= 0.0: shut.append(key)
			continue
		_row_open[key] = move_toward(now, target, delta / span)
		if is_entrance_key: moved = true
	for key : Vector2i in shut: _row_open.erase(key)
	if moved or not shut.is_empty(): _apply_row_openings()
	return growing or not _row_open.is_empty()

## One frame of every landing depth layer growing into its height. Shares the reveal's clock
## (`Q75`=a: *"reusing the existing eased `_row_open` machinery"*) so a placement during a cascade
## compresses with the act speed-up exactly like the reveal does, rather than running on wall time
## of its own. An entry that reaches 1 is ERASED — arrived height is permanent, and an idle board
## then carries no growth state at all.
func _ease_layer_arrivals(delta: float) -> bool:
	if _layer_grown.is_empty(): return false
	var game := CardEnvironment.get_current_game()
	var unit : float = game.get_delay() if game else PlayArea.settings().base_delay
	var span := maxf(unit * PlayArea.settings().spotlight_reveal_fraction, 0.0001)
	var done : Array[Vector2i] = []
	for key : Vector2i in _layer_grown:
		var now : float = _layer_grown[key]
		if now >= 1.0:
			done.append(key)
			continue
		_layer_grown[key] = move_toward(now, 1.0, delta / span)
	for key : Vector2i in done: _layer_grown.erase(key)
	return not _layer_grown.is_empty()

## The board itself has no per-frame work (rebuilds are signal-driven, see queue_rebuild);
## this hook keeps the visible focus inspector pinned to its live anchor, and drives S16's reveal.
func _process(delta: float) -> void:
	_position_focus_info()
	var revealing := _ease_row_openings(delta)
	# ⚠ Both consumers have to be idle before processing stops, or whichever finishes first switches
	# the other one off mid-animation.
	if not revealing and _focus_info_anchor == null: set_process(false)

func hide_focus_info() -> void:
	_focus_info_anchor = null
	# ⚠ ONLY IF THE REVEAL IS ALSO IDLE. This used to be an unconditional `set_process(false)`, which
	# with S16 would freeze a row mid-open the moment the focus panel closed.
	# ⚠ **AND ONLY IF NO DEPTH LAYER IS STILL ARRIVING.** `_process` drives both easings; checking
	# the reveal alone froze a growing row at whatever fraction it had reached, leaving the row
	# arithmetic permanently short of the height its container had already taken. Measured: a row
	# stuck at 54 against a container at 74, with a growth entry that never cleared.
	if _row_open.is_empty() and _layer_grown.is_empty():
		set_process(false)  # nothing to pin while hidden
	if not _focus_info or not is_instance_valid(_focus_info):
		_focus_info = null
		return
	_focus_info.hide()

func update_score_controls() -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	set_score_zone(true, upper_zone_left, game_state.scores_row_upper)
	# scores_row_lower / scores_col_legacy: storage only, LowerZone/MiddleZone no longer render.
	# K12: set_score_zone just reset every gutter to its base height, and banking a line score
	# reaches here while the scored row is still OPEN (rows close on the act's release). Without
	# this the open row's gutter collapsed and the score numbers desynced from their rows —
	# `_ease_row_openings` never re-applies once a row has settled at its target.
	_apply_row_openings()

func set_score_zone(is_row:bool, zone:BoxContainer, scores:Array[BigNumber]) -> void:
	var scores_size := scores.size()
	if is_row and scores_size == 0: scores_size += 1 # there should always be at least 1 control as buffer
	var row_diff : int = scores_size - zone.get_child_count()
	if row_diff > 0:
		for i in row_diff:
			zone.add_child(BigNumberLabel.new())
	elif row_diff < 0:
		for i in absi(row_diff):
			var child : BigNumberLabel = zone.get_child(-1)
			zone.remove_child(child)
			child.queue_free()
	for i in zone.get_child_count():
		var label : BigNumberLabel = zone.get_child(i)
		if is_row:
			label.custom_minimum_size = Vector2(CardVisual.card_separation_play, CardVisual.card_separation_play_custom)
		else:
			label.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play)
		if i < scores.size():
			label.current_num = scores[i]
		else: label.text = ""

func update_score(zone:Array[BigNumber], index:int, score:BigNumber) -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	# syncs to game data
	update_score_controls()
	var label : BigNumberLabel
	if zone == game.state.scores_row_upper:
		label = upper_zone_left.get_child(index)
	# scores_row_lower / scores_col_legacy: storage only, no rendering surface anymore.
	if label: label.update_score_anim(score)
		
#func get_control_from_data(data : CardData) -> Control:
	#if data in data_ui:
		#return data_ui[data]
	#return null
#
func get_data_from_control(control : Control) -> CardData:
	flush_rebuild() #reads ui_data
	if control in ui_data:
		return ui_data[control]
	return null

#func get_card_from_data(data : CardData) -> CardVisual:
	#if data in data_card:
		#return data_card[data]
	#return null
	
## **THE SPRING.** Jump `data`, and lift every card stacked ABOVE it in its own cell by the same
## rise, rigidly (`Q310`=a). Returns how long the raise takes, like `anim_jump` does.
##
## ⚠ **THE BOARD KNOWLEDGE BELONGS HERE, NOT IN `CardVisual`.** A card visual has no idea what is
## stacked on it; every caller that used to reach for `anim_jump()` directly gets the spring by
## calling this instead, so a jump can never again lift only the card it happened to.
## ⚠ Grid cells only. The Entrance still fans DOWNWARD from its control tops, so "above" there is
## not the same relation and lifting it would move cards toward the board rather than with it.
func jump_card_with_its_stack(data: CardData) -> float:
	var vis : CardVisual = data_card.get(data)
	if not vis or not is_instance_valid(vis): return 0.0
	var rise := vis.anim_jump()
	var game := CardEnvironment.get_current_game()
	if not game: return rise
	var coord : BoardCoord = game.state.grid_position_of(data)
	if coord.is_nowhere() or coord.is_entrance(): return rise
	var grids := game.state.grids
	if coord.grid < 0 or coord.grid >= grids.size(): return rise
	var grid : GridData = grids[coord.grid]
	if not grid: return rise
	var idx := grid.cell_index(coord.x, coord.y)
	if idx < 0 or idx >= grid.cells.size(): return rise
	var stack : Array[CardData] = grid.cells[idx].datas
	for h : int in range(coord.h + 1, stack.size()):
		var rider : CardVisual = data_card.get(stack[h])
		if rider and is_instance_valid(rider): rider.anim_spring_lift()
	return rise

func popup_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	var wait_time : float = 0
	for data in result.meld:
		if data in data_card:
			var anim_time := jump_card_with_its_stack(data)
			wait_time = anim_time if anim_time > wait_time else wait_time
	await Pacing.wait(self, wait_time).timeout
	
func reset_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	for data in result.meld:
		if data in data_card:
			data_card[data].anim_reset()

func popup_score(result : Scoring.Result) -> void:
	if EventLog.is_on(EventLog.CH_SCORE):
		EventLog.event(EventLog.CH_SCORE, "popup_score", "meld=%d" % result.meld.size())
	flush_rebuild() #reads data_card
	if not result.meld: return
	var combo_pos : Vector2 = Vector2.ZERO
	var meld_size : int = 0
	for card in result.meld:
		if card in data_card:
			meld_size += 1
			combo_pos += data_card[card].global_position
	if meld_size == 0: return
	combo_pos /= meld_size
	combo_pos.y -= CardVisual.card_size_play.y * 0.5
	var score_name_popup := TextPopup.new_popup(result.name + "\n" + str(result.score), combo_pos)
	# OverlayLayer (last sibling) draws above every card and prop by tree order. It rides the
	# scroll content, so a global-space combo_pos stays put; the old PlayArea-root parent + z=100
	# scheme is gone (see LAYERING.md).
	overlay_layer.add_child(score_name_popup)
	await Pacing.wait(self, CardEnvironment.CURRENT.get_delay()*.3).timeout
	score_name_popup.queue_free()
