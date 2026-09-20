---
name: godot-editor-disk-sync
description: Godot editor open during edits silently rewrites files and runs stale data — re-read before trusting context
metadata:
  node_type: memory
  type: feedback
---

When the owner's Godot editor is open while you edit project files, three things bite:
1. The editor **auto-rewrites inferred `:=` declarations to explicit types** — e.g. a
   `var len_esc := 1.0 + ...` came back as `var len_esc : int = ...`, truncating the
   float and silently breaking scoring. Loop vars get auto-typed too (`for sz : int in`).
2. Earlier file-read context can be **stale vs disk** (localization.csv showed
   `Flush (%s)` in old context but disk had `Flush %s`), and the running game can use
   **stale imported resources** (`.translation` from `TranslationServer`, not the CSV).
3. **A `--import` run is itself a writer** — solatro's list of the tracked files it rewrites:
   `solatro/HEADLESS_TESTING.md` §2.

**Why:** the live editor is a second writer/runtime you don't control.

**How to apply:** before diagnosing a "wrong output," re-Read the actual on-disk file
(don't trust prior context), and prefer explicit type annotations over `:=` in
hot numeric code. Localization names come from imported `.translation`, not CSV text —
a CSV edit needs reimport to affect runtime. Check for editor processes before any run and never
kill one — [[running-godot-scenes]] has the procedure. See [[architecture-map]], [[no-mocks-in-tools]].
