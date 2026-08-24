class_name PlayerProfile
extends Resource
## One save slot's unlocked-picture record, saved to `user://profile.tres` by `ProfileManager`.
## Keyed by slot even though slot 0 is the only slot today, so adding more needs no migration.

## Slot index -> Array[StringName] of unlocked picture ids.
@export var unlocked : Dictionary[int, Array] = {}
