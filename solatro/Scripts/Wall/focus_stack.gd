class_name FocusStack
extends RefCounted
## The Back/Forward history for the picture wall — ids only, no geometry, no node references.
## `_back` is the visited history with its LAST element as the current picture; `_forward` holds
## what a `back()` can still return to, cleared on every new `visit()` as a browser clears redo.
##
## Depth is bounded by the number of DISTINCT ids visited, never by a fixed cap: `visit` on an id
## already present moves it to the top rather than appending a second entry.
##
## Wall view is never an entry — there is no method here for it. The caller simply stops calling
## `visit()` while the wall is shown.

var _back : Array[StringName] = []
var _forward : Array[StringName] = []

## Navigate to `id`. If already in the history, MOVES it to the top rather than duplicating it.
## Clears the forward list, as a browser does on any new navigation.
func visit(id: StringName) -> void:
	_forward.clear()
	var existing := _back.find(id)
	if existing != -1:
		_back.remove_at(existing)
	_back.append(id)

## Retraces to the picture visited just before the current one. &"" when there is nothing below
## the current entry, which the caller reads as "go to wall view".
func back() -> StringName:
	if _back.size() < 2:
		return &""
	var left : StringName = _back.pop_back()
	_forward.append(left)
	return _back[-1]

## Redoes the most recent `back()`, returning the picture that was just left. &"" when there is
## nothing to redo.
func forward() -> StringName:
	if _forward.is_empty():
		return &""
	var id : StringName = _forward.pop_back()
	_back.append(id)
	return id

## The picture the history sits on — `_back`'s top — WITHOUT moving the cursor. &"" on an empty
## stack. Wall view is not an entry, so while the wall is shown this is still the picture the
## player left, and stepping "back" from wall view goes HERE; `back()` would skip past it and
## strand it on the forward list.
func current() -> StringName:
	return &"" if _back.is_empty() else _back[-1]

func can_back() -> bool:
	return _back.size() >= 2

func can_forward() -> bool:
	return not _forward.is_empty()
