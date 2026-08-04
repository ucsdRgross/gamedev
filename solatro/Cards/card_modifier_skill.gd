@tool
@abstract class_name CardModifierSkill
extends CardModifier
## `@tool` for the same reason as its siblings — a placeholder base strips every member of every
## concrete stamp/skill in the editor, where the FX editor and CardVisual's own preview button both
## stand up real cards. See `CardData`.

const SKILL_TEXTURE : Texture2D = preload("res://Assets/skill_art.png")
const H_FRAMES: int = 16
const V_FRAMES: int = 16
## The CACHED spotlight flag — `@export_storage`, so it is saved and rewound with the board.
## Renamed from `active` 2026-08-04 (spotlight Q2=b). ⚠ THE RENAME IS A SAVE MIGRATION: a
## `run.tres` written before it loads with `spotlit` absent, which defaults false, and
## `Game._resume_show()` re-derives it straight from `is_spotlit()` — the resync that
## deliberately fires NO hooks. So an old save comes up with exactly the set a fresh check
## derives and zero `on_spotlight` calls, with no upgrade code (asserted, gate G1.3).
@export_storage var spotlit := false

func set_texture(polygon2d: Polygon2D) -> void:
	update_polygon_uv_frame(polygon2d, SKILL_TEXTURE, H_FRAMES, V_FRAMES, get_frame())
