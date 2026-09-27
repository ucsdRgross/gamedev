---
name: no-git-staging
description: "Never commit to main — the owner drives it through GitHub Desktop; on ANY OTHER BRANCH committing is fine and needs no permission"
metadata:
  node_type: memory
  type: feedback
---

**Never commit to `main`.** The owner drives it through GitHub Desktop, which picks up working-tree
changes by itself, so agent staging there is noise that interrupts their flow.

**On any other branch committing is fine and needs no permission.** Owner, verbatim: *"you are
allowed to commit when its not in main branch."* Commit after a verification you ran yourself, one
logical step per commit, the evidence in the message — a long agent run needs those rollback points,
and `/plan-run` depends on them. CLAUDE.md hard rule 1 is the enforced form.
