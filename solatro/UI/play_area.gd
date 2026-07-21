extends Control
class_name PlayArea

signal data_selected(data : CardData)
## Emitted once a rebuild's CardVisuals are all in-tree and _ready. CardVisuals add_child via
## call_deferred, so right after set_card_zones they're mapped in data_card but not yet ready;
## a deferred emit queued after those adds (FIFO) fires only once they've entered the tree.
## Lets callers that must animate a freshly built board (e.g. a resumed show) await instead
## of poll. Pair with visuals_ready() for the already-ready case (check-then-await).
signal board_visuals_ready

var focused_control : Control = null
var moused_hovered_control : Control = null
var selected_cards : Array[CardData] = []

var separation : int = 4: 
	set(value):
		separation = value
		set_separation()
	get():
		return separation * SettingsManager.settings.card_scale

var ui_data : Dictionary[Control, CardData]
var data_ui : Dictionary[CardData, Control]
var data_card : Dictionary[CardData, CardVisual]
var new_data_card : Dictionary[CardData, CardVisual]

@onready var containers : Array[Control] = [%TopLevelVBox, %UpperZone, %UpperZoneLeft, 
								%UpperZoneRight, %MiddleZone, %MiddleZoneRight, 
								%LowerZone, %LowerZoneLeft, %LowerZoneRight]
@onready var upper_zone_left: VBoxContainer = %UpperZoneLeft
@onready var lower_zone_left: VBoxContainer = %LowerZoneLeft
@onready var upper_zone_right: HBoxContainer = %UpperZoneRight
@onready var lower_zone_right: HBoxContainer = %LowerZoneRight
@onready var middle_zone_left: Control = %MiddleZoneLeft
@onready var middle_zone_right: HBoxContainer = %MiddleZoneRight
@onready var prop_layer: PropLayer = %PropLayer   ## Phase 4 prop-animation surface
## CardVisual host INSIDE the scroll content (a Node2D the containers ignore, like PropLayer):
## the scroll transform carries cards, controls, and props together. Parented to the PlayArea
## root, cards chased their anchors' scrolled globals through the _process ease and visibly
## lagged every scroll (owner report 2026-07-12).
@onready var card_layer: Node2D = %CardLayer
## Always-on-top surface (last sibling of TopLevelVBox): the focus inspector panel and score
## popups live here so they render above every card and prop by TREE ORDER — no z_index needed.
@onready var overlay_layer: Node2D = %OverlayLayer

func _ready() -> void:
	SettingsManager.settings_changed.connect(update_gui)
	setup_gui()
	set_process(false)  # _process only pins the focus inspector — enabled while it is visible

func setup_gui() -> void:
	set_separation()
	set_card_zones()
	update_score_controls()
	middle_zone_left.custom_minimum_size = Vector2.ONE * CardVisual.card_separation_play

func update_gui() -> void:
	set_separation()
	set_card_zones_visuals()
	update_score_controls()
	middle_zone_left.custom_minimum_size = Vector2.ONE * CardVisual.card_separation_play

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
				data_selected.emit(ui_data[focused_control])

## Keyboard/controller accept + cancel. Key events go ONLY to the focused control (a plain
## card control consumes nothing), then fall through the focus-navigation pass to unhandled
## input — this is the first place the board can hear them. Buttons (Submit/Continue/…)
## consume their own ui_accept before this runs, so a focused button never double-acts.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		flush_rebuild() #reads ui_data
		# Act only when a BOARD control genuinely holds focus RIGHT NOW (focused_control is
		# our last-known card control; it can go stale when focus moves to other UI, and it
		# must stay inert while the game-over overlay has the board focus-locked).
		if (is_instance_valid(focused_control)
				and focused_control in ui_data
				and get_viewport().gui_get_focus_owner() == focused_control):
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
			# CardLayer). move_child to the end of CardLayer — no z_index (structural order,
			# LAYERING.md). ungrab_cards -> rebuild restores row-major order.
			if card_visual.get_parent() == card_layer:
				card_layer.move_child(card_visual, -1)
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
		set_card_zones()

## The board Control at a slot coord (z == -1 header, z >= 0 row card), or null if the layout
## has no control there (empty slot past the built rows). Focus/input helpers use this;
## slot GEOMETRY does not — slot_center_global below is pure math (owner spec 2026-07-15).
func control_for_coord(v: Vector3i) -> Control:
	var hbox : HBoxContainer = upper_zone_right if v.x == 0 else lower_zone_right
	if v.y < 0 or v.y >= hbox.get_child_count(): return null
	var vbox := hbox.get_child(v.y)
	var idx := v.z + 1   # child 0 = the zone/type header (z == -1)
	if idx < 0 or idx >= vbox.get_child_count(): return null
	return vbox.get_child(idx) as Control

## Global-space center of the CARD at any slot coord — PURE MATH from the zone container's
## origin plus layout constants, NO control_for_coord / control rect reads (owner spec
## 2026-07-15): geometry is deterministic and independent of container relayout timing, and the
## one formula covers occupied, empty, and off-board slots alike — so a prop crossing a row keeps
## ONE y through empty and short columns (the header-fallback bugs of 2026-07-12/13 can't recur:
## an inflated empty-column header or a focus-resized row no longer moves the slot line).
## Derivation (mirrors the container build in set_card_zone / update_card_zone_visuals):
##   column x = zone hbox left + column * (card width + separation) + half card width
##   slot top = zone hbox top + header height (0) + separation + slot * row pitch
##     with row pitch = card strip height (card_separation_play_custom) + separation
##   card anchor = slot top + half a card (CardVisual.get_card_control_center) — stacked row
##     strips are thin while the card art hangs a full card below its control top.
func slot_center_global(v: Vector3i) -> Vector2:
	var hbox : HBoxContainer = upper_zone_right if v.x == 0 else lower_zone_right
	var origin := hbox.global_position
	var width := CardVisual.card_size_play.x
	var pitch := float(CardVisual.card_separation_play_custom) + float(separation)
	var x := origin.x + float(v.y) * (width + float(separation)) + width * 0.5
	var y := origin.y + float(separation) + pitch * float(v.z) + CardVisual.card_size_play.y * 0.5
	return Vector2(x, y)

## Every CardVisual on slot `v`'s ROW — same zone, row v.z across every column (z == -1 = the
## zone/type header row); ragged/short columns simply have no control at that row and are
## skipped, so an empty slot never pulls another row's card into the set. Row-major CardLayer
## order (_order_board_cards) keeps a row contiguous, so PropLayer brackets [first..last] of
## this set to render a split prop behind / in front of the WHOLE row.
func row_card_visuals(v: Vector3i) -> Array[CardVisual]:
	var out : Array[CardVisual] = []
	var hbox : HBoxContainer = upper_zone_right if v.x == 0 else lower_zone_right
	var idx := v.z + 1   # child 0 = the zone/type header (z == -1)
	if idx < 0: return out
	for col : Node in hbox.get_children():
		if idx >= col.get_child_count(): continue
		var d : CardData = ui_data.get(col.get_child(idx))
		var vis : CardVisual = data_card.get(d) if d else null
		if vis and is_instance_valid(vis):
			out.append(vis)
	return out

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
	set_card_zone(lower_zone_right, game_state.lower_zone_type, game_state.lower_zone)
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
	update_card_zone_visuals(lower_zone_right, game_state.lower_zone_type, game_state.lower_zone)
	_order_board_cards(game_state)

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

## Register one board control <-> CardData mapping and carry over (or create) its CardVisual.
func _bind_slot(c: Control, connected_data: CardData) -> void:
	ui_data[c] = connected_data
	data_ui[connected_data] = c
	# Interactivity is a FUNCTION OF THE CURRENT STATE, never a leftover. Board controls are
	# POOLED per slot and rebound to whatever card lands there, so the MOUSE_FILTER_IGNORE
	# grab_cards puts on a held card's control must be re-derived here — otherwise a rebuild
	# that happens while a grab is live (auto-Next folds a Next into try_place) leaves the
	# filter on a control that now belongs to a DIFFERENT card, which becomes permanently
	# uninteractable and survives undo (owner bug report 2026-07-20).
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE if connected_data in selected_cards \
			else Control.MOUSE_FILTER_PASS
	if connected_data in data_card and is_instance_valid(data_card[connected_data]):
		new_data_card[connected_data] = data_card[connected_data]
		new_data_card[connected_data].control_anchor = c
	else:
		new_data_card[connected_data] = CardVisual.add_child_card_visual(
			card_layer, connected_data, CardVisual.DisplayContext.PLAY_AREA, c)

## Structural draw order (no z_index anywhere, LAYERING.md), ROW-MAJOR across columns
## (owner spec 2026-07-16): per zone, the type/zone headers first, then row 0 of every column,
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
func _order_board_cards(game_state: GameData) -> void:
	var ordered : Array[CardVisual] = []
	var seen : Dictionary[CardVisual, bool] = {}
	var pending : Array[bool] = [false]
	_append_zone_row_major(ordered, seen, pending, game_state.upper_zone_type, game_state.upper_zone)
	_append_zone_row_major(ordered, seen, pending, game_state.lower_zone_type, game_state.lower_zone)
	for i : int in ordered.size():
		var vis := ordered[i]
		if vis.get_index() != i:
			card_layer.move_child(vis, i)
	# Freshly created CardVisuals enter the tree via call_deferred and were skipped above — but
	# their creation order is COLUMN-major, so without a follow-up pass a fresh board keeps the
	# wrong row order until some unrelated rebuild happens (which nothing guarantees: hoop halves
	# then bracketed scattered indices — back arcs behind the row above, owner report 2026-07-16).
	# Queue exactly ONE re-order behind the pending add_childs (deferred FIFO: adds run first).
	if pending[0] and not _reorder_queued:
		_reorder_queued = true
		_deferred_reorder.call_deferred()

var _reorder_queued := false

func _deferred_reorder() -> void:
	_reorder_queued = false
	var game := CardEnvironment.get_current_game()
	if game: _order_board_cards(game.state)

## Append one zone's CardVisuals in row-major order: headers (row -1), then each row across all
## columns (ragged columns simply skip the rows they don't have). `pending[0]` flips true when a
## visual exists but is not yet in CardLayer (deferred add) — the caller re-orders once it lands.
func _append_zone_row_major(out: Array[CardVisual], seen: Dictionary[CardVisual, bool],
		pending: Array[bool], type: Array[CardData], datas: Array[ArrayCardData]) -> void:
	var max_rows := 0
	for col : ArrayCardData in datas:
		max_rows = maxi(max_rows, col.datas.size())
	for data : CardData in type:
		_append_ordered_visual(out, seen, pending, data)
	for z : int in max_rows:
		for i : int in datas.size():
			if z < datas[i].datas.size():
				_append_ordered_visual(out, seen, pending, datas[i].datas[z])

func _append_ordered_visual(out: Array[CardVisual], seen: Dictionary[CardVisual, bool],
		pending: Array[bool], data: CardData) -> void:
	if data in selected_cards: return   # held cards stay lifted at the layer's end
	var vis : CardVisual = data_card.get(data)
	if vis == null or not is_instance_valid(vis): return
	if vis.get_parent() != card_layer:
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

func create_card_control() -> Control:
	var new_control := Control.new()
	new_control.add_to_group("CardVisualControl")
	new_control.focus_mode = Control.FOCUS_ALL
	new_control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	new_control.focus_entered.connect(func()->void:on_control_focus_entered(new_control))
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
	var row_index := control.get_index()
	var column_node : Control = control.get_parent()
	if focused_visual: focused_visual.focused = false
	if ui_data.has(control) and data_card.has(ui_data[control]):
		focused_visual = data_card[ui_data[control]]
		focused_visual.focused = true
	# Card inspector for EVERY input mode (mouse hover grabs focus too, so focus is the one
	# unified hover signal). NOT Control.tooltip_text: the native tooltip is a popup Window
	# that sat under the cursor and blocked clicks — this panel is pure display (IGNORE).
	if ui_data.has(control):
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

## The board itself has no per-frame work (rebuilds are signal-driven, see queue_rebuild);
## this hook ONLY keeps the visible focus inspector pinned to its live anchor position.
func _process(_delta: float) -> void:
	_position_focus_info()

func hide_focus_info() -> void:
	_focus_info_anchor = null
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
	set_score_zone(true, lower_zone_left, game_state.scores_row_lower)
	set_score_zone(false, middle_zone_right, game_state.scores_col)
	
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
	if zone == game.state.scores_row_lower:
		label = lower_zone_left.get_child(index)
	elif zone == game.state.scores_col:
		label = middle_zone_right.get_child(index)
	elif zone == game.state.scores_row_upper:
		label = upper_zone_left.get_child(index)
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
	
func popup_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	var wait_time : float = 0
	for data in result.meld:
		if data in data_card:
			var anim_time := data_card[data].anim_jump()
			wait_time = anim_time if anim_time > wait_time else wait_time
	await get_tree().create_timer(wait_time).timeout
	
func reset_meld(result : Scoring.Result) -> void:
	flush_rebuild() #reads data_card
	for data in result.meld:
		if data in data_card:
			data_card[data].anim_reset()

func popup_score(result : Scoring.Result) -> void:
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
	await get_tree().create_timer(CardEnvironment.CURRENT.get_delay()*.3).timeout
	score_name_popup.queue_free()
