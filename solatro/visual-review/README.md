# Visual review — before/after pairs for the owner

After a pass of visual work, the worker registers the shots that show it; `review.py` renders each
one twice — **AFTER** on the working tree, **BEFORE** on the code the work started from — and the
owner walks the pairs in a slideshow, approving, rejecting or commenting on each. The images are
the worker's PNGs byte for byte, so the owner sees exactly what the worker says it saw.

## The files

| File | Writer | What |
|---|---|---|
| `manifest.json` | worker | one entry per shot (below) |
| `after/<id>.png`, `before/<id>.png` | `review.py` | the pair; gitignored, reshot on every refresh |
| `status.agent.json` | `review.py`, the watch | `ready` after a shoot, `working` once the watch wakes |
| `review.log` | the page, via the server | append-only, one verdict per line |
| `review.json` | the page, via the server | the latest verdict per shot, rebuilt after every log append |
| `status.owner.json` | the page, via the server | `done` when the owner presses Done |

A shot:

```json
{ "id": "grid3_overview", "title": "Three grids, the every-grid overview", "row": "P43",
  "scene": "res://Tests/Visual/grid_zoom_shot.tscn", "env": { "GRID_COUNT": "3" },
  "png": "user://reveal_shots/grid_zoom_3_overview.png",
  "seen": "what the worker saw in after/grid3_overview.png, written after reading it",
  "crops": [{ "label": "what to look at", "x": 437, "y": 294, "w": 68, "h": 84 }] }
```

`crops` is optional: every region the worker zoomed into, as a box in the image's own pixels. The
page shows each under the pair, the same box cut from BEFORE and AFTER side by side, scaled up
with no smoothing; a shot with no BEFORE shows only the AFTER crop.

`scene` must be a shot scene in the repo that writes `png` and quits by itself; `env` is how
the scenes take their knobs. Shots with the same `scene` and `env` share one Godot run.

## The worker

1. **Register** the shots in `manifest.json`, with `seen` left empty.
2. **Refresh** from the repo root, with `GODOT_BIN` set (see `.claude/memory/machine-profiles.md`):
   `py solatro/visual-review/review.py refresh`. It reshoots BEFORE on `git merge-base main HEAD`
   in a temporary `git worktree` (imported headless first, then removed) and AFTER on the working tree.
   `shoot` redoes AFTER only; `shoot --base <ref>` redoes BEFORE only, against `<ref>`.
   ⚠ Once main is merged into the branch, the merge base is main's tip: shoot BEFORE on the
   branch's commit just before the merge, so a pair shows only the reviewed group's change.
   Every run gets a fresh private APPDATA and a hard timeout that kills by PID. A scene that is
   absent or fails on the base leaves no BEFORE, and the page says "no before"; a shot that fails
   on the working tree fails the command.
   ⚠ **A shot shows only a state a player can reach.** Stage it by real input through the
   viewport; where a shot must write state directly, restore it before the next capture and print
   a consistency check at each capture (e.g. the map's current node == the node the token is on).
   Set any focus the shot depends on by input - it otherwise varies run to run. Measured: a stale
   direct write drew a map with no edges and cost the owner a question about a harness bug. A shot
   scene the base commit lacks gives no BEFORE; say so in `seen`, or shoot BEFORE with `--base`.
3. **Read every AFTER PNG yourself and write its `seen`** — what the image shows, not what the
   change was meant to do. Look at every BEFORE too. Every crop you looked at goes in `crops`.
4. **Park:** `npm --prefix designloop run watch -- visual-review/solatro`. It wakes when the owner
   presses Done, prints every verdict with its comment, and marks the worker `working`. Park only
   after a shoot: a Done older than the last shoot does not count, so parking again without one
   waits.
5. Every **reject** and every **comment** becomes the next implementer step, with the owner's
   comment, verbatim, as its brief. Verdicts stay in `review.json` across rounds; the page marks
   one given on an older AFTER and shows its comment beside it, leaving the comment box empty.

## The owner

`npm --prefix designloop start`, then `http://localhost:5273/visual-review/solatro/`.
One pair per screen, BEFORE left and AFTER right, each scaled down to fit with smoothing, since a
nearest-neighbour downscale drops one-pixel outlines (click an image for its native pixels). Keys: `a` approve, `r` reject, `c` type a comment, `Enter` saves
the comment, `Esc` leaves the box, `←` `→` move. A verdict carries whatever is in the comment box.
**Done** hands the review back to the worker.
