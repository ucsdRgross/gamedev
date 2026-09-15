---
name: verify-visuals-by-eye
description: "Never declare visual/shader work done from tests, coverage, or reasoning — render a snapshot and describe what the image actually shows, or say UNVERIFIED"
metadata:
  node_type: memory
  type: feedback
---

**A visual/shader/prop-art change is not "working", "fixed" or "correct" until a rendered image
has been looked at.** Coverage metrics, green suites, and reasoning about what a shader should
emit are not evidence about pixels. If rendering is impossible right now, say **UNVERIFIED** in
plain text and avoid those three words entirely.

**Why:** this is the owner's most-repeated correction — success was declared off coverage numbers
while they were looking at visibly broken output. The first windowed snapshot harness immediately
exposed defects every metric had agreed were fine: inverted Y, a bad sentinel value, dynamic array
indexing in the shader. Their trust goes to their eyes, and they are right to.

⚠ **A STILL FRAME IS NECESSARY AND NOT SUFFICIENT.** Anything with a DURATION — a pulse, a travel, a
fade, a sequence — is run and reported by what MOVED, because a still of a working loop and of a dead
one are identical. `/fx-verify` carries that rule and the instrument.

⚠ **AN INSTRUMENT CAN GO STALE AND KEEP PRODUCING CONFIDENT PICTURES.** Measured: a by-eye shot
rendered the screen in a fixed window size, then the product's render target was resized around it —
the shot kept working, kept being read, and its framing had quietly stopped describing anything the
player would see. **Before trusting an image, ask what surface it rendered into and whether that is
still the product's.**

**How to apply:** run the `/fx-verify` skill — render WINDOWED, read the PNG, and report the
silhouette/edges/artifacts in words. Quote measured before/after numbers for any perf claim
(`Tests/Visual/fx_cost.tscn`), never an estimate. See [[running-godot-scenes]] for invocation and
[[no-mocks-in-tools]] for why the harness must host the real scene.
