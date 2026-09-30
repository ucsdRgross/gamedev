class_name PartIcon
extends VBoxContainer

## The one part a partial card carries -- a type, stamp, skill, suit or rank -- drawn as a small labelled icon instead of a card.

## The partial card this icon stands for; the list sticks and describes it like any listed card.
var data : CardData
## The part's own art, framed by the part itself exactly as a card frames it.
var _art := Polygon2D.new()
## The box the art is centred in: the cell every icon of one list shares.
var _art_box := Control.new()
## The part's name, in the UI font, shrunk with the rest of its list's to fit the card cell's width.
var _label := AutosizeLabel.new()
## The part's framed window in art units, its outline rim included.
var _window : Vector2

## Lists one icon for `part_data` under `parent`.
static func add_child_part_icon(parent: Node, part_data: CardData) -> PartIcon:
	var icon := PartIcon.new()
	icon.data = part_data
	parent.add_child(icon)
	return icon

## The one part `card` carries, in the order a pack lists them.
static func part_of(card: CardData) -> Resource:
	var carried : Array[Resource] = []
	for part : Resource in [card.type, card.stamp, card.skill, card.suit, card.rank]:
		if part: carried.append(part)
	assert(carried.size() == 1, "a listed part is a card carrying exactly one part")
	return carried[0]

# A focus stop and a pointer target like a listed card, so the list's hover, click and key rules
# reach it unchanged; the art and the label stay out of the pointer's way.
func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var part := part_of(data)
	_label.text = part.call(&"get_str")
	_art.polygon = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	part.call(&"set_texture", _art)
	CardOutline.fill_texture(_art)
	CardOutline.set_rim(_art, CardOutline.STYLE, CardVisual.CARD_SIZE)
# THE PART'S OWN FRAMING SAYS HOW BIG IT IS: every sheet frames through CardOutline.frame_polygon,
# whose UVs span the frame plus its rim in source texels, which are art units.
	var framed := Rect2(_art.uv[0], Vector2.ZERO)
	for point : Vector2 in _art.uv:
		framed = framed.expand(point)
	_window = framed.size
	_art.polygon = PackedVector2Array([Vector2.ZERO, Vector2(_window.x, 0.0), _window,
			Vector2(0.0, _window.y)])
	_art_box.add_child(_art)
	add_child(_art_box)
	add_child(_label)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

## Whether the pointer is on this icon, which wears the hover mark while it is.
var _hovered := false

func _set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()

# ONE COLUMN WIDTH FOR EVERY VIEWER (owner): a list of parts is as wide as a list of cards of the same
# column count, so the cell is the card's width and the labels share the one font the longest fits.
## The cell every icon of one list shares: a card's width, as tall as the largest non-type part at the viewer's card scale.
static func cell_of(icons: Array[PartIcon]) -> Vector2:
	var cell := Vector2(CardVisual.preview_window_px().x, 0.0)
	var font := icons[0]._label.font_size_max
	for icon : PartIcon in icons:
		if icon.data.type == null:
			cell.y = maxf(cell.y, icon._window.y * CardVisual.DECK_VIEWER_SCALE)
		var label := icon._label
		label.custom_minimum_size = Vector2(cell.x,
				label.get_theme_font(&"font").get_height(label.font_size_max))
		font = mini(font, label.best_font_size())
	for icon : PartIcon in icons:
		icon._label.force_font_size(font)
	return cell

# ONE ART UNIT AT THE CARD SCALE, AS ON A CARD, except a type: its face is a whole card, so it is
# the one part shrunk to the cell (owner: the type drawn scaled down to the same small cell).
func fit(cell: Vector2) -> void:
	_art_box.custom_minimum_size = cell
	var fits := cell / _window
	_art.scale = Vector2.ONE * minf(CardVisual.DECK_VIEWER_SCALE, minf(fits.x, fits.y))
	_art.position = ((cell - _window * _art.scale) / 2.0).floor()

## The part described in the sidebar: its own name and description, previewed in its place on a blank card.
static func part_info(part_data: CardData) -> InfoEntry:
	var previewed := part_data
# A COPY, so the listed card keeps its own part: TypePaper's face is CardVisual.BLANK_CARD_FRAME,
# the body a card with no printed type shows.
	if not part_data.type:
		previewed = part_data.duplicate_deep()
		GameData.relink_card_backrefs(previewed)
		previewed.with_type(TypePaper.new())
	var entry := PlayArea.highlight_info(previewed, CardVisual.preview_window_px())
	var part := part_of(part_data)
	entry.title = part.call(&"get_str")
	entry.body = part.call(&"get_description")
	return entry

# The theme's own Button marks, so an icon reads as hovered or focused the way every control does.
func _draw() -> void:
	if _hovered:
		draw_style_box(get_theme_stylebox(&"hover", &"Button"), Rect2(Vector2.ZERO, size))
	if has_focus():
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))
