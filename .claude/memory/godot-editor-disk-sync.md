---
name: godot-editor-disk-sync
description: Godot editor open during edits silently rewrites files and runs stale data — re-read before trusting context
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ab0799cc-b99d-40c0-ba1c-7f602b92a482
  modified: 2026-07-30T22:01:06.130Z
---

When the user's Godot editor is open while I edit project files, two things bite:
1. The editor **auto-rewrites inferred `:=` declarations to explicit types** — e.g. a
   `var len_esc := 1.0 + ...` came back as `var len_esc : int = ...`, truncating the
   float and silently breaking scoring. Loop vars get auto-typed too (`for sz : int in`).
2. My earlier file-read context can be **stale vs disk** (localization.csv showed
   `Flush (%s)` in old context but disk had `Flush %s`), and the running game can use
   **stale imported resources** (`.translation` from `TranslationServer`, not the CSV).

3. **A `--import` run is itself a writer.** It rewrites tracked files —
   `Locale/localization.en.translation` and two `~`-prefixed GDExtension DLLs. Check
   `git status` afterwards and revert them, or they land in the owner's next commit.

**Why:** the live editor is a second writer/runtime I don't control.

**How to apply:** before diagnosing a "wrong output," re-Read the actual on-disk file
(don't trust prior context), and prefer explicit type annotations over `:=` in
hot numeric code. Localization names come from imported `.translation`, not CSV text —
a CSV edit needs reimport to affect runtime. A headless run alongside their OPEN editor hangs,
so check for editor processes first and never kill one — [[running-godot-scenes]] has the full
procedure. See [[architecture-map]], [[no-mocks-in-tools]].
