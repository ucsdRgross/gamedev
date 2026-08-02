---
name: no-git-staging
description: "User uses GitHub Desktop; don't run git add/stage commands (deletions via git rm are fine when needed, but plain file deletion works too)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 06399959-4da7-488e-a177-7f72e1a2ef41
---

Don't run `git add` / staging commands in this repo.

**Why:** The user manages the repo with GitHub Desktop, which picks up working-tree changes automatically; agent-side staging is redundant noise and interrupted their flow.

**How to apply:** Just edit/create/delete files in the working tree. Ask before committing (existing rule). Related: [[running-godot-scenes]].
