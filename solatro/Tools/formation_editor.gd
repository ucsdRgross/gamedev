@tool
class_name FormationEditor
extends Node2D
## Authors prop formations from the inspector and previews real props over them; the card drawings are debug scenery, and nothing here ships.

## The unscaled card footprint the formation points live in.
const CARD := CardVisual.CARD_SIZE
## The stand-in card's real outline at rest, centred on the card, in the same space.
static var _outline : PackedVector2Array = CardVisual.star_outline(CARD, 0.0)

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
## How a batch maps onto the points: ORDERED gives prop i point i, RANDOM a seeded shuffle; saved per formation.
@export var mode : PropFormationData.Mode = PropFormationData.Mode.ORDERED:
	set(value):
		mode = value
		var f := _formation()
		if f: f.mode = mode
		_live_update()
# Pushed only when set by hand, re-encoding the on-screen points: while `_pull_points` assigns it
# FROM the formation, a push would overwrite the stored points with the previous strip view.
## Spreads the formation's height with the card separation, its points stored normalised to the full card.
@export var spread_by_separation : bool = false:
	set(value):
		spread_by_separation = value
		var f := _formation()
		if f and not _syncing:
			f.spread_by_separation = spread_by_separation
			_push_points()
		_live_update()
## The current formation's points as seen at the current stack_separation; points outside the valid area draw red.
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
## Props to spawn; beyond one formation's capacity the rest spill into further columns, as adjacent slots do in game.
@export_range(0, 64) var preview_count : int = 8
## Per-column formation pick/point-subset seed (column i uses preview_seed + i).
@export var preview_seed : int = 0
## Stand-in for the game's card_scale: scales the footprint, the offsets and the prop art as PropLayer does.
@export var preview_scale : float = 2.5
## Debug stack scenery: cards drawn per column and their vertical separation (unscaled).
@export_range(1, 12) var stack_cards : int = 3
# Changing it re-projects the SAME stored normalised points into the new strip: `points` moves, the
# .tres pattern does not. Skipped during scene load, when this setter fires before `_load_set`.
## Card separation stand-in (unscaled), and the spread factor's source: stack_separation / CARD_SEPARATION.
@export var stack_separation : float = float(CardVisual.CARD_SEPARATION):
	set(value):
		stack_separation = value
		if _set: _pull_points()
		_live_update()
## Distance between column anchors, unscaled: the board's own card width plus its gap.
@export var column_pitch : float = CardVisual.CARD_SIZE.x + PlayArea.BOARD_SEPARATION
@export_tool_button("Spawn Preview Props") var _btn_preview : Callable = _spawn_preview
@export_tool_button("Clear Preview") var _btn_clear : Callable = _clear_preview

var _set : PropFormationSet
## Columns the last preview used, which the scenery draws.
var _preview_columns : int = 1

func _ready() -> void:
	if Engine.is_editor_hint():
		_load_set()

func _formation() -> PropFormationData:
	if _set == null or _set.formations.is_empty(): return null
	return _set.formations[clampi(formation_index, 0, _set.formations.size() - 1)]

# A kind with no saved set KEEPS the points already in the inspector: they may be saved with this
# scene and never to a .tres, and clearing them would lose that work.
func _load_set() -> void:
	_set = PropFormationSet.load_for_kind(kind)
	if _set == null:
		_set = PropFormationSet.new()
		print("FormationEditor: no saved set for %s yet (Add Formation + SAVE to create %s)"
				% [PropFormationSet.KIND_NAMES[kind], PropFormationSet.path_for_kind(kind)])
		queue_redraw()
		return
	print("FormationEditor: loaded %s (%d formation(s))"
			% [PropFormationSet.path_for_kind(kind), _set.formations.size()])
	formation_index = 0

## The game's card_separation_scale: 1 at the default separation, CARD.y / CARD_SEPARATION at a full card.
func _sep_factor() -> float:
	return stack_separation / float(CardVisual.CARD_SEPARATION)

## What the .tres stores for strip-space points: full-card normalised y for a spread formation, else as-is.
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
	points = _to_strip(f.points) if f else PackedVector2Array()

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

# Fills `points` from the chosen pattern, to hand-tweak afterwards in the inspector. A formation
# stays inside ONE card; a spread one inside the CURRENT strip, which storage scales to the card.
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
		out[i] = _into_outline(out[i])
		out[i].y = minf(out[i].y, y_max)
	points = out

## Bottom of the valid editing area: the top-anchored visible strip for a spread formation, else the card.
func _edit_y_max() -> float:
	if spread_by_separation:
		return -CARD.y * 0.5 + minf(stack_separation, CARD.y)
	return CARD.y * 0.5

func _into_outline(p: Vector2) -> Vector2:
	if Geometry2D.is_point_in_polygon(p, _outline): return p
	var best := _outline[0]
	for i : int in _outline.size():
		var q := Geometry2D.get_closest_point_to_segment(p, _outline[i], _outline[(i + 1) % _outline.size()])
		if q.distance_squared_to(p) < best.distance_squared_to(p): best = q
	return best

func _column_origin(col: int) -> Vector2:
	return Vector2(float(col) * column_pitch * preview_scale, 0.0)

## Realtime refresh: a spawned preview re-spawns so the tuning knobs show at once; otherwise just a redraw.
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

# Real PropVisuals over the assigned points, in columns EXACTLY as the game assigns a batch: column i
# draws a formation and point subset from seed preview_seed + i, spread by the stack's separation
# factor, and positions and art scale by the card-scale stand-in as PropLayer does at runtime.
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
		var sep_factor := stack_separation / float(CardVisual.CARD_SEPARATION)
		var offsets := _set.offsets_for(n, seed_value, sep_factor)
		for i : int in n:
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

# The debug scenery: each column's card stack fanning DOWN by stack_separation, back cards first so
# the overlap reads right, then the current formation's points on column 0 with their indices, red
# outside the valid edit area.
func _draw() -> void:
	if not Engine.is_editor_hint(): return
	var card := Transform2D.IDENTITY.scaled(Vector2.ONE * preview_scale)
	for col : int in _preview_columns:
		var origin := _column_origin(col)
		for j : int in range(stack_cards - 1, -1, -1):
			card.origin = origin + Vector2(0.0, float(j) * stack_separation * preview_scale)
			var alpha := 0.7 if j == 0 else 0.25
			var ring := card * _outline
			ring.append(ring[0])
			draw_polyline(ring, Color(0.4, 0.8, 1.0, alpha), 1.0)
	var font := ThemeDB.fallback_font
	var y_max := _edit_y_max()
	for i : int in points.size():
		var inside : bool = Geometry2D.is_point_in_polygon(points[i], _outline) and points[i].y <= y_max
		var p := points[i] * preview_scale
		draw_circle(p, 2.0 * preview_scale, Color(1.0, 0.6, 0.2) if inside else Color.RED)
		draw_string(font, p + Vector2(3.0, -3.0) * preview_scale, str(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(8 * preview_scale), Color.WHITE)
