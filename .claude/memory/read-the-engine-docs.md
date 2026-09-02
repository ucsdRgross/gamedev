---
name: read-the-engine-docs
description: "Read the engine's own documentation before designing around a feature, and confirm an API EXISTS before calling it — this repo not using something is not evidence the engine lacks it, and neither is your memory of the API"
metadata:
  node_type: memory
  type: feedback
---

Before designing around any engine, library or platform feature: **fetch the official doc page and
search for the known bug that page does not mention.** Cite the URL beside the fact.

**Why:** grepping this repo tells you what this repo does, not what the engine offers. The
picture-wall design needed to pause one screen while another ran; nothing in the project used
`get_tree().paused`, so the root fork was authored as *"`PROCESS_MODE_DISABLED` on a subtree **or** a
hand-rolled `pause()` contract"*. That dichotomy does not exist —
[Godot's pause tutorial](https://docs.godotengine.org/en/latest/tutorials/scripting/pausing_games.html)
describes a **global** `SceneTree.paused` plus a per-node `process_mode`, and says outright that
pausing "only affects the entire game". The owner answered by pasting the doc URL. Twelve downstream
questions were built on the wrong premise.

**How to apply:** the test is **"could the owner answer this by pasting a doc link?"** If yes, it was
never a design question — a design question asks what the owner WANTS, not what the engine DOES, and
a plausible wrong option set steers the answer rather than surfacing the gap. The facts worth hunting
are the ones the tutorial omits: `SceneTree.create_timer()` defaults `process_always = true` and runs
through a pause; shader `TIME` keeps advancing while paused. Where sources disagree, mark the fact
UNVERIFIED and check it in-project — see [[verify-visuals-by-eye]].

Applies to any design work, but the `/flowchart-design` skill carries the full rule in its §1.
Related: [[seam-checks-not-rereading]], [[general-not-shape-specific]].

## ⚠ AND CONFIRM THE METHOD EXISTS BEFORE YOU CALL IT

Recalling an API from memory is not knowing it is there. Measured: a call to
`Camera2D.get_global_transform_interpolated()` was written from memory into `game_view.gd`; **that
method does not exist in Godot 4.7.2**, confirmed against `ClassDB.class_get_method_list`.

⚠ **A COMPILE ERROR CASCADES INTO EVERY DEPENDENT SCRIPT AND SURFACES AS SYMPTOMS THAT NAME NONE OF
THEM.** That one line took down `card_data.gd`, `pip_suit.gd`, `card_modifier.gd`, `run_manager.gd`
and more, so the owner saw **"the map no longer enters a game"** and **"card packs have no rank or
suit pips"** — two unrelated-looking reports, neither pointing at the file that was broken. The
typed instantiation then failed with *"Trying to assign value of type 'Control' to a variable of
type 'game_view.gd'"*, which is what a failed script compile looks like at the call site.

**How to apply:** check the class reference or `ClassDB.class_get_method_list(<Class>, true)` in the
build you are actually running, before writing the call. Then **launch one scene for two seconds** —
a compile break is instant and free to find, and no test suite is needed to see it. ⚠ Never leave an
unsmoked product-code edit in a worktree someone is playing from.
