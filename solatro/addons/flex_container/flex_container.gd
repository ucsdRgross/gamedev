@tool
@icon("./icon.svg")

## A Container that arranges its children horizontally or vertically 
## and provides various additionnal properties.
##
## These properties include : axis alignement, wrapping, sorting, 
## reverse filling, allowing children to expand, margins, gaps and stylebox.
## Script inheriting from this node should have the [code]@tool[/code] tag.
class_name FlexContainer
extends Container

## More properties may appear in the future.

#region Export Layout

@export_group("Layout")
## If [code]true[/code], arranges its children vertically instead of horizontally.
@export var vertical : bool = false :
	set(value):
		vertical = value
		_update_axis()
		queue_sort() 

## Children alignment on the horizontal axis (must be one of [enum BEGIN], [enum CENTER], or [enum END])
@export var align_horizontal : Align = Align.BEGIN :
	set(value):
		align_horizontal = value
		_update_axis()
		queue_sort() 

## Children alignment on the vertical axis (must be one of [enum BEGIN], [enum CENTER], or [enum END])
@export var align_vertical : Align = Align.BEGIN :
	set(value):
		align_vertical = value
		_update_axis()
		queue_sort() 

## The way children are sorted (must be one of [enum NORMAL], [enum REVERSE], or [enum RANDOM])
@export var sort : Sort = Sort.NORMAL :
	set(value):
		sort = value
		queue_sort() 

#endregion

#region Export Wrapping

@export_group("Wrapping")
## If [code]true[/code], creates new rows or columns to fit children
@export var wrapping : bool = false :
	set(value):
		wrapping = value
		queue_sort() 

## Alignement of the last row or column when [code]wrapping is true[/code], relative to the largest row or column.
@export var align_wrap : Align = Align.BEGIN :
	set(value):
		align_wrap = value
		queue_sort() 

## If [code]wrapping is true[/code], places the rows or columns from last to first
@export var reverse_fill : bool = false :
	set(value):
		reverse_fill = value
		queue_sort()

#endregion

#region Export Items

@export_group("Items")
## If [code]true[/code], children minimum space matche the biggest [member custom_minimum_size] among them
@export var match_largest : bool = false :
	set(value):
		match_largest = value
		queue_sort() 

## The way children are allowed to expand (must be one of [enum NONE], [enum VERTICAL], [enum HORIZONTAL], or [enum BOTH])
@export var allow_expand : Expand = Expand.NONE :
	set(value):
		allow_expand = value
		queue_sort() 

#endregion

#region Export Margin

@export_group("Margin")
## General margin applied to the content, changing this values changes the value of all detailed margins ([member margin_top], [member margin_bottom], [member margin_left], and [member margin_right])
@export var margin : float = 0 :
	set(value):
		margin = value
		margin_top = value
		margin_bottom = value
		margin_left = value
		margin_right = value
		queue_sort() 

@export_subgroup("Detailed margins")
## Margin from the top
@export var margin_top : float = 0 :
	set(value):
		margin_top = value
		queue_sort() 

## Margin from the bottom
@export var margin_bottom : float = 0 :
	set(value):
		margin_bottom = value
		queue_sort() 

## Margin from the left
@export var margin_left : float = 0 :
	set(value):
		margin_left = value
		queue_sort() 

## Margin from the right
@export var margin_right : float = 0 :
	set(value):
		margin_right = value
		queue_sort() 

#endregion

#region Export Gap

@export_group("Gap")
## Vertical gap between children
@export var gap_vertical : float = 0 :
	set(value):
		gap_vertical = value
		_update_axis()
		queue_sort() 

## Horizontal gap between children
@export var gap_horizontal : float = 0 :
	set(value):
		gap_horizontal = value
		_update_axis()
		queue_sort() 

#endregion

#region Export Panel

@export_group("Panel")
## StyleBox applied as a background of the FlexContainer
@export var panel : StyleBox :
	set(value):
		panel = value
		queue_redraw()
		queue_sort()

#endregion

#region Enums

enum Align {
	BEGIN, ## Align children at the beginning of this axis
	CENTER, ## Align children at the center of this axis
	END ## Align children at the end of this axis
}

enum Expand {
	NONE, ## Children keep their minimum size
	VERTICAL, ## Children are allowed to expand vertically
	HORIZONTAL, ## Children are allowed to expand horizontally
	BOTH ## Children are allowed to expand on both axis
}

enum Sort {
	NORMAL, ## Sorts children the way they appear in the tree
	REVERSE, ## Sorts the children in reverse order of their appearance in the tree
	RANDOM ## Sorts children randomly, [color=red]children order will be randomized every time the container calculate their placement ![/color]
}

#endregion

#region Var directions

var main := 0
var cross := 1

var gap_main := 0.0
var gap_cross := 0.0

var align_main := Align.BEGIN
var align_cross := Align.BEGIN

#endregion

#region Var cache

var _cached_wrap_size: float = 0.0

var _cached_largest_children_minimum_size : Vector2 = Vector2(0,0)

#endregion

#region Func Main


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()
	elif what == NOTIFICATION_DRAW:
		_draw_panel()


func _draw_panel() -> void:
	if panel:
		panel.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


func _sort_children() -> void:
	var children := _get_layout_children()
	if children.is_empty():
		_cached_wrap_size = 0.0
		_cached_largest_children_minimum_size = Vector2.ZERO
		return

	var inner := _get_inner_rect()
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		_cached_wrap_size = 0.0
		_cached_largest_children_minimum_size = Vector2.ZERO
		return

	var lines := _build_lines(children, inner.size)
	_place_lines(lines, inner)
	update_minimum_size()


#endregion

#region Func Lines


func _build_lines(children: Array[Control], available_size: Vector2) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var line := _make_line()

	var max_main := available_size[main]

	for child in children:
		var item := _make_item(child)
		
		item["size"][cross] = _cached_largest_children_minimum_size[cross]
		
		if match_largest:
			item["size"][main] = _cached_largest_children_minimum_size[main]
	
		var projected : float = line["size"][main]

		if not line["items"].is_empty():
			projected += gap_main
		projected += item["size"][main]

		var should_wrap : bool = wrapping and not line["items"].is_empty() and projected > max_main

		if should_wrap:
			lines.append(line)
			line = _make_line()

		if not line["items"].is_empty():
			line["size"][main] += gap_main

		line["items"].append(item)
		line["size"][main] += item["size"][main]
		line["size"][cross] = maxf(line["size"][cross], item["size"][cross])

	if not line["items"].is_empty():
		lines.append(line)

	_update_cached_wrap_size(lines)

	_expand_items(lines, available_size)

	return lines


func _place_lines(lines: Array[Dictionary], inner: Rect2) -> void:
	var content_cross := 0.0
	for i in lines.size():
		content_cross += lines[i]["size"][cross]
		if i > 0:
			content_cross += gap_cross

	var cross_start := _aligned_offset(
		inner.size[cross],
		content_cross,
		align_cross
	)

	var cursor_cross := cross_start

	if reverse_fill:
		lines.reverse()

	for index in lines.size():
		var line = lines[index]
		
		var main_space := inner.size[main]
		var main_start := _aligned_offset(main_space, line["size"][main], align_main)

		if wrapping:
			if (reverse_fill and index == 0) or (!reverse_fill and index == (lines.size() - 1)):
				var main_max := _get_largest_line(lines)
				main_start = _aligned_offset(main_space, main_max, align_main) + _aligned_offset(main_max, line["size"][main], align_wrap)

		var cursor_main := main_start

		for item in line["items"]:
			var child: Control = item["child"]
			var child_size: Vector2 = item["size"]

			var rect := Rect2()

			rect.position = inner.position
			rect.position[main] += cursor_main
			rect.position[cross] += cursor_cross
			rect.size[main] = child_size[main]
			rect.size[cross] = child_size[cross]
			cursor_main += item["size"][main] + gap_main

			fit_child_in_rect(child, rect)

		cursor_cross += line["size"][cross] + gap_cross


#endregion

#region Func Expand


func _expand_items(lines : Array[Dictionary], available_size : Vector2) -> void:
	if allow_expand == Expand.NONE:
		return

	if allow_expand == Expand.HORIZONTAL or allow_expand == Expand.BOTH:
		if _direction_matches_main_axis(Expand.HORIZONTAL):
			_expand_on_main_axis(lines, available_size[main], Expand.HORIZONTAL)
		else:
			_expand_on_cross_axis(lines, available_size[cross], Expand.HORIZONTAL)

	if allow_expand == Expand.VERTICAL or allow_expand == Expand.BOTH:
		if _direction_matches_main_axis(Expand.VERTICAL):
			_expand_on_main_axis(lines, available_size[main], Expand.VERTICAL)
		else:
			_expand_on_cross_axis(lines, available_size[cross], Expand.VERTICAL)


func _expand_on_main_axis(lines: Array[Dictionary], available_main: float, expand_direction: Expand) -> void:
	for line in lines:
		var remaining := maxf(0.0, available_main - line["size"][main])
		var stretch_shares := 0.0

		for item in line["items"]:
			if _has_expand_flag(item["child"], expand_direction):
				stretch_shares += item["child"].size_flags_stretch_ratio

		if stretch_shares <= 0.0:
			continue

		for item in line["items"]:
			var child: Control = item["child"]
			if not _has_expand_flag(child, expand_direction):
				continue

			var stretch := child.size_flags_stretch_ratio / stretch_shares * remaining
			item["size"][main] += stretch

		line["size"][main] = available_main


func _expand_on_cross_axis(lines: Array[Dictionary], available_cross: float, expand_direction: Expand) -> void:
	var used := 0.0
	var stretch_shares := 0.0
	var line_ratios: Array[float] = []

	for i in lines.size():
		used += lines[i]["size"][cross]
		if i > 0:
			used += gap_cross

		var ratio := _get_max_ratio(lines[i]["items"], expand_direction)
		line_ratios.append(ratio)
		stretch_shares += ratio

	var remaining := maxf(0.0, available_cross - used)

	if stretch_shares <= 0.0:
		return

	for i in lines.size():
		var line := lines[i]
		var stretch := line_ratios[i] / stretch_shares * remaining
		line["size"][cross] += stretch

		for item in line["items"]:
			item["size"][cross] = line["size"][cross]


#endregion

#region Func Getters


func _get_minimum_size() -> Vector2:
	var children := _get_layout_children()
	if children.is_empty():
		return _get_total_insets()

	var children_sizes: Array[Vector2] = []
	for child in children:
		children_sizes.append(child.get_combined_minimum_size())

	var minimum_size := Vector2.ZERO
	
	_cached_largest_children_minimum_size = _get_largest_children_minimum_size(children_sizes)

	if wrapping:
		minimum_size = _cached_largest_children_minimum_size
		if _cached_wrap_size > 0.0:
			minimum_size[cross] = _cached_wrap_size
	else:
		var max_cross := 0.0
		var total_main := 0.0
		for index in children_sizes.size():
			var child_size := children_sizes[index]
			total_main += _cached_largest_children_minimum_size[main] if match_largest else child_size[main]
			if index > 0:
				total_main += gap_main
			max_cross = maxf(max_cross, child_size[cross])
		minimum_size[main] = total_main
		minimum_size[cross] = max_cross
	
	return minimum_size + _get_total_insets()


func _get_layout_children() -> Array[Control]: 
	var result: Array[Control] = []
	for child in get_children():
		if child is Control:
			if child.visible and not child.top_level:
				result.append(child)
	if sort == Sort.REVERSE:
		result.reverse()
	elif sort == Sort.RANDOM:
		result.shuffle()
	return result


func _get_total_insets() -> Vector2:
	return Vector2(margin_left + margin_right, margin_top + margin_bottom)


func _get_inner_rect() -> Rect2:
	var pos := Vector2(margin_left, margin_top)
	var rect_size := size - _get_total_insets()
	rect_size.x = maxf(0.0, rect_size.x)
	rect_size.y = maxf(0.0, rect_size.y)
	return Rect2(pos, rect_size)


func _get_largest_line(lines: Array[Dictionary]) -> float:
	var largest := 0.0
	for line in lines:
		largest = maxf(largest, line["size"][main])
	return largest


func _get_max_ratio(items: Array, expand_direction: Expand) -> float:
	return items.reduce(func(max_value: float, item: Dictionary) -> float:
		var child: Control = item["child"]
		return max(
			max_value,
			child.size_flags_stretch_ratio if _has_expand_flag(child, expand_direction) else 0.0
		)
	, 0.0)


func _get_largest_children_minimum_size(children_sizes: Array[Vector2]) -> Vector2:
	var max_height := 0.0
	var max_width := 0.0
	for index in children_sizes.size():
		var child_size: Vector2 = children_sizes[index]
		max_height = maxf(max_height, child_size.y)
		max_width = maxf(max_width, child_size.x)
	var minimum_size := Vector2(max_width, max_height)
	return minimum_size


#endregion

#region Func Update


func _update_axis():
	main = int(vertical)
	cross = int(!vertical)
	gap_main = gap_vertical if vertical else gap_horizontal
	gap_cross = gap_horizontal if vertical else gap_vertical
	align_main = align_vertical if vertical else align_horizontal
	align_cross = align_horizontal if vertical else align_vertical


func _update_cached_wrap_size(lines: Array[Dictionary]) -> void:
	var total_cross := 0.0

	for index in lines.size():
		total_cross += lines[index]["size"][cross]
		if index > 0:
			total_cross += gap_cross

	_cached_wrap_size = total_cross


#endregion

#region Func Make


func _make_line() -> Dictionary:
	return {
		"items": [],
		"size": Vector2(0,0)
	}


func _make_item(child: Control) -> Dictionary:
	return {
		"child": child,
		"size": child.get_combined_minimum_size(),
	}


#endregion

#region Func Other helpers


func _aligned_offset(available: float, used: float, align_mode: Align) -> float:
	match align_mode:
		Align.CENTER:
			return (available - used) * 0.5
		Align.END:
			return available - used
		_:
			return 0.0


func _has_expand_flag(control : Control, expand_direction : Expand) -> bool:
	match expand_direction:
		Expand.VERTICAL:
			return (control.size_flags_vertical & Control.SIZE_EXPAND) != 0
		Expand.HORIZONTAL:
			return (control.size_flags_horizontal & Control.SIZE_EXPAND) != 0
		_:
			return false


func _direction_matches_main_axis(expand_direction: Expand) -> bool:
	if vertical:
		return expand_direction == Expand.VERTICAL
	return expand_direction == Expand.HORIZONTAL


#endregion
