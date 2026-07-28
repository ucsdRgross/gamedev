class_name StatusJuggling
extends CardModifierStatus
## Dropped by Ball props. When its card is scored, banks `stacks` into that card's COLUMN
## gutter (the balls it is juggling pay out). Self-scoped like every status.

## Fire stacks carried by EACH juggled ball, index-aligned with `stacks` and with the rendered
## balls. A ball's flame is its OWN effect at its own level (owner ruling 21) — never read from
## this card's StatusBurning, and a burning card does not light its balls (ruling 3). 0 = not on
## fire. Packed rather than an Array, matching the packed score arrays persistence already uses.
##
## BALL INDEX IS BALL IDENTITY: ball i renders at phase + i/n, so append on add and remove from
## the END. Removing from the middle re-indexes every later ball and makes flames jump between
## balls — the least debuggable way to break "no visual jumps".
##
## The setter emits data_changed itself: only the stacks setter did, so a ball catching fire
## WITHOUT the ball count changing would never refresh the visual — the plume simply would not
## appear until something else touched the card.
@export_storage var ball_fire : PackedInt32Array = PackedInt32Array():
	set(value):
		ball_fire = value
		fit_to_stacks()
		if data: data.data_changed.emit()

## The per-ball levels, guaranteed index-aligned with `stacks`. Fitted on READ as well as on
## write because a save written before ball_fire existed loads with an empty array against a
## non-zero stacks — exactly the drift the invariant guards. No migration file needed.
func fire_levels() -> PackedInt32Array:
	fit_to_stacks()
	return ball_fire

## Keep one fire level per ball. Growing pads with zeros (a new ball is not on fire until
## something says so); shrinking truncates from the END, never the middle.
func fit_to_stacks() -> void:
	var want := maxi(stacks, 0)
	if ball_fire.size() != want: ball_fire.resize(want)

## Merge: the incoming balls JOIN this card's pattern, so their fire levels are concatenated in
## the same operation the stacks add. A merge that only added stacks would silently extinguish
## the incoming balls.
func merge_from(other: CardModifierStatus) -> void:
	var incoming : PackedInt32Array = PackedInt32Array()
	var juggling := other as StatusJuggling
	if juggling: incoming = juggling.fire_levels()
	var joined := fire_levels()
	joined.append_array(incoming)
	stacks += other.stacks              # setter re-fits, so assign the levels after it
	ball_fire = joined

## A ball dropped by a burning prop arrives already alight, at the level the PROP carried. The
## newest ball is the last index — appended, never inserted.
func on_dropped_by(prop: PropData) -> void:
	if not prop or prop.fire_stacks <= 0: return
	var levels := fire_levels()
	if levels.is_empty(): return
	levels[levels.size() - 1] = prop.fire_stacks
	ball_fire = levels

## The balls, and the fire riding them. Two requests from ONE class, which is what keeps the
## knowledge that ball fire depends on ball POSITIONS inside the class that owns both — and lets
## FxJuggle compute the pattern once and hand the same geometry to both quads, so a plume can
## never trail its ball by a frame.
func fx_request() -> Array[FxRequest]:
	return FxJuggle.requests(stacks, fire_levels(), JUGGLE_STYLE, BALL_FIRE_STYLE)

const JUGGLE_STYLE := preload("res://Shaders/Styles/juggle_default.tres")
const BALL_FIRE_STYLE := preload("res://Shaders/Styles/fire_ball.tres")

func get_str() -> String: return TRANSLATION.find('STATUS_JUGGLING')
func get_description() -> String:
	return TRANSLATION.find('STATUS_JUGGLING_DESCRIPTION') % stacks
func get_frame() -> int: return 0

## Placeholder: a small ball (matches BallVisual's fill).
func draw_icon(canvas: CanvasItem, at: Vector2, size: float) -> void:
	canvas.draw_circle(at + Vector2(size, size) * 0.5, size * 0.4, Color(1.0, 0.8, 0.3))

func on_score(target: CardData) -> void:
	if target != data: return
	if not game: return
	var v := game.find_data_vec3(data)
	if v == Vector3i.MIN: return
	# §15a: self-register at the score seam (also reaches the dispatch hook via run_all_mods;
	# register_combo is idempotent, so the double registration is harmless).
	game.register_combo(combo_key())
	game.add_line_score(false, game.state.scores_col, v.y, stacks)
