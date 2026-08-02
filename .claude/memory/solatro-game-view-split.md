---
name: solatro-game-view-split
description: Game is headless logic + GameView is the UI layer; the view==null seam is how tests/Plan 1 hook in
metadata: 
  node_type: memory
  type: project
  originSessionId: 5ffb7c7f-0fc8-4d9d-bd2b-4ae680c7d484
  modified: 2026-07-30T21:58:50.603Z
---

`Levels/game.gd` (`Game extends CardEnvironment`, a `Node`) is now a **headless data/logic layer** — zero UI, mutates only `state`, runs a full show with `view == null`. `Levels/game_view.gd` (`GameView extends Control`, scene `game_view.tscn`) owns ALL UI/input/HUD and holds a `Game` child it creates via `Game.new()` and injects with `game.view = self`.

**Contract (the seam Plan 1 / [[graph-spec-step-a]]-style suit work builds on):**
- Game→view reactive signals: `state_bound` (state reassigned → view rebinds via `_bind_state`, N9), `processing_changed`, `submit_label_changed`, `show_resolved`; plus `GameData.state_changed`/`board_changed`.
- Game→view paced (all `if view: await view.<m>()`, no-op headless): `rebuild`, `sync_scores`, `load_board_visuals`, `animate_meld`, `show_meld_score`, `reset_meld`, `update_line_score`.
- View→Game commands (Game owns the `processing` guard): `submit()`, `next()`, `undo()`, `try_grab(data)`, `try_place(stack,target)`, `exit_show()`.
- `score_row`/`score_col` unified into `score_line(result, is_row, zone, index)`.

`Main.enter_game()` instantiates `game_view.tscn` and binds `view.game_ended`/`run_lost` (forwarded). `card_visual.gd` reaches UI anchors via `_game_view()` (= `get_current_game().view`), not Game. `game.tscn` is now a bare `Game` node. Tests: `Tests/Engine/test_game_data.gd` (pure GameData) + `test_game_headless.gd` (Game with `view==null`, bare `Game.new()` + manual `CardEnvironment.CURRENT`). Both run as part of the full suite, which Claude runs itself — see [[running-godot-scenes]].
