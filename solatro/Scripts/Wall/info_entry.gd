class_name InfoEntry
extends RefCounted
## What a hoverable thing returns from `get_info()`. Duck-typed via `has_method(&"get_info")` —
## GDScript has no formal interface — and PULLED by the caller on hover, never pushed ahead of
## time.

## Already localised by whatever built this entry; no `TRANSLATION.find()` happens here.
var title : String = ""
var body : String = ""
## Optional visual of the hovered thing, shown beside the description. May be null.
## Ownership: the caller that builds the entry frees this unless `HudContainer.show_description()`
## takes it into the container's own tree — see that method.
var visual : Node = null

# ⚠ THE ENTRY OWNS THE LIVE PREVIEW NODE its publisher built, so a relay owns what it cannot pass
# on: a screen with nothing listening would otherwise orphan one preview per highlight.
func relay_to(out: Signal) -> void:
	if not out.get_connections().is_empty():
		out.emit(self)
		return
	if visual: visual.queue_free()
