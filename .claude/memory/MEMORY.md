<!-- SOURCE OF TRUTH. This directory travels in git; the per-user memory directory is a cache that a
     second computer does not have. Write new and updated memories HERE. See /CLAUDE.md.

     SCOPE RULE: memory holds only what applies ACROSS projects — working agreements, engine
     practice, the machine profiles, and the architecture map. Anything specific to one project
     (its contracts, status, backlog, design decisions) belongs in that project's own docs.
     INDEX RULE: one line per memory, a hook only. No status, dates, counts or gap IDs. -->

**Orientation**
- [Architecture map](architecture-map.md) — what each project is, where they collide, which doc to read
- [Machine profiles](machine-profiles.md) — per-box repo root, Godot binary, GPU, Node; the ONLY home for absolute paths

**Working agreements**
- [No git staging](no-git-staging.md) — never `git add` or commit; the owner uses GitHub Desktop
- [Code style: lean + documented](code-style-lean-documented.md) — delete unused code, `##` purpose comments, kept short
- [Verify visuals by eye](verify-visuals-by-eye.md) — describe the rendered image; a still cannot verify a duration
- [No mocks in tools](no-mocks-in-tools.md) — harnesses host the real scene and real data
- [General, not shape-specific](general-not-shape-specific.md) — no one-silhouette hacks; offer the general form first
- [Seam checks, not re-reading](seam-checks-not-rereading.md) — two representations of one fact need a comparison
- [Read the engine docs](read-the-engine-docs.md) — search before designing around a feature; the repo is not the engine

**Godot practice** (applies to solatro and worldgen alike)
- [Running Godot scenes](running-godot-scenes.md) — run the suite yourself, WINDOWED; a green banner is not proof
- [Godot editor disk sync](godot-editor-disk-sync.md) — an open editor rewrites files and locks dlls; never kill it
- [Key events don't bubble](godot-key-events-no-bubble.md) — area-wide accept/cancel goes in `_unhandled_input`
- [Type all arrays](gdscript-type-all-arrays.md) — warnings-as-errors: type elements and loop variables
- [PowerShell mangles UTF-8](powershell-mangles-utf8.md) — never `Get-Content | Set-Content` a source file

**Running a plan** (everything else lives in the `/plan-run` skill)
- [Tests that prove nothing](tests-that-prove-nothing.md) — ten ways a green test asserts nothing; prove every one red first
- [Built but not wired](built-but-not-wired.md) — a done-when must name the call site, or the component ships with no caller
- [One fix at a time](one-fix-at-a-time.md) — full suite between fixes; a crashing batch cannot be diagnosed

**Design workflow** (everything else lives in the `/flowchart-design` skill)
- [Design answers need a claimant](design-answers-need-a-claimant.md) — check nodes→steps, not just steps→nodes
