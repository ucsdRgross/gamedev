extends Control
class_name PlayArea

signal data_selected(data : CardData)
## A gesture travelled far enough to be a drag; this is the card it started on, and whatever was held lets go.
signal card_dragged(data: CardData)
## The drag's release landed on this card: the same placement a click asks for.
signal card_dropped(data: CardData)
## A second press paired with the first one into a tap on this card.
signal card_tapped(data: CardData)
## The drag's release landed on nothing that takes the card, so the player has dropped it.
signal hand_released
## A card is highlighted: its `InfoEntry` for the wall's one container.
signal info_requested(entry: InfoEntry)

# NO CARD IS HIGHLIGHTED ANY MORE: the pointer left every card, or the board focus moved off them.
# Card to card is SILENT -- the card being entered publishes its own description, and a clear
# between the two would flick a locked card's description back in for a frame.
signal highlight_cleared

## The player asked to close the description: a cancel press, or a press on bare board.
signal description_dismiss_requested

## Emitted on every write of `selected_cards`, `held` true when it holds a card: the sidebar leaves Up and Down to the board while one is held.
signal hand_changed(held: bool)

## A navigation key reached the BOARD'S OWN LEFT EDGE: the sidebar is the only place left to go, and it is in another viewport, so nothing here can take the focus there.
signal sidebar_requested
#A CardVisual enters the tree through call_deferred, so right after set_card_zones it is mapped
#in data_card and not yet ready; a deferred emit queued after those adds fires only once they
#are. visuals_ready() is the check-then-await pair for a board that is already built.

## Emitted once a rebuild's CardVisuals are all in-tree and ready, so a caller can await a board.
signal board_visuals_ready

#The board has exactly TWO view modes and nothing in between: OVERVIEW shows every grid for
#orientation, FOCUSED shows the one grid the player is acting on. Switching is a transition —
#there is no intermediate zoom to sit at.
enum ViewMode { OVERVIEW, FOCUSED }

## No grid is focused. ⚠ Never 0 — grid 0 is a real grid.
const NO_GRID := -1

#The width the HUD's rectangle takes on the LEFT, published by `GameView`. The board lays out in
#what is left of the screen and CENTRES THERE, not on the screen (owner ruling). Zero for any host
#that mounts a bare `PlayArea` with no HUD around it.

#⚠ THE BOARD'S WINDOW IS WHAT MOVES, NOT THE CONTENT. Insetting the scroller's own left edge makes
#every centring the board already does land in the post-HUD space for free; offsetting the content
#instead would leave each of those to re-discover the inset separately.
var board_inset_left : float = 0.0:
	set(value):
		if is_equal_approx(board_inset_left, value): return
		board_inset_left = maxf(value, 0.0)
		if not is_instance_valid(scroll_container): return
		_re_fit_after_inset_change()

## The same reserve off the TOP: the container's height in the TOP-band case, plus that edge's crop.
var board_inset_top : float = 0.0:
	set(value):
		if is_equal_approx(board_inset_top, value): return
		board_inset_top = maxf(value, 0.0)
		if not is_instance_valid(scroll_container): return
		_re_fit_after_inset_change()

## The picture px a covering window crops off the RIGHT and BOTTOM, so the board fits and centres in what the player can SEE rather than in the whole picture. Zero at the picture's own aspect.
var board_visible_crop : Vector2 = Vector2.ZERO:
	set(value):
		if board_visible_crop.is_equal_approx(value): return
		board_visible_crop = value
		if not is_instance_valid(scroll_container): return
		_re_fit_after_inset_change()

#⚠ THE SLIDE MOVES THE BOARD'S WINDOW, IT NEVER RESIZES IT. `board_inset_*` above are the RESTING
#reserve, which the board's SIZE and so its zoom are fitted against whatever the sidebar is doing;
#this is the displacement from it. The live reserve re-scaled the board by up to 1.333x.
var board_slide_offset : Vector2 = Vector2.ZERO:
	set(value):
		if board_slide_offset.is_equal_approx(value): return
		board_slide_offset = value
		if not is_instance_valid(scroll_container): return
		_apply_board_zoom_rect()
#The slide moves the grid the Entrance sits under on EVERY frame of it; left to the physics tick,
#the Entrance trailed its grid by ~45 px (measured).
		_sync_entrance_x()

## How many WINDOW pixels one of this picture's own pixels is drawn at, published by `GameView` -- the same boundary `board_inset_*` crosses the other way.
var picture_to_window_scale : float = 1.0

## The size a board card occupies in THIS picture's own pixels: its card size at the scale it is drawn.
func board_card_picture_px() -> Vector2:
	return CardVisual.card_size_play * _content_scale_on_screen()

## The size a board card is DRAWN at on the player's screen: this board's card size, at its live zoom, in window pixels.
func board_card_window_px() -> Vector2:
	return board_card_picture_px() * picture_to_window_scale

# ⚠ **THE RESERVE ARRIVES AFTER THE SHOW HAS ALREADY OPENED**, against a view fitted to an inset of
# zero, so both views re-fit here or the board keeps the whole picture's fit. It lands before the
# picture goes live (measured), so the snap is unseen and no sidebar slide ever reaches here.
func _re_fit_after_inset_change() -> void:
	_apply_entrance_strip_height()
	if view_mode == ViewMode.FOCUSED and focused_grid != NO_GRID:
		focus_grid(focused_grid)
	elif view_mode == ViewMode.OVERVIEW:
		_zoom_board_to(overview_board_zoom())
	snap_the_view_into_place()

## The view mode changed. Carries the mode and the grid it focuses (`NO_GRID` in the overview).
signal view_mode_changed(mode: ViewMode, grid: int)

#⚠ THE OVERVIEW IS ORIENTATION ONLY: A CLICK ON A GRID THERE FOCUSES IT AND PLACES NOTHING.
#Placement only ever happens focused. Set through `open_zoomed_out` / `focus_grid`, never by hand.

#⚠ THE RESTING DEFAULT IS THE ACTING MODE. The overview is a state a show is explicitly OPENED
#into, so a show that never opens it reads as one that opens focused rather than silently matching
#a default.
var view_mode : ViewMode = ViewMode.FOCUSED
var focused_grid : int = 0

var focused_control : Control = null
var moused_hovered_control : Control = null
var selected_cards : Array[CardData] = []:
	set(value):
		selected_cards = value
		hand_changed.emit(not value.is_empty())

#The board's inter-card gap in ART units, before `card_scale`. One number, so the board and the
#picture that has to hold it cannot disagree about the pitch.
const BOARD_SEPARATION := 4

var separation : int = BOARD_SEPARATION: 
	set(value):
		separation = value
		set_separation()
	get():
		return separation * PlayArea.settings().card_scale

#Which `PlayerSettings` the BOARD reads. ⚠ THE SAME ACCESSOR THE WALL USES, AND THAT IS THE POINT:
#the wall editor hosts a real `GameView`, and its one override is `WallPicture.editor_settings`, so
#a board going straight to `SettingsManager` ignored every knob the tool's own panel edits.

#In the shipped game nothing sets that override and this resolves to `SettingsManager.settings`.
static func settings() -> PlayerSettings:
	return WallPicture.settings()

#THE REVEAL. Which board rows are held open, and how far: the value is the eased 0..1 this row is
#through its opening. A row at 0 is absent from the map entirely, so an un-revealed board carries
#no state and `slot_center_global` costs what it always did.

#⚠ A COLUMN OPENS EVERY ROW IT PASSES THROUGH, not none — the reveal set is every board row that
#must expand to make each member of the spotlight set fully visible, so column scoring on the
#longest column expands nearly every row at once. This is keyed by ROW for exactly that reason.

#⚠ THE KEY IS `(grid, h)`, WITH THE ENTRANCE ON A RESERVED GRID INDEX (`REVEAL_ENTRANCE_GRID`) —
#one key shape for the whole board. `h` is a DEPTH within a stack, not a screen row: on the
#Entrance a level of a fanned column, on a grid a height layer. Build every key with `_reveal_key`.
var _row_open : Dictionary[Vector2i, float] = {}
#The rows that WANT to be open. Separate from `_row_open` because a row that has just left the set
#still has to ease back down, and a map that only held the current set would snap it.
var _row_open_wanted : Dictionary[Vector2i, bool] = {}

#The Entrance's reserved slot in the reveal key's grid axis. Real grids index from 0, so -1 is free
#and can never collide with `coord.grid` — the Entrance carries the index of whichever grid it is
#attached to, which is a REAL grid.
const REVEAL_ENTRANCE_GRID := -1

## The `_row_open` key for a board coordinate.
func _reveal_key(coord: BoardCoord) -> Vector2i:
	return Vector2i(REVEAL_ENTRANCE_GRID if coord.is_entrance() else coord.grid, coord.h)

#Each grid panel's resolved global origin, keyed by its index among `GameData.grids`. A panel's own
#rect is a LAYOUT RESULT, so the panel publishes its origin here whenever its rect changes and
#`slot_center_global` reads only this cache, keeping the prop-anchor path free of tree reads.

#Grids are only appended or truncated from the end, so a panel's index is stable for its whole
#lifetime and is a safe cache key.

#⚠ Empty for any grid whose panel has not yet reported a `resized` at all — a lookup then falls
#back to `Vector2.ZERO`, the same silent-until-seen failure mode the cache accepts by design.
var _grid_panel_origin : Dictionary[int, Vector2] = {}

#The board's floor: the screen line every grid panel is bottom-aligned against. See
#`_publish_board_floor` for why this, and not a panel's own rect, is what the row geometry reads.
var _board_floor_y := 0.0

#Each grid's CELL BLOCK — where the columns actually start, and where its rows actually bottom out.
#Distinct from the panel once the panel carries score gutters. See `_publish_cell_rects`.
var _grid_cells_origin : Dictionary[int, Vector2] = {}
var _grid_cells_bottom : Dictionary[int, float] = {}



#How tall a revealed row's strip becomes, in screen pixels — the only place either formula is
#written.

#⚠ NEITHER FORMULA MAY LOOK AT ANY CARD'S POSITION. Sizing the opening from the lowest card that
#had to be seen breaks on a FLUSH, where every card in the row is lit and jumps: that card is then
#the lowest on the board, and the opening lifts rows that are no part of the scored set.
func _row_open_height() -> float:
	return row_open_height(PlayArea.settings(), float(separation))

#The two modes, STATIC so the tuning tool reads the same formula instead of a hand copy that
#drifts. `separation_px` is the SCALED inter-row gap: `PlayArea.separation`'s getter applies
#`card_scale`, and a caller without the node applies it itself.
static func row_open_height(settings_res: PlayerSettings, separation_px: float) -> float:
	var full := CardVisual.card_size_play.y
	if settings_res.spotlight_separation_mode == PlayerSettings.SeparationMode.JUMP_ADJUSTED:
#The jumping cards clear the row while a card that does NOT jump stays slightly covered, which is
#the whole point of this mode rather than a rounding artefact.

#⚠ `separation` COMES OFF THIS MODE TOO (owner: *"jump adjusted needs to be card height -
#separation - jump height then"*). Both branches return a TOTAL pitch — `row_open_span` takes the
#container's `separation` off again — so this is the distance measured between two rows.
		return full - separation_px - CardVisual.card_jump_rise_play
	return full

#The strip-level EXTRA a fully open row adds over the stacked layout — the mode's total pitch minus
#the separation the container already provides and the stacked strip itself.
static func row_open_span(settings_res: PlayerSettings, separation_px: float) -> float:
	return maxf(row_open_height(settings_res, separation_px) - separation_px \
			- float(CardVisual.card_separation_play_custom), 0.0)

#The board's inter-card gap in SCREEN pixels. Static so anything that has to size the board WITHOUT
#one on screen -- the picture that hosts it -- reads the same number the board lays out with,
#rather than a copy that can drift.
static func board_separation_px(settings_res: PlayerSettings) -> float:
	return float(BOARD_SEPARATION) * settings_res.card_scale

#One grid's CELL BLOCK in board pixels: `grid_width` cards across and `grid_height` down with the
#board separation between them. ⚠ The score gutters are deliberately NOT in it -- they sit inside
#the buffer between grids, which is what `_apply_grid_buffer()` enforces on screen.
static func grid_block_size_px(settings_res: PlayerSettings, grid: GridData) -> Vector2:
	var sep := board_separation_px(settings_res)
	var card := CardVisual.CARD_SIZE * settings_res.card_scale
	var w := float(maxi(grid.grid_width, 1))
	var h := float(maxi(grid.grid_height, 1))
	return Vector2(w * card.x + (w - 1.0) * sep, h * card.y + (h - 1.0) * sep)

#The clear band kept ABOVE the board and BELOW the Entrance so neither hugs the window's edge
#(owner ruling). One whole card, in BOARD units, so it scales with the board exactly as a row does
#-- an unscaled band would read as half a card once focused.
static func board_edge_pad_px(settings_res: PlayerSettings) -> float:
	return CardVisual.CARD_SIZE.y * settings_res.card_scale * settings_res.board_edge_pad_rows

#The Entrance strip's height, in screen pixels, at a given zoom. `zoom = 1.0` for the two static
#picture-sizing sites, since the render-target picture is fixed and zoom-independent; the live
#strip passes `drawn_zoom` so it tracks the same scale the grid renders at.
static func entrance_strip_height_px(settings_res: PlayerSettings, zoom: float) -> float:
	return CardVisual.CARD_SIZE.y * settings_res.card_scale * settings_res.entrance_visible_rows * zoom

#Everything `focused_board_zoom()` divides the board's window by, in board units: the cell block,
#the Entrance strip and the two card-row edge buffers.

#⚠ THE BUFFER DERIVATION MUST SOLVE FOR THE ZOOM THE BOARD REALLY USES. Solving for
#`picture.y / (block.y + strip)` while the live fit had grown two card rows of edge buffer in its
#denominator left 108 of 475 units unmodelled, and the buffer it produced isolated nothing.

#⚠ STILL AN UNDER-COUNT, AND DELIBERATELY: the remainder is ~35 units of ~510, and the two
#card-row buffers were the term worth closing.

#The one term no SETTING describes is the panel's column-label row. ⚠ ASKED OF THE ENGINE, NOT
#GUESSED AT: a Label states its own minimum height without being in a tree.

#⚠ CACHED, BECAUSE THE PICTURE IS ONE SIZE FOR A RUN. A font or theme swap mid-run would have to
#invalidate this, and nothing in this game does one.
static var _furniture_h := -1.0
static func board_furniture_height_px(settings_res: PlayerSettings) -> float:
	if _furniture_h < 0.0:
		var label := Label.new()
		_furniture_h = label.get_combined_minimum_size().y
		label.free()
	return _furniture_h + board_separation_px(settings_res)

static func focused_content_height_px(settings_res: PlayerSettings) -> float:
	return grid_block_size_px(settings_res, GridData.new()).y \
			+ entrance_strip_height_px(settings_res, 1.0) \
			+ 2.0 * board_edge_pad_px(settings_res) \
			+ board_furniture_height_px(settings_res)

#What the picture's width is divided by to get the half-width a neighbour must clear.

#⚠ THE BOARD'S OWN AREA IS WHAT VIEW ISOLATION IS MEASURED IN, NOT THE CAMERA'S WHOLE RECT (owner).
#The HUD takes `hud_width_fraction` off the left, so the board's own view is the remaining share
#and a neighbour is out of view once it clears THAT.

#⚠ THIS IS WHY THE CONDITION IS SYMMETRIC AGAIN. The board centres in its own area, so both
#neighbours sit the same distance from its edges and the one-sided HUD offset cancels out. It also
#asks LESS than the old `wall_overfill_margin` did: `0.375 W` against `0.49 W`.

#⚠ SYMMETRIC IN THE BOARD'S AREA IS NOT SYMMETRIC ON THE SCREEN, AND THAT IS EXPECTED. With the HUD
#on the left a left-hand grid really does sit nearer the screen's edge, so anything that reasons
#about DISTANCE TO THE SCREEN EDGE must not assume the two sides match.

#⚠ THIS DIVISOR IS HORIZONTAL, AND IT ASSUMES THE HUD IS A LEFT COLUMN. A HUD on TOP takes nothing
#off the width, so the horizontal divisor is 1 and the share comes off the HEIGHT instead. Whoever
#moves the HUD moves this with it.
static func board_view_divisor(settings_res: PlayerSettings) -> float:
	return 1.0 / maxf(1.0 - settings_res.container_size_fraction, 0.0001)

#The buffer between two grid panels, DERIVED so a FOCUSED grid isolates its neighbours: at the
#isolation check's own scale, the neighbour panel's near edge must clear the OVERVIEW picture's own
#resting half-width, which is what the wall camera shows at rest since it always fits the picture.

#⚠ MEASURED, NOT INFERRED: `wall_overfill_margin` DOES apply here. The picture's height is rounded
#to a whole pixel, which breaks the exact aspect match by a hair, so `WallPicture.focused_scale()`'s
#axis ratios read as unequal and the margin branch fires.

#⚠ THE ZOOM MUST BE `focused_board_zoom()`'s OWN FIXED POINT, NOT A FLAT SUBTRACTION. A flat
#`(picture.y - strip_h) / block.y` is a different, smaller quantity than the real fixed point
#(2.340 modelled against 2.044 real), which is why a flat-model buffer still left a neighbour in.

#⚠ CLOSED FORM, NOT A SEARCH. `grid_position_size_px()`'s width and height are both AFFINE in the
#buffer, so the isolation inequality expands to `a*buffer^2 + b*buffer + c >= 0`, and sampling the
#real function at buffer 0 and 1 reads its two affine coefficients exactly.

#With one grid there is no neighbour to isolate.
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

#The all-grids view's gap between two grids, measured the way the isolating buffer is -- cell block
#to cell block, each panel's score gutters inside it. Fixed rather than derived: with every grid in
#frame at once there is nothing to isolate, and the ruling asks for the grids close.
static func overview_grid_gap_px(settings_res: PlayerSettings) -> float:
	return CardVisual.CARD_SIZE.x * settings_res.card_scale * settings_res.grid_overview_gap_cards

#Does buffer `buffer` isolate a FOCUSED grid's neighbours? Reads `grid_position_size_px()` at the
#candidate buffer for the picture's own width and height, so this can never disagree with the thing
#it is certifying; the only math left here is the isolation check itself.

#The zoom is `focused_board_zoom()`'s own fixed-point shape, not a flat subtraction — see
#`isolating_grid_buffer_px()`.
static func _isolates_at_buffer(settings_res: PlayerSettings, buffer: float) -> bool:
	var block := grid_block_size_px(settings_res, GridData.new())
	var picture := grid_position_size_px(settings_res, buffer)
	var z := picture.y / maxf(focused_content_height_px(settings_res), 0.0001)
	if z <= 0.0: return false
	var visible_half := picture.x / (2.0 * board_view_divisor(settings_res))
	var neighbour_near_edge := z * (buffer + block.x * 0.5)
#The closed-form root sits exactly ON this boundary -- an exact equality two different arithmetic
#paths (this and the solver's quadratic formula) can round to either side of.
	return neighbour_near_edge >= visible_half or is_equal_approx(neighbour_near_edge, visible_half)

#THE WHOLE PICTURE'S span: `grid_max_count` grids of the DEFAULT shape side by side, spaced by
#`isolating_grid_buffer_px()`, with that SAME buffer again as margin on each side against the
#picture's own edge.

#⚠ THE PICTURE IS SIZED FOR THE FOCUSED VIEW ALONE (owner ruling). The edge margin and the gap a
#player sees between two grids are one quantity only while focused: inside this same picture the
#overview draws `overview_grid_gap_px()` instead and the set centres in what is left.

#The OVERVIEW camera rests on this whole span — every grid the picture holds fits inside it at
#once, which is what lets zooming out show them all. FOCUSED reuses the same span: isolation comes
#from the buffer, not from a second camera box.

#`buffer_override` lets a candidate buffer be tried without re-entering the derivation that
#produces the real one: pass a value `>= 0.0` to use it as-is, and the default of `-1.0` resolves
#through `isolating_grid_buffer_px()` as every non-solving caller wants.
static func grid_position_size_px(settings_res: PlayerSettings, buffer_override: float = -1.0) -> Vector2:
	var block := grid_block_size_px(settings_res, GridData.new())
	var count := float(maxi(settings_res.grid_max_count, 1))
	var buffer := buffer_override if buffer_override >= 0.0 else isolating_grid_buffer_px(settings_res)
	var span := count * block.x + (count - 1.0) * buffer
	var width := span + 2.0 * buffer
	var reference := reference_window_size()
	return Vector2(width, maxf(block.y, width * reference.y / reference.x))

## The project's own authored window shape -- the reference aspect the picture's height is built to and the container's cap is measured against, read from the project rather than restated.
static func reference_window_size() -> Vector2:
	var width : float = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var height : float = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	assert(width > 0.0 and height > 0.0, "the project's viewport size is authored")
	return Vector2(width, height)

#The size the game picture is laid out at: `grid_max_count` grids side by side, exactly the span
#`grid_position_size_px()` already computes, at the larger of the board's own height and the
#window-aspect minimum. The picture is therefore window-shaped and fits in frame at once.

#⚠ DERIVED FROM THE CAP AND THE DEFAULT GRID SHAPE, NEVER FROM THE GRIDS A RUN HAS. The picture is
#one fixed size for every run: a deck that unlocks a second grid mid-show must not resize a render
#target, and a 1-grid run sits in a picture built for three.
static func game_picture_design_size(settings_res: PlayerSettings) -> Vector2i:
	var span := grid_position_size_px(settings_res)
	return Vector2i(roundi(span.x), roundi(span.y))

#The EXTRA height this row currently carries over a stacked strip. Zero for every row on a board
#with no reveal up, which is what keeps the unexpanded layout bit-for-bit what it was.
func row_open_extra(coord: BoardCoord) -> float:
	var t : float = _row_open.get(_reveal_key(coord), 0.0)
	if t <= 0.0: return 0.0
#⚠ A ROW THAT COVERS NOTHING DOES NOT OPEN, AND LEAVING THIS OUT WAS A REAL BUG. The opening exists
#to lift a covering card off a buried one; on a board one card deep there is nothing underneath, so
#growing the strip adds PURE EMPTY SPACE and only shoves the zone below it down.

#⚠ Decided per DEPTH LAYER, never per column or cell: every column's VBox and every CellSlot must
#give that layer the same height or the rows stop lining up across the board.
	if not _row_covers_anything(coord): return 0.0
#⚠ THE VBOX ALREADY PUTS `separation` BETWEEN ROWS — SUBTRACT IT OR THE OPENING OVERSHOOTS.
#`row_open_height` is the TOTAL distance the mode asks for, but the row-to-row pitch is
#`strip + separation`, and `slot_center_global` adds the same term.

#Sizing the STRIP to the full height therefore produced height + separation, an extra
#`4 * card_scale` (10 px at the shipped scale) that reads as an odd gap between the rows.
#`row_open_span` supplies the remainder.
	return row_open_span(PlayArea.settings(), float(separation)) * t

#Does any stack in `coord`'s half of the board hold a card BELOW depth `coord.h` — is there
#anything for this layer to uncover? The deepest layer covers nothing and must stay put. The
#Entrance asks it of its fanned columns, a grid of its cells; the question is the same one.

#⚠ Read from STATE, not the control tree: rebuilds are DEFERRED, so mid-mutation the child counts
#describe the previous board — and `slot_center_global` routes through here, so a tree read made
#its geometry depend on rebuild timing after all.
func _row_covers_anything(coord: BoardCoord) -> bool:
	var game := CardEnvironment.get_current_game()
	if not game: return false
	for stack : ArrayCardData in _reveal_stacks(coord):
		if stack.datas.size() > coord.h + 1: return true
	return false

#The stacks a reveal layer spans: the Entrance's columns, or one grid's cells. Empty for a grid
#index no grid answers to.
func _reveal_stacks(coord: BoardCoord) -> Array[ArrayCardData]:
	var empty : Array[ArrayCardData] = []
	var game := CardEnvironment.get_current_game()
	if not game: return empty
	if coord.is_entrance(): return game.state.upper_zone
	var grids := game.state.grids
	if coord.grid < 0 or coord.grid >= grids.size(): return empty
	var grid : GridData = grids[coord.grid]
	return grid.cells if grid else empty

#How much taller the reveal is currently making an Entrance column -- exactly what the hbox has
#grown BY, so a floor taken from its bottom edge can be corrected back to its resting line.
func _entrance_open_total() -> float:
	var sum := 0.0
	for key : Vector2i in _row_open:
		if key.x != REVEAL_ENTRANCE_GRID: continue
		sum += row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, key.y))
	return sum

#Everything the layers ABOVE `coord.h` in the same half of the board have pushed down. ⚠ Above
#only: a layer's own opening grows the gap BELOW it, so it does not move its own card.
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

#⚠ `%UpperZone` (an `HSplitContainer`) IS DELIBERATELY NOT IN THIS LIST. Its "separation" theme
#constant is the GUTTER RESERVED BETWEEN ITS TWO PANES, not a card-row spacing — matching it to the
#shared card `separation` pushed every Entrance column 4 px off its own left edge (measured).

#`UpperZoneLeft` is hidden (`setup_gui`), so the gutter has nothing to separate from and is zeroed
#there instead.
@onready var containers : Array[Control] = [%TopLevelVBox, %UpperZoneLeft, %UpperZoneRight]
@onready var top_level_vbox: VBoxContainer = %TopLevelVBox
@onready var upper_zone_left: VBoxContainer = %UpperZoneLeft
@onready var upper_zone_right: HBoxContainer = %UpperZoneRight
## Phase 4 prop-animation surface.
@onready var prop_layer: PropLayer = %PropLayer
#A panel's own answer to "which buckets, and from which row" -- set when a panel is mounted
#somewhere `get_index()` cannot answer for it. Absent on a board grid, which still answers by
#position, so this changes nothing for the grids.
const META_BUCKET_GRID := &"bucket_grid"
const META_ROW_OFFSET := &"row_offset"

@onready var scroll_container: ScrollContainer = $SmoothScrollContainer
#⚠ Typed `HBoxContainer` and NAMED `GridContainer`: the name is the registry's, the type is what
#puts the panels side by side. The grid of cells INSIDE each panel is the real `GridContainer`,
#built per panel in `_create_grid_panel`.
@onready var grid_container: HBoxContainer = %GridContainer
#CardVisual host INSIDE the scroll content (a Node2D the containers ignore, like PropLayer): the
#scroll transform carries cards, controls and props together. Parented to the PlayArea root
#instead, cards chased their anchors' scrolled globals and visibly lagged every scroll.
@onready var card_layer: Node2D = %CardLayer
#Always-on-top surface (last sibling of TopLevelVBox): the focus inspector panel and score popups
#live here so they render above every card and prop by TREE ORDER — no z_index needed.
@onready var overlay_layer: Node2D = %OverlayLayer

#THE PINNED ENTRANCE. A sibling of `SmoothScrollContainer`, outside the board's scroll, so it never
#scrolls away vertically. `EntranceStrip` is the fixed visible window; `EntranceHTrack` is the track
#slid in X onto the grid the Entrance belongs to, or centred in the window (`_sync_entrance_x`).

#`EntranceVScroll` does not resize or clip, so a stack deeper than the configured strip simply
#draws past the window. Resizing the strip itself was tried and rejected: it re-lays out everything
#anchored inside it, drifting a prop off its own slot mid-cycle.

#`EntranceCardLayer` is its OWN card layer — a card layer INSIDE the board's scroll cannot pin,
#because its cards would scroll away from their own pinned controls. The board's own scrollbar is
#the ONLY one on screen, since `EntranceVScroll`'s own bar is hidden.
@onready var entrance_strip: Control = %EntranceStrip
@onready var entrance_h_track: Control = %EntranceHTrack
@onready var entrance_v_scroll: ScrollContainer = %EntranceVScroll
@onready var entrance_card_layer: Node2D = %EntranceCardLayer

func _ready() -> void:
	SettingsManager.settings_changed.connect(update_gui)
#⚠ NEITHER SCROLLBAR MAY ADVERTISE WHICH MECHANISM IS MOVING THE VIEW (owner): a camera step in the
#overview and a scroll in focused mode must read as the same motion, and *"no scrollbar should be
#visible"* when a focused grid opens.

#⚠ SIZING THE BOARD TO CLEAR THE BAR IS NOT ENOUGH. Measured: the vertical bar shows at EXACT
#equality of content and page — hidden at a 1152x648 window, shown at 1147x649 with the identical
#313 == 313 — so any fit lands on a coin toss between two widths five pixels apart.

#`SCROLL_MODE_SHOW_NEVER` hides a bar and reserves no band for it: the page is the whole rect.
#Scrolling itself is untouched — the zoom, the pan actions, the touch drag and a deep stack all
#still move the board.
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
#Pay every FX shader's first-use compile here, on invisible one-pixel quads, rather than on the
#first card that catches fire mid-act.
	FxAttachment.warm(overlay_layer)
	setup_gui()
#THE SHOW OPENS ON ITS OPENING VIEW. A show is one PlayArea, so this is that view -- and with no
#grids built yet it is the all-grids view, which the first rebuild that has one revisits.
	open_show_view()
	_show_view_opened = grid_container.get_child_count() > 0
#_process only pins the focus inspector — enabled while it is visible
	set_process(false)
#X-SLAVING RUNS EVERY PHYSICS FRAME, UNCONDITIONALLY: a board scroll can happen at any time whether
#or not the focus inspector or a reveal is live, and a ScrollContainer's `scroll_horizontal` can be
#written directly without reliably firing its scrollbar's `value_changed`.

#Same "recompute live, never trust a signal alone" rule every other per-frame board anchor in this
#file already follows.
	set_physics_process(true)

func setup_gui() -> void:
	set_separation()
	set_card_zones()
#A REBUILT BOARD OPENS IN PLAY: the layer view is transient, never saved, and a board rebuilt
#or restored under it is no longer the board it was opened over.
	plan_layer_open = false
#THE ENTRANCE LINES UP WITH THE GRID'S COLUMNS, which is what makes it read as the row below the
#board rather than a separate strip nearby. Two things pushed it out of line: its row-score gutter,
#a leftover of the retired upper zone, and its row being left-aligned inside a centred width.
	upper_zone_left.visible = false
	upper_zone_right.alignment = BoxContainer.ALIGNMENT_CENTER
#⚠ A BOARD NARROWER THAN THE WINDOW SITS CENTRED, NOT PARKED AT THE LEFT EDGE. A ScrollContainer
#hands its content exactly the content's own minimum width unless the content asks to expand, and
#the scroll range then collapses with the board still hard left (measured: 555 against a 782 centre).

#Asking to expand gives the spare width to the content, where `GridContainer`'s centre alignment
#spends it, so the centring is the LAYOUT's answer and not arithmetic written here. Content wider
#than the window keeps its own minimum, so an overflowing board is untouched.
	top_level_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
#The split gutter has nothing to separate now the left pane is hidden -- zero it so
#`UpperZoneRight` starts flush with `UpperZone`'s own left edge (see the `containers` note).
	(%UpperZone as Control).add_theme_constant_override("separation", 0)
#The board grows UPWARD out of the Entrance, so the Entrance is the part the player acts on and it
#is the bottom of the picture. Anchor the scroll there ON ENTRY -- deferred, because the containers
#have not been sized yet at this point and the maximum is still 0.

#⚠ THE SCROLLER MUST NOT CHASE KEYBOARD FOCUS. A card control grabs focus on `mouse_entered`, and a
#`ScrollContainer` with `follow_focus` scrolls whatever just took focus into view, so moving the
#mouse across the board scrolled it (measured: the gap wandered between 44.2 and 25.3 px).

#The board's own `pan_to_grid` and `_recentre_board` are the only things allowed to aim it.
	if is_instance_valid(scroll_container): scroll_container.follow_focus = false
#⚠ THE BOARD DOES NOT CLIP, AND THAT IS A RULING, NOT AN OVERSIGHT. `%CardLayer` lives inside this
#scroller, so a clip here CULLS card visuals outright -- and props and animations are authored to
#leave the board's edges on purpose (owner). Hiding a neighbouring grid is the CAMERA's job alone.
	if is_instance_valid(scroll_container): scroll_container.clip_contents = false
	_last_scroll_max = -1.0
	_scroll_growth_carry = 0.0
	_anchor_scroll_to_bottom.call_deferred()
	update_score_controls()
	_apply_entrance_strip_height()
#The floor is measured against THIS control's height, so re-measure it whenever the window changes
#— otherwise the board keeps growing off a stale floor.
	if not resized.is_connected(_apply_entrance_strip_height):
		resized.connect(_apply_entrance_strip_height)
	_sync_entrance_x()

# RUNS EVERY PHYSICS FRAME, UNCONDITIONALLY (never toggled off the way `_process` is): a board
# scroll can happen at any time, and a ScrollContainer's `scroll_horizontal` can be written
# directly without reliably firing `value_changed` -- recompute live, never trust a signal alone.
func _physics_process(delta: float) -> void:
	_apply_grid_buffer()
	_follow_board_growth()
	_sync_row_label_heights()
	_sync_score_label_font()
	_advance_the_entrance_slide(delta)
	_sync_entrance_x()
#⚠ ONE control's rect, on the tick `_sync_entrance_x` already reads on. `resized` alone left this
#8 px stale (562 against a real 554) because the content's POSITION can settle without its size
#changing, and a stale floor moves every row on the board at once.

#⚠ This is safe where the per-PANEL version was not: that one read the rects the floor code WRITES
#to, every frame, and the board never settled. `TopLevelVBox` is written only from
#`_give_the_board_a_floor`, which runs on a window resize, not on this tick.
	_publish_board_floor()
	_sync_cell_score_labels()

#A stack's height score sits ABOVE its topmost card and rises as the stack grows. One label per
#cell that has ever scored; `scores_cell` is already keyed per cell.

#⚠ POSITIONED BY ARITHMETIC IN ITS OWN LAYER, NOT PARENTED INTO THE CELL. A label inside the
#`CellSlot` would add its own height to the cell, and `_measure_grid_row_height` would have to know
#about it. Riding `slot_center_global` instead makes the label follow the stack for free.

#⚠ `at` IS A MEASURED GLOBAL, ALREADY SCALED ON SCREEN; THE CARD AND LABEL SIZES ARE NOT. Both
#live in `card_layer`, so their local magnitudes are taken into screen pixels by
#`_content_scale_on_screen()` before being subtracted from `at`.
func _sync_cell_score_labels() -> void:
	if not is_inside_tree() or not is_instance_valid(card_layer): return
	var game := CardEnvironment.get_current_game()
	if not game:
		for key : Vector3i in _cell_score_labels:
			if is_instance_valid(_cell_score_labels[key]): _cell_score_labels[key].queue_free()
		_cell_score_labels.clear()
		return
	var state := game.state
	var z := _content_scale_on_screen()
	var live : Dictionary[Vector3i, bool] = {}
	for key : Vector3i in state.scores_cell:
#Resolved through the ZONE that owns the row, never by reaching into `grids` -- a row past a grid's
#own height belongs to the Entrance, and reaching in rendered nothing for it.
		var stack := state.stack_at_banked_cell(key.x, key.y, key.z)
		if not stack: continue
		var depth : int = stack.datas.size()
#nothing to sit above yet
		if depth <= 0: continue
		live[key] = true
		var label : BigNumberLabel = _cell_score_labels.get(key)
		if not label or not is_instance_valid(label):
			label = BigNumberLabel.new()
			label.name = "CellScore_%d_%d_%d" % [key.x, key.y, key.z]
#A height score stands over its own column of cards, so it is centred like the column gutter is.
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_layer.add_child(label)
			_cell_score_labels[key] = label
		label.current_num = state.scores_cell[key]
#ABOVE the topmost card: its centre, less half a card, less the label's own height. The SAME
#arithmetic in every zone -- the owner's *"heights be above stacks always even for bottom"* -- so
#only the coordinate lookup knows which zone this is.
		var top := state.coord_for_banked_cell(key.x, key.y, key.z, depth - 1)
		var at := slot_center_global(top)
		label.global_position = Vector2(at.x - label.size.x * z * 0.5,
				at.y - CardVisual.card_size_play.y * z * 0.5 - label.size.y * z)
	for key : Vector3i in _cell_score_labels.keys():
		if live.has(key): continue
		var doomed : BigNumberLabel = _cell_score_labels[key]
		if is_instance_valid(doomed): doomed.queue_free()
		_cell_score_labels.erase(key)

## One height-score label per cell that has scored, keyed the same way `scores_cell` is.
var _cell_score_labels : Dictionary[Vector3i, BigNumberLabel] = {}

#X SLAVED TO THE COLUMNS OF THE GRID THE ENTRANCE BELONGS TO, and centred in the board's own window
#while it belongs to none (owner spec). Its slots then stay under that grid's columns wherever the
#view goes, which is what makes a committed Entrance leave the screen when the player looks away.

#⚠ THE ONE WRITER of `entrance_h_track.position.x`. The travel between the two positions is the
#slide `_advance_the_entrance_slide` integrates; both ends are recomputed live here, so a slide
#that starts while the board is still panning still lands under the grid.

#⚠ THE TRACK TAKES THE GRID'S OWN CELL BLOCK, NOT A WIDTH SHARED WITH THE WHOLE BOARD. Both halves
#are read off the cells' live rect, because the cells, not the panel, are where the columns start
#(a 20 px gutter apart).
func _sync_entrance_x() -> void:
	if not is_instance_valid(entrance_h_track) or not is_instance_valid(scroll_container): return
#⚠ THE BOARD'S CONTENT STAYS AT LEAST AS WIDE AS THE ENTRANCE, OR AN ENTRANCE WIDER THAN THE WINDOW
#CANNOT BE REACHED. The Entrance rides the board's horizontal scroll, so the scroll needs the reach
#even on a board with no grid of its own to supply it.

#The Entrance's own minimum is read, never the container's own width, which would fold in last
#call's answer and could then only ever grow.
	grid_container.custom_minimum_size.x = upper_zone_right.get_combined_minimum_size().x
#⚠ READ IN THE STRIP'S OWN SPACE, NOT AS A GLOBAL DIFFERENCE: a fresh show's opening scales the
#whole board, and a global difference is that scale times the offset the track is written in.
	var to_strip := entrance_strip.get_global_transform().affine_inverse()
	var columns_x := (to_strip * grid_container.global_position).x
	var columns_w := grid_container.size.x
	var home := entrance_home_grid()
	var cells := _grid_cells(pan_grid if home == NO_GRID else home)
	if cells:
		var xf := to_strip * cells.get_global_transform()
		columns_x = xf.origin.x
		columns_w = xf.basis_xform(cells.size).x
#The strip already starts at the board window's left edge, so the centred position is the spare
#width either side of the row, halved, carried along by the sidebar's slide as the set is.
	var under_the_grid := columns_x
	var centred := (_board_width_left() - columns_w) * 0.5 + board_slide_offset.x
	entrance_h_track.position.x = lerpf(centred, under_the_grid, _entrance_slide)
	entrance_h_track.size.x = columns_w
	_apply_entrance_zoom_rect()

#THE GRID THE ENTRANCE BELONGS TO, or `NO_GRID` while it belongs to none and sits centred in the
#board's window. ONLY A PLACEMENT commits it (owner ruling): a focus, a pickup or a pan leaves it
#centred, so the player can still choose another grid and the grid comes to the Entrance.
func entrance_home_grid() -> int:
	var game := CardEnvironment.get_current_game()
	if game and game.state.committed_grid != -1: return game.state.committed_grid
	return NO_GRID

## How far the Entrance has travelled from the centre of the window to its grid: 0 centred, 1 there.
var _entrance_slide : float = 0.0

#THE ENTRANCE TAKES THE SAME CLOCK AS A GRID PAN to cross between the centre of the window and the
#grid it belongs to, so the two moves a pickup starts read as one. Integrated against the live aim
#rather than tweened: nothing has to be cancelled when the aim changes part way across.
func _advance_the_entrance_slide(delta: float) -> void:
	var aim := 0.0 if entrance_home_grid() == NO_GRID else 1.0
	_entrance_slide = move_toward(_entrance_slide, aim, delta / PlayArea.settings().grid_pan_duration)

#THE SCALE MUST LIVE ON THE SCROLL CONTAINER, NOT ITS CONTENT — the same rule
#`_apply_board_zoom_rect` follows. `%EntranceVScroll` carries `drawn_zoom` so the Entrance's cards
#scale with the grid's, and its rect is divided by it first so the window stays its own rect.

#⚠ Height is RECOMPUTED, never read off `entrance_h_track.size.y`: a strip resize has not
#necessarily reached this Control's own rect yet, the same trap `_board_window_local` avoids, and
#this runs both right after that write and every physics frame. Width is safe to read live.
func _apply_entrance_zoom_rect() -> void:
	if not is_instance_valid(entrance_v_scroll) or not is_instance_valid(entrance_h_track): return
	var z := maxf(drawn_zoom, 0.0001)
	var window := Vector2(entrance_h_track.size.x,
			entrance_strip_height_px(PlayArea.settings(), z))
	var local := window / z
	entrance_v_scroll.scale = Vector2.ONE * z
	entrance_v_scroll.offset_right = local.x - window.x
	entrance_v_scroll.offset_bottom = local.y - window.y

#The Entrance's REAL depth, past the configured visible strip -- what the board's floor must clear
#so a deep Entrance never covers a grid card. Distinct from the visible strip on purpose: the strip
#itself must stay fixed, or a prop drifts off its own anchor mid-cycle (measured: 4 px).
func _entrance_strip_full_height() -> float:
	return maxf(entrance_strip_height_px(PlayArea.settings(), drawn_zoom), _entrance_row_height())

## The cell block of grid `gi`, clamped to the board, or null when the board has no grids.
func _grid_cells(gi: int) -> Control:
	if not is_instance_valid(grid_container): return null
	var last := grid_container.get_child_count() - 1
	if last < 0: return null
	return _cells_root(grid_container.get_child(clampi(gi, 0, last)) as Control)

#The strip's FIXED visible height, and the matching reservation carved out of the board's own
#scroll so the two never overlap on screen. A multiple of one card's height, re-applied on every
#settings change since `card_scale` resizes the card the multiple is measured against.

#Stays fixed even when the Entrance stacks deeper: the strip is a player setting, and resizing it
#re-lays out everything anchored inside it (see `_entrance_strip_full_height`). The board's floor
#is what clears the real depth instead.
func _apply_entrance_strip_height() -> void:
	if not is_instance_valid(entrance_strip) or not is_instance_valid(scroll_container): return
	entrance_strip.offset_left = hud_reserve_px()
	_apply_board_zoom_rect()
	_apply_entrance_zoom_rect()
	_give_the_board_a_floor(_entrance_strip_full_height())

#Put the board's window back where it was after the zoom made it bigger, with the Entrance strip
#under it: the sidebar's slide shifts both as one set, on either axis.

#⚠ THE ZOOM SCALES THE SCROLL CONTAINER, AND ITS RECT IS DIVIDED BY THE ZOOM TO COMPENSATE. The
#scale cannot go on the CONTENT: a `Container` rewrites its children's scale on every sort
#(measured -- the scale was back at 1 the next frame), so the scroller's own child cannot carry it.

#The scroller itself is a child of this plain `Control`, which rewrites nothing. Dividing the rect
#by the same factor leaves the window exactly the pixels it occupied unzoomed, so the side panels
#keep their room and only the BOARD grows.
func _apply_board_zoom_rect() -> void:
	if not is_instance_valid(scroll_container): return
	var local := _board_window_at(drawn_zoom)
	var pad := board_edge_pad_px(PlayArea.settings()) * drawn_zoom
	scroll_container.scale = Vector2.ONE * drawn_zoom
	var top := pad + board_inset_top + board_slide_offset.y
	scroll_container.offset_top = top
	var inset := hud_reserve_px() + board_slide_offset.x
	scroll_container.offset_left = inset
	scroll_container.offset_right = inset + local.x - size.x
	scroll_container.offset_bottom = top + local.y - size.y
	var strip_bottom := board_slide_offset.y - pad
	entrance_strip.offset_top = strip_bottom - entrance_strip_height_px(PlayArea.settings(), drawn_zoom)
	entrance_strip.offset_bottom = strip_bottom

#The board's window in the SCROLLER'S OWN units AT SCALE `z`: what it occupies on screen, divided
#by `z`. The Entrance strip it gives up scales with `z` too, so the strip is derived here rather
#than remembered -- a remembered one is a frame of some other scale.

#⚠ COMPUTED, NEVER READ BACK OFF `scroll_container.size`. A container's size only catches up with
#the offsets on the next sort, so anything measuring it on the tick the zoom changed reads the
#PREVIOUS mode's window -- a whole grid's worth of aim, and a board floor left where it was.
func _board_window_at(z: float) -> Vector2:
	var pad := board_edge_pad_px(PlayArea.settings()) * z
	var strip := entrance_strip_height_px(PlayArea.settings(), z)
	return Vector2(maxf(_board_width_left(), 0.0),
			maxf(_board_height_left() - strip - 2.0 * pad, 0.0)) / maxf(z, 0.0001)

#THE WINDOW AN AIM IS BUILT FROM IS THE ONE THE BOARD IS TRAVELLING TO, never the frame it is on.
#Every aim reads this; only what is DRAWN reads `drawn_zoom`.
func _board_window_local() -> Vector2:
	return _board_window_at(board_zoom)

## The width the board has: this control's own, less the container's capped reserve and the crop off the right edge.
func _board_width_left() -> float:
	return size.x - hud_reserve_px() - board_visible_crop.x

## The height the board has: this control's own, less the top reserve and the crop off the bottom edge.
func _board_height_left() -> float:
	return size.y - board_inset_top - board_visible_crop.y

#`board_inset_left`, capped so the board is never starved of the room for a grid.

#⚠ THE HUD IS AUTHORED AGAINST A 1152-WIDE CANVAS AND DOES NOT SHRINK WITH THE SCREEN. On a 412 px
#phone its 402 px rectangle leaves the board TEN PIXELS, measured, with the whole grid off screen.
#Yielding room the board does not have is a different thing from yielding what the HUD asks for.

#⚠ Derived from the panel the board must show, never a fraction or an authored floor: the rule is
#"a grid still fits", and that is exactly what it says. It keeps the board legible until the HUD
#either scales with the screen or moves off it; it does not stop the HUD overlapping the board.
func hud_reserve_px() -> float:
	var panel := _panel_width(resting_grid())
	if panel <= 0.0: return board_inset_left
	return minf(board_inset_left, maxf(size.x - panel, 0.0))

#⚠ THE ENTRANCE IS ROW -1, AND ITS OWN HEIGHT PUSHES THE BOARD UP (owner: a deeper Entrance raises
#everything above it so as not to cover any card in the grid). Same arithmetic a grid row uses — a
#whole card plus a fanned strip for every card under the top one.

#The Entrance therefore participates in the board's geometry rather than being a fixed reservation
#the board happens to sit above. The configured `entrance_visible_rows` stays the FLOOR of that: a
#shallow Entrance still shows the strip the player expects.
func _entrance_row_height() -> float:
	var full := CardVisual.card_size_play.y * drawn_zoom
	var game := CardEnvironment.get_current_game()
	if not game: return full
	var deepest := 0
	for col : ArrayCardData in game.state.upper_zone:
		deepest = maxi(deepest, col.datas.size())
	if deepest == 0: return full
	var depth_pitch := (float(CardVisual.card_separation_play_custom) + float(separation)) * drawn_zoom
	return float(separation) * drawn_zoom + full + float(deepest - 1) * depth_pitch

#⚠ THE BOARD NEEDS A FLOOR TO GROW UP OFF, AND A SCROLL CONTAINER DOES NOT GIVE IT ONE.
#`TopLevelVBox` hugs its own content, so without this the grid block starts at the top of the
#scrolled content and every deepened stack pushes the rows BELOW it down.

#⚠ `alignment`, NOT `size_flags_vertical`. A vertical size flag aligns a child inside its OWN
#allotted slot, and a `VBoxContainer` allots each child exactly its minimum height, so
#`SIZE_SHRINK_END` on the grid block moved it by nothing at all (measured: the full 40 px).

#`ALIGNMENT_END` packs the container's children against its end, which is what actually pins the
#floor.
func _give_the_board_a_floor(strip_h: float) -> void:
	if not is_instance_valid(top_level_vbox) or not is_instance_valid(grid_container): return
#⚠ Divided by the zoom, and by NOTHING ELSE: the height term is the floor in SCREEN pixels while
#the content is laid out in the scroller's own, smaller ones. `strip_h` is the Entrance's REAL
#depth, not the window's reservation, so a deeper Entrance lowers the floor rather than raising it.

#⚠ `_board_height_left()`, NEVER `size.y`: the scroller's own window is that height less the
#picture's inset and crop, so the FULL control made the content
#`(board_inset_top + board_visible_crop.y) / drawn_zoom` taller than the page.

#30 px of inset then left 30.25 of scroll range on a board with nothing out of view -- a board the
#player could slide off its own spawn position.
	var pad := board_edge_pad_px(PlayArea.settings()) * drawn_zoom
	top_level_vbox.custom_minimum_size.y = \
			maxf(_board_height_left() - strip_h - 2.0 * pad, 0.0) / maxf(drawn_zoom, 0.0001)
	top_level_vbox.alignment = BoxContainer.ALIGNMENT_END
	_publish_board_floor()
	if not top_level_vbox.resized.is_connected(_publish_board_floor):
		top_level_vbox.resized.connect(_publish_board_floor)

#⚠ THE FLOOR COMES FROM THE SCROLL CONTENT, NOT FROM A PANEL'S RECT. Every grid panel is
#bottom-aligned against this same line, so it is the one number the row geometry needs — and unlike
#a panel it does NOT move when a stack deepens, which is exactly why caching it is safe.

#Caching the PANEL's rect was not: its origin lagged a whole depth pitch behind (measured: 264
#against a real 244). `resized` is enough here because this control only changes with the WINDOW.
func _publish_board_floor() -> void:
	if not is_instance_valid(top_level_vbox): return
	var z := _content_scale_on_screen()
	_board_floor_y = top_level_vbox.global_position.y + top_level_vbox.size.y * z
	_publish_cell_rects()

#⚠ THE ARITHMETIC FOLLOWS THE CELLS, NOT THE PANEL. Once the panel carries score gutters the two
#are no longer the same rect: the row-label column pushes the cells right and the column-label row
#lifts their bottom. Reading the panel put every card a gutter off its cell (20 px by 27 px).

#Refreshed on this same tick, and safe for the same reason: nothing writes these rects per frame.
func _publish_cell_rects() -> void:
	if not is_instance_valid(grid_container): return
	var z := _content_scale_on_screen()
	for i : int in grid_container.get_child_count():
		var panel := grid_container.get_child(i) as Control
		if not panel or panel.is_queued_for_deletion(): continue
		var cells := _cells_root(panel)
		if not cells: continue
		_grid_cells_origin[i] = cells.global_position
#⚠ A GLOBAL origin plus a LOCAL size is not a global edge once the board is zoomed --
#`global_position` carries the zoom and `size` never does.
		_grid_cells_bottom[i] = cells.global_position.y + cells.size.y * z

#The scroll range the board last had. -1 until a tick has seen one, so a rebuild re-baselines
#rather than treating the whole range as fresh growth.
var _last_scroll_max := -1.0
#The sub-pixel part of the growth not yet handed to `scroll_vertical`, which is an INT. Carried
#rather than rounded away: rounding each step independently drifts by up to half a unit per card,
#measured at 5.1 px of accumulated slip over six placements.
var _scroll_growth_carry := 0.0

#Keep the board's BOTTOM line where it is as the board gets taller.

#⚠ THE BOARD GROWS UPWARD, AND THAT MEANS ITS BOTTOM DOES NOT MOVE. A deepening stack makes the
#scroll content taller; with the offset left alone every new pixel appears BELOW the window, so the
#board reads as sinking out of its own frame and under the Entrance.

#Measured on a single column: at depth 3 the cell block hung 14.7 px past the window's bottom edge,
#and at depth 6, 112.8 px. Adding the growth to the offset puts the new height at the TOP, where
#the stack actually grew.

#⚠ THIS IS NOT `_anchor_scroll_to_bottom()`. That one SNAPS to the bottom and runs on entry only,
#because a rebuild that snapped would yank the view away from a player who had scrolled elsewhere.
#Following the growth keeps whatever offset the player chose.
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

#Wait for `card`'s visual to reach the cell it was just placed in. ⚠ Bounded by the act clock: a
#visual that never settles must not stall the show.

#⚠ TWO FRAMES BEFORE THE FIRST POLL, AND THEY ARE NOT OPTIONAL. The rebuild that starts the card's
#flight is deferred, so on the frame the placement commits there is no `move_tween` yet and polling
#immediately reads "not moving" before the card has begun to travel.
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

#Scroll to the bottom of the board. ⚠ ON ENTRY ONLY -- a rebuild that re-anchored would yank the
#view out from under a player who had scrolled somewhere else.

#⚠ WAITS FOR THE SCROLL RANGE TO STOP CHANGING before aiming: panel positions, the shared width and
#the scroll range all settle separately over several frames, so reading `max_value` after a single
#frame clamps the aim against a range that is still growing.

#Re-read `max_value` every frame rather than latching a copy, which would freeze at the same stale
#value. The wait is capped at the pan clock so a board that never settles still gets an aim.
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
# ==============================================================================

#The show opens on the all-grids view; a click on a grid focuses that grid. The overview is
#orientation, so a click there costs the player nothing: it moves the view and never the board.

#The show's OPENING view: the all-grids view, or the single grid FOCUSED when that is all there is.
#The overview is orientation BETWEEN grids, so with exactly one it frames what focused mode already
#frames and the click that leaves it buys the player nothing (owner ruling).

#One grid is the DEFAULT and not an edge case -- a deck of 52 or fewer unlocks exactly one.
func open_show_view() -> void:
	if grid_container.get_child_count() == 1:
#A panel exists, so the game that built it does too; the commitment is the GAME's to make.
		var game := CardEnvironment.get_current_game()
		assert(game, "a grid panel is on the board, so a game built it")
		game.commit_the_only_grid()
		focus_grid(0)
		_snap_the_entrance_home()
		return
	open_zoomed_out()
	_snap_the_entrance_home()

#The Entrance is WHERE IT BELONGS the moment the show opens, never sliding into place: a one-grid
#show opens on its grid and a resumed show opens on the grid it was already committed to, and
#neither is a move the player made.
func _snap_the_entrance_home() -> void:
	_entrance_slide = 0.0 if entrance_home_grid() == NO_GRID else 1.0
	snap_the_view_into_place()

#THE BOARD IS AT ITS SCALE AND ITS GAP ON THIS FRAME, with no travel: the ease belongs to a mode
#change the PLAYER asked for and to a fresh show going live, and nothing else may spend the pan clock.

#⚠ A RE-FIT IS NOT A MODE CHANGE, and neither is a suite latching the view its checks were written
#against. A re-fit issued every frame restarts an eased clock each time, and the board never
#reached its scale at all (measured).
func snap_the_view_into_place() -> void:
	_land_the_opening()
	if _view_tween and _view_tween.is_valid(): _view_tween.kill()
	_view_ease = 1.0
	drawn_zoom = board_zoom
	_drawn_grid_gap = _grid_gap_target()
	_apply_entrance_strip_height()
	_apply_grid_buffer()

## The fraction of its rest scale a fresh show's board is drawn at on the frame it is first seen.
const OPENING_ZOOM_FRACTION := 0.6

#THE ONE OWNER OF "FRESH": a PlayArea is one show, so it owes the opening ease from birth and the
#first time its picture goes live spends it. A resumed show lands at rest (owner ruling).
var _opening_ease_owed := true

## True from a fresh show going live until its board has grown to rest or a view change took over.
var _opening_in_flight := false

#⚠ WHEN THE PICTURE GOES LIVE, NOT AT OPEN: the picture draws no board before then, ~30 frames after
#`open_show_view` (measured), so an ease begun at open is spent unseen.
func ease_the_opening_in() -> void:
	if not _opening_ease_owed: return
	assert(_show_view_opened, "a show lands after its opening view was chosen")
	_opening_ease_owed = false
	_opening_in_flight = true
#⚠ PINNED JUST BEFORE EVERY DRAW: the scroller moves the layout in its own `_process`, after the
#ease's physics tick, and a pin taken there drew the focal point 2.39 px off at 3 grids (measured).
	RenderingServer.frame_pre_draw.connect(_re_pin_the_opening)
	_grow_the_opening_to(0.0)
	_start_the_view_ease()

#⚠ THE WHOLE BOARD SCALES ABOUT THE POINT ITS REST VIEW CENTRES, with its layout left at rest. A
#smaller `drawn_zoom` re-lays the content inside a larger window and the scroll clamps at zero, so
#the board grew from the top-left corner (measured: 215 px of drift at one grid).
func _grow_the_opening_to(t: float) -> void:
	_re_pin_the_opening()
	scale = Vector2.ONE * lerpf(OPENING_ZOOM_FRACTION, 1.0, t)
	if t < 1.0: return
	_opening_in_flight = false
	RenderingServer.frame_pre_draw.disconnect(_re_pin_the_opening)

#The pivot is the point the rest view centres, in this board's own unscaled pixels: the focused
#grid's cell block, or the whole set's in the overview.
func _re_pin_the_opening() -> void:
	if not _opening_in_flight: return
	var to_local := get_global_transform().affine_inverse()
	var span := Rect2()
	for gi : int in grid_container.get_child_count():
		if view_mode == ViewMode.FOCUSED and gi != focused_grid: continue
		var cells := _cells_root(grid_container.get_child(gi) as Control)
		var xf := to_local * cells.get_global_transform()
		var drawn := Rect2(xf.origin, xf.basis_xform(cells.size))
		span = drawn if span.size == Vector2.ZERO else span.merge(drawn)
	pivot_offset = span.get_center()

#A view change or a snap takes over from an opening part way through, so the board is put at scale.
func _land_the_opening() -> void:
	if _opening_in_flight: _grow_the_opening_to(1.0)

#True once the opening view has been settled against the grids that actually EXIST.

#⚠ THERE ARE NO GRIDS AT `_ready()`. The rules deck builds them during the deal, so the opening view
#cannot be chosen until the first rebuild that has one -- and it must be chosen exactly ONCE, or a
#player who zoomed out is yanked back on the next placement.
var _show_view_opened := false

func _open_show_view_once() -> void:
	if _show_view_opened or grid_container.get_child_count() == 0: return
	_show_view_opened = true
	open_show_view()

## Open the all-grids view with nothing focused.
func open_zoomed_out() -> void:
	_set_view(ViewMode.OVERVIEW, NO_GRID)
	_zoom_board_to(overview_board_zoom())
	rest_board()

#The grid the board RESTS centred on, per view mode. `NO_GRID` while there is no grid to rest on.
#FOCUSED: the grid being acted on, and the ONLY grid the "no cut-off grid" rule speaks about -- a
#neighbour sliced by the window edge is not a defect. OVERVIEW: the MIDDLE grid.

#⚠ A RESTING BOARD IS A POSITIONED BOARD. Nothing used to place the board horizontally, so it sat
#at scroll zero -- hard left -- while the view claimed to be centred on a grid.
func resting_grid() -> int:
	var last := grid_container.get_child_count() - 1
	if last < 0: return NO_GRID
	if view_mode == ViewMode.FOCUSED and focused_grid != NO_GRID:
		return clampi(focused_grid, 0, last)
	return last / 2

#Bring the board to its resting position. Reuses the removal re-centre, so opening the board and
#losing a grid move it the same way -- including its wait for the panels to stop moving, which is
#what makes this safe to call before the layout has ever run.
func rest_board() -> void:
	var gi := resting_grid()
	if gi == NO_GRID: return
	pan_grid = gi
	_recentre_board()

#Focus one grid -- what a click on a grid in the overview does. Placement happens focused. Focusing
#also CENTRES the view on that grid: the grid being acted on is the grid in the middle, in both
#modes, so `pan_grid` can never disagree with `focused_grid` about where the view is.
func focus_grid(gi: int) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
	_set_view(ViewMode.FOCUSED, gi)
	_zoom_board_to(focused_board_zoom(gi))
	pan_to_grid(gi)
#⚠ AIM AGAIN ONCE THE ZOOM'S RELAYOUT HAS LANDED. The aim above is exact horizontally -- the
#content's own columns do not move when the board zooms -- but the FLOOR does, and a grid's
#vertical position is measured from it. The same re-aim a removal uses, for the same reason.
	_recentre_board()

#A PICKUP AIMS THE BOARD AT THE GRID THE PLAYER IS LOOKING AT: the Entrance is about to come under
#that grid, and a placement only ever lands focused. A committed grid already owns the board, and
#the grid already focused is where the aim would land anyway, so neither of those re-aims.
func focus_the_grid_in_view() -> void:
	var game := CardEnvironment.get_current_game()
	if game and game.state.committed_grid != -1: return
	var gi := _grid_nearest_the_window_centre()
	if gi == NO_GRID: return
	if view_mode == ViewMode.FOCUSED and gi == focused_grid: return
	focus_grid(gi)

#WHICH GRID SITS NEAREST THE MIDDLE OF THE BOARD'S WINDOW. In the overview the camera is the only
#thing that moves the view and it is always aimed at `pan_grid`, so that IS the answer there.
#Focused, the scroller's live position decides, so a pickup mid-pan lands on the grid still in view.
func _grid_nearest_the_window_centre() -> int:
	var count := grid_container.get_child_count()
	if count == 0: return NO_GRID
	if view_mode == ViewMode.OVERVIEW: return clampi(pan_grid, 0, count - 1)
#⚠ DRAWN ON BOTH SIDES. This answers what the PLAYER is looking at on this frame -- a pickup, a
#drag release, the ease's own re-aim -- so the window it measures against is the drawn one, not the
#one the board is travelling to. Mixed, a pickup mid-ease named the grid the board had left.
	var z := _content_scale_on_screen()
	var centre := _board_window_at(drawn_zoom).x * 0.5
	var best := NO_GRID
	var best_dx := INF
	for gi : int in count:
		var cells := _cells_root(grid_container.get_child(gi) as Control)
		if not cells: continue
		var at := (cells.global_position.x - scroll_container.global_position.x) / z \
				+ cells.size.x * 0.5
		if absf(at - centre) >= best_dx: continue
		best_dx = absf(at - centre)
		best = gi
	return best

# ------------------------------------------------------------------------------
# THE ZOOM — what makes the two modes different on screen and not merely in state
# ------------------------------------------------------------------------------

#The scale a board with nothing to fit is laid out at, and the answer every fit falls back to.
const DEFAULT_BOARD_ZOOM := 1.0

#THE ALL-GRIDS VIEW FITS THE GRIDS THE RUN ACTUALLY HAS. The picture's own size never follows the
#grid count (owner ruling), so the FIT does: two grids in a span built for three used to sit small
#in the middle of it, which is the "shrunk down version" the owner saw.

#⚠ THE SAME FIXED-POINT SHAPE `focused_board_zoom` SOLVES, for the same reason: every term on the
#bottom is authored at scale 1 and grows with the zoom, so the answer is the ratio of the window to
#the authored set, never a value read back off the last layout.
func overview_board_zoom() -> float:
	var count := grid_container.get_child_count()
	if count == 0 or size.x <= 0.0 or size.y <= 0.0: return DEFAULT_BOARD_ZOOM
	var settings_res := PlayArea.settings()
	var gutters := _grid_gutters()
#THE SEPARATION THE CONTAINER ACTUALLY GETS, not the gap: each panel already carries its score
#gutters, and the gap is measured cell block to cell block, so the gutters sit INSIDE it.
	var sep := roundi(maxf(overview_grid_gap_px(settings_res) - gutters.x - gutters.y, 0.0))
	var block_h := 0.0
	var gutter_h := 0.0
	for gi : int in count:
		var grid : GridData = _bound_grids[gi] if gi < _bound_grids.size() else GridData.new()
		block_h = maxf(block_h, grid_block_size_px(settings_res, grid).y)
		gutter_h = maxf(gutter_h, _panel_gutter_h(gi))
	if block_h <= 0.0: return DEFAULT_BOARD_ZOOM
#⚠ ASKED OF THE CONTAINER THAT LAYS THE SET OUT, at the separation this view will give it -- not
#summed here. A sum of the panels missed whatever else the box adds, and the set drew 5.2 px wider
#than the window it was fitted to (measured).
	var was := grid_container.get_theme_constant(&"separation")
	grid_container.add_theme_constant_override("separation", sep)
	var wide := grid_container.get_combined_minimum_size().x
	grid_container.add_theme_constant_override("separation", was)
#⚠ THE FIT IS EXACT AND IDEMPOTENT: the set's authored width at the fit is the window's width, to
#the pixel, twice over.
	var tall := maxf(_board_height_left(), 0.0) / (block_h + gutter_h
			+ entrance_strip_height_px(settings_res, 1.0)
			+ 2.0 * board_edge_pad_px(settings_res))
	return minf(tall, maxf(_board_width_left(), 1.0) / wide)

#The scale the board is being TAKEN TO. Every aim is computed at this one, so a pan and a zoom
#started together land together.
var board_zoom : float = DEFAULT_BOARD_ZOOM

## The scale the board is DRAWN at this frame: it eases toward `board_zoom` over the pan clock.
var drawn_zoom : float = DEFAULT_BOARD_ZOOM

#The focused view's scale: grid `gi`'s CELL BLOCK made exactly as tall as the board's window.
#Derived from the grid's own shape and the window, never authored — a taller grid zooms less. ⚠ The
#block, not the grid's live height: a stack growing upward must not re-scale the board.

#⚠ SOLVED IN CLOSED FORM, NOT READ OFF THE LAST WINDOW. The window and the Entrance strip both
#scale with THIS zoom, so "the block exactly fills the window" is a fixed point in `z`, not a value
#last zoom's strip can supply. Reading it made the first focus and a later step land differently.
func focused_board_zoom(gi: int) -> float:
	if not is_instance_valid(scroll_container): return DEFAULT_BOARD_ZOOM
	var grid : GridData = _bound_grids[gi] if gi >= 0 and gi < _bound_grids.size() else GridData.new()
	var block_h := grid_block_size_px(PlayArea.settings(), grid).y
	var base_strip := entrance_strip_height_px(PlayArea.settings(), 1.0)
	var pad := board_edge_pad_px(PlayArea.settings())
	if block_h <= 0.0 or size.y <= 0.0 or size.x <= 0.0: return DEFAULT_BOARD_ZOOM
	var tall := maxf(_board_height_left(), 0.0) / (block_h + _panel_gutter_h(gi) + base_strip
			+ 2.0 * pad)
	var wide := _panel_width(gi)
	return tall if wide <= 0.0 else minf(tall, maxf(_board_width_left(), 1.0) / wide)

#The whole panel's width — the row-label gutter, the cells and the special-meld label — as one
#MINIMUM-size query, for the same reasons `_panel_gutter_h()` gives.
func _panel_width(gi: int) -> float:
	if gi < 0 or gi >= grid_container.get_child_count(): return 0.0
	var panel := grid_container.get_child(gi) as Control
	return panel.get_combined_minimum_size().x if panel else 0.0

#The score furniture a grid panel carries BELOW its cells: the column-label row and the gap above
#it. Part of what the board's window must hold, or the panel overflows it and the scroller shows a
#bar on a board the player has not even touched.

#⚠ MEASURED FROM THE PANEL, AND IT HAS TO BE. The label's height comes from the FONT (23 px at the
#shipped one), so there is no constant to derive it from.

#⚠ THE DIFFERENCE OF TWO MINIMUM SIZES, NOT OF TWO RECTS. A container answers
#`get_combined_minimum_size()` from its children on demand rather than from the last layout pass,
#so this cannot serve a stale rect the way a `size` read would.

#Subtracting the cells' own minimum takes the stacks' DEPTH back out, which is what keeps a
#deepening stack from re-scaling the board under the player's hand.
func _panel_gutter_h(gi: int) -> float:
	if gi < 0 or gi >= grid_container.get_child_count(): return 0.0
	var panel := grid_container.get_child(gi) as Control
	if not panel: return 0.0
	var cells := _cells_root(panel)
	if not cells: return 0.0
	return maxf(panel.get_combined_minimum_size().y - cells.get_combined_minimum_size().y, 0.0)

#ONE CLOCK FOR THE WHOLE MODE CHANGE: the scale, the gap between grids and the scroll all ease over
#`grid_pan_duration`, so the board travels into place instead of snapping (owner ruling).

#The whole board is re-measured here rather than on the next layout pass, because `pan_to_grid`
#runs immediately after and reads the window and the floor this writes.

#⚠ EVERY AIM IS ISSUED AGAINST THE END STATE, WHICH IS WHAT LETS THE SCALE EASE AT ALL: an aim
#reads `board_zoom` and the end gap, and only what is DRAWN reads `drawn_zoom` and
#`_drawn_grid_gap`.
func _zoom_board_to(z: float) -> void:
	if not is_instance_valid(scroll_container): return
	var target := maxf(z, 0.0001)
#⚠ THE GAP IS PART OF "ALREADY THERE". Once the overview fits the set, two grids leave the two
#modes at the SAME scale and only the gap between them changes -- and a zoom-only test let that
#change snap, which is the thing this ease exists to stop.
	if is_equal_approx(board_zoom, target) and is_equal_approx(drawn_zoom, target) \
			and is_equal_approx(_drawn_grid_gap, _grid_gap_target()): return
	board_zoom = target
	_land_the_opening()
	_start_the_view_ease()

#Travel from the drawn scale and gap to `board_zoom` and the mode's gap over the pan clock.
func _start_the_view_ease() -> void:
	if _view_tween and _view_tween.is_valid(): _view_tween.kill()
	_view_ease = 0.0
	_ease_from = Vector2(drawn_zoom, _drawn_grid_gap)
#READ OFF THE LIVE BOX, not restated: the margin the board is wearing right now is the only honest
#end of the travel, and a mode change part way through another one starts from where it stands.
	var box := scroll_container.get_theme_stylebox(&"panel")
	_end_margin_before_the_ease = box.content_margin_left + _grid_gutters().x
	_view_tween = create_tween()
#⚠ IT MUST RUN WHILE THE TREE IS PAUSED, AND A BOUND TWEEN DOES NOT. The wall holds the tree paused
#for the whole session, so the default `TWEEN_PAUSE_BOUND` froze this one on every Main-hosted
#board: measured, the ease never reached 1 and the board sat mid-transition for good.
	_view_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_view_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_view_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_view_tween.tween_method(_travel_the_view_ease, 0.0, 1.0,
			PlayArea.settings().grid_pan_duration)
	_apply_entrance_strip_height()
	_publish_board_floor()

## How far this mode change has travelled: 0 the frame it started, 1 once the board has arrived.
var _view_ease : float = 1.0
## The drawn scale and the drawn gap this mode change started from -- the ends the ease reads back to.
var _ease_from : Vector2 = Vector2.ZERO
## The one tween the view change runs on, killed by the next change rather than left to fight it.
var _view_tween : Tween = null

#The one writer of both drawn quantities. `_apply_grid_buffer` runs every physics frame and reads
#the gap from here; the scale has to be pushed, because nothing else re-applies the rect.
func _travel_the_view_ease(t: float) -> void:
	_view_ease = t
	if _opening_in_flight: _grow_the_opening_to(t)
	drawn_zoom = lerpf(_ease_from.x, board_zoom, t)
	_drawn_grid_gap = lerpf(_ease_from.y, _grid_gap_target(), t)
	_apply_entrance_strip_height()
	_publish_board_floor()
#⚠ RE-AIMED EVERY FRAME WITH THE TIME LEFT, which is what makes the landing exact. Each aim is
#clamped against the reach the board has THAT frame, and the reach opens with the gap; the final
#frame asks for zero seconds, so the board arrives on the target rather than near it.
	_apply_grid_buffer()
	_aim_the_board_at(pan_grid, PlayArea.settings().grid_pan_duration * (1.0 - t))

#How many global pixels one content pixel is drawn at: the zoom, and the opening's grow above it.
func _content_scale_on_screen() -> float:
	return maxf(scroll_container.get_global_transform().get_scale().x, 0.0001)

#Where the scroller puts the content at `pos` zero: the margin offset it centres with, measured
#rather than restated, so an aim is expressed in the same units the scroller stores.
func _board_content_origin() -> Vector2:
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return Vector2.ZERO
	var z := _content_scale_on_screen()
	return (top_level_vbox.global_position - scroll_container.global_position) / z - smooth.pos


#The grid the view is CENTRED on. Distinct from `focused_grid`, which is `NO_GRID` in the overview:
#the view is centred on some grid in both modes.
var pan_grid : int = 0

#The grid Back zoomed out of, so Forward can return to the same view. `NO_GRID` until Back has
#zoomed out of a focused grid — Forward then has nothing to return to.
var _zoom_out_grid : int = NO_GRID

## True while the grid cells draw their marks instead of the cards played on them.
var plan_layer_open := false:
	set(value):
		if plan_layer_open == value: return
		plan_layer_open = value
#A QUEUED REBUILD DRAWS THIS CLOSE ITSELF: refreshing here instead runs that whole rebuild inside
#the mutation's own await chain, rebinding every pooled slot under a running meld animation.
		if _rebuild_queued: return
#THE CURSOR SURVIVES THE SWAP: the control it sat on stops taking focus the moment a cell's cards
#step aside or come back, so the CELL is read before the resize releases it and its new target
#grabbed after. Focus anywhere but a board cell -- the HUD, the Entrance -- is left where it is.
		var cursor_cell := _coord_of_control(get_viewport().gui_get_focus_owner())
		set_card_zones_visuals()
		if not cursor_cell.is_nowhere() and not cursor_cell.is_entrance():
			var target := _cell_focus_control(cursor_cell)
			if target: target.grab_focus()

#⚠ THE BOARD IS ONE LEVEL OF A STACK THAT CONTINUES PAST IT — one grid, then every grid, then the
#wall. Back steps OUT one level and Forward steps back IN, and both FALL THROUGH once this screen
#has no level left to give, or the wall becomes unreachable from inside a show.

#Panning has its own actions and never touches these. True when this screen consumed the event.
func _consume_as_view_action(event: InputEvent) -> bool:
#The overview's arrow keys pick a GRID, not a cell. Read here as well as on a focused cell's
#own `gui_input` so the arrows still work when nothing on the board holds focus.
	if _consume_as_grid_select(event):
		return true
	if event.is_action_pressed(&"grid_pan_left"):
		pan_by_grids(-1)
		return true
	if event.is_action_pressed(&"grid_pan_right"):
		pan_by_grids(1)
		return true
#Back always takes this one step, even on a one-grid board; cancel there falls straight to the wall.
	if event.is_action_pressed(&"wall_back"):
		if view_mode != ViewMode.FOCUSED: return false
		_zoom_out_grid = focused_grid
		open_zoomed_out()
		return true
	if event.is_action_pressed(&"wall_forward"):
		if view_mode != ViewMode.OVERVIEW or _zoom_out_grid == NO_GRID: return false
		focus_grid(_zoom_out_grid)
		return true
#HELD, AND THE RELEASE IS THE OTHER HALF OF THE PEEK: the marks show while the action is down
#and the played board comes back when it is let go, so the board is never left showing a layer
#nobody asked to stay in. The HUD control toggles this same one flag.
	if event.is_action_pressed(&"ui_plan_layer"):
#NOT OPENED MID-CASCADE, the way a selection is refused there: the board is still resolving and the
#rebuild it ends in would close this peek anyway. The release below still closes, so a peek already
#open when the cascade began is not left behind.
		var game := CardEnvironment.get_current_game()
		if game and not game.processing:
			plan_layer_open = true
		return true
	if event.is_action_released(&"ui_plan_layer"):
		plan_layer_open = false
		return true
	return false

#Pan `step` grids from whichever grid the view is centred on. There is nothing to centre past the
#outermost grid, so the board bounces there instead of moving.
func pan_by_grids(step: int) -> void:
	var last := grid_container.get_child_count() - 1
	if last < 0: return
	var target := pan_grid + step
	if target < 0 or target > last:
		_bounce_board(step)
		return
	pan_to_grid(target)

#Centre the view on grid `gi`.

#⚠ THE CLAMP IS THE SCROLL CONTAINER'S OWN, NOT ARITHMETIC WRITTEN HERE. `scroll_x_to` clamps the
#request to the content's real range. An edge grid reaches the middle of the window because
#`_apply_grid_buffer()` gives the content bare board at each end, never because an aim overshoots.
func pan_to_grid(gi: int) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
	pan_grid = gi
	_aim_the_board_at(gi, PlayArea.settings().grid_pan_duration)

#The aim itself, over `dur`, so the view ease can re-issue it each frame with the time it has LEFT.
#⚠ The scroller clamps each aim to the reach it can see, and the reach opens with the gap: aimed
#once at the start, an outermost grid stayed 2487.7 px from the window's centre (measured).
func _aim_the_board_at(gi: int, dur: float) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
#⚠ OVERVIEW MOVES NOTHING BUT `pan_grid`. The whole set fits the picture, and inside a picture the
#camera rests on the picture's centre — so the step is orientation state the Entrance follows, and
#the scroller's horizontal aim stays dead range rather than becoming a second writer.
	if view_mode == ViewMode.OVERVIEW: return
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	var cells := _cells_root(grid_container.get_child(gi) as Control)
	if not cells: return
	var origin := _board_content_origin()
	var local := _board_local_rect(cells)
#⚠ EVERY TERM HERE IS IN THE SCROLLER'S OWN LOCAL SPACE, WHICH THE ZOOM DOES NOT TOUCH. The zoom
#scales the scroller and divides its rect, so inside it the content keeps its authored size and the
#WINDOW shrinks; multiplying a board length by the zoom again aims the board a whole grid out.
	var window := _board_window_local()
	smooth.scroll_x_to(window.x * 0.5
			- (local.position.x + local.size.x * 0.5) - origin.x, dur)
#⚠ THE VERTICAL AIM IS THE FOCUSED VIEW'S ALONE. Zoomed in, the grid is taller than the window
#unless it is framed, and the edge to frame it by is the FLOOR every grid grows up out of. In the
#overview the board rests vertically and a pan must not yank a player reading a stack.
	smooth.scroll_y_to(window.y - (local.position.y + local.size.y) - origin.y, dur)

#A board control's rect in the CONTENT's own unzoomed space. ⚠ `global_position` already carries the
#scale while `size` never does, so the two cannot be mixed: everything an aim is built from is
#divided back out here, and the target zoom is applied once, at the end.
func _board_local_rect(c: Control) -> Rect2:
	var z := _content_scale_on_screen()
	return Rect2((c.global_position - top_level_vbox.global_position) / z, c.size)

#The edge push-back. FOCUSED keeps the scroll container's OWN overdrag, which supplies the
#counterforce and carries the board back to rest, so the edge feels like every other overscroll in
#the game and nothing here can park the board off its own edge.

#OVERVIEW has nothing to bounce: the camera does not move inside a picture and the scroller's
#horizontal range is dead there, so an end-stop press reads as a board that will not move.
func _bounce_board(step: int) -> void:
	if view_mode == ViewMode.OVERVIEW: return
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	smooth.scroll_horizontally(float(step) * PlayArea.settings().grid_bounce_velocity_px)

## The single write path for the view mode; announces only real changes.
func _set_view(mode: ViewMode, gi: int) -> void:
	if view_mode == mode and focused_grid == gi: return
	view_mode = mode
	focused_grid = gi
	view_mode_changed.emit(mode, gi)

#Which grid a board control belongs to, or `NO_GRID` for anything that is not on a grid — the
#Entrance included, so grabbing a card from the Entrance still works in the overview.
func _grid_index_of(c: Control) -> int:
	if not is_instance_valid(c): return NO_GRID
	var node : Node = c
	while is_instance_valid(node):
		var parent := node.get_parent()
		if parent == grid_container: return node.get_index()
		node = parent
	return NO_GRID

#In the overview, a click on a grid focuses that grid INSTEAD of acting on the card. True when it
#consumed the press. Info mode is not placement, so it is asked first and passes through.
func _consume_as_focus_click(c: Control) -> bool:
	if view_mode != ViewMode.OVERVIEW: return false
	var gi := _grid_index_of(c)
	if gi == NO_GRID: return false
	focus_grid(gi)
	return true

# A press on a face-down card describes its SLOT instead of selecting it: the hidden card is not
# something the player can be handed, so the sidebar must never lock to it. True when it consumed
# the press.
func _consume_as_stock_press(c: Control) -> bool:
	if not is_stock_control(c): return false
	_publish_stock_info(_stock_slot_of_control[c])
	return true

# ==============================================================================
# MOVING THE SELECTION — ARROWS, AND THE ONE-FINGER SWIPE
# ==============================================================================

#The arrows mean two different things, and which one depends on the view mode: focused, they move
#the SELECTED CELL along the board's lattice and cross into the next grid; in the overview they
#select a whole GRID, which Enter then focuses. Same key, two granularities.

#The overview's cursor: which grid the arrows have selected, and the one Enter focuses. Kept in
#step with the board focus, so a grid picked with the mouse and a grid picked with the arrows are
#the same fact.
var selected_grid : int = 0

#Which way an arrow or d-pad press points, `ZERO` for anything else. ⚠ `y` grows DOWNWARD: row 0 is
#a grid's TOP row, so Up is -1.
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

#The board coordinate a bound control names, or `NOWHERE`. An EMPTY cell presents its own zone card,
#which names the cell rather than a card in it — so both are asked.
func _coord_of_control(c: Control) -> BoardCoord:
	if not is_instance_valid(c) or c not in ui_data: return BoardCoord.NOWHERE
	var game := CardEnvironment.get_current_game()
	if not game: return BoardCoord.NOWHERE
	var data : CardData = ui_data[c]
	var coord : BoardCoord = game.state.grid_position_of(data)
	if not coord.is_nowhere(): return coord
	return game.state.cell_type_coord(data)

#ASKED OF THE SIZING, NEVER DECIDED AGAIN HERE: `_size_stack_slot` leaves exactly one child of a
#slot focusable, so a second rule for "the card on show" would be a second answer to one question.
## The control the selection sits on for a cell, or null where no cell is built.
func _cell_focus_control(coord: BoardCoord) -> Control:
	var game := CardEnvironment.get_current_game()
	if not game: return null
	if coord.grid < 0 or coord.grid >= grid_container.get_child_count(): return null
	if coord.grid >= game.state.grids.size(): return null
	var grid : GridData = game.state.grids[coord.grid]
	if not grid: return null
	var slot := _cell_slot(grid_container.get_child(coord.grid) as Control, grid,
			grid.cell_index(coord.x, coord.y))
	if not slot: return null
	for child : Node in slot.get_children():
		var control := child as Control
		if control.focus_mode == Control.FOCUS_ALL: return control
	return null

#Arrow movement of the selected CELL, focused mode only. True when it consumed the press.

#⚠ THE MOVEMENT IS `BoardCoord.step` OVER THE UNBOUNDED LATTICE, NEVER ARITHMETIC WRITTEN HERE.
#Stepping off a grid's edge lands in the next grid's block; whether a cell EXISTS there is asked at
#landing, and a landing on nothing consumes the press and moves nothing rather than wrapping.

#⚠ CROSSING CARRIES THE VIEW WITH IT, or the selection would walk off screen: the landing grid is
#focused, which also centres it.

#DOWN OFF THE BOTTOM ROW IS THE ENTRANCE'S DOOR with nothing in hand: the stop nearest the column,
#or, when the Entrance sits under ANOTHER grid, its leftmost card with the view carried there.
#With a card in hand the aim stays on the grid, and the press moves nothing.
func _consume_as_cell_move(event: InputEvent, control: Control) -> bool:
	if view_mode != ViewMode.FOCUSED: return false
	var d := _arrow_delta(event)
	if d == Vector2i.ZERO: return false
	var from := _coord_of_control(control)
	if from.is_nowhere() or from.is_entrance(): return false
	var game := CardEnvironment.get_current_game()
	if not game: return false
	var to := from.step(d.x, d.y, _grid_widths())
	if not game.state.has_cell(to):
		if (d == Vector2i.DOWN and selected_cards.is_empty()
				and to.y >= game.state.grids[to.grid].grid_height):
			var home := entrance_home_grid()
			var elsewhere := home not in [NO_GRID, to.grid]
			var stop := _entrance_stop_nearest(
					NO_RELEASE_X if elsewhere else control.get_global_rect().get_center().x)
			if stop: stop.grab_focus()
			if stop and elsewhere: focus_grid(home)
		return true
	var target := _cell_focus_control(to)
	if not target: return true
	target.grab_focus()
	if to.grid != from.grid: focus_grid(to.grid)
	return true

#Arrow selection of a whole GRID, overview only — a different granularity from the focused mode's
#cell movement, matching the wall's own overview. The view follows the selection and the board
#focus moves with it, so Enter and the mouse agree. Up and Down mean nothing here and fall through.

#⚠ THE PAN IS THE LAST WRITER, ALWAYS — GRAB THE FOCUS FIRST. The scroll container follows focus,
#so a focus change kills the in-flight pan and re-aims to put the control just inside the window
#edge, leaving the selected grid on screen but NOT centred (measured: 227 px off).
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

#Key input on a FOCUSED board cell.

#⚠ THIS IS THE ONLY PLACE THE BOARD CAN HEAR AN ARROW KEY. The viewport's own focus-neighbour
#search runs in the GUI pass and consumes any arrow that finds a neighbour, so an arrow read from
#`_unhandled_input` would never arrive while a cell holds focus.

#The selection would then drift by SCREEN GEOMETRY instead of along the board's lattice, with
#nothing panning to follow it. `accept_event` is what stops that search from also running.
func _on_cell_gui_input(event: InputEvent, control: Control) -> void:
	if _arrow_delta(event) == Vector2i.ZERO: return
	if _consume_as_sidebar_edge(event, control) or _consume_as_cell_move(event, control) \
			or _consume_as_grid_select(event):
		control.accept_event()

#THE BOARD'S LEFT EDGE IS THE SIDEBAR'S DOOR, the way a viewer list's edge is: the press has
#nowhere left to go on the board, and the sidebar is in the overlay's viewport, which no focus
#search reaches from here. Asked FIRST, so the movers below never swallow the edge press.

#⚠ THE ENTRANCE AND A CELL ARE DIFFERENT QUESTIONS. An Entrance stop is at the edge when
#`_link_arrow_stops` left it no left neighbour, which is the same fact a skipped face-down slot
#moves; a cell is at the edge when the lattice step lands on no cell at all.
func _consume_as_sidebar_edge(event: InputEvent, control: Control) -> bool:
	if _arrow_delta(event) != Vector2i.LEFT: return false
	var at_the_edge := false
	if upper_zone_right.is_ancestor_of(control):
		at_the_edge = control.focus_neighbor_left.is_empty()
	elif view_mode == ViewMode.OVERVIEW:
		at_the_edge = selected_grid <= 0
	else:
		var from := _coord_of_control(control)
		at_the_edge = (not from.is_nowhere()
				and not CardEnvironment.get_current_game().state.has_cell(
				from.step(-1, 0, _grid_widths())))
	if not at_the_edge: return false
	sidebar_requested.emit()
	return true

#Does a BOARD control genuinely hold the focus right now? `focused_control` is a last-known value
#and goes stale as soon as focus moves to other UI, so the viewport is asked too.
func _board_control_has_focus() -> bool:
	return (is_instance_valid(focused_control) and focused_control in ui_data
			and get_viewport().gui_get_focus_owner() == focused_control)

## Where the live one-finger drag began, in screen pixels.
var _swipe_origin := Vector2.ZERO
#Armed only by a touch that began on BARE BOARD. A drag that begins on a card is a placement — the
#same distinction the wall draws between a press on a picture and a press on bare wall.
var _swipe_armed := false
## ONE GRID PER SWIPE: latched when the threshold is crossed, re-armed only when the finger lifts.
var _swipe_fired := false

#How far a finger must travel before the drag is a pan, in px: the millimetre knob converted at the
#screen's DPI, clamped to the SWIPE's own millimetre bounds converted the same way.

#⚠ THE CLAMP GUARDS THE DPI READING, NOT THE GESTURE'S SIZE. A DPI reading is unreliable on
#multi-monitor Windows, which reports the primary screen's for all of them, and on Android, so an
#unclamped conversion can produce any number at all.

#⚠ BOTH BOUNDS ARE MILLIMETRES, so the whole clamp survives a DPI change together. Touch-TARGET
#bounds are the wrong ones here: their floor of 32 px is ~8.5 mm at 96 DPI, roughly three times the
#paging slop Android uses, and it sat above the knob's own default so turning the knob did nothing.
func _swipe_threshold_px() -> float:
	return GestureMetrics.drag_threshold_px(board_card_picture_px(), PlayArea.settings())

#The bound board control under a point, or null for bare board. The zone card an EMPTY cell presents
#counts as a card: it is the cell's drop target, so a drag begun on it is a placement.
func _card_control_at(at: Vector2) -> Control:
	for c : Control in ui_data:
		if not is_instance_valid(c) or not c.is_visible_in_tree(): continue
		if c.get_global_rect().has_point(at): return c
	return null

#The one-finger swipe. True only when a pan actually fired. ⚠ A press only ARMS: it consumes
#nothing, and moves nothing until the finger does.

#⚠ READ FROM `InputEventScreenDrag` AND NOTHING ELSE. With `emulate_mouse_from_touch` at its
#default of true, one finger arrives as BOTH a screen drag and a synthesised
#`InputEventMouseMotion`, and a reader that accepted either form pans TWICE per swipe.

#⚠ `device == -1` MARKS THE ENGINE'S OWN SYNTHESIS (a mouse emulating touch), so filtering it keeps
#a real mouse drag from panning the board.

#⚠ DRIVEN FROM `_input`, NEVER `_unhandled_input` — see the routing note there.
func _consume_as_swipe(event: InputEvent) -> bool:
	if event.device == -1: return false
	var touch := event as InputEventScreenTouch
	if touch:
		_swipe_fired = false
		_swipe_armed = false
		if touch.pressed:
			flush_rebuild()
			_swipe_origin = touch.position
			_swipe_armed = _card_control_at(touch.position) == null
		return false
	var drag := event as InputEventScreenDrag
	if not drag or not _swipe_armed or _swipe_fired: return false
	var travel := drag.position.x - _swipe_origin.x
	if absf(travel) < _swipe_threshold_px(): return false
	_swipe_fired = true
#The board follows the finger: dragging RIGHT brings the grid on the left into view.
	pan_by_grids(-1 if travel > 0.0 else 1)
	return true

## Where the live gesture's press landed, in this board's own pixels.
var _press_origin := Vector2.ZERO
## The card the press landed on, or null on bare board -- the DATA, never the control, which slot pooling can free.
var _press_data : CardData = null
## The pressed card's drawn size, which is this gesture's own threshold reference.
var _press_card_px := Vector2.ZERO
## ONE PICKUP PER DRAG -- the swipe's own latch, in the card's half of the gesture.
var _drag_began := false
## The board's committed depth when the press a second one could pair with landed.
var _depth_when_pressed : int = 0
## Set by a closed PAIR, tapped or refused, and read by the release closing its gesture: that release is not a click, so it can neither re-grab what a tap let go nor place again after a refusal.
var _tapped_this_gesture := false
## Where the last finger press landed, for the next one to pair with.
var _touch_press_at := Vector2.ZERO
## When the last finger press landed, in milliseconds.
var _touch_press_msec : int = 0
## The board's committed depth when the finger press a second one could pair with landed.
var _touch_press_depth : int = 0
## When the last accept press on a board card landed, in milliseconds.
var _accept_press_msec : int = 0
## The card the last accept press landed on: a pair is two presses on ONE card, as a click pair is.
var _accept_press_data : CardData = null

# A press only ARMS the gesture -- which card, where, and at what size -- so the release can tell a
# click from a drag. A FINGER ARMS IT TOO: `emulate_mouse_from_touch` gives every touch its mouse
# form, which is why one gesture model needs no reader of its own for the touch forms.
func _arm_card_gesture(at: Vector2) -> void:
	flush_rebuild()
	_press_origin = at
	_drag_began = false
	_depth_when_pressed = _committed_depth()
	var control := _card_control_at(at)
	_press_data = ui_data.get(control)
	_press_card_px = control.get_global_rect().size if control else board_card_picture_px()

# How far this gesture must travel before its release places instead of its click grabbing.
func _gesture_threshold_px() -> float:
	return GestureMetrics.drag_threshold_px(_press_card_px, PlayArea.settings())

# How many steps the board has committed. A placement moves it, which is how a tap tells one
# apart from the grab it is allowed to undo.
func _committed_depth() -> int:
	var game := CardEnvironment.get_current_game()
	return game.save_history.size() if game else 0

# The card a pointer tap found, flushed first because a pending rebuild moves the controls it reads.
func _tapped_card_at(at: Vector2) -> CardData:
	flush_rebuild()
	var data : CardData = ui_data.get(_card_control_at(at))
	return data

# A TAP UNDOES THE PRESS THAT OPENED ITS PAIR, and only a GRAB can be undone: once that press has
# committed a step it placed a card, and a placement is never rewound by a tap.
func _pair_taps(data: CardData, depth_at_the_opening_press: int) -> bool:
	if not data or _committed_depth() != depth_at_the_opening_press: return false
	return _emit_if_played(card_tapped, data)

# THE ENGINE PAIRS THE MOUSE'S OWN PRESSES: `double_click` arrives on the second one, at the OS
# interval. A finger's mouse form (device -1) is left to the touch reader below, so one pair of
# finger presses can never tap twice.
func _press_closes_a_pair(button: InputEventMouseButton) -> bool:
	if not button.double_click or button.device == -1: return false
	_close_a_pair(_tapped_card_at(button.position), _depth_when_pressed)
	return true

# ⚠ THE ONE PLACE A PAIR CLOSES, whichever input closed it: the release that ends it is never a
# click, so a REFUSAL is marked exactly as a tap is, or it places again through the GUI pass.
func _close_a_pair(data: CardData, depth_at_the_opening_press: int) -> bool:
	var tapped := _pair_taps(data, depth_at_the_opening_press)
	_tapped_this_gesture = true
	return tapped

# GODOT NEVER MARKS A DOUBLE TAP ON A WINDOWS TOUCHSCREEN, so the board pairs two finger presses
# itself: inside the tap window, no further apart than this gesture's own drag threshold, and
# against a depth of its OWN -- the mouse form Godot emulates arrives first and re-arms the gesture.
func _consume_as_touch_tap(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if not touch or not touch.pressed or touch.device == -1: return false
	var now := Time.get_ticks_msec()
	var paired := (now - _touch_press_msec <= PlayArea.settings().card_tap_window_ms
			and _touch_press_at.distance_to(touch.position) <= _gesture_threshold_px())
	_touch_press_msec = now
	_touch_press_at = touch.position
	if not paired:
		_touch_press_depth = _committed_depth()
		return false
	return _close_a_pair(_tapped_card_at(touch.position), _touch_press_depth)

# Two accept presses inside the tap window are a tap, which is how a keyboard or pad reaches one
# without the bound action. The OPENING press is the one whose committed depth a refusal reads.

#⚠ ON THE SAME CARD: a lift, one arrow and an accept on a cell fit inside the window (measured
#~300 ms), and pairing them tapped the lifted card back instead of placing it.
func _accept_press_pairs() -> bool:
	var now := Time.get_ticks_msec()
	var data : CardData = ui_data[focused_control]
	var paired := (data == _accept_press_data
			and now - _accept_press_msec <= PlayArea.settings().card_tap_window_ms)
	_accept_press_msec = now
	_accept_press_data = data
	if not paired: _depth_when_pressed = _committed_depth()
	return paired

# THE DRAG DECIDES WHICH CARD IS MOVING, so one that starts on a card the player is not already
# holding takes that card up, and lets go of whatever was held.
func _take_up_the_dragged_card(at: Vector2) -> void:
	if _drag_began or not _press_data: return
	if _press_origin.distance_to(at) <= _gesture_threshold_px(): return
	_drag_began = true
	if _press_data in selected_cards: return
	_next_grab_follows = true
	_emit_if_played(card_dragged, _press_data)

# ⚠ THE ONE PLACE A GESTURE ENDS -- a release, or a cancel that let the card go. Motion once no
# press is live is not a drag, a remembered press turned the next hover into one, and a cancelled
# drag whose press outlived it placed a hand nobody was holding.
func _end_the_gesture() -> void:
	_press_data = null

# A gesture that TRAVELLED is never a click, and the GUI pass below never sees it. It places only
# when the dragged card IS the held one: a card no rule picked up carries nothing, so a card
# already lifted must not land in its place. EVERY release ends the chase, whichever branch it takes.
func _consume_as_card_release(button: InputEventMouseButton) -> bool:
	if button.button_index != MOUSE_BUTTON_LEFT or button.pressed: return false
	var dragged := _press_data
	_end_the_gesture()
	stop_following()
	if _tapped_this_gesture:
		_tapped_this_gesture = false
		return true
	if _press_origin.distance_to(button.position) <= _gesture_threshold_px(): return false
	if dragged in selected_cards: _release_places(button.position)
	return true

# The release places onto whatever the board offers under it, and the board answers whether that
# is legal. Over bare board, over the container or off the window nothing is under it at all, so the
# card is simply let go -- an ACT by the player, unlike a cancel, which is why the view is told.
func _release_places(at: Vector2) -> void:
	var target := _card_control_at(at)
	if target:
		_emit_if_played(card_dropped, ui_data[target])
		return
	ungrab_cards()
	hand_released.emit()

## Nothing tracks the cursor until the next drag: a held card stays held and lifted, and a drag still waiting on its grab no longer promises one.
func stop_following() -> void:
	_next_grab_follows = false
	for data : CardData in selected_cards:
		if data in data_card: data_card[data].following = false

# A CLICK IS DECIDED AT THE RELEASE: a press that travelled places instead, and `_input` consumes
# that one before the GUI pass ever reaches here.
func _on_gui_input(event: InputEvent) -> void:
	flush_rebuild()
#Mouse ONLY: key and joypad events never reach this root handler — Godot 4 delivers them to the
#FOCUSED control alone, with no ancestor bubbling — so keyboard and controller accept and cancel
#live in `_unhandled_input` below.
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
# left click
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
# is_instance_valid guard: a board rebuild (e.g. submit clearing the board)
# can free the control this still points at, and `freed in typed_dict` errors.
			if (is_instance_valid(focused_control)
					and focused_control == moused_hovered_control
					and focused_control in ui_data):
#and not focused_control.is_in_group("CardVisualZoneControl")):
				if (not _consume_as_focus_click(focused_control)
						and not _consume_as_stock_press(focused_control)):
					_emit_if_played(data_selected, ui_data[focused_control])
			elif _card_control_at(get_global_mouse_position()) == null:
				description_dismiss_requested.emit()

#Keyboard and controller accept + cancel. Key events go ONLY to the focused control, then fall
#through the focus-navigation pass to unhandled input, which is the first place the board can hear
#them. A button consumes its own ui_accept before this runs, so a focused button never double-acts.
func _unhandled_input(event: InputEvent) -> void:
#THE VIEW GETS FIRST REFUSAL, and gives the event straight back when it has no level left to step
#out of — see `_consume_as_view_action`.
	if _consume_as_view_action(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("card_tap"):
		flush_rebuild()
		if _board_control_has_focus():
			_emit_if_played(card_tapped, ui_data[focused_control])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
#IN THE OVERVIEW, ENTER FOCUSES THE SELECTED GRID even when nothing on the board holds focus:
#an arrow selection must be committable on its own. A focused board control goes through
#_consume_as_focus_click below instead, which keeps an ENTRANCE card selectable in the overview.
		if view_mode == ViewMode.OVERVIEW and not _board_control_has_focus():
			focus_grid(selected_grid)
			get_viewport().set_input_as_handled()
			return
		flush_rebuild()
#Act only when a BOARD control genuinely holds focus RIGHT NOW: `focused_control` is our last-known
#card control, it can go stale when focus moves to other UI, and it must stay inert while the
#game-over overlay has the board focus-locked.
		if _board_control_has_focus():
			if _accept_press_pairs():
				_pair_taps(ui_data[focused_control], _depth_when_pressed)
			elif (not _consume_as_focus_click(focused_control)
					and not _consume_as_stock_press(focused_control)):
				_emit_if_played(data_selected, ui_data[focused_control])
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _cancel_everything(): get_viewport().set_input_as_handled()

#Clicks outside the play area reach here too.

#⚠ THE ONE-FINGER PAN IS READ HERE, AND CANNOT BE READ FROM `_unhandled_input`. Godot routes
#`InputEventScreenTouch` and `InputEventScreenDrag` through the same viewport GUI pass as the
#mouse, and the first MOUSE_FILTER_STOP control under the finger marks them handled.

#`_input` runs BEFORE that pass, which is the only place the board can hear a finger on it.
#Measured: the swipe reader was unreachable in the product while its tests, which called the
#handler directly, were green.
func _input(event: InputEvent) -> void:
	if _consume_as_swipe(event):
		get_viewport().set_input_as_handled()
		return
	if _consume_as_touch_tap(event):
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion:
		_take_up_the_dragged_card(motion.position)
		_on_pointer_moved(motion.position)
# Mouse
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
#right click / cancel
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_cancel_one_step()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if not _press_closes_a_pair(mouse_event): _arm_card_gesture(mouse_event.position)
			return
#A GESTURE THAT TRAVELLED CARRYING NO CARD IS A PAN, and it is the only release that ends on a
#grid. Read BEFORE the release resolves, which clears the press it is measured from.
		var panned := (_press_origin.distance_to(mouse_event.position) > _gesture_threshold_px()
				and not (_press_data in selected_cards))
		if _consume_as_card_release(mouse_event):
			get_viewport().set_input_as_handled()
		_end_the_content_drag(panned, mouse_event.position.x)

# ONLY A LIVE DRAG CARRIES A CARD: motion with no button down leaves a lifted card resting in its
# slot. Crossing OUT of the held card's own cell closes the description, read before that, and
# NEVER for the card that same click locked.
func _on_pointer_moved(at: Vector2) -> void:
	if selected_cards.is_empty(): return
	var carried : CardVisual = data_card.get(selected_cards[0])
	if not carried: return
	var inside := _origin_cell_rect(carried).has_point(at)
	var crossed_out_of_its_cell := carried.following and _pointer_was_in_the_origin_cell and not inside
	if crossed_out_of_its_cell and locked_data != selected_cards[0]:
		description_dismiss_requested.emit()
	_pointer_was_in_the_origin_cell = inside
	if _drag_began and _press_data: follow_cards()

## Where the pointer was last seen relative to the held card's own cell: a dismissal needs a real crossing OUT of it, and a card lifted with the cursor elsewhere was never inside it to cross.
var _pointer_was_in_the_origin_cell : bool = false

# The cell a held card came from: its own control stays put — only the visual rides the cursor —
# and a card control's parent IS its cell slot.
func _origin_cell_rect(carried: CardVisual) -> Rect2:
	return (carried.control_anchor.get_parent() as Control).get_global_rect()

## Every held card now tracks the cursor — one way, until the card is placed or cancelled.
func follow_cards() -> void:
	for data : CardData in selected_cards:
		if data in data_card: data_card[data].following = true

# A card a DRAG took up follows at once, but the pickup lands behind `try_grab`'s own await, after
# the motion that started the drag has returned. The drag leaves this for the grab it asked for;
# any other way the selection resolves drops it.
var _next_grab_follows : bool = false

#THE LAYER VIEW IS A VIEWER AND INPUT IS LOCKED TO LOOKING: no signal that grabs, places or drops
#a card is emitted while it is open, whichever route asked -- click, pad, tap or drag. Camera
#navigation and inspection reach the board through other paths and stay live.

## False when the layer view refused it, which is the caller's cue to rest the card it was carrying.
func _emit_if_played(sig: Signal, data: CardData) -> bool:
	if plan_layer_open: return false
	sig.emit(data)
	return true

# A card a CLICK took up is lifted in its slot; only a card a DRAG took up is born following.
func grab_cards(datas:Array[CardData]) -> void:
	var follows_at_once := _next_grab_follows
#reads data_card / data_ui
	flush_rebuild()
	ungrab_cards()
	selected_cards = datas
	set_card_zones_visuals()
	for index in selected_cards.size():
		var data := selected_cards[index]
		if data in data_card:
			var card_visual := data_card[data]
			card_visual.held = index + 1
			card_visual.following = follows_at_once
#Held cards ride ABOVE all resting cards and still below PropLayer: move_child to the end of the
#card's OWN layer, never z_index, which is the structural order LAYERING.md states. A rebuild
#after ungrab_cards restores row-major order.
			var vis_layer := card_visual.get_parent()
			if vis_layer == card_layer or vis_layer == entrance_card_layer:
				(vis_layer as Node2D).move_child(card_visual, -1)
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var carried : CardVisual = data_card.get(selected_cards[0]) if selected_cards else null
	_pointer_was_in_the_origin_cell = (carried != null
			and _origin_cell_rect(carried).has_point(get_global_mouse_position()))
	_sweep_legal_cells()

#⚠ THE SCROLL CONTAINER NEVER SEES THE RELEASE THAT ENDS ITS DRAG, so the board ends it. A release
#this board consumes is marked handled before the GUI pass, so `content_dragging` stayed latched
#and bare motion went on panning until a later click fell through: the pan became a toggle.

#`lands_on_a_grid` is true for a gesture that TRAVELLED carrying no card -- a drag pan, which the
#owner's rule ends on the grid nearest the middle of the window, as Left and Right do -- and for a
#CANCEL, which ends a latched pan the same way rather than leaving the board between two grids.
func _end_the_content_drag(lands_on_a_grid: bool, release_x: float) -> void:
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth or not smooth.input_handler.content_dragging: return
	smooth.input_handler._end_content_drag()
	if not lands_on_a_grid: return
#A DRAG PAN IS A POINTER GESTURE, so the keyboard carries on from where the pointer left off: the
#Entrance CARD nearest the release takes the focus, the leftmost when no x names one.
#⚠ GRAB BEFORE THE PAN. A focus change re-aims the scroller, so a later grab would undo the aim.

	var target := _entrance_stop_nearest(release_x)
	if target: target.grab_focus()
	pan_to_grid(_grid_nearest_the_window_centre())

#The Entrance CARD nearest `x`, or the leftmost when `x` is not finite; null while the Entrance is
#empty, between the last placement and the refill, which neither a drag pan nor an arrow waits out.
#⚠ AN EMPTIED SLOT IS STILL AN ARROW STOP: the stops that HOLD a card win, the rest only when none do.
func _entrance_stop_nearest(x: float) -> Control:
	if _entrance_stops.is_empty(): return null
	var state := CardEnvironment.get_current_game().state
	var stops : Array[Control] = []
	for stop : Control in _entrance_stops:
		if _entrance_slot_holding(state, ui_data[stop]) != -1: stops.append(stop)
	if stops.is_empty(): stops = _entrance_stops
	var target := stops[0]
	if not is_finite(x): return target
	var nearest := INF
	for stop : Control in stops:
		var dx := absf(stop.get_global_rect().get_center().x - x)
		if dx >= nearest: continue
		nearest = dx
		target = stop
	return target

## A release with no pointer behind it: the Entrance's leftmost stop takes the focus instead.
const NO_RELEASE_X := INF

# THE SECOND BUTTON CANCELS ONE THING PER PRESS: the held card is let go first, so the description
# it was read against survives that press, then the description, then the grid itself.
func _cancel_one_step() -> void:
	_end_the_gesture()
#THE LANDING IS NOT A RUNG: it rides the press and the ladder below still spends it, so a cancel
#that also steps out lands first and the overview's own rest then supersedes the aim.
	_end_the_content_drag(true, NO_RELEASE_X)
	if selected_cards:
		ungrab_cards()
		return
	if locked_data != null:
		description_dismiss_requested.emit()
		return
	if _step_out_of_the_focused_grid(): return
	description_dismiss_requested.emit()

#THE FOCUSED GRID IS A LEVEL OF ITS OWN, and a cancel steps out of it to the every-grid view, where
#another grid can be chosen (owner ruling). Back takes this same step, and leaves `_zoom_out_grid`
#the same way so Forward returns to the grid that was left.

#⚠ ONE GRID IS NOT A LEVEL: the overview frames exactly what the focused view frames, so there is
#nothing to step out to and the press belongs to the wall instead (`open_show_view`).
func _step_out_of_the_focused_grid() -> bool:
	if view_mode != ViewMode.FOCUSED or grid_container.get_child_count() <= 1: return false
	_zoom_out_grid = focused_grid
	open_zoomed_out()
	return true

# Escape does everything the second button would, in the one press. It is consumed ONLY when it
# stepped out of a grid; otherwise the wall hears it and takes its own step out of the screen.
func _cancel_everything() -> bool:
	_end_the_gesture()
	_end_the_content_drag(true, NO_RELEASE_X)
#⚠ READ BEFORE THE CANCEL SPENDS THEM. A press that let a card go or took a description down has
#done its work, and the owner's one-press rule sends it on to the wall from there.
	var spent := not selected_cards.is_empty() or locked_data != null
	ungrab_cards()
	description_dismiss_requested.emit()
	return false if spent else _step_out_of_the_focused_grid()

func ungrab_cards() -> void:
	_next_grab_follows = false
#reads data_card / data_ui
	flush_rebuild()
	for data in selected_cards:
		if data in data_card:
			var card_visual := data_card[data]
			card_visual.held = 0
			card_visual.following = false
			var card_control := data_ui[data]
			card_control.mouse_filter = Control.MOUSE_FILTER_PASS
	selected_cards = []
	set_card_zones_visuals()
	_sweep_legal_cells()

# THE EXIT X TAKES THE FOCUS OUT OF THE BOARD'S VIEWPORT, and hiding it leaves nothing focused, so a
# key/pad player is put back on the card they were reading, or rested on the board once that control
# is gone. A rest, not a highlight: it must not re-open the description that was just dismissed.
func return_focus_to_board() -> void:
	flush_rebuild()
	if is_instance_valid(focused_control) and focused_control in ui_data:
		_rest_focus_on(focused_control)
	else:
		rest_focus_on_board()

# A pad player needs a control to move from with nothing in hand: the selected grid's origin cell,
# the cell the overview's arrow selection lands on. A card the player is holding takes it instead.
# It is a rest, not a highlight -- it publishes no description.

# ⚠ A BOARD CAN OFFER NOTHING TO REST ON, and then there is nothing to do. `_cell_focus_control`
# answers null with no current game, with a grid not built, and while `board_focus_locked` holds
# every cell at FOCUS_NONE -- which both of GameView's callers reach, so it is answered once, here.
func rest_focus_on_board() -> void:
	flush_rebuild()
	if selected_cards:
		var held : Control = data_ui.get(selected_cards[0])
		assert(held, "a held card has a control: grab_cards indexes data_ui for every card it takes")
		_rest_focus_on(held)
		return
	var cell := _cell_focus_control(BoardCoord.new(selected_grid, 0, 0, 0))
	if not cell: return
	_rest_focus_on(cell)

func _rest_focus_on(control: Control) -> void:
	assert(control, "a rest needs a control; rest_focus_on_board answers the empty board")
	_focus_is_resting = true
	control.grab_focus()
	_focus_is_resting = false

## True only across a rest focus, which marks a card without announcing it.
var _focus_is_resting : bool = false

#Game over: the outcome overlay covers the board and blocks the mouse, but keyboard or controller
#focus could still walk onto the covered cards — drop it, and KEEP it dropped through rebuilds,
#because the final Submit's discard queues a rebuild that lands after the overlay went up.
var board_focus_locked := false

func disable_board_focus() -> void:
	board_focus_locked = true
	for control : Control in ui_data:
		control.focus_mode = Control.FOCUS_NONE

#Outcome dismissed (undo): unlock and restore card focus. The dismissal's full rebuild follows
#immediately and re-derives the header focus exceptions, so a blanket FOCUS_ALL here is safe.
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
#A VIEWER CANNOT WATCH A BOARD THAT CHANGED UNDER IT, so every mutation closes the layer view.
#Closed AFTER the request is queued: the close then draws nothing of its own and the rebuild above
#draws the closed board at the end of the frame, like every other mutation's.
	plan_layer_open = false

func _deferred_rebuild() -> void:
	if not _rebuild_queued: return
	set_card_zones()

#GUARD RULE: ui_data / data_ui / data_card and the control tree are only valid for the CURRENT
#revision. Anything that reads them must flush the queued rebuild first, or it operates on a stale
#layout (out-of-bounds crashes, missing visuals).

#True once every current card visual is in-tree and _ready, i.e. its @onready nodes exist.
#CardVisuals add_child via call_deferred, so right after a rebuild they are mapped in data_card but
#not yet ready, and a caller that animates visuals immediately waits on this first.
func visuals_ready() -> bool:
	for visual: CardVisual in data_card.values():
		if not is_instance_valid(visual) or not visual.is_node_ready():
			return false
	return true

func flush_rebuild() -> void:
	if _rebuild_queued:
#A board rebuild is the single most disruptive thing the visual layer does — every pooled slot
#control is rebound, so any card position read before it is stale after it. Logged because "the
#beam was in the wrong place" and "the board moved under the beam" look identical on screen.
		EventLog.event(EventLog.CH_BOARD, "rebuild", "cards=%d" % data_card.size())
		set_card_zones()

#The board Control at a slot coord (z == -1 header, z >= 0 row card), or null when the layout has
#no control there. Focus and input helpers use this; slot GEOMETRY does not, because
#`slot_center_global` below is pure math (owner spec).
func control_for_coord(v: Vector3i) -> Control:
	var hbox : HBoxContainer = upper_zone_right
	if v.y < 0 or v.y >= hbox.get_child_count(): return null
	var vbox := hbox.get_child(v.y)
	var cards := vbox.get_child_count() - 1
	var idx := cards if v.z < 0 else cards - 1 - (v.z + _face_down_depth(v.y))
	if idx < 0 or idx >= vbox.get_child_count(): return null
	return vbox.get_child(idx) as Control

#Global-space centre of the CARD at any board coord — PURE MATH, with no control-rect reads on the
#hot path (owner spec): geometry is deterministic and independent of container relayout timing, and
#the one formula covers occupied, empty and off-board slots alike. Every prop anchors through it.
func slot_center_global(coord: BoardCoord) -> Vector2:
	if coord.y == BoardCoord.ENTRANCE_ROW:
		return _entrance_slot_center_global(coord)
	return _grid_slot_center_global(coord)

#Which `CardVisual` layer a BOARD COORD's card draws in — `PropLayer`'s split-prop bracketing needs
#this to move or query the right layer now that the Entrance and the grids no longer share one
#`CardLayer`.
func card_layer_for(coord: BoardCoord) -> Node2D:
	return entrance_card_layer if coord.y == BoardCoord.ENTRANCE_ROW else card_layer

#THE ONE PLACE THE BOARD'S STACKING GEOMETRY LIVES. A card at height `h` sits `h` depth pitches
#ABOVE the line its stack rests on, and its centre is half a card above its own bottom edge; column
#`column` is that many card-and-separation steps right of `origin_x`.

#⚠ A GRID CELL AND AN ENTRANCE COLUMN ARE THE SAME STACK (owner: *"all stacking should use same
#code. no duplication"*). They differ only in which line they rest on and where their columns
#start, so that is all either caller supplies.

#⚠ EVERY LENGTH HERE IS A BOARD LENGTH AND THE ORIGIN IS A SCREEN POINT. The board draws at
#`drawn_zoom`, so each is taken into screen pixels before it is added to a measured global.
func _stack_slot_center(origin_x: float, floor_y: float, column: int, h: int) -> Vector2:
	var z := _content_scale_on_screen()
	var width := CardVisual.card_size_play.x * z
	var sep := float(separation) * z
	var x := origin_x + float(column) * (width + sep) + width * 0.5
	var y := floor_y - _depth_pitch_px() * z * float(h) \
			- CardVisual.card_size_play.y * z * 0.5
	return Vector2(x, y)

#⚠ NO SEPARATION: a `VBoxContainer` gives even a zero-height child one and the row grew at its
#FIRST card. In the `marks_layer` a cell's cards collapse instead, so its mark takes size and focus.
#⚠ NEVER GRANTS FOCUS WHILE `board_focus_locked`: every visuals refresh runs here.

#⚠ A FACE-DOWN STOCK CARD KEEPS ITS OWN FOCUS_CLICK, which is what walks the arrows past it.
#This runs on every refresh, after `_mark_stock_controls` set it.

#⚠ A FACE-DOWN STOCK CARD TAKES NO HEIGHT: a lift means the player is holding the card, so the
#stock must sit UNDER the slot's card at the same point rather than displace it one pitch up.

## **THE ONE PLACE A STACK'S CONTROLS ARE SIZED, AND SO WHERE A CELL'S FOCUS LANDS.**
func _size_stack_slot(slot: Control, marks_layer: bool) -> void:
	slot.add_theme_constant_override("separation", 0)
	var occupied := slot.get_child_count() > 1 and not marks_layer
	var grants_focus := not board_focus_locked
	var zone_control : Control = slot.get_child(-1)
	zone_control.custom_minimum_size = CardVisual.card_size_play if not occupied \
			else Vector2(CardVisual.card_size_play.x, 0)
	zone_control.focus_mode = Control.FOCUS_ALL if grants_focus and not occupied else Control.FOCUS_NONE
	for j : int in slot.get_child_count() - 1:
		var card_control : Control = slot.get_child(j)
		card_control.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
				0.0 if marks_layer or is_stock_control(card_control) else _depth_pitch_px())
		card_control.focus_mode = (Control.FOCUS_NONE if marks_layer or not grants_focus
				else Control.FOCUS_CLICK if is_stock_control(card_control)
				else Control.FOCUS_ALL)
	if occupied:
		(slot.get_child(0) as Control).custom_minimum_size = CardVisual.card_size_play

#THE ONE PLACE A STACK'S CONTROL ORDER IS DECIDED. A `VBoxContainer` lays its children out top to
#bottom and a card hangs from its control's BOTTOM edge, so the card at the greatest height takes
#the FIRST control and the slot's own zone card the very last one.

#⚠ Leaving the zone card FIRST draws it a full card ABOVE an occupied slot: its control collapses
#to zero height once a card covers it, so bottom-anchoring puts it off the top of the slot.
func _bind_stack(slot: Control, stack: Array[CardData], zone_card: CardData) -> void:
	_fit_children(slot, stack.size() + 1, create_card_control)
	var depth := stack.size()
	for j : int in depth:
		_bind_slot(slot.get_child(j) as Control, stack[depth - 1 - j])
	_bind_slot(slot.get_child(depth) as Control, zone_card)
#DERIVED HERE, NEVER CACHED ON THE SLOT: a slot is pooled and rebound to whatever cell it draws
#next, so a rebuild that lands mid-reveal still shows exactly the marks the reveal has dealt.
	new_data_card[zone_card].mark_drawn = zone_card not in _plan_reveal_pending

# The marks the opening reveal has not dealt yet, as the cells' own zone cards. Empty at every other
# moment in a show, so `_bind_stack` asks a list of nothing.
var _plan_reveal_pending : Array[CardData] = []

# DEAL THE PLAN ON SCREEN, cell by cell in the order the deal actually walked -- which is what makes
# the randomness legible -- the WHOLE deal taking one tunable multiple of the live delay. Consumed
# once: a resumed show carries no order and opens with its plan already printed.
func reveal_plan() -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var order := game.state.plan_reveal_order.duplicate()
	game.state.plan_reveal_order.clear()
	_plan_reveal_pending.clear()
	for coord : BoardCoord in order:
		var mark := game.state.cell_type_at(coord)
		if mark: _plan_reveal_pending.append(mark)
#Held back BEFORE the first frame they would be drawn on: the visuals this rebuild created enter the
#tree deferred, so their own first refresh has not run yet and nothing flashes. MEASURED: a cell
#whose slot the layout has not built yet has NO visual, and `_bind_stack` holds that one back later.
	for mark : CardData in _plan_reveal_pending:
		var held : CardVisual = data_card.get(mark)
		if held: held.mark_drawn = false
	if not visuals_ready(): await board_visuals_ready
#Nothing left to deal is nothing to schedule, and a Tween with no steps is an engine error.
	if _plan_reveal_pending.is_empty(): return
	var cells := _plan_reveal_pending.size()
	var stagger := SettingsManager.settings.plan_reveal_multiplier * game.get_delay() / float(cells)
	var cascade := create_tween()
	for i : int in cells:
		cascade.tween_callback(_deal_next_mark.bind(game)).set_delay(stagger if i > 0 else 0.0)
	await cascade.finished

# ONE CELL'S TURN in that cascade: the mark joins the board the moment its spin STARTS and the spin
# is left running, so the next cell arrives on the cascade's own clock and the spins overlap. The
# pacing comes off the game the reveal resolved, never off a global any screen change rewrites.
func _deal_next_mark(game: Game) -> void:
	var mark : CardData = _plan_reveal_pending.pop_front()
	var visual : CardVisual = data_card.get(mark)
	if visual:
		visual.mark_drawn = true
		visual.anim_spin(game.get_delay())

func _entrance_slot_center_global(coord: BoardCoord) -> Vector2:
#⚠ THE CONTAINER'S OWN `global_position` STOPS MIRRORING ITS CHILDREN THE MOMENT IT IS CENTRED: the
#columns start at an offset INSIDE the hbox and the two disagree by half the slack (measured:
#20 px). The first column's own position already carries that offset, so read it directly.
	var origin := upper_zone_right.global_position
	if upper_zone_right.get_child_count() > 0:
		origin = (upper_zone_right.get_child(0) as Control).global_position
#⚠ THE RESTING LINE IS COMPUTED, NOT READ. `upper_zone_right`'s bottom edge is CONTENT-driven: a
#reveal makes a column taller and the hbox grows with it, so a floor read off that edge moves by
#the opening and CANCELS the opening the reveal term then subtracts (measured: a prop drifted 34 px).

#⚠ Subtracting the growth back off works at rest but LAGS mid-ease, because a control rect is a
#frame behind the eased numbers. The column's resting height is a function of the DATA, so it is
#derived: one whole card plus a pitch for every card above it.

#⚠ Reading the STRIP instead is not the answer either: its height comes from
#`entrance_visible_rows`, so it stops being the columns' line the moment they outgrow it.

#⚠ THE FACE-DOWN STOCK CARD IS NOT A ROW. It draws under the slot's own card at the same point,
#so it adds neither to the resting height nor to the height of the card above it.
	var deepest := 0
	var game := CardEnvironment.get_current_game()
	if game:
		for i : int in game.state.upper_zone.size():
			deepest = maxi(deepest, game.state.upper_zone[i].datas.size())
	var resting_h := CardVisual.card_size_play.y \
			+ float(maxi(deepest - 1, 0)) * _depth_pitch_px()
	var z := _content_scale_on_screen()
	var floor_y := upper_zone_right.global_position.y + resting_h * z
	var at := _stack_slot_center(origin.x, floor_y, coord.x, coord.h)
#⚠ THE UNIFORM PITCH IS NOT THE WHOLE STORY, AND EVERY PROP ANCHORS TO THIS. A reveal grows one
#layer's strip and lifts every layer above it by an amount the pitch does not describe. The offset
#comes from the same eased numbers that size the controls, so geometry outlives relayout timing.
	at.y -= _row_open_offset(coord) * z
	return at

#A grid cell: column and row come from the DATA, height from the cell's own stack. The panel's
#origin is a cached publish (`_grid_panel_origin`), never a live rect read, because a grid panel's
#position is a layout result inside an HBoxContainer of siblings.

#⚠ STACKS GROW UPWARD FROM A SHARED BOTTOM EDGE. Every card in a row bottoms out on that row's
#bottom line; height `h` lifts a card by one depth pitch, so a covered card shows its bottom strip,
#which is where the pips are. The centre is measured UP from the row's bottom.

#⚠ ROW HEIGHTS ARE NOT UNIFORM, AND THAT IS THE POINT. A row is as tall as its deepest cell, and a
#tall stack pushes every row ABOVE it up. Still pure arithmetic: the heights come from the DATA, so
#geometry stays independent of relayout timing.
func _grid_slot_center_global(coord: BoardCoord) -> Vector2:
	var origin : Vector2 = _grid_cells_origin.get(coord.grid,
			_grid_panel_origin.get(coord.grid, Vector2.ZERO))
#⚠ EVERY LENGTH HERE IS A BOARD LENGTH AND THE ORIGIN IS A SCREEN POINT. Each is taken into screen
#pixels by `_content_scale_on_screen()` before it is added to a measured global origin; leaving one
#unscaled puts the card a growing fraction of a cell off.
	var z := _content_scale_on_screen()
	var width := CardVisual.card_size_play.x * z
	var full := CardVisual.card_size_play.y * z
	var sep := float(separation) * z
	var depth_pitch := (float(CardVisual.card_separation_play_custom) + float(separation)) * z
	var x := origin.x + float(coord.x) * (width + sep) + width * 0.5
#⚠ THE ROW BOTTOMS ARE MEASURED FROM THE BOARD'S FLOOR, NOT FROM THIS PANEL. Every panel is
#bottom-aligned against that one line and it does not move when a stack deepens. Do NOT refresh a
#rect cache from `_physics_process` instead: that feeds the relayout the floor code writes into.
	var bottom : float = _grid_cells_bottom.get(coord.grid, _board_floor_y)
	for r : int in range(coord.y + 1, _grid_rows(coord.grid)):
		bottom -= (_grid_row_height(coord.grid, r) + float(separation)) * z
#⚠ THE STACK STARTS ON THE ROW'S BOTTOM LINE, NOT ONE SEPARATION ABOVE IT. A covered cell frame is
#HIDDEN rather than flattened, so it takes no separation under the stack any more — the height-0
#card's bottom edge IS the row's bottom line, exactly where the frame's was.
	var y := bottom - depth_pitch * float(coord.h) - full * 0.5
	return Vector2(x, y)

#⚠ MEMOISED ON THE STATE'S REVISION, AND IT HAS TO BE. `slot_center_global` runs for every card and
#every prop EVERY FRAME, and the row heights it needs are an O(rows x cols) scan of the cells.

#Computing them per call collapsed the frame rate far enough that awaited placement animations
#stopped finishing, which presents as a HANG with no error rather than as slowness.

#`revision` is the same key `GameData._ensure_pos_index` rebuilds on and it bumps on every board
#mutation, so a stale entry cannot outlive a change to the cells it measured.
var _row_height_cache : Dictionary[Vector2i, float] = {}
var _row_height_revision := -1
var _row_height_aligned := false

func _row_heights_for(g: int) -> void:
	var game := CardEnvironment.get_current_game()
	var rev : int = game.state.revision if game else -1
#⚠ THE ALIGNMENT SETTING IS PART OF THE KEY. It changes every row height on the board without
#touching the state, so a memo keyed on `revision` alone kept serving the pre-toggle answer —
#measured: a shallow grid stayed at its own 58 where the shared maximum was 98.
	var aligned : bool = PlayArea.settings().grid_align_rows_globally
	if rev == _row_height_revision and aligned == _row_height_aligned: return
	_row_height_cache.clear()
	_row_height_revision = rev
	_row_height_aligned = aligned

## How many rows grid `g` has, from the DATA. Zero for a grid index nothing answers to.
func _grid_rows(g: int) -> int:
	var game := CardEnvironment.get_current_game()
	if not game: return 0
	var grids := game.state.grids
	if g < 0 or g >= grids.size(): return 0
	var grid : GridData = grids[g]
	return grid.grid_height if grid else 0

#How tall row `r` of grid `g` stands: its deepest cell decides, because a `GridContainer` row is as
#tall as its tallest child. An EMPTY cell is a whole card; a stack of `d` is the top card whole plus
#a strip for every card under it, and the cell's own zone-card child adds one `separation`.

#Reads the DATA, never a rect — `slot_center_global` is on the every-frame prop-anchor path.
func _grid_row_height(g: int, r: int) -> float:
#⚠ While anything is EASING the height is a function of time, not of the revision, so the memo would
#freeze the animation on its first frame. An idle board — which is nearly every frame — still takes
#the cached path.
	if not _row_open.is_empty() or not _layer_grown.is_empty():
		return _measure_grid_row_height(g, r)
	_row_heights_for(g)
	var key := Vector2i(g, r)
	if _row_height_cache.has(key): return _row_height_cache[key]
	var h := _measure_grid_row_height(g, r)
	_row_height_cache[key] = h
	return h

#⚠ CROSS-GRID ALIGNMENT LIVES HERE, AND NOWHERE ELSE. With the setting on, row `r` takes a SHARED
#maximum across every grid so the boards read as one ruled sheet; with it off, each grid sizes its
#own rows.

#Putting it in the one function every row's height comes from is what keeps it PURELY VISUAL:
#scoring never reads a row height, so the same board scores identically either way.
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
#⚠ EACH DEPTH LAYER CONTRIBUTES ITS PITCH THROUGH THE EASE, NOT ALL AT ONCE — the row GROWS into
#its new height instead of snapping there, reusing the very clock the reveal already runs on. A
#layer with no entry in `_row_open` has finished arriving and counts whole.
	var grown := 0.0
	for h : int in range(1, deepest):
		grown += depth_pitch * _layer_arrival(g, h)
#⚠ NOTHING IS ADDED FOR THE FIRST CARD. A stack of one is exactly one card tall -- there is no gap
#inside it -- and every layer above brings its own pitch, which already carries the separation its
#own gap needs.
	return full + grown

#How far depth layer `h` of grid `g` is through arriving, 0..1.

#⚠ THE GUARD IS ABOUT THE STACK, NOT ABOUT WHAT IS ABOVE IT. A layer only contributes height if the
#stack really reaches it; guarding on whether a row has anything ABOVE it is the misreading, and a
#row with nothing above it still pushes.
func _layer_arrival(g: int, h: int) -> float:
	var key := Vector2i(g, h)
	if not _layer_grown.has(key): return 1.0
	return clampf(_layer_grown[key], 0.0, 1.0)

#How far each newly-landed depth layer is through arriving. ⚠ SEPARATE FROM `_row_open`, ON PURPOSE:
#they share the key shape and the clock but not the semantics. A reveal OPENS and then CLOSES, and
#`set_reveal_cards` REPLACES its wanted-set every section.

#A growth entry living in there would be closed by the next section and the row would shrink back
#under a card that is still sitting on it. Arrived height is permanent, so an entry is erased once
#it reaches 1 and an absent key reads as fully arrived.
var _layer_grown : Dictionary[Vector2i, float] = {}
#The deepest stack each grid had at the last rebuild, so a DEEPER one can be told apart from a board
#that simply already looked like this.
var _known_depth : Dictionary[int, int] = {}

#Seed the arrival of any depth layer that appeared since the last rebuild, so the row eases into its
#new height instead of snapping.

#⚠ A grid seen for the FIRST time animates nothing: a dealt or restored board is already the shape
#it should be, and easing it in would play a growth that never happened.
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

#Every CardVisual in `coord`'s BRACKET ROW — the set PropLayer brackets a split prop around.

#⚠ THE BRACKET ROW IS THE HEIGHT LAYER `h`, IN BOTH HALVES OF THE BOARD — NEVER THE CELL ROW `y`.
#`_append_grids_row_major` emits grid cards `for h: for every cell`, so one height layer is
#contiguous in `card_layer` while a row `y` is scattered through it.

#`PropLayer._row_bounds` brackets [first..last] of whatever set it gets, so a non-contiguous set
#would swallow every card between its ends. Short columns simply have no card at that depth and
#are skipped, so an empty slot never pulls another layer's card into the set.
func row_card_visuals(coord: BoardCoord) -> Array[CardVisual]:
	var out : Array[CardVisual] = []
	if coord.h < 0: return out
#⚠ READ FROM STATE, NOT FROM THE CONTROLS — BOTH HALVES OF THE BOARD. Rebuilds are DEFERRED, so
#mid-mutation the controls still describe the previous board. Which child holds which height is a
#layout detail; the stack itself is the fact.
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
#this rebuild satisfies any queued request
	_rebuild_queued = false
	var game := CardEnvironment.get_current_game()
	if not game: return
	ui_data.clear()
	data_ui.clear()
	_stock_slot_of_control.clear()
	var game_state := game.state
# Handles structural validation, instantiations, and dictionary mapping
	set_card_zone(upper_zone_right, game_state.upper_zone_type, _entrance_drawn_columns())
	set_grid_zones(game_state)
	data_card = new_data_card
	new_data_card = {}
	set_card_zones_visuals()
	_sweep_legal_cells()
# Game-over lock outlives rebuilds: re-strip whatever focus the passes above assigned.
	if board_focus_locked:
		for control : Control in ui_data:
			control.focus_mode = Control.FOCUS_NONE
	_open_show_view_once()
#The CardVisuals just created queued their add_child via call_deferred; this deferred emit is
#queued AFTER them (FIFO), so it fires once they are all in-tree and _ready.
	_emit_board_visuals_ready.call_deferred()

func _emit_board_visuals_ready() -> void:
	board_visuals_ready.emit()

func set_card_zones_visuals() -> void:
#A queued rebuild means the control tree is STALE against the state arrays, and running the visual
#pass against it can index out of bounds. Flush the rebuild instead — set_card_zones ends with the
#visual pass anyway.
	if _rebuild_queued:
		flush_rebuild()
		return
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
# Sizing, style overrides, and focus logic per zone; then ONE structural ordering pass over
# both zones (row-major — see _order_board_cards). Upper zone first, lower second, so
# lower-zone cards draw over upper.
	var columns := _entrance_drawn_columns()
	update_card_zone_visuals(upper_zone_right, game_state.upper_zone_type, columns)
	_turn_the_entrance_over(game_state)
	update_grid_zone_visuals(game_state)
	_refresh_mark_matches(game_state)
	_seed_new_layers(game_state)
#The Entrance is row -1: its depth is part of the board's geometry, so a rebuild that changed it
#has to re-measure the floor. This moves the BOARD, never the strip.
	_apply_entrance_strip_height()
	_order_board_cards(game_state, columns)

#Re-sync now too, not only every physics frame: a caller that reads Entrance geometry synchronously
#right after a rebuild, in the SAME frame, must not see a track width from before this rebuild
#changed the grid's size.
	_sync_entrance_x()
	_refresh_card_marking()

func set_card_zone(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
#⚠ AN ENTRANCE COLUMN *IS* A CELL SLOT -- same constructor, so it cannot drift from one.
	_fit_children(hbox, type.size(), _create_cell_slot)

#⚠ ONE bind path for the whole board: `_bind_stack()` fits the controls, orders them and binds
#them. A grid cell goes through the same call.
	for i in type.size():
		_bind_stack(hbox.get_child(i) as Control, datas[i].datas, type[i])
		_mark_stock_controls(hbox.get_child(i) as Control, i)

## A slot's deepest control is its face-down card: it publishes the STOCK's description, never the hidden card's, and the arrows walk past it because nothing there can be played yet.
func _mark_stock_controls(slot: Control, slot_index: int) -> void:
	var stock_depth := _face_down_depth(slot_index)
	var cards := slot.get_child_count() - 1
	for j : int in stock_depth:
		var control := slot.get_child(cards - 1 - j) as Control
		_stock_slot_of_control[control] = slot_index
		control.focus_mode = Control.FOCUS_CLICK

## The board HEIGHT a slot's j-th control draws: the face-down card lies under height 0, so a stocked slot's heights start one control up from the bottom and the face-down card's own is below them all.
func _control_height(slot_index: int, depth: int, j: int) -> int:
	return depth - 1 - j - _face_down_depth(slot_index)

## Which Entrance slot's stock a control draws, for the controls that draw one.
var _stock_slot_of_control : Dictionary[Control, int] = {}

## True while this control draws one of a slot's face-down stock rather than a card the slot holds.
func is_stock_control(control: Control) -> bool:
	return _stock_slot_of_control.has(control)

## ONE face-down card under a slot that still has a stock, none for an exhausted one: the card about to be flipped is the only stock card that is ever an entity, and it implies the rest.
func _face_down_depth(slot_index: int) -> int:
	var game := CardEnvironment.get_current_game()
	if not game: return 0
	var stocks := game.state.entrance_stocks()
	if slot_index < 0 or slot_index >= stocks.size(): return 0
	return 1 if stocks[slot_index].datas.size() > 0 else 0

## What each Entrance slot DRAWS, bottom to top: the one face-down card, then the cards it holds.
func _entrance_drawn_columns() -> Array[ArrayCardData]:
	var game := CardEnvironment.get_current_game()
	var columns : Array[ArrayCardData] = []
	if not game: return columns
	var stocks := game.state.entrance_stocks()
	for i : int in game.state.upper_zone.size():
		var column := ArrayCardData.new()
		var stock : Array[CardData] = stocks[i].datas
		column.datas.assign(stock.slice(stock.size() - _face_down_depth(i)))
		column.datas.append_array(game.state.upper_zone[i].datas)
		columns.append(column)
	return columns

# A SLOT'S STOCK IS FACE DOWN AND WHAT THE SLOT HOLDS IS NOT. A card just drawn is the very visual
# that lay face down on top of that stock, already in its slot, so all it has left to do is turn
# over -- and the slots turn over left to right, in the order they drew.
func _turn_the_entrance_over(game_state: GameData) -> void:
	for data : CardData in data_card:
		var visual : CardVisual = data_card[data]
		if data.stage == CardData.Stage.DRAW:
			visual.face_down = true
		elif visual.face_down:
			visual.flip_up_after(entrance_flip_delay(_entrance_slot_of(game_state, data)))

## Which Entrance slot holds this card, or the leftmost when it is not in the Entrance at all.
func _entrance_slot_of(game_state: GameData, data: CardData) -> int:
	return maxi(_entrance_slot_holding(game_state, data), 0)

## Which Entrance slot HOLDS this card, or -1: a spent slot's zone card is an Entrance control too.
func _entrance_slot_holding(game_state: GameData, data: CardData) -> int:
	for i : int in game_state.upper_zone.size():
		if game_state.upper_zone[i].datas.has(data): return i
	return -1

## The wait before slot `slot` turns its drawn card over: one stagger per slot from the left, as a fraction of the game's own delay, so the flip rides the pacing like every other animation.
func entrance_flip_delay(slot: int) -> float:
	var game := CardEnvironment.get_current_game()
	if not game: return 0.0
	return float(slot) * settings().entrance_flip_stagger * game.get_delay()

#Which CardVisual layer a slot control's card belongs in: the Entrance's own pinned layer if `c`
#lives under `upper_zone_right`, the board's otherwise. Walking `c`'s own ancestry rather than a
#caller-supplied flag leaves every call site exactly as it was.
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
#Interactivity is a FUNCTION OF THE CURRENT STATE, never a leftover. Board controls are POOLED per
#slot and rebound to whatever card lands there, so the MOUSE_FILTER_IGNORE grab_cards puts on a
#held card must be re-derived here, or a rebuild mid-grab leaves a control permanently dead.
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE if connected_data in selected_cards \
			else Control.MOUSE_FILTER_PASS
	c.focus_mode = Control.FOCUS_ALL
	var target_layer := _target_card_layer(c)
#⚠ EVERY card on this board hangs from its control's BOTTOM edge, the Entrance included: the pips
#are on a card's bottom, so a stack that grew downward buried the very row the player reads.
#Owner: *"entrance should stack upwards since downwards stacking hides pip row."*
	var bottom := true
	if connected_data in data_card and is_instance_valid(data_card[connected_data]):
		var vis := data_card[connected_data]
		vis.bottom_anchored = bottom
		new_data_card[connected_data] = vis
		vis.control_anchor = c
#A CARD MOVED BETWEEN LAYERS (Entrance <-> grid): a pooled visual does not follow its card between
#layers on its own. Guarded on a non-null parent — a visual created THIS rebuild is still awaiting
#its own deferred add_child, and reparenting a parentless node is an ENGINE ERROR, not a no-op.
		if vis.get_parent() != target_layer and vis.get_parent() != null:
			vis.reparent(target_layer)
	else:
		var fresh := CardVisual.add_child_card_visual(
			target_layer, connected_data, CardVisual.DisplayContext.PLAY_AREA, c)
		fresh.bottom_anchored = bottom
		new_data_card[connected_data] = fresh

#ROW-MAJOR, so each row is CONTIGUOUS in CardLayer and a split prop can bracket a whole one: its
#back half before the row's first card, its front half after the last. Cards overlap only WITHIN
#a column, so the cards themselves render as column-major did. PropLayer._apply_split reads this.

#Index-safe by construction: targets are 0,1,2,... ascending and only ever assigned to visuals
#verified in CardLayer at this moment, each at most once, so an index can never run past the
#child count. Ascending also converges in one pass and a still board does zero move_childs.

#A freshly created CardVisual is not in CardLayer yet, so it is skipped and the next rebuild
#slots it; a held card keeps its lifted end-of-layer spot, and PropLayer re-fixes prop halves.

#⚠ TWO LAYERS, TWO INDEPENDENT ORDERINGS: a move_child index means nothing outside the layer
#holding the child, and the Entrance has its OWN EntranceCardLayer.

#So it can never share one ordered list, `seen` set or `pending` flag with the grids' CardLayer:
#a visual correctly parented in the other layer reads as a deferred add that never lands, and the
#reorder requeues every frame until the stack overflows. Measured twice.

## Structural draw order, row-major across columns, upper zone before lower; no z_index anywhere.
func _order_board_cards(game_state: GameData, entrance_columns: Array[ArrayCardData]) -> void:
	var entrance_ordered : Array[CardVisual] = []
	var entrance_seen : Dictionary[CardVisual, bool] = {}
	var entrance_pending : Array[bool] = [false]
	_append_zone_row_major(entrance_ordered, entrance_seen, entrance_pending, entrance_card_layer,
			game_state.upper_zone_type, entrance_columns)
	_apply_layer_order(entrance_card_layer, entrance_ordered)

	var grid_ordered : Array[CardVisual] = []
	var grid_seen : Dictionary[CardVisual, bool] = {}
	var grid_pending : Array[bool] = [false]
	_append_grids_row_major(grid_ordered, grid_seen, grid_pending, card_layer, game_state.grids)
	_apply_layer_order(card_layer, grid_ordered)

#Freshly created CardVisuals enter the tree via call_deferred and were skipped above, but their
#creation order is COLUMN-major, so without a follow-up pass a fresh board keeps the wrong row
#order. Queue exactly ONE re-order behind the pending add_childs (deferred FIFO: adds run first).
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
	if game: _order_board_cards(game.state, _entrance_drawn_columns())

#Append one zone's CardVisuals in row-major order, scoped to `layer`: headers first, then each row
#across all columns, ragged columns skipping the rows they do not have. `pending[0]` flips true
#when a visual belongs in `layer` but is not parented there yet, and the caller re-orders.
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

#The grid half of the board's draw order, mirroring `_append_zone_row_major` and scoped to `layer`:
#a cell's zone card first, then the stacks height-major, so a card always draws OVER the cell it
#sits on and a whole height layer stays contiguous for PropLayer's brackets.

#⚠ Without this, grid cards were never assigned an index at all: they kept creation order, and a
#cell frame rebuilt after its card drew on top of it.
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
#held cards stay lifted at the layer's end
	if data in selected_cards: return
	var vis : CardVisual = data_card.get(data)
	if vis == null or not is_instance_valid(vis): return
	if vis.get_parent() != layer:
#deferred add still in flight; re-order once it lands
		pending[0] = true
		return
	if vis in seen: return
	seen[vis] = true
	out.append(vis)

func update_card_zone_visuals(hbox: HBoxContainer, type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	for i in type.size():
		_size_stack_slot(hbox.get_child(i) as Control, false)

#⚠ the loop above resets every strip to its stacked height, so a rebuild that lands mid-act would
#slam an open row shut. Re-push the live openings over the top of it.
	_apply_row_openings()

	_link_arrow_stops(hbox, type.size())

#⚠ THE BESPOKE HELD/SELECTED WIDENING IS GONE, BY OWNER RULING. It reached into this container by
#fixed child index, which the reversal above inverts, and it was a second highlight mechanism
#beside the one every other card uses. ⚠ The look when picking a card up CHANGES; that is the rule.

# Chains each slot's topmost control to its neighbours for the arrows, skipping a slot that shows
# only its face-down card: the engine honours an explicit neighbour at every focus mode but
# FOCUS_NONE, so a skipped slot must be left OUT of the chain, not relied on to refuse the focus.
func _link_arrow_stops(hbox: HBoxContainer, slots: int) -> void:
	_entrance_stops.clear()
	for i : int in slots:
		var top := hbox.get_child(i).get_child(0) as Control
		top.focus_neighbor_left = ^""
		top.focus_neighbor_right = ^""
		if not is_stock_control(top): _entrance_stops.append(top)
	for i : int in _entrance_stops.size() - 1:
		_entrance_stops[i].focus_neighbor_right = _entrance_stops[i + 1].get_path()
		_entrance_stops[i + 1].focus_neighbor_left = _entrance_stops[i].get_path()

## The Entrance's arrow stops, left to right: the chain above is the one home that decides them.
var _entrance_stops : Array[Control] = []

# ==============================================================================
# THE GRID BOARD
# ==============================================================================

#One GridPanel per grid, each holding a GridContainer of CellSlots. A cell slot is built exactly
#like a zone column — child 0 the cell's own zone card, children 1..n the cards stacked in it — so
#the binding, the pooling, the focus wiring and the CardVisual creation are all the existing ones.

#⚠ THE CELLS ARE CONTROLS; THE CARDS ARE NOT. A Godot container overwrites its children's position
#and size, so a CardVisual can never live in one — it stays in %CardLayer, positioned by
#arithmetic, which is what lets a springing card overlap the row above without a re-flow.

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
#⚠ A GRID ARRIVING MOVES THE RESTING POSITION AS SURELY AS ONE LEAVING: the board is wider and its
#middle is somewhere else, so a board left where it was is a board off its rest.
	elif diff > 0: rest_board()

#The grid list as it was at the last rebuild. The panels are bound by POSITION, so without this
#nothing can tell a grid that was REMOVED from one that merely shifted left into its place.
var _bound_grids : Array[GridData] = []

#Which bound grid is no longer on the board, or NO_GRID. Grids go one at a time, so the first one
#missing is the one that went.
func _removed_grid_index(grids: Array[GridData]) -> int:
	if grids.size() >= _bound_grids.size(): return NO_GRID
	for i : int in _bound_grids.size():
		var grid : GridData = _bound_grids[i]
		if grid and not grids.has(grid): return i
	return NO_GRID

#Where the view goes when the grid it was on is removed: the NEAREST survivor, the LEFT one when
#both neighbours are equally near. They always are, so this is the left neighbour, except when the
#board's first grid went and there is none.
func _nearest_surviving_grid(removed: int) -> int:
	return clampi(removed - 1, 0, grid_container.get_child_count() - 1)

#Keep the view honest on a board that just lost a grid: every index right of the hole shifts left,
#a view that was ON that grid moves to the nearest survivor, and the board re-centres either way.

#⚠ THE RE-CENTRE IS NOT CONDITIONAL ON THE REFOCUS — a grid removed elsewhere on the board still
#leaves the remaining grids sitting off centre.

#⚠ EVERY INDEX THIS SCREEN REMEMBERS IS FIXED UP HERE. The view and the arrow cursor both take the
#NEAREST SURVIVOR, preferring the one to the left, so the board cannot re-centre on one grid while
#the cursor sits on another (owner ruling).

#Forward's memory is the exception: the view it would return to no longer exists, so it is cleared
#and Forward falls through to the wall.
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

#True while a re-centre waits for the board to stop re-laying out, so a second removal in the same
#breath does not start a second wait.
var _recentre_waiting := false

#Re-centre on whichever grid the view is on, animated over the pan clock — the player's own pan,
#reused, so a removal moves the board exactly the way a pan key does.

#⚠ AIM ONLY ONCE THE PANELS HAVE STOPPED MOVING. Losing a grid re-lays the board out over several
#frames, and a pan aimed at where the grids WERE lands short of centre (measured: 118 px, half a
#grid). The wait is capped at the pan clock so a board that never settles still re-centres.
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
	pan_to_grid(pan_grid)
#⚠ AIM TWICE: A BOARD SITTING AT SCROLL ZERO LIES ABOUT WHERE IT IS. At exactly zero the scroll
#container still holds the half-margin it centred the content with (measured: 4 px) and drops it
#the moment the scroll moves, so an aim from rest lands short. One frame in, the second corrects.
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(grid_container):
		_recentre_waiting = false
		return
	pan_to_grid(pan_grid)
#⚠ THE FLAG COVERS BOTH AIMS, NOT JUST THE WAIT. Cleared before them, it said "settled" one frame
#before the second aim landed -- and anything that read the board in that frame had its own scroll
#taken back from under it.
	_recentre_waiting = false

#What "the board has stopped moving" means to a re-centre: where the centred grid sits INSIDE the
#board, how wide the board is, and how far the view can scroll. ⚠ All three are read relative to
#the board, never in screen space, whose own easing moves every frame.
func _recentre_probe() -> Vector3:
	if pan_grid < 0 or pan_grid >= grid_container.get_child_count(): return Vector3.ZERO
	var cells := _cells_root(grid_container.get_child(pan_grid) as Control)
	if not cells: return Vector3.ZERO
	var bar := scroll_container.get_h_scroll_bar()
	var reach : float = bar.max_value if bar else 0.0
	return Vector3(cells.global_position.x - grid_container.global_position.x,
			grid_container.size.x, reach)

#ONE GRID PER GRID POSITION: THE PITCH BETWEEN TWO CELL BLOCKS IS ONE BLOCK PLUS ONE BUFFER. The
#picture holds `grid_max_count` grids side by side, so spacing the panels at that pitch places them
#edge to edge — never the whole picture's width, which would scatter them across empty board.

#Each panel carries score gutters either side of its cells, and those gutters sit INSIDE the buffer
#rather than adding to the board's width, so a wider label never widens the board. The container's
#separation is the buffer LESS the gutters it absorbs, set by the WIDEST pair.

#⚠ THE SEPARATION IS RAW, NOT DIVIDED BY THE ZOOM: it grows on screen with `drawn_zoom` like every
#other authored length, and that growth IS the isolating mechanism `isolating_grid_buffer_px()`
#solves for, so dividing it back out would defeat the derivation.

#⚠ Measured every frame, not once: a score label appearing changes a gutter's width. The override
#is written only when the value changes, so a settled board stops re-sorting, and every quantity
#here is panel-RELATIVE, so it cannot feed back the way the per-panel floor code did.

#The widest score gutter on each side, in BOARD px -- divided by the on-screen scale, since the
#positions they are measured from are screen ones. `Vector2.ZERO` while no panel carries cells yet.
func _grid_gutters() -> Vector2:
	var left := 0.0
	var right := 0.0
	var z := _content_scale_on_screen()
	for i : int in grid_container.get_child_count():
		var panel := grid_container.get_child(i) as Control
		if not panel: continue
		var cells := _cells_root(panel)
		if not cells: continue
		left = maxf(left, (cells.global_position.x - panel.global_position.x) / z)
		right = maxf(right, panel.global_position.x / z + panel.size.x
				- (cells.global_position.x / z + cells.size.x))
	return Vector2(left, right)

## The gap this MODE is laid out with: the overview's small fixed one, or the buffer that carries a focused grid's neighbours out of frame.
func _grid_gap_target() -> float:
	var settings_res := PlayArea.settings()
	return overview_grid_gap_px(settings_res) if view_mode == ViewMode.OVERVIEW \
			else isolating_grid_buffer_px(settings_res)

## The gap the board is DRAWN with this frame: it eases toward `_grid_gap_target()` on the pan clock.
var _drawn_grid_gap : float = 0.0
## The end margin the ease started from, so the margins travel with the gap instead of switching under it.
var _end_margin_before_the_ease : float = 0.0

#The ONE writer of the SEPARATION between two grids AND of the bare board beyond the outermost two
#-- one quantity, and the only thing the two views lay out differently: the overview draws a small
#fixed gap, the focused view the buffer that carries the neighbours out of frame.

#⚠ THE END MARGIN IS WHAT LETS AN EDGE GRID REACH THE MIDDLE OF THE WINDOW. The scroller clamps
#every aim to its content's range, so content ending at the last cell block leaves the first and
#last grids against the window's edge with a neighbour in frame (measured: 326.8 px off centre).

#Half a window less half a block is exactly the buffer, so the board ends in the space it already
#holds between two grids. The scroll container's `panel` box carries it: the engine insets the
#content by that box's margins and takes them off the range, so aim and clamp cannot disagree.
func _apply_grid_buffer() -> void:
	if not is_instance_valid(grid_container) or grid_container.get_child_count() == 0: return
	var gutters := _grid_gutters()
	var settings_res := PlayArea.settings()
#WITH NO EASE RUNNING THE DRAWN GAP IS THE MODE'S OWN, which is also what makes a settings change
#reach a board that is standing still.
	if _view_ease >= 1.0: _drawn_grid_gap = _grid_gap_target()
	var wanted := roundi(maxf(_drawn_grid_gap - gutters.x - gutters.y, 0.0))
	if grid_container.get_theme_constant(&"separation") != wanted:
		grid_container.add_theme_constant_override("separation", wanted)
#⚠ THE END MARGIN EASES WITH THE GAP, or the content's reach jumps a whole buffer in one frame
#while the scroll is still travelling, and the scroller clamps the aim against a range it no longer
#has. Both are the same quantity opening, so one fraction carries both.
	var isolating := view_mode == ViewMode.FOCUSED and grid_container.get_child_count() > 1
	var ends := lerpf(_end_margin_before_the_ease,
			isolating_grid_buffer_px(settings_res) if isolating else 0.0, _view_ease)
	var box := scroll_container.get_theme_stylebox(&"panel")
	var left := roundf(maxf(ends - gutters.x, 0.0))
	var right := roundf(maxf(ends - gutters.y, 0.0))
	if is_equal_approx(box.content_margin_left, left) \
			and is_equal_approx(box.content_margin_right, right):
		return
	var padded : StyleBox = box.duplicate()
	padded.content_margin_left = left
	padded.content_margin_right = right
	scroll_container.add_theme_stylebox_override(&"panel", padded)
#⚠ SORT IT AGAIN BY HAND. The content keeps the place the last sort gave it, so a margin taken back
#off leaves the board parked where the wider one put it -- measured: the overview set 187.8 px right
#of centre with the margin already reported as zero.
	scroll_container.queue_sort()

#The screen-independent distance from one grid panel's cell block centre to the next: ONE BLOCK
#PLUS THE ACTUAL APPLIED BUFFER (the rounded container separation plus the gutters it absorbed),
#never the unrounded value, so the camera step lands on the panel that was actually placed.
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
#Grids are aligned by their BOTTOM edges: every grid sits on the same floor and grows upward
#independently, which is what the board growing up out of the Entrance means. With cross-grid row
#alignment off (the default) the bottom edge is the ONLY thing that lines up.
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
#Stated for the same reason the cell slots state it: this board's fixed edge is the bottom.
	panel.alignment = BoxContainer.ALIGNMENT_END
#⚠ ONE CONTAINER PER ROW, NOT ONE GRID FOR THE WHOLE PANEL (owner spec). A GridContainer gives
#every cell in a row the row's full height, so a cell has nothing to bottom-align against and a
#deep stack bleeds into the row above. A row of its own keeps every cell of a row on ONE y.
	panel.add_theme_constant_override("separation", separation)
#⚠ THE SCORE GUTTERS LIVE IN THE PANEL AROUND THE CELLS: row labels LEFT, column labels BELOW, and
#ONE special-meld label to the RIGHT, centred on the grid, opposite the row labels. Everything that
#walks ROWS goes through `_cells_root`, so a lookup can never read a gutter as a row.
	var board := HBoxContainer.new()
	board.name = "Board"
	board.add_theme_constant_override("separation", separation)
	var row_labels := VBoxContainer.new()
	row_labels.name = "RowLabels"
	row_labels.add_theme_constant_override("separation", separation)
	row_labels.alignment = BoxContainer.ALIGNMENT_END
#⚠ Takes its OWN height at the top of the row, not the whole row's. Its stacks already mirror the
#cell rows, so its own minimum IS the cell block's height and its bottom edge lands on the cells' --
#which stays true now that the column labels have made `Board` taller than `Cells`.
	row_labels.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	board.add_child(row_labels)
#⚠ THE COLUMN LABELS ARE A SIBLING OF THE CELLS, IN THE CELLS' OWN COLUMN. That is what puts a
#column's label under that column: the container does it, and nothing measures an indent. As a bare
#child of the panel they began at the panel's left edge, a column left of what they name.
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
#⚠ `resized` IS NOT ENOUGH: it fires on SIZE changes only, and a panel shoved up or sideways by a
#sibling — exactly what happens to a bottom-aligned panel when the board grows — changes POSITION
#with no size change. Measured: 574 against a real 554. `item_rect_changed` covers both.
	panel.item_rect_changed.connect(_publish_grid_panel_origin.bind(panel))
	panel.sort_children.connect(_publish_grid_panel_origin.bind(panel))
	return panel

## One row of a grid: an HBox of cells, the same shape the original play area gave a zone.
func _create_grid_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "GridRow"
	row.add_theme_constant_override("separation", separation)
#Rows keep their own width centred on the panel, like the panel does on the board.
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return row

#One cell: a VBox holding its stack. ⚠ BOTTOM-ALIGNED INSIDE ITS ROW — this is the whole reason a
#row is its own HBox. The row is as tall as its deepest cell and every shallower cell shrinks to
#its own stack, so a row's zone cards are ALWAYS on one y however uneven the stacks are.
func _create_cell_slot() -> Control:
	var slot := VBoxContainer.new()
	slot.name = "CellSlot"
#⚠ NO SEPARATION; EACH CARD CARRIES ITS OWN GAP -- see `update_grid_zone_visuals()`, where the
#reason lives. Set here as well so the authored value is not a different number from the one the
#board actually runs on.
	slot.add_theme_constant_override("separation", 0)
	slot.size_flags_vertical = Control.SIZE_SHRINK_END
#⚠ STATED, NOT LEFT TO THE DEFAULT. The slot shrinks to its own stack today, so packing from the
#top is invisible — but a board that grows UPWARD wants the bottom edge to be the fixed one, and
#the label gutters had exactly this bug from exactly this default.
	slot.alignment = BoxContainer.ALIGNMENT_END
	return slot

#Grows or truncates `parent`'s children to exactly `wanted`, building new ones with `make`. The
#same add/remove-from-the-end shape `set_card_zone` uses for a zone's columns.
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

#WHICH grid's score buckets a panel draws from. A board grid answers with its own position in
#`GridContainer`; a panel mounted anywhere else — the Entrance's, which lives in its own strip —
#states it instead, because a child index there means nothing.
func _panel_bucket_grid(panel: Control) -> int:
	return panel.get_meta(META_BUCKET_GRID, panel.get_index())

#WHERE a panel's first row sits inside those buckets. A board grid starts at 0; the Entrance starts
#past the grid's own last row, which is the owner's *"its own row bucket as if grid is 5x6"* --
#expressed once, here, rather than at every reader.
func _panel_row_offset(panel: Control) -> int:
	return panel.get_meta(META_ROW_OFFSET, 0)

#Fills a grid's score gutters from its buckets. ⚠ EVERY (index, height) ENTRY GETS A LABEL, and the
#heights stack in the same order as the cards they describe: a row's height-0 label beside its
#height-0 cards, height-1 above it.

#⚠ That is why a row's labels are their own VBox built exactly like a `CellSlot` — bottom-aligned,
#`h` rising — rather than one label per row. Any other layout puts a height-1 score beside
#height-0 cards.
func _bind_grid_score_labels(panel: Control, grid: GridData) -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var gi := _panel_bucket_grid(panel)
	var row0 := _panel_row_offset(panel)
	var state := game.state
	var board := panel.get_node_or_null("Board") as Control
	if not board: return
	var col_levels := state.line_score_levels(state.scores_col, gi)

	var row_labels := board.get_node_or_null("RowLabels") as Control
	if row_labels:
		_fit_children(row_labels, grid.grid_height, _create_label_stack)
		for ry : int in grid.grid_height:
			var bucket_row := row0 + ry
			_fill_label_stack(row_labels.get_child(ry) as VBoxContainer, state.scores_row,
					gi, bucket_row, _row_score_levels(state.scores_row, gi, bucket_row), true)
	var col_labels := panel.get_node_or_null("Board/CellsColumn/ColLabels") as Control
	if col_labels:
		_fit_children(col_labels, grid.grid_width, _create_label_stack)
		for cx : int in grid.grid_width:
			_fill_label_stack(col_labels.get_child(cx) as VBoxContainer, state.scores_col,
					gi, cx, col_levels, false)
	var special := board.get_node_or_null("SpecialLabel") as BigNumberLabel
	if special:
#⚠ THE SPECIAL LABEL NEEDS A BOX OR IT IS NOT A SCORE LABEL. With none it shrank to whatever its
#own text measured and `AutosizeLabel` pinned its font at the minimum. It is the row gutter's
#mirror on the far side of the cells, so it takes the row gutter's box.
		special.custom_minimum_size = Vector2(CardVisual.card_size_play.x, _depth_pitch_px())
#⚠ Right-aligned like the ROW gutter, NOT mirrored (owner, reversing an earlier call): leaning it
#toward the cells made it read as belonging to whichever row it sat beside.
		special.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
#⚠ ONE label for every diagonal and every future non-directional meld (owner ruling), and the
#bucket really is one in the data too.
		var value : BigNumber = state.score_special[gi] if gi < state.score_special.size() else null
		if value: special.current_num = value
		else: special.text = ""

#One depth layer's pitch in BOARD units: the strip a covered card shows plus the gap above it. The
#ONE place a score gutter and the cells agree about how far apart two heights are.
func _depth_pitch_px() -> float:
	return float(CardVisual.card_separation_play_custom) + float(separation)

#Give every score label on a grid ONE font size: the smallest any of them would pick for its own
#box and its own text.

#⚠ EQUAL BOXES ARE NOT ENOUGH. `AutosizeLabel` fits its font to its own TEXT as well as its box, so
#a four-digit row score and a two-digit column score in identical boxes still render at different
#sizes. The set must read as one set, which is a property of the GROUP and no label can decide it.

#⚠ ASKING DOES NOT DEPEND ON THE ANSWER. `best_font_size()` measures against `custom_minimum_size`,
#which the container hands back unchanged whatever font is applied, so this cannot oscillate.
#Written only on change, so a settled board stops re-sorting.
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

#Every score label a grid panel carries: the row gutter, the column gutter and the one special
#label. NOT the per-cell height labels, which live in the card layer and are positioned by
#arithmetic rather than by this panel.
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

#Keep every row-label stack exactly as tall as the cell row it names.

#⚠ PER TICK, BECAUSE A ROW'S HEIGHT IS A FUNCTION OF TIME WHILE A LAYER IS ARRIVING. Anything that
#binds mid-growth latched whatever fraction the ease had reached, and the gutter then sat below the
#row it belongs to. Written only on change, so a settled board stops re-sorting.
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

#Pop the ONE score label a grid line just banked into, the way a legacy gutter label pops.

#⚠ THE LABELS ARE RE-BOUND FIRST. A line scoring at a height nothing has reached before has no
#label yet, and a pop on a label that does not exist is a silently dropped animation — which is
#what "the scores are not popping up" looked like from the outside.
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
			return _cell_score_labels.get(Vector3i(_panel_bucket_grid(panel), section.cell.x,
					section.cell.y))
	return null

#Height `h`'s label inside gutter stack `index`. ⚠ A STACK IS BUILT HIGHEST FIRST, so height 0 is
#the LAST child, not the first — the same order `_fill_label_stack` writes them in.
func _label_in_stack(gutter: Control, index: int, h: int) -> BigNumberLabel:
	if not gutter or index < 0 or index >= gutter.get_child_count(): return null
	var stack : Control = gutter.get_child(index)
	var i := stack.get_child_count() - 1 - h
	if i < 0 or i >= stack.get_child_count(): return null
	return stack.get_child(i) as BigNumberLabel

#THAT ROW's own score-level count, not the grid-wide max `state.line_score_levels` returns — a
#shallow row must never get surplus fixed-height children forcing it past `_grid_row_height`.
func _row_score_levels(bucket: Dictionary[Vector3i, BigNumber], gi: int, ry: int) -> int:
	var deepest := -1
	for key : Vector3i in bucket:
		if key.x == gi and key.y == ry: deepest = maxi(deepest, key.z)
	return deepest + 1

#One line's labels: a VBox of one label per height, built like a `CellSlot` so the stack reads in
#the same direction the cards do.
func _create_label_stack() -> Control:
	var stack := VBoxContainer.new()
	stack.name = "LabelStack"
#⚠ NO SEPARATION; EACH LABEL CARRIES THE DEPTH PITCH ITSELF. A stack's pitch has to equal the CARD
#depth pitch exactly or the scores fan away from the cards they name — measured, a 20 px label plus
#a 4 px separation walked 6.5 px per level off a 32.7 px card pitch.
	stack.add_theme_constant_override("separation", 0)
	stack.size_flags_vertical = Control.SIZE_SHRINK_END
#⚠ BOTTOM-ALIGNED, LIKE THE CARDS BESIDE IT. Left at the default of BEGIN, a stack as tall as its
#row packed its scores against the row's TOP edge, 37 px (60.5 at the focused zoom) above the pip
#row they name. The label pitch equals the card depth pitch, so this lines up every height at once.
	stack.alignment = BoxContainer.ALIGNMENT_END
	return stack

#⚠ HIGHEST HEIGHT FIRST, so the column reads bottom-up exactly like the cards beside it: the last
#child is height 0, level with the height-0 cards, and each earlier child is one level up.

#⚠ A ROW STACK'S OWN MINIMUM HEIGHT FOLLOWS `_grid_row_height`, THE CELLS' MEASURED HEIGHT. The
#cell block is authoritative, so a row gutter is only ever as tall as its cell row really is and it
#tracks an easing row. Column stacks stay levels-sized: a column's width never varies by data.

#Row labels expand to fill the stack's already-authoritative height, never grow it, so their text
#has real room to sit at the bottom, level with the pip row on a card's bottom edge.
func _fill_label_stack(stack: VBoxContainer, bucket: Dictionary[Vector3i, BigNumber],
		gi: int, index: int, levels: int, is_row: bool) -> void:
	if not stack: return
	_fit_children(stack, maxi(levels, 1), _create_score_label)
	var game := CardEnvironment.get_current_game()
	if not game: return
	for i : int in stack.get_child_count():
#child 0 is the HIGHEST height
		var h := stack.get_child_count() - 1 - i
		var label : BigNumberLabel = stack.get_child(i)
#⚠ ONE WIDTH FOR EVERY SCORE LABEL (owner). `AutosizeLabel` fits its font to its own box, so a
#16 px row gutter and a 40 px column gutter rendered the same number at 8 px and 14 px. The heights
#still differ by kind: a row label's is the depth strip, so its stack's pitch matches the cards'.
		label.custom_minimum_size = Vector2(CardVisual.card_size_play.x, _depth_pitch_px())
#⚠ EACH GUTTER LEANS TOWARD THE CELLS IT DESCRIBES (owner). The row gutter sits LEFT of the grid,
#so its numbers are right-aligned, hard against the cells; the column gutter sits under its
#columns, so its numbers are centred on them.
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if is_row \
				else HORIZONTAL_ALIGNMENT_CENTER
		var key := Vector3i(gi, index, h)
		if bucket.has(key): label.current_num = bucket[key]
		else: label.text = ""
	if is_row:
		stack.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
				_grid_row_height(gi, index))

func _create_score_label() -> Control:
	return BigNumberLabel.new()

#The node holding a grid's ROW containers. ⚠ Everything that walks rows goes through here: the
#panel also carries score gutters, and a lookup that indexed the panel directly would silently
#start reading a gutter as a row.
func _cells_root(panel: Control) -> Control:
	var board := panel.get_node_or_null("Board") as Control
	return board.get_node_or_null("CellsColumn/Cells") as Control if board else null

#The slot for grid cell index `ci`, found through its row. Cells are row-major in the data, so the
#row is `ci / width` and the column `ci % width`.
func _cell_slot(panel: Control, grid: GridData, ci: int) -> VBoxContainer:
	var w := maxi(grid.grid_width, 1)
	var ry := ci / w
	var cx := ci % w
	var cells := _cells_root(panel)
	if not cells or ry < 0 or ry >= cells.get_child_count(): return null
	var row : Control = cells.get_child(ry)
	if cx < 0 or cx >= row.get_child_count(): return null
	return row.get_child(cx) as VBoxContainer

#Caches one grid panel's resolved global origin, so `slot_center_global` can read it instead of the
#panel's rect. Keyed by the panel's CURRENT index, which is stable for a panel's whole lifetime
#(see `_grid_panel_origin`).
func _publish_grid_panel_origin(panel: Control) -> void:
	_grid_panel_origin[panel.get_index()] = panel.global_position


#Fills one panel with `grid_width * grid_height` cell slots and binds every card in them. The cell
#count comes from the DATA, never from a hard-coded 5.
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

#Sizes every cell slot. An EMPTY cell takes a FULL card's worth, so a grid is a complete block of
#card-sized slots from the moment it is built and never changes shape as it fills; a covered card
#shows exactly CARD_SEPARATION of itself and the top card of a stack shows whole.
func update_grid_zone_visuals(game_state: GameData) -> void:
	for gi : int in mini(game_state.grids.size(), grid_container.get_child_count()):
		var grid : GridData = game_state.grids[gi]
		if not grid: continue
		var panel : Control = grid_container.get_child(gi)
		panel.add_theme_constant_override("separation", separation)
		for ci : int in grid.cells.size():
			var slot : VBoxContainer = _cell_slot(panel, grid, ci)
			if slot: _size_stack_slot(slot, plan_layer_open)
#THE LAYER SWAP, AND THE WHOLE OF IT: the marks layer draws each cell's plan, so the cards played
#on it step aside -- out of the drawing here, out of the sizing and the focus in `_size_stack_slot`.
#Derived on every refresh and stored nowhere, like the rims beside it.
			for card : CardData in grid.cells[ci].datas:
				var played : CardVisual = data_card.get(card)
				if played: played.visible = not plan_layer_open

#DERIVED HERE AND STORED NOWHERE: the grab, the placement and the undo all end in this pass, so
#nothing has to be un-set, and a bare cell is skipped before anything is asked of it.
## A mark lights the elements a held card agrees with; a card on a mark lights the ones it realized.
func _refresh_mark_matches(game_state: GameData) -> void:
	for gi : int in game_state.grids.size():
		var grid : GridData = game_state.grids[gi]
#A CELL THE SHOW CANNOT PLACE INTO IS NOT ONE THE HELD CARD WOULD MATCH: the Entrance commits to one
#grid at its first placement and `place_card_in_grid` refuses every other, so lighting them promises
#a placement the board silently drops. Only the commitment -- height rules still change mid-show.
		var takes_a_placement := game_state.committed_grid == -1 or gi == game_state.committed_grid
		for ci : int in grid.cell_types.size():
			var mark : CardData = grid.cell_types[ci]
			if not BoardPlan.is_marked(mark): continue
			var coord := BoardCoord.new(gi, ci % grid.grid_width, ci / grid.grid_width, 0)
			var realized := 0
			for card : CardData in grid.cells[ci].datas:
				var matched := await MarkMatch.matches_at(game_state, card, coord)
				realized |= matched
				_wear_match_rim(card, matched, PaletteDB.ROLES.match_rim_active)
#IN THE MARKS LAYER THE MARK WEARS ITS OWN REALIZED RIM AND NOTHING ELSE: the card that agreed with
#it is hidden there, and the layer is looked at and never played -- a would-match rim there would
#promise the placement it refuses.
			if plan_layer_open:
				_wear_match_rim(mark, realized, PaletteDB.ROLES.match_rim_active)
				continue
			var would_match := 0
			if takes_a_placement:
				for held : CardData in selected_cards:
					would_match |= await MarkMatch.matches_at(game_state, held, coord)
			_wear_match_rim(mark, would_match, PaletteDB.ROLES.match_rim)

# The match test AWAITS, so the walk above can resume into a board that has been rebuilt under it
# and a card it started with may have no visual any more.
func _wear_match_rim(card: CardData, properties: int, palette_index: int) -> void:
	var visual : CardVisual = data_card.get(card)
	if visual: visual.set_match_rim(properties, palette_index)

# The pointer leaving a card announces the lost highlight only when it landed on NO other card:
# whether it did is the engine's own answer, read back through `_card_control_at`, so this never
# disagrees with what the board thinks is under the cursor.
func create_card_control() -> Control:
	var new_control := Control.new()
	new_control.add_to_group("CardVisualControl")
	new_control.focus_mode = Control.FOCUS_ALL
	new_control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	new_control.focus_entered.connect(func()->void:on_control_focus_entered(new_control))
#ARROW KEYS ARE READ HERE, on the focused cell itself — see `_on_cell_gui_input` for why
#`_unhandled_input` is too late.
	new_control.gui_input.connect(func(e: InputEvent)->void:_on_cell_gui_input(e, new_control))
	new_control.mouse_entered.connect(func()->void:
			if new_control.has_focus(): _describe_control(new_control)
			else: new_control.grab_focus()
			moused_hovered_control = new_control)
	new_control.mouse_exited.connect(func()->void:
			if moused_hovered_control == new_control:
				moused_hovered_control = null
				if _card_control_at(get_global_mouse_position()) == null: highlight_cleared.emit())
	new_control.focus_exited.connect(_publish_focus_left_cards, CONNECT_DEFERRED)
	return new_control

# DEFERRED, and it has to be: at `focus_exited` the viewport has dropped the old focus and not yet
# taken the new one, so the owner reads null however the focus is moving; one idle call later it
# is settled. A board torn down while a card holds the focus is called after it left the tree.
func _publish_focus_left_cards() -> void:
	if not is_inside_tree(): return
	if not ui_data.has(get_viewport().gui_get_focus_owner()): highlight_cleared.emit()

# THE ONE PLACE A DESCRIPTION IS PUBLISHED -- a highlight or a click, mouse or key/pad alike. The
# locked card is already described by its lock, and only that entry carries the X, so a highlight
# landing back on it hands the sidebar back to the lock instead of publishing a copy.
func _publish_info(data: CardData) -> void:
	if data == locked_data:
		highlight_cleared.emit()
		return
	highlight_info(data, CardVisual.preview_window_px()).relay_to(info_requested)

## `card_info()` for a HIGHLIGHT -- the one home for what a hover or a focus publishes, on the board and in every viewer alike.
static func highlight_info(data: CardData, card_px: Vector2) -> InfoEntry:
	var entry := card_info(data, card_px)
	entry.transient = true
	return entry

# A FACE-DOWN CARD DESCRIBES THE SLOT, NEVER ITSELF -- what is hidden stays hidden, and what the
# player is asking is how much this slot has left to draw.
func _publish_stock_info(slot: int) -> void:
	var game := CardEnvironment.get_current_game()
	var entry := InfoEntry.new()
	entry.title = game.state.upper_zone_type[slot].type.get_str()
	entry.body = TRANSLATION.find('SIDEBAR_STOCK_REMAINING') % game.state.entrance_stocks()[slot].datas.size()
	entry.transient = true
	info_requested.emit(entry)

#DERIVED, NEVER CACHED: a placement or a removal rebinds the focused cell's control to another card
#without moving the focus, so only the control can say which card the focus is on now.
var focused_visual : CardVisual:
	get():
		if not is_instance_valid(focused_control): return null
		var data : CardData = ui_data.get(focused_control)
		return data_card.get(data)

## The card the sidebar is locked to, pushed in by `GameView` -- `null` while nothing is locked.
var locked_data : CardData = null:
	set(value):
		locked_data = value
		_refresh_card_marking()

#A card wears the focus marking while it HOLDS the board focus or while the sidebar is LOCKED to
#it, so what is being read stays marked once the focus moves on. A rebuild re-applies it, and the
#drop map from the last sweep with it, because it hands the same cell a different visual.
func _refresh_card_marking() -> void:
	var focused := focused_visual
	for data : CardData in data_card:
		var visual : CardVisual = data_card[data]
		visual.focused = visual == focused or data == locked_data
		visual.on_drop_map = data in _legal_cells

## The zone card of every cell the held card may land in — the drop map the highlight draws.
var _legal_cells : Dictionary[CardData, bool] = {}

# THE DROP MAP, read from the Game's one legality walk so no placement rule is restated here.
# ⚠ NEVER PER FRAME, AND NEVER FOR AN EMPTY HAND: the walk asks every card on the board for every
# cell, so it runs only once per rebuild or hand change, and an empty hand lands nowhere unasked.
func _sweep_legal_cells() -> void:
	var legal : Dictionary[CardData, bool] = {}
	if not selected_cards.is_empty():
		var game := CardEnvironment.get_current_game()
#THE CALLER OWNS WHICH GRIDS ARE ASKED, as the match rim's site does: once the Entrance has
#committed, `place_card_in_grid` refuses every other grid outright, so a cell there is not one the
#held card may land in and the walk is never asked about it.
		var grids : Array[GridData] = game.state.grids
		if game.state.committed_grid != -1:
			grids = [game.state.grids[game.state.committed_grid]]
		for zone_card : CardData in await game.legal_cells_for(selected_cards, grids):
			legal[zone_card] = true
	_legal_cells = legal
	_refresh_card_marking()

# A pointer re-entering the card that already holds the focus moves no focus, so the hover
# publishes here itself; a hover that DOES move the focus publishes only through focus_entered.
func _describe_control(control: Control) -> void:
	if not ui_data.has(control) or _focus_is_resting: return
	if is_stock_control(control):
		_publish_stock_info(_stock_slot_of_control[control])
	else:
		_publish_info(ui_data[control])

func on_control_focus_entered(control:Control) -> void:
	flush_rebuild()
#ONE CURSOR FOR BOTH INPUT MODES: whatever moved the board focus onto a grid — mouse hover, arrows,
#a click — is also what the overview's Enter will focus.
	var focus_grid_index := _grid_index_of(control)
	if focus_grid_index != NO_GRID: selected_grid = focus_grid_index
	_describe_control(control)

#⚠ HOVER DOES NOT RESIZE THE STACK, AND ESPECIALLY NOT ITS ZONE CARD. Hand-sizing controls by fixed
#child index on every focus named the ZONE card once the board stacked upward, and the zone visibly
#dipped DOWN under the card being hovered (owner: stacking must not move the zone).

#⚠ It was also a second sizing mechanism beside `_size_stack_slot()`, which is the ONE place a
#stack's controls are sized.
	focused_control = control
	set_card_zones_visuals()

# ⚠ THE CALLER OWNS `entry.visual`, a LIVE preview card built per call. A BOX, never a
# `FlowContainer`: a flow reports the minimum its LAST SORT measured, so a re-size reads stale.

# ⚠ THE EMPTY FIRST LINE IS KEPT: a card with neither rank nor suit has no title, and dropping it
# would promote its first effect BLOCK into the title, BBCode tags and all.
static func card_info(data: CardData, card_px: Vector2) -> InfoEntry:
	var entry := InfoEntry.new()
	var text := ControlCard.describe_card(data)
	var split := text.split("\n", true, 1)
	entry.title = split[0] if split.size() > 0 else ""
	entry.body = split[1] if split.size() > 1 else ""
	var row := HBoxContainer.new()
	entry.visual = row
	var card := CardsViewer.new(row, CardVisual.DisplayContext.PREVIEW).populate(
			[data] as Array[CardData])
	card.size_preview_to(card_px)
	return entry

#OPEN THE ROWS THESE CARDS SIT IN. Called with the section being scored, or empty to close
#everything again. The set REPLACES: a row that has left the set eases shut rather than being
#dropped, which is why `_row_open` outlives `_row_open_wanted`.
func set_reveal_cards(cards: Array[CardData]) -> void:
#a hook may have just compacted the board
	flush_rebuild()
	var game := CardEnvironment.get_current_game()
	var wanted : Dictionary[Vector2i, bool] = {}
	if game:
		for data : CardData in cards:
#⚠ ASK THE ENGINE WHERE THE CARD IS, do not walk the controls. `grid_position_of` answers for the
#WHOLE board, grids and Entrance alike, off a revision-keyed index; the control walk this replaced
#could only ever find an Entrance card and was a second, staler answer.
			var coord : BoardCoord = game.state.grid_position_of(data)
			if coord.is_nowhere(): continue
			wanted[_reveal_key(coord)] = true
	_row_open_wanted = wanted
	for key : Vector2i in wanted:
		if not _row_open.has(key): _row_open[key] = 0.0
	set_process(true)

#Push the current openings onto the row strips AND the row score gutters.

#⚠ THE GUTTER GROWS BY THE SAME AMOUNT OR THE SCORE NUMBERS DESYNC FROM THEIR ROWS. The labels are
#a parallel column with no knowledge of the cards, so nothing else keeps them level, and it fails
#silently and looks like a labelling bug.
func _apply_row_openings() -> void:
#⚠ The GRID's opening needs no control pass: a grid row's height is a function of its cells' depth
#(`_measure_grid_row_height`), which the containers already resolve on their own. Only the
#Entrance's fanned strips and its score gutter have to be pushed by hand.
	var hbox : HBoxContainer = upper_zone_right
	if hbox:
#⚠ THIS FOLLOWS THE ENTRANCE'S REVERSED ORDER AND IS THE LAST WRITER OF THOSE HEIGHTS. Child 0 is
#the newest card and shows whole, each card under it shows one depth pitch, and the slot's own
#zone card is the last child, which update_card_zone_visuals() owns.

#A face-down stock card under a card the slot holds shows nothing of itself, so no height here.
		for i : int in hbox.get_child_count():
			var col : Node = hbox.get_child(i)
			var depth := col.get_child_count() - 1
			for j : int in depth:
				var c := col.get_child(j) as Control
				if not c: continue
				if j > 0 and is_stock_control(c):
					c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0.0)
					continue
				var base : float = CardVisual.card_size_play.y if j == 0 else _depth_pitch_px()
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
						base + row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW,
						_control_height(i, depth, j))))
	var gutter : VBoxContainer = upper_zone_left
	if not gutter: return
	for i : int in gutter.get_child_count():
		var label := gutter.get_child(i) as Control
		if not label: continue
		label.custom_minimum_size = Vector2(CardVisual.card_separation_play,
				float(CardVisual.card_separation_play_custom)
				+ row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, i)))

#One frame of the reveal. Returns whether anything is still open or moving.

#⚠ A FRACTION OF `Game.get_delay()`, never wall clock — the expansion compresses with the act
#speed-up exactly like the dim, the travel and the hold, so a long cascade cannot leave a row still
#opening while the next section has already started.
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
#⚠ Only an ENTRANCE key can make the control pass necessary — a grid row's height is a function of
#its cells' depth and its containers resolve it themselves. Running the pass for a grid key
#rewrites the Entrance's strips for nothing, and the relayout drifts anything anchored to a slot.
		var is_entrance_key := key.x == REVEAL_ENTRANCE_GRID
		if is_equal_approx(now, target):
#⚠ A fully CLOSED row leaves the map, so an idle board holds no reveal state at all and
#`_row_open_offset` stays free. A fully OPEN one must stay — it is still displacing.
			if target <= 0.0: shut.append(key)
			continue
		_row_open[key] = move_toward(now, target, delta / span)
		if is_entrance_key: moved = true
	for key : Vector2i in shut: _row_open.erase(key)
	if moved or not shut.is_empty(): _apply_row_openings()
	return growing or not _row_open.is_empty()

#One frame of every landing depth layer growing into its height. Shares the reveal's clock, so a
#placement during a cascade compresses with the act speed-up rather than running on wall time of
#its own. An entry that reaches 1 is ERASED: arrived height is permanent.
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

#The board itself has no per-frame work — rebuilds are signal-driven, see queue_rebuild. This hook
#keeps the visible focus inspector pinned to its live anchor, and drives the reveal.
func _process(delta: float) -> void:
	if not _ease_row_openings(delta): set_process(false)

func update_score_controls() -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	set_score_zone(true, upper_zone_left, game_state.scores_row_upper)
#`scores_row_lower` and `scores_col_legacy` are storage only; nothing renders them. Banking a line
#score reaches here while the scored row is still OPEN and `set_score_zone` has just reset every
#gutter to its base height, so without this the numbers desync from their rows.
	_apply_row_openings()

func set_score_zone(is_row:bool, zone:BoxContainer, scores:Array[BigNumber]) -> void:
	var scores_size := scores.size()
#there should always be at least 1 control as buffer
	if is_row and scores_size == 0: scores_size += 1
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
	update_score_controls()
	var label : BigNumberLabel
	if zone == game.state.scores_row_upper:
		label = upper_zone_left.get_child(index)
#scores_row_lower / scores_col_legacy: storage only, no rendering surface anymore.
	if label: label.update_score_anim(score)

	
#THE SPRING. Jump `data`, and lift every card stacked ABOVE it in its own cell by the same rise,
#rigidly. Returns how long the raise takes, like `anim_jump` does.

#⚠ THE BOARD KNOWLEDGE BELONGS HERE, NOT IN `CardVisual`. A card visual has no idea what is stacked
#on it, so every caller that reached for `anim_jump()` directly calls this instead and a jump can
#never again lift only the card it happened to.

#⚠ Grid cells only. The Entrance still fans DOWNWARD from its control tops, so "above" is not the
#same relation there and lifting it would move cards toward the board rather than with it.
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
	flush_rebuild()
	var wait_time : float = 0
	for data in result.meld:
		if data in data_card:
			var anim_time := jump_card_with_its_stack(data)
			wait_time = anim_time if anim_time > wait_time else wait_time
	await Pacing.wait(self, wait_time).timeout
	
func reset_meld(result : Scoring.Result) -> void:
	flush_rebuild()
	for data in result.meld:
		if data in data_card:
			data_card[data].anim_reset()

func popup_score(result : Scoring.Result) -> void:
	if EventLog.is_on(EventLog.CH_SCORE):
		EventLog.event(EventLog.CH_SCORE, "popup_score", "meld=%d" % result.meld.size())
	flush_rebuild()
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
#OverlayLayer (the last sibling) draws above every card and prop by tree order. It rides the scroll
#content, so a global-space combo_pos stays put (LAYERING.md).
	overlay_layer.add_child(score_name_popup)
	await Pacing.wait(self, CardEnvironment.CURRENT.get_delay()*.3).timeout
	score_name_popup.queue_free()
