---
name: powershell-mangles-utf8
description: Never round-trip source files through PowerShell Get-Content | Set-Content — PS 5.1 reads as ANSI and corrupts every non-ASCII character
metadata:
  node_type: memory
  type: feedback
---

**Never edit a source file with `(Get-Content f) -replace ... | Set-Content f` on this box.** Windows
PowerShell 5.1 reads with the system ANSI codepage, so every non-ASCII character comes back mangled
(`⚠` → `âš `, `§` → `Â§`, `—` → `â€"`), and silently — the file still parses and the tests still
pass, so nothing catches it but a diff.

**How to apply:** use the Edit/Write tools for file content, or a python heredoc that writes
`encoding='utf-8'`. Reserve PowerShell for running things. If it has already happened:
`git checkout -- <file>` and re-apply the edits with Edit — do not try to un-mangle in place.

⚠ **A hook enforces this** (`.claude/hooks/block-source-rewrite.ps1`): `Set-Content`, `Out-File` or
`Add-Content` aimed at a source extension is refused. **`Copy-Item` and `Move-Item` pass, and are the
sanctioned way** to park and restore a file around a red-then-green run — they are byte copies.
Scratchpad paths pass too.
