class_name InfoEntry
extends RefCounted
## What a hoverable thing returns from `get_info()`. Duck-typed via `has_method(&"get_info")` —
## GDScript has no formal interface — and PULLED by the caller on hover, never pushed ahead of
## time.

## Already localised by whatever built this entry; no `TRANSLATION.find()` happens here.
var title : String = ""
var body : String = ""
## Optional visual of the hovered thing, shown beside the description. May be null.
## Ownership: the caller that builds the entry frees this unless `InfoCard.show_entry()` takes it
## into its own tree — see that method.
var visual : Node = null
