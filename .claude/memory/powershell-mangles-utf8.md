---
name: powershell-mangles-utf8
description: Never round-trip source files through PowerShell Get-Content | Set-Content — PS 5.1 reads as ANSI and corrupts every non-ASCII character
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 370cbe17-0a50-49f3-b743-cebab35129ae
  modified: 2026-07-29T10:56:52.357Z
---

**Never edit a source file with `(Get-Content f) -replace ... | Set-Content f` on this box.** Windows
PowerShell 5.1 reads with the system ANSI codepage, so every non-ASCII character comes back mangled
(`⚠` → `âš `, `§` → `Â§`, `—` → `â€"`). Hit 2026-07-29 on `solatro/Tests/Visual/fx_cost.gd`, whose
comments are full of all three; the whole file was corrupted in one command.

**Why:** these projects' files are heavily commented with `⚠`/`§`/em-dashes, and the corruption is
silent — the file still parses and the tests still pass, so nothing catches it but a diff.

**How to apply:** use the Edit/Write tools for file content, always. Reserve PowerShell for running
things. If it has already happened: `git checkout -- <file>` and re-apply the edits with Edit —
do not try to un-mangle in place. See [[running-godot-scenes]].
