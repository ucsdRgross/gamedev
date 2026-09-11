# ASSUMPTIONS.md — reversible decisions taken while executing PLAN.md

- `HudContainer`'s children are authored in `hud_container.tscn`, so `HudContainer.new()` yields a
  bare `PanelContainer` with no children. `TestSidebar` instantiates `hud_container.tscn` instead,
  still with no `Main` and no wall in the tree (C1, Q150).
- `GameView` finds the one shared `HudContainer` (§1.9 migration item 2) through a Godot group
  (`HudContainer.GROUP`) rather than a hand-carried reference: `HudContainer.add_to_group()` in its
  own `_ready()`, `GameView.get_tree().get_first_node_in_group()` in its. A standalone fixture with
  no wall in the tree finds none and instantiates a private `HudContainer` as its own child instead
  -- same scene, same accessors, freed with the view like everything else it owns.
- `HudContainer`'s rect in `wall.tscn` is an authored placeholder (`PRESET_LEFT_WIDE`, 320px wide)
  so it is visible and reachable now; S3's §1.1 geometry replaces it with the real computed rect.
