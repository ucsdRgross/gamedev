---
name: verify-visuals-by-eye
description: "Never declare visual/shader work done from tests, coverage, or reasoning — render a snapshot and describe what the image actually shows, or say UNVERIFIED"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75157de2-6326-43ea-b7df-1a25b81a7de6
  modified: 2026-07-30T22:11:22.688Z
---

**A visual/shader/prop-art change is not "working", "fixed" or "correct" until a rendered image
has been looked at.** Coverage metrics, green suites, and reasoning about what a shader should
emit are not evidence about pixels. If rendering is impossible right now, say **UNVERIFIED** in
plain text and avoid those three words entirely.

**Why:** this is the owner's most-repeated correction across the FX sessions — success was
declared off coverage numbers while they were looking at visibly broken output (clipping, wrong
silhouette, bad hoop fire). When a windowed snapshot harness was finally built, it immediately
exposed real defects that every metric had agreed were fine: inverted Y, a bad sentinel value,
dynamic array indexing in the shader. Their trust goes to their eyes, and they are right to.

**How to apply:** run the `/fx-verify` skill (`.claude/skills/fx-verify/`) — render
`Tests/Visual/fx_snapshot.tscn` or `prop_art_snapshot.tscn` WINDOWED, read the PNG, and report
the silhouette/edges/artifacts in words. Quote measured before/after numbers for any perf claim
(`Tests/Visual/fx_cost.tscn`), never an estimate. Never `--headless` for pixels — a dummy
renderer cannot compile a shader. See [[running-godot-scenes]] for invocation details and
[[no-mocks-in-tools]] for why the harness must host the real scene.
