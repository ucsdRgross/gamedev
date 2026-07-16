@tool
class_name FormationEditor
extends Node2D
## Standalone formation AUTHORING + PREVIEW tool (owner spec 2026-07-13) — open
## res://Cards/Props/Tools/formation_editor.tscn, select the root node, and work entirely
## from the inspector: pick a prop kind, add/generate/hand-edit formations, save them to the
## kind's PropFormationSet .tres (what PropLayer loads in game), and spawn real prop visuals
## over the points to see the result — including OVERFLOW: preview counts beyond one
## formation spill into extra columns, each drawing its own seeded formation exactly like
## adjacent in-game slots would. The card footprint/stack drawings are PURELY debug scenery
## (size/separation knobs below), never used in game. Editor-only; ships no runtime code.

const CARD := CardVisual.CARD_SIZE   # unscaled card footprint; points live in this space

enum Kind { HOOP, KNIFE, BALL, FIRE, FIREWORK }
enum Pattern { GRID, RING, SCATTER, LINE }

@export_group("Formation")
## Which prop kind's formation set is being edited (maps to Formations/<name>.tres).
@export var kind : Kind = Kind.HOOP:
	set(value):
		kind = value
		_load_set()
## Which formation inside the set is being edited/shown.
@export var formation_index : int = 0:
	set(value):
		formation_index = maxi(value, 0)
		_pull_points()
## How a batch maps onto this formation's points: ORDERED = exact point-list order
## (prop i -> point i), RANDOM = seeded shuffle of the list (points only, no repeats until
## all are used). Saved per formation.
@export var mode : PropFormationData.Mode = PropFormationData.Mode.ORDERED:
	set(value):
		mode = value
		var f := _formation()
		if f: f.mode = mode
		_live_update()
## When ON, the formation's HEIGHT spreads with the card-separation setting (see
## PropFormationData.spread_by_separation) and point storage flips to full-card NORMALIZED space:
## `points` below always shows/edits the CURRENT strip's positions (at stack_separation), and the
## conversion pair strip_to_norm/norm_to_strip keeps the stored .tres separation-agnostic —
## placing points at ANY separation level authors the same normalized pattern. Toggling keeps the
## visible positions put (they are re-encoded under the new flag). Saved alongside `mode`.
@export var spread_by_separation : bool = false:
	set(value):
		spread_by_separation = value
		var f := _formation()
		# _syncing: _pull_points assigns this field FROM the formation — pushing then would
		# overwrite the stored points with the previous strip view before they were pulled.
		if f and not _syncing:
			f.spread_by_separation = spread_by_separation
			_push_points()   # re-encode the on-screen points under the new storage rule
		_live_update()
## The current formation's points as SEEN at the current stack_separation — for
## spread_by_separation formations this is the projection of the stored full-card points into the
## visible strip (edits convert back on the way in, so the stored pattern is separation-agnostic);
## otherwise raw unscaled card space. Points outside the valid area draw RED.
@export var points : PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		_push_points()
		queue_redraw()
@export_tool_button("Reload Set From Disk") var _btn_reload : Callable = _load_set
@export_tool_button("Add Formation") var _btn_add : Callable = _add_formation
@export_tool_button("Delete This Formation") var _btn_delete : Callable = _delete_formation
@export_tool_button("SAVE Set To .tres") var _btn_save : Callable = _save_set

@export_group("Generator")
@export var gen_pattern : Pattern = Pattern.SCATTER
@export_range(1, 32) var gen_count : int = 6
## Point-to-point spacing (grid/line/ring radius step), unscaled pixels.
@export var gen_spacing : float = 9.0
## Random nudge applied to every generated point (0 = perfectly regular).
@export var gen_jitter : float = 3.0
@export var gen_seed : int = 0
@export_tool_button("Generate Points") var _btn_gen : Callable = _generate

@export_group("Preview (debug only)")
## How many props to spawn over the formation(s); beyond one formation's capacity the rest
## spill into further columns, one seeded formation each — in-game adjacent slots.
@export_range(0, 64) var preview_count : int = 8
## Per-column formation pick/point-subset seed (column i uses preview_seed + i).
@export var preview_seed : int = 0
## Stand-in for the game's card_scale: scales the card footprint, the point offsets, AND the
## prop art relative to PropVisual.AUTHORED_CARD_SCALE — exactly like in game (PropLayer writes
## vis.scale = card_scale / AUTHORED_CARD_SCALE every frame, owner spec 2026-07-15). Default =
## the game's default card_scale for exact parity.
@export var preview_scale : float = 2.5
## Debug stack scenery: cards drawn per column and their vertical separation (unscaled).
@export_range(1, 12) var stack_cards : int = 3
## Card vertical separation stand-in (unscaled). Also the separation FACTOR source for
## spread_by_separation formations: factor = stack_separation / CARD_SEPARATION. Changing it
## re-spreads a live preview in realtime (mirrors the in-game card-separation setting).
@export var stack_separation : float = float(CardVisual.CARD_SEPARATION):
	set(value):
		stack_separation = value
		# Re-project the SAME stored normalized points into the new strip: `points` (the strip-space
		# view) moves, the .tres pattern doesn't — the separation-agnostic invariant, live in-editor.
		# Guarded on _set: during scene load this setter fires before _load_set and must not wipe
		# points saved with the scene.
		if _set: _pull_points()
		_live_update()
## Distance between column anchors (unscaled) — matches the play area's REAL default column
## pitch: card width + PlayArea.separation's unscaled default (4).
@export var column_pitch : float = CardVisual.CARD_SIZE.x + 4.0
@export_tool_button("Spawn Preview Props") var _btn_preview : Callable = _spawn_preview
@export_tool_button("Clear Preview") var _btn_clear : Callable = _clear_preview

var _set : PropFormationSet
var _preview_columns : int = 1   # columns the last preview used (drives the scenery)

func _ready() -> void:
	if Engine.is_editor_hint():
		_load_set()

func _formation() -> PropFormationData:
	if _set == null or _set.formations.is_empty(): return null
	return _set.formations[clampi(formation_index, 0, _set.formations.size() - 1)]

## Load (or start fresh) the selected kind's set and show its first formation.
func _load_set() -> void:
	_set = PropFormationSet.load_for_kind(kind)
	if _set == null:
		_set = PropFormationSet.new()
		print("FormationEditor: no saved set for %s yet (Add Formation + SAVE to create %s)"
				% [PropFormationSet.KIND_NAMES[kind], PropFormationSet.path_for_kind(kind)])
		# KEEP any points already sitting in the inspector (e.g. saved with this scene but
		# never SAVEd to a .tres) — clearing them here would lose unsaved work.
		queue_redraw()
		return
	print("FormationEditor: loaded %s (%d formation(s))"
			% [PropFormationSet.path_for_kind(kind), _set.formations.size()])
	formation_index = 0   # setter pulls points + mode + redraws

## Current separation as the shared normalization factor (mirrors the game's
## card_separation_scale: factor 1 == default separation, CARD.y/CARD_SEPARATION == full card).
func _sep_factor() -> float:
	return stack_separation / float(CardVisual.CARD_SEPARATION)

## Stored (.tres) representation of strip-space edited points: spread formations store full-card
## normalized y (strip_to_norm); non-spread formations store the points as-is.
func _to_stored(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if spread_by_separation:
		for i : int in out.size():
			out[i] = Vector2(out[i].x, PropFormationSet.strip_to_norm(out[i].y, _sep_factor()))
	return out

## Inverse of _to_stored: project stored points into the current strip for editing/preview.
func _to_strip(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if spread_by_separation:
		for i : int in out.size():
			out[i] = Vector2(out[i].x, PropFormationSet.norm_to_strip(out[i].y, _sep_factor()))
	return out

## True while _pull_points syncs inspector fields FROM the formation (setters must not push back).
var _syncing := false

func _pull_points() -> void:
	var f := _formation()
	if f:
		_syncing = true
		mode = f.mode
		spread_by_separation = f.spread_by_separation
		_syncing = false
	points = _to_strip(f.points) if f else PackedVector2Array()   # setter pushes back + redraws

func _push_points() -> void:
	var f := _formation()
	if f: f.points = _to_stored(points)

func _add_formation() -> void:
	if _set == null: _set = PropFormationSet.new()
	var f := PropFormationData.new()
	f.mode = mode
	f.spread_by_separation = spread_by_separation
	f.points = _to_stored(points) if not points.is_empty() else PackedVector2Array([Vector2.ZERO])
	_set.formations.append(f)
	formation_index = _set.formations.size() - 1
	print("FormationEditor: added formation %d (unsaved until SAVE)" % formation_index)

func _delete_formation() -> void:
	var f := _formation()
	if f == null: return
	_set.formations.erase(f)
	formation_index = mini(formation_index, maxi(_set.formations.size() - 1, 0))
	print("FormationEditor: deleted (unsaved until SAVE); %d left" % _set.formations.size())

func _save_set() -> void:
	if _set == null or _set.formations.is_empty():
		push_warning("FormationEditor: nothing to save — add a formation first.")
		return
	DirAccess.make_dir_recursive_absolute(PropFormationSet.DIR)
	var path := PropFormationSet.path_for_kind(kind)
	var err := ResourceSaver.save(_set, path)
	if err == OK: print("FormationEditor: saved %s" % path)
	else: push_error("FormationEditor: save FAILED (%s): %s" % [path, error_string(err)])

## Fill `points` from the chosen pattern; hand-tweak afterwards in the inspector.
func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	var out : PackedVector2Array = PackedVector2Array()
	match gen_pattern:
		Pattern.GRID:
			var cols := ceili(sqrt(float(gen_count)))
			var rows := ceili(float(gen_count) / float(cols))
			var origin := -Vector2(cols - 1, rows - 1) * gen_spacing * 0.5
			for i : int in gen_count:
				out.append(origin + Vector2(float(i % cols), floorf(float(i) / float(cols))) * gen_spacing)
		Pattern.RING:
			for i : int in gen_count:
				var ang := TAU * float(i) / float(gen_count)
				out.append(Vector2.from_angle(ang) * gen_spacing)
		Pattern.SCATTER:
			for i : int in gen_count:
				out.append(Vector2(rng.randf_range(-CARD.x, CARD.x),
						rng.randf_range(-CARD.y, CARD.y)) * 0.4)
		Pattern.LINE:
			var origin := Vector2(-(gen_count - 1) * gen_spacing * 0.5, 0.0)
			for i : int in gen_count:
				out.append(origin + Vector2(i * gen_spacing, 0.0))
	var y_max := _edit_y_max()
	for i : int in out.size():
		if gen_jitter > 0.0:
			out[i] += Vector2(rng.randf_range(-gen_jitter, gen_jitter),
					rng.randf_range(-gen_jitter, gen_jitter))
		# A formation stays inside ONE card; spread formations additionally edit inside the
		# CURRENT strip (storage scales them up to full-card space).
		out[i] = out[i].clamp(-CARD * 0.5, Vector2(CARD.x * 0.5, y_max))
	points = out   # setter pushes into the live formation + redraws

## Bottom of the valid editing area: the visible strip for spread formations (top-anchored,
## stack_separation tall, capped at one card), the full card footprint otherwise.
func _edit_y_max() -> float:
	if spread_by_separation:
		return -CARD.y * 0.5 + minf(stack_separation, CARD.y)
	return CARD.y * 0.5

# --- preview -------------------------------------------------------------------

func _column_origin(col: int) -> Vector2:
	return Vector2(float(col) * column_pitch * preview_scale, 0.0)

## Realtime refresh: if a preview is currently spawned, re-spawn it so tuning knobs
## (spread_by_separation, stack_separation, mode) update the view immediately; else just redraw.
func _live_update() -> void:
	if not Engine.is_editor_hint(): return
	if get_child_count() > 0:
		_spawn_preview()
	else:
		queue_redraw()

func _clear_preview() -> void:
	for child : Node in get_children():
		child.queue_free()
	_preview_columns = 1
	queue_redraw()

## Spawn real PropVisuals over assigned points, chunked into columns EXACTLY like the game
## assigns a batch: column i draws formation + point subset from seed preview_seed + i.
func _spawn_preview() -> void:
	_clear_preview()
	if _set == null or _set.formations.is_empty():
		push_warning("FormationEditor: no formations to preview.")
		return
	var remaining := preview_count
	var col := 0
	while remaining > 0 and col < 32:
		var seed_value := preview_seed + col
		var f := _set.pick_formation(seed_value)
		if f == null or f.points.is_empty(): break
		var n := mini(remaining, f.points.size())
		# Separation factor mirrors the game's card_separation_scale: how much the debug stack's
		# separation exceeds the authored base. Formations flagged spread_by_separation stretch by it.
		var sep_factor := stack_separation / float(CardVisual.CARD_SEPARATION)
		var offsets := _set.offsets_for(n, seed_value, sep_factor)
		for i : int in n:
			# Game parity: positions scale by the card-scale stand-in, and the ART scales
			# relative to its authored card scale exactly like PropLayer does at runtime.
			var vis := _make_prop()
			add_child(vis)
			vis.position = _column_origin(col) + offsets[i] * preview_scale
			vis.scale = Vector2.ONE * (preview_scale / PropVisual.AUTHORED_CARD_SCALE)
		remaining -= n
		col += 1
	_preview_columns = maxi(col, 1)
	queue_redraw()

func _make_prop() -> PropVisual:
	match kind:
		Kind.KNIFE: return KnifeVisual.new()
		Kind.BALL: return BallVisual.new()
		Kind.FIRE: return FireVisual.new()
		Kind.FIREWORK: return FireworkVisual.new()
		_: return HoopVisual.new()

# --- debug scenery -------------------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint(): return
	var half := CARD * 0.5 * preview_scale
	for col : int in _preview_columns:
		var origin := _column_origin(col)
		# Card stack scenery (play-area look-alike: cards fan DOWN by stack_separation,
		# formation sits on the TOP card's anchor). Back cards first so overlap reads right.
		for j : int in range(stack_cards - 1, -1, -1):
			var top_left := origin - half + Vector2(0.0, float(j) * stack_separation * preview_scale)
			var alpha := 0.7 if j == 0 else 0.25
			draw_rect(Rect2(top_left, CARD * preview_scale), Color(0.4, 0.8, 1.0, alpha), false, 1.0)
	# Editable points of the CURRENT formation on column 0 (strip-space view), with indices;
	# outside the valid edit area (the strip for spread formations, the card otherwise) = RED.
	var font := ThemeDB.fallback_font
	var y_max := _edit_y_max()
	for i : int in points.size():
		var inside : bool = absf(points[i].x) <= CARD.x * 0.5 \
				and points[i].y >= -CARD.y * 0.5 and points[i].y <= y_max
		var p := points[i] * preview_scale
		draw_circle(p, 2.0 * preview_scale, Color(1.0, 0.6, 0.2) if inside else Color.RED)
		draw_string(font, p + Vector2(3.0, -3.0) * preview_scale, str(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(8 * preview_scale), Color.WHITE)
