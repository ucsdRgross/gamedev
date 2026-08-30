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

## The board has exactly TWO view modes and nothing in between: OVERVIEW shows every grid for
## orientation, FOCUSED shows the one grid the player is acting on. Switching is a transition —
## there is no intermediate zoom to sit at.
enum ViewMode { OVERVIEW, FOCUSED }

## No grid is focused. ⚠ Never 0 — grid 0 is a real grid.
const NO_GRID := -1

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

var separation : int = 4: 
	set(value):
		separation = value
		set_separation()
	get():
		return separation * SettingsManager.settings.card_scale

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
	return row_open_height(SettingsManager.settings, float(separation))

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
	return row_open_span(SettingsManager.settings, float(separation)) * t

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
## `GridContainer`, built per panel in `_build_grid_panel`.
@onready var scroll_container: ScrollContainer = $SmoothScrollContainer
@onready var grid_container: HBoxContainer = %GridContainer
@onready var card_layer: Node2D = %CardLayer
## Always-on-top surface (last sibling of TopLevelVBox): the focus inspector panel and score
## popups live here so they render above every card and prop by TREE ORDER — no z_index needed.
@onready var overlay_layer: Node2D = %OverlayLayer

## **THE PINNED ENTRANCE.** A sibling of `SmoothScrollContainer`, outside the board's scroll, so
## it never scrolls away vertically: `EntranceStrip` is the fixed, clipped window; `EntranceHTrack`
## is the wide (board-content-width) track slid in X to mirror the board's own horizontal scroll
## (`_sync_entrance_x`); `EntranceVScroll` is the Entrance's OWN vertical scroll for a stack
## deeper than the strip; `EntranceCardLayer` is its OWN card layer — a card layer INSIDE the
## board's scroll cannot pin, because its cards would scroll away from their own pinned controls.
@onready var entrance_strip: Control = %EntranceStrip
@onready var entrance_h_track: Control = %EntranceHTrack
@onready var entrance_v_scroll: ScrollContainer = %EntranceVScroll
@onready var entrance_card_layer: Node2D = %EntranceCardLayer

func _ready() -> void:
	SettingsManager.settings_changed.connect(update_gui)
	# Pay every FX shader's first-use compile here, on invisible one-pixel quads, rather than on
	# the first card that catches fire mid-act.
	FxAttachment.warm(overlay_layer)
	setup_gui()
	# THE SHOW OPENS ZOOMED OUT. A show is one PlayArea, so this is the show's opening view.
	open_zoomed_out()
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
	_anchor_scroll_to_bottom.call_deferred()
	update_score_controls()
	_apply_entrance_strip_height()
	# The floor is measured against THIS control's height, so re-measure it whenever the window
	# changes — otherwise the board keeps growing off a stale floor.
	if not resized.is_connected(_apply_entrance_strip_height):
		resized.connect(_apply_entrance_strip_height)
	_sync_entrance_x()

func _physics_process(_delta: float) -> void:
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
			card_layer.add_child(label)
			_cell_score_labels[key] = label
		label.current_num = state.scores_cell[key]
		# ABOVE the topmost card: its centre, less half a card, less the label's own height.
		var top := BoardCoord.new(key.x, key.y, key.z, depth - 1)
		var at := slot_center_global(top)
		label.global_position = Vector2(at.x - label.size.x * 0.5,
				at.y - CardVisual.card_size_play.y * 0.5 - label.size.y)
	for key : Vector3i in _cell_score_labels.keys():
		if live.has(key): continue
		var doomed : BigNumberLabel = _cell_score_labels[key]
		if is_instance_valid(doomed): doomed.queue_free()
		_cell_score_labels.erase(key)

## One height-score label per cell that has scored, keyed the same way `scores_cell` is.
var _cell_score_labels : Dictionary[Vector3i, BigNumberLabel] = {}

## X SLAVED TO THE BOARD'S HORIZONTAL SCROLL (owner spec): the Entrance never scrolls on its own
## in X, it mirrors whatever the board's own scroll reads, so its columns stay under the grid's.
##
## ⚠ **ONE SHARED WIDTH, NOT TWO INDEPENDENT ONES.** Before the Entrance was pinned, `GridContainer`
## and `UpperZone` were BOTH direct children of the same `TopLevelVBox`, each filling it (default
## `SIZE_FILL`) — so `TopLevelVBox`'s own width was the max of BOTH their natural (minimum)
## widths, and THAT shared width is what `GridContainer`'s panels (SIZE_SHRINK_CENTER) and
## `upper_zone_right` (ALIGNMENT_CENTER) each centred inside — the same box, so their centres
## agreed. Splitting them into two separate branches loses that unless this reproduces the
## SAME shared width on both sides: `GridContainer` is stretched to it too (`custom_minimum_size`),
## exactly mirroring what the old shared VBox parent gave it for free. Using `grid_container.size.x`
## alone (a NARROWER, already-settled value) left the two centred in different-width boxes and
## measurably 4 px apart (TP-80k) on a board narrower than an Entrance with more columns than it.
func _sync_entrance_x() -> void:
	if not is_instance_valid(entrance_h_track) or not is_instance_valid(scroll_container): return
	# ⚠ **ANCHORED TO THE GRID'S OWN RESOLVED POSITION, NOT `-scroll_horizontal` FROM ZERO.**
	# `grid_container` sits inside `SmoothScrollContainer`'s content, which carries its own
	# internal layout (a ScrollContainer reserves margin the plain `EntranceStrip` chain never
	# had) -- mirroring the raw scroll delta reproduced the SCROLL, correctly, but not the
	# CONSTANT offset baked into where the scrolled content starts, which is exactly the same
	# "control-rect read, not arithmetic" fix `_grid_slot_center_global`'s own panel-origin cache
	# already made once (measured: 4 px, TP-80k). Reading `grid_container`'s live global position
	# folds the scroll delta AND that constant in together, correct by construction either way.
	# ⚠ **SLAVED TO THE COLUMNS, NOT TO THE CONTAINER.** The Entrance's slots line up with the grid
	# COLUMNS above them, and once a panel carries a row-label gutter the container's left edge is
	# no longer where the columns start — measured: every slot 20 px out, exactly the gutter's width.
	var columns_x := grid_container.global_position.x
	if grid_container.get_child_count() > 0:
		var first_cells := _cells_root(grid_container.get_child(0) as Control)
		if first_cells: columns_x = first_cells.global_position.x
	entrance_h_track.position.x = columns_x - entrance_strip.global_position.x
	# ⚠ ZERO `grid_container`'s OWN override BEFORE measuring it: `get_combined_minimum_size()`
	# folds in `custom_minimum_size`, and this function is the only writer of that override — an
	# un-reset read would fold in LAST call's answer, so `shared_width` could only ever grow
	# (never shrink back down once an Entrance was briefly wider), converging on a WRONG, sticky
	# value instead of the two containers' true natural widths.
	grid_container.custom_minimum_size.x = 0.0
	var shared_width := maxf(grid_container.get_combined_minimum_size().x,
			upper_zone_right.get_combined_minimum_size().x)
	grid_container.custom_minimum_size.x = shared_width
	entrance_h_track.size.x = shared_width

## The strip's fixed visible height, and the matching reservation carved out of the board's own
## scroll so the two never overlap on screen. A multiple of one card's height
## (`entrance_visible_rows`) — re-applied on every settings change since `card_scale` resizes
## the card the multiple is measured against.
func _apply_entrance_strip_height() -> void:
	if not is_instance_valid(entrance_strip) or not is_instance_valid(scroll_container): return
	# ⚠ **THE VISIBLE STRIP AND THE ENTRANCE'S OWN HEIGHT ARE TWO DIFFERENT NUMBERS.** The strip is
	# a player setting — how much Entrance is on screen — and it must NOT move when cards land in
	# the Entrance: resizing it re-lays out everything anchored INSIDE it, which drifted a prop off
	# its slot mid-reveal (4 px) and moved an Entrance slot 17 px between cycles. What Q313 asks for
	# is that the BOARD rises, and only the board.
	var h := CardVisual.card_size_play.y * SettingsManager.settings.entrance_visible_rows
	entrance_strip.offset_top = -h
	scroll_container.offset_bottom = -h
	# ⚠ **THE FLOOR CLEARS THE ENTRANCE'S ACTUAL HEIGHT, NOT ITS RESERVATION** (`Q313`=a, owner:
	# *"it raises everything above it up as well so as to not cover any card in the grid"*). A
	# stacked Entrance that outgrows its strip pushes the board up by the overflow; a shallow one
	# changes nothing.
	_give_the_board_a_floor(maxf(h, _entrance_row_height()))

## ⚠ **THE ENTRANCE IS ROW −1, AND ITS OWN HEIGHT PUSHES THE BOARD UP** (`Q313`=a, owner: *"if
## entrance/input cards are somehow stacked with multiple cards as well increasing in height, then
## it raises everything above it up as well so as to not cover any card in the grid"*). Same
## arithmetic a grid row uses — a whole card plus a fanned strip for every card under the top one —
## so the Entrance participates in the board's geometry rather than being a fixed reservation the
## board happens to sit above. The configured `entrance_visible_rows` stays the FLOOR of that: a
## shallow Entrance still shows the strip the player expects.
func _entrance_row_height() -> float:
	var full := CardVisual.card_size_play.y
	var game := CardEnvironment.get_current_game()
	if not game: return full
	var deepest := 0
	for col : ArrayCardData in game.state.upper_zone:
		deepest = maxi(deepest, col.datas.size())
	if deepest == 0: return full
	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(separation)
	return float(separation) + full + float(deepest - 1) * depth_pitch

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
	top_level_vbox.custom_minimum_size.y = maxf(size.y - strip_h, 0.0)
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
	_board_floor_y = top_level_vbox.global_position.y + top_level_vbox.size.y
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
		_grid_cells_bottom[i] = cells.global_position.y + cells.size.y

## Scroll to the bottom of the board. ⚠ ON ENTRY ONLY -- a rebuild that re-anchored would yank
## the view out from under a player who had scrolled somewhere else.
func _anchor_scroll_to_bottom() -> void:
	if not is_instance_valid(scroll_container): return
	await get_tree().process_frame
	var bar := scroll_container.get_v_scroll_bar()
	if bar: scroll_container.scroll_vertical = int(bar.max_value)

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

## Open the all-grids view with nothing focused. The show's opening view.
func open_zoomed_out() -> void:
	_set_view(ViewMode.OVERVIEW, NO_GRID)

## Focus one grid — what a click on a grid in the overview does. Placement happens focused.
## Focusing also CENTRES the view on that grid: the grid being acted on is the grid in the middle,
## in both modes, so `pan_grid` can never disagree with `focused_grid` about where the view is.
func focus_grid(gi: int) -> void:
	if gi < 0 or gi >= grid_container.get_child_count(): return
	_set_view(ViewMode.FOCUSED, gi)
	pan_to_grid(gi)

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
	if _consume_as_swipe(event):
		return true
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
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	var cells := _cells_root(grid_container.get_child(gi) as Control)
	if not cells: return
	var want_centre := scroll_container.global_position.x + scroll_container.size.x * 0.5
	var have_centre := cells.global_position.x + cells.size.x * 0.5
	smooth.scroll_x_to(smooth.pos.x + want_centre - have_centre,
			SettingsManager.settings.grid_pan_duration)

## The edge push-back: velocity spent into the scroll container's OWN overdrag, which supplies the
## counterforce and carries the board back to rest. Reused rather than hand-tweened so the board's
## edge feels like every other overscroll in the game — and so nothing here can park the board off
## its own edge.
func _bounce_board(step: int) -> void:
	var smooth := scroll_container as SmoothScrollContainer
	if not smooth: return
	smooth.scroll_horizontally(float(step) * SettingsManager.settings.grid_bounce_velocity_px)

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
func _consume_as_grid_select(event: InputEvent) -> bool:
	if view_mode != ViewMode.OVERVIEW: return false
	var d := _arrow_delta(event)
	if d.x == 0: return false
	var last := grid_container.get_child_count() - 1
	if last < 0: return false
	selected_grid = clampi(selected_grid + d.x, 0, last)
	pan_to_grid(selected_grid)
	var target := _cell_focus_control(BoardCoord.new(selected_grid, 0, 0, 0))
	if target: target.grab_focus()
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
## the screen's DPI and clamped to the same touch-target bounds, because a DPI reading is
## unreliable on multi-monitor Windows (which reports the primary screen's for all of them) and on
## Android, and an unclamped conversion can therefore produce any number at all.
func _swipe_threshold_px() -> float:
	var s := SettingsManager.settings
	return clampf(WallInput.mm_to_px(s.grid_swipe_threshold_mm, DisplayServer.screen_get_dpi()),
			s.wall_touch_target_min_px, s.wall_touch_target_max_px)

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
func _input(event: InputEvent) -> void:
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
func _entrance_slot_center_global(coord: BoardCoord) -> Vector2:
	# ⚠ **THE CONTAINER'S OWN `global_position` STOPS MIRRORING ITS CHILDREN THE MOMENT IT IS
	# CENTRED** (`ALIGNMENT_CENTER`, set in `setup_gui` so the Entrance lines up with the grid):
	# the columns start at an offset INSIDE the hbox, and the two disagree by half the slack
	# (measured: 20 px). The first column's own `global_position` already carries that
	# offset, so read it directly instead of teaching this formula the alignment math. Falls back
	# to the container's own position for an entrance with no columns built yet.
	var origin := upper_zone_right.global_position
	if upper_zone_right.get_child_count() > 0:
		origin = (upper_zone_right.get_child(0) as Control).global_position
	var width := CardVisual.card_size_play.x
	var pitch := float(CardVisual.card_separation_play_custom) + float(separation)
	var x := origin.x + float(coord.x) * (width + float(separation)) + width * 0.5
	var y := origin.y + float(separation) + pitch * float(coord.h) + CardVisual.card_size_play.y * 0.5
	# ⚠ **THE UNIFORM PITCH IS NOT THE WHOLE STORY, AND EVERY PROP ANCHORS TO THIS.** The reveal lets
	# one row's strip grow, so the rows below it are pushed down by an amount the pitch does not
	# describe. Without this term a prop anchored under an expanding row stays where the unexpanded
	# maths says it should be and visibly detaches from its slot.
	# ⚠ Still PURE MATH, no control-rect reads: the offset comes from the same eased numbers that size
	# the controls, so geometry stays independent of container relayout timing (owner spec).
	y += _row_open_offset(coord)
	return Vector2(x, y)

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
	var width := CardVisual.card_size_play.x
	var full := CardVisual.card_size_play.y
	var depth_pitch := float(CardVisual.card_separation_play_custom) + float(separation)
	var x := origin.x + float(coord.x) * (width + float(separation)) + width * 0.5
	# ⚠ **THE ROW BOTTOMS ARE MEASURED FROM THE BOARD'S FLOOR, NOT FROM THIS PANEL.** Every panel is
	# bottom-aligned against that one line, and it does not move when a stack deepens — so nothing
	# here lags the way a per-panel rect cache did. Do NOT refresh a rect cache from
	# `_physics_process` instead: reading panel rects every frame feeds the relayout the floor code
	# writes into, and the board never settles.
	var bottom : float = _grid_cells_bottom.get(coord.grid, _board_floor_y)
	for r : int in range(coord.y + 1, _grid_rows(coord.grid)):
		bottom -= _grid_row_height(coord.grid, r) + float(separation)
	# The cell's own frame sits ON the row's bottom line; the stack starts one `separation` above
	# it — the gap the CellSlot puts between the frame and the card covering it.
	var y := bottom - float(separation) - depth_pitch * float(coord.h) - full * 0.5
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
	var aligned : bool = SettingsManager.settings.grid_align_rows_globally
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
	if not SettingsManager.settings.grid_align_rows_globally:
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
	return float(separation) + full + grown

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
	if coord.is_entrance():
		var hbox : HBoxContainer = upper_zone_right
		var idx := coord.h + 1   # child 0 = the zone/type header
		for col : Node in hbox.get_children():
			if idx >= col.get_child_count(): continue
			var d : CardData = ui_data.get(col.get_child(idx))
			_append_row_visual(out, d)
		return out
	# ⚠ Read the GRID from STATE, not from the cell controls: rebuilds are DEFERRED, so mid-mutation
	# the controls still describe the previous board — the same reason `_row_covers_anything` reads
	# state. The Entrance keeps its control walk because its fanned columns ARE the structure.
	var game := CardEnvironment.get_current_game()
	if not game: return out
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
	var card_columns := type.size()
	var column_diff: int = card_columns - hbox.get_child_count()
	
	# Structure layout columns
	if column_diff > 0:
		for i in column_diff:
			var new_vbox := VBoxContainer.new()
			new_vbox.add_theme_constant_override("separation", separation)
			hbox.add_child(new_vbox)
	elif column_diff < 0:
		for i in absi(column_diff):
			var child: Control = hbox.get_child(-1)
			hbox.remove_child(child)
			child.queue_free()

	# Structure rows per column and register data mappings
	for i in type.size():
		var card_rows := datas[i].datas.size() + 1 # +1 for zone/type
		var vbox: VBoxContainer = hbox.get_child(i)
		var row_diff: int = card_rows - vbox.get_child_count()
		
		if row_diff > 0:
			for j in row_diff:
				var new_control := create_card_control()
				vbox.add_child(new_control)
		elif row_diff < 0:
			for j in absi(row_diff):
				var child: Control = vbox.get_child(-1)
				vbox.remove_child(child)
				child.queue_free()
				
		# Map the main Zone/Type Control (Index 0), then the Row Cards (Index 1 onwards) —
		# one bind path for both (E6)
		_bind_slot(vbox.get_child(0) as Control, type[i])
		for j in range(1, vbox.get_child_count()):
			_bind_slot(vbox.get_child(j) as Control, datas[i].datas[j-1])

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
	# A GRID card hangs from its control's BOTTOM edge (stacks grow upward, a row shares one bottom
	# edge); the Entrance still fans downward from its control tops. The layer the control belongs
	# to is exactly that distinction, so it is the one thing asked.
	var bottom := target_layer == card_layer
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
		var vbox: VBoxContainer = hbox.get_child(i)
		vbox.add_theme_constant_override("separation", separation)
		
		# 1. Visual settings for Zone/Type Card (Index 0)
		var c: Control = vbox.get_child(0)
		c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
		c.focus_mode = Control.FOCUS_ALL
		
		if selected_cards:
			if c == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)
			elif vbox.get_child_count() > 1 and vbox.get_child(1) == focused_control:
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom / 2.5)
		elif vbox.get_child_count() != 1:
			c.focus_mode = Control.FOCUS_NONE
			
		# 2. Visual settings for Row Cards (Index 1 onwards). (Structural ordering moved to the
		# dedicated row-major pass — _order_board_cards, run once after both zones.)
		for j in range(1, vbox.get_child_count()):
			c = vbox.get_child(j)
			c.custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)

		(vbox.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play

	# ⚠ S16: the loop above resets every strip to its stacked height, so a rebuild that lands mid-act
	# would slam an open row shut. Re-push the live openings over the top of it.
	_apply_row_openings()

	# 3. Focus neighborhood linking
	for i in type.size() - 1:
		var left: Control = hbox.get_child(i).get_child(0)
		var right: Control = hbox.get_child(i+1).get_child(0)
		left.focus_neighbor_right = right.get_path()
		right.focus_neighbor_left = left.get_path()

	# 4. Held stack expansion logic
	if selected_cards and selected_cards[0] in data_ui:
		var selected_control := data_ui[selected_cards[0]]
		var control_index := selected_control.get_index()
		if selected_control.get_index() > 0:
			var vbox: Control = selected_control.get_parent()
			(vbox.get_child(control_index - 1) as Control).custom_minimum_size = CardVisual.card_size_play
			if selected_control.get_index() == 1:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
			else:
				(vbox.get_child(-1) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)

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
func _on_grid_removed(removed: int) -> void:
	if grid_container.get_child_count() == 0: return
	if pan_grid > removed: pan_grid -= 1
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
	while waited < SettingsManager.settings.grid_pan_duration:
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

## A panel: a positioning node that draws nothing, holding the cell grid.
func _create_grid_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "GridPanel"
	# Grids are aligned by their BOTTOM edges: every grid sits on the same floor and grows
	# upward independently, which is what the board growing up out of the Entrance means. With
	# cross-grid row alignment off (the default) the bottom edge is the ONLY thing that lines up.
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	board.add_child(row_labels)
	var cells := VBoxContainer.new()
	cells.name = "Cells"
	cells.add_theme_constant_override("separation", separation)
	cells.alignment = BoxContainer.ALIGNMENT_END
	board.add_child(cells)
	var special := BigNumberLabel.new()
	special.name = "SpecialLabel"
	special.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	board.add_child(special)
	panel.add_child(board)
	var col_labels := HBoxContainer.new()
	col_labels.name = "ColLabels"
	col_labels.add_theme_constant_override("separation", separation)
	panel.add_child(col_labels)
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
	slot.add_theme_constant_override("separation", separation)
	slot.size_flags_vertical = Control.SIZE_SHRINK_END
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
	var levels := maxi(state.line_score_levels(state.scores_row, gi),
			state.line_score_levels(state.scores_col, gi))

	var row_labels := board.get_node_or_null("RowLabels") as Control
	if row_labels:
		_fit_children(row_labels, grid.grid_height, _create_label_stack)
		for ry : int in grid.grid_height:
			_fill_label_stack(row_labels.get_child(ry) as VBoxContainer, state.scores_row,
					gi, ry, levels, true)
	var col_labels := panel.get_node_or_null("ColLabels") as Control
	if col_labels:
		_fit_children(col_labels, grid.grid_width, _create_label_stack)
		for cx : int in grid.grid_width:
			_fill_label_stack(col_labels.get_child(cx) as VBoxContainer, state.scores_col,
					gi, cx, levels, false)
	var special := board.get_node_or_null("SpecialLabel") as BigNumberLabel
	if special:
		# ⚠ ONE label for every diagonal and every future non-directional meld — the owner's Q110
		# ruling, and the bucket really is one in the data too.
		var value : BigNumber = state.score_special[gi] if gi < state.score_special.size() else null
		if value: special.current_num = value
		else: special.text = ""

## One line's labels: a VBox of one label per height, built like a `CellSlot` so the stack reads
## in the same direction the cards do.
func _create_label_stack() -> Control:
	var stack := VBoxContainer.new()
	stack.name = "LabelStack"
	stack.add_theme_constant_override("separation", separation)
	stack.size_flags_vertical = Control.SIZE_SHRINK_END
	return stack

## ⚠ **HIGHEST HEIGHT FIRST**, so the column reads bottom-up exactly like the cards beside it: the
## last child is height 0, level with the height-0 cards, and each earlier child is one level up.
func _fill_label_stack(stack: VBoxContainer, bucket: Dictionary[Vector3i, BigNumber],
		gi: int, index: int, levels: int, is_row: bool) -> void:
	if not stack: return
	_fit_children(stack, maxi(levels, 1), _create_score_label)
	var game := CardEnvironment.get_current_game()
	if not game: return
	for i : int in stack.get_child_count():
		var h := stack.get_child_count() - 1 - i   # child 0 is the HIGHEST height
		var label : BigNumberLabel = stack.get_child(i)
		label.custom_minimum_size = Vector2(CardVisual.card_separation_play,
				CardVisual.card_separation_play_custom) if is_row 				else Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play)
		var key := Vector3i(gi, index, h)
		if bucket.has(key): label.current_num = bucket[key]
		else: label.text = ""

func _create_score_label() -> Control:
	return BigNumberLabel.new()

## The node holding a grid's ROW containers. ⚠ Everything that walks rows goes through here: the
## panel also carries score gutters, and a lookup that indexed the panel directly would silently
## start reading a gutter as a row.
func _cells_root(panel: Control) -> Control:
	var board := panel.get_node_or_null("Board") as Control
	return board.get_node_or_null("Cells") as Control if board else null

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
		var stack : Array[CardData] = grid.cells[ci].datas
		var rows := stack.size() + 1   # +1 for the cell's own zone card
		var row_diff := rows - slot.get_child_count()
		if row_diff > 0:
			for _j : int in row_diff:
				slot.add_child(create_card_control())
		elif row_diff < 0:
			for _j : int in absi(row_diff):
				var doomed : Node = slot.get_child(-1)
				slot.remove_child(doomed)
				doomed.queue_free()
		# ⚠ **REVERSED, AND THE CELL'S OWN FRAME GOES LAST.** A VBox lays its children out top to
		# bottom and a card now hangs from its control's BOTTOM edge, so: the card at the greatest
		# height takes the FIRST control, h 0 the last CARD control, and the cell's zone card the very
		# last one — because the frame marks the CELL, which sits on the row's bottom line and does
		# not rise with the stack.
		# ⚠ Leaving the frame FIRST drew it a full card ABOVE an occupied cell: its control collapses
		# to zero height once a card covers it, so bottom-anchoring put the frame off the top of the
		# cell and onto the row above — which reads as a whole extra row of frames. Found by eye.
		var depth := stack.size()
		for j : int in depth:
			_bind_slot(slot.get_child(j) as Control, stack[depth - 1 - j])
		_bind_slot(slot.get_child(depth) as Control, grid.cell_types[ci])

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
			if not slot: continue
			slot.add_theme_constant_override("separation", separation)
			# The cell's zone card is the LAST child: a full card while the cell is empty (it IS what
			# an empty cell shows), collapsed to nothing once a card covers it.
			var zone_control : Control = slot.get_child(-1)
			zone_control.custom_minimum_size = CardVisual.card_size_play 					if slot.get_child_count() == 1 else Vector2(CardVisual.card_size_play.x, 0)
			# The TOPMOST card of the stack (child 0 after the flip) shows whole; every card under it
			# contributes only its own bottom strip.
			for j : int in slot.get_child_count() - 1:
				(slot.get_child(j) as Control).custom_minimum_size = Vector2(
						CardVisual.card_size_play.x, CardVisual.card_separation_play_custom)
			if slot.get_child_count() > 1:
				(slot.get_child(0) as Control).custom_minimum_size = CardVisual.card_size_play

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
	var row_index := control.get_index()
	var column_node : Control = control.get_parent()
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

	# resize zone control so it is possible to place card behind first card
	if focused_control and focused_control.get_index() == 0:
		focused_control.custom_minimum_size = Vector2(CardVisual.card_size_play.x, 0)
		(focused_control.get_parent().get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
	if row_index == 0:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom/1.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
	elif row_index == 1:
		(column_node.get_child(0) as Control).custom_minimum_size = Vector2(CardVisual.card_size_play.x, CardVisual.card_separation_play_custom/2.5)
		(column_node.get_child(-1) as Control).custom_minimum_size = CardVisual.card_size_play
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
		for col : Node in hbox.get_children():
			var last := col.get_child_count() - 1
			for j : int in range(1, col.get_child_count()):
				var c := col.get_child(j) as Control
				if not c: continue
				var base : float = CardVisual.card_size_play.y if j == last \
						else float(CardVisual.card_separation_play_custom)
				c.custom_minimum_size = Vector2(CardVisual.card_size_play.x,
						base + row_open_extra(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, j - 1)))
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
	var unit : float = game.get_delay() if game else SettingsManager.settings.base_delay
	var span := maxf(unit * SettingsManager.settings.spotlight_reveal_fraction, 0.0001)
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
	var unit : float = game.get_delay() if game else SettingsManager.settings.base_delay
	var span := maxf(unit * SettingsManager.settings.spotlight_reveal_fraction, 0.0001)
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
	if _row_open.is_empty(): set_process(false)  # nothing to pin while hidden
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
