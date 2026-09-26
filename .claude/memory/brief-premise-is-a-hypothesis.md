---
name: brief-premise-is-a-hypothesis
description: "A brief's named site and cause are a hypothesis: every brief says MEASURE FIRST, and a measurement that contradicts the premise stops the step for an owner question"
metadata:
  type: feedback
---

**A brief's fix site and cause are a hypothesis, not a spec.** Every implementer brief says
MEASURE FIRST in the real running program, and tells the implementer to STOP and report under
OWNER QUESTIONS, with lettered options, when the measurement contradicts the premise. It never
tells them to build the brief's fix regardless.

**Why:** on one fourteen-step stretch of the playtest stream, measurement overturned the brief's
premise seven times, and each forced build would have shipped the wrong fix: an ease started
where it finished 38 frames before anything was drawn; a re-fit "on every slide" that no slide
ever reached; a settings migration for a value no saved file could hold (the engine omits
defaults); a focus leak blamed on opening a viewer that came from a later rest; a key route
"fixed" at a neighbour table the press never reached; a "weaker rim" that was already identical,
its ink the same colour as the paper; a layout write called inert that a 12-column test needed.
Several of those turned into a one-line owner question, and the owner's answer changed the
feature.

**How to apply:**
- The brief names the suspected writer with `file:line` and says "measure first; if the premise is
  wrong, say so and stop".
- The report states each candidate's MEASURED contribution, not just the winner's.
- The overseer looks at the evidence (frames, numbers) itself, then asks the owner the one
  question the measurement raised, with a shot per option when it is a look.
- Keep "the docs say X" apart from "I measured X here" (CLAUDE.md rule 6).
- ⚠ **A read-only recon's claim about RUNTIME behaviour is a reading of code, not a measurement** -
  write it into the brief as "traced, not measured". Measured: a recon said an opaque backdrop "is
  the ONLY thing keeping the map inert"; under it the wheel still zoomed the map and the first
  motion hovered a node. A premise stated as fact steers the implementer toward building on it.

Related: [[read-the-engine-docs]], [[implementer-routing]], [[tests-that-prove-nothing]],
[[verify-visuals-by-eye]].
