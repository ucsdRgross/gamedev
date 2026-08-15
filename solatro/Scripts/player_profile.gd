class_name PlayerProfile
extends Resource
## One save slot's unlocked-picture record. PLAN.md §1.5, Q151=b. Slot 0 is the only slot in v1
## (Q213=a), but the format is keyed by slot from day one so a later multi-slot save needs no
## migration. Saved to user://profile.tres by ProfileManager.

@export var unlocked : Dictionary[int, Array] = {}   ## slot index -> Array[StringName] (Q151=b)
