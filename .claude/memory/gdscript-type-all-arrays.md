---
name: gdscript-type-all-arrays
description: Warnings-as-errors — type every Array and every for-iterator variable in this Godot project
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9142ade9-f98d-4441-8895-a93351149aea
---

In the Solatro project, warnings are treated as errors, so **every `Array` carries its element
type** (`Array[PropData]`), **every `Dictionary` carries both key+value types**
(`Dictionary[PropData, PropVisual]`, `Dictionary[CardData, Dictionary]` — nested typed collections
aren't supported, so the inner one stays bare `Dictionary`), and **every `for` iterator variable
is explicitly typed** — `for prop: PropData in live`, `for entry: Array in relocated`,
`for r: PropData.Reaction in prop.reactions_for(card)`, `for card: CardData in dict`. An untyped
`Dictionary` makes `dict[key]` infer `Variant`, so calling any method on the result raises
"method X is not present on the inferred type Variant"; typing the Dictionary's value fixes it.
Iterating an untyped/Variant collection raises "iterator variable has no static type", and passing
a Variant into a typed-subtype parameter raises "supertype Variant was provided". Godot 4.4+
typed-dict methods like `.get()`/`.keys()` still RETURN `Variant` — assign to an explicitly typed
local (`var v : PropVisual = dict.get(k)`).

**Why:** the project compiles with warnings-as-errors; an untyped array or loop var fails the
build outright, not just a lint nag.

**How to apply:** when writing GDScript here, type the array on creation AND type every loop
variable at the `in`. Ranges/ints (`for i in n`) infer fine and don't need it. Class-ref arrays
in a function body must be `var … : Array[GDScript]`, never `const` (see [[code-style-lean-documented]]).
Related: [[architecture-map]].
