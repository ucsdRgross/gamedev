---
name: no-git-staging
description: "User uses GitHub Desktop; don't run git add/stage commands (deletions via git rm are fine when needed, but plain file deletion works too)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 06399959-4da7-488e-a177-7f72e1a2ef41
---

Don't run `git add` / staging commands in this repo **by default**.

⚠ **THE EXCEPTION, granted by the owner:** *"you are allowed to commit when its not in main branch."*
So on a feature branch, committing is permitted; on `main` it is not, and staging noise is still
unwelcome anywhere the owner has not asked for commits.

**Why:** The user manages the repo with GitHub Desktop, which picks up working-tree changes
automatically; agent-side staging is redundant noise and interrupted their flow. The branch
exception exists because a long agent-run needs rollback points, and only commits provide them.

**How to apply:** On `main`, just edit files and let GitHub Desktop see them. On a feature branch,
commit after a verification you ran yourself, one logical step per commit, with the evidence in the
message. `/plan-run` depends on this. Related: [[running-godot-scenes]], [[one-fix-at-a-time]].
