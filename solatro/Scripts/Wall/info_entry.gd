class_name InfoEntry
extends RefCounted
## What `get_info()` returns (PLAN.md §1.11; NAMES.md). Q133=b: the hovered thing implements
## `func get_info() -> InfoEntry` (duck-typed via `has_method(&"get_info")`, GDScript has no
## formal interface) rather than emitting a signal or pushing to an autoload -- the caller pulls
## on hover, never pushed to ahead of time.

## Already localised by the caller (PLAN.md §1.11) -- this class does no TRANSLATION.find() of
## its own; whatever builds an InfoEntry has already resolved the string.
var title : String = ""
var body : String = ""
## Optional copy of the hovered thing (Q130 note: "shows a copy of the hovered item as a visual
## beside the description") -- may be null. Ownership: the CALLER that builds the InfoEntry also
## owns freeing this node if `InfoCard` does not take it into its own tree (see `InfoCard.
## show_entry()`'s own doc comment for which one actually happens).
var visual : Node = null
