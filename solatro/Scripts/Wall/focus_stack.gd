class_name FocusStack
extends RefCounted
## The Back/Forward history for the picture wall -- ids only, no geometry, no node references.
## PLAN.md §1.4. Two arrays: `_back` is the visited history with the LAST element as the current
## picture; `_forward` holds what a `back()` can still `forward()` back to, cleared on every new
## `visit()` exactly as a browser clears redo history on a fresh navigation.
##
## Depth is bounded by the number of DISTINCT ids ever visited, never by a fixed cap (Q64): `visit`
## on an id already in `_back` MOVES it to the top instead of appending a second entry, so `_back`
## can never hold more entries than there are distinct pictures to hold.
##
## Wall view is never an entry (Q66=b) -- there is no method here for it. The caller simply stops
## calling `visit()` while the wall is shown; the stack is unaffected either way.

var _back : Array[StringName] = []
var _forward : Array[StringName] = []

## Navigate to `id`. If it is already in the history, MOVES it to the top rather than duplicating
## it (Q64). Clears the forward list, as a browser does on any new navigation.
func visit(id: StringName) -> void:
	_forward.clear()
	var existing := _back.find(id)
	if existing != -1:
		_back.remove_at(existing)
	_back.append(id)

## Retraces to the picture visited just before the current one. &"" when there is nothing below
## the current entry -- the caller's contract is to go to wall view (Q65=a).
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

## The picture the history currently sits on -- `_back`'s top -- WITHOUT moving the cursor. &"" on
## an empty stack. Needed because wall view is never an entry (Q66=b), so while the wall is shown
## `Main._current_focus` is &"" but this is still the picture the player left: the step "back" from
## wall view is THIS id, and reaching it with `back()` would skip past it and push it onto the
## forward list as something never revisited.
func current() -> StringName:
	return &"" if _back.is_empty() else _back[-1]

func can_back() -> bool:
	return _back.size() >= 2

func can_forward() -> bool:
	return not _forward.is_empty()
