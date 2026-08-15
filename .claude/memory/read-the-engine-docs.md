---
name: read-the-engine-docs
description: "Read the engine's own documentation and search for the known bug before designing around an engine feature — this repo not using something is not evidence the engine lacks it"
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
