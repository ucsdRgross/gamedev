# PreToolUse guard: block PowerShell text round-trips over SOURCE files.
#
# Why: `Get-Content x.gd | Set-Content x.gd` and `... | Out-File x.gd` re-encode the file. On this
# repo that mangles UTF-8 — the comments are full of non-ASCII (⚠, —, é) — and a mangled .gd is a
# parse error that looks like a logic bug. It has happened; see /CLAUDE.md hard rule 3.
#
# ALLOWED, and deliberately not matched:
#   * Copy-Item / Move-Item — byte copies, no re-encoding. The right way to park and restore a file.
#   * Set-Content into a NON-source path (a .txt log, a scratch file).
#   * Anything under a scratchpad/temp directory — not the repo's source.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$cmd = ''
if ($payload.tool_input -and $payload.tool_input.command) {
    $cmd = [string]$payload.tool_input.command
}
if (-not $cmd) { exit 0 }

# Only PowerShell's own writers re-encode. Bash heredocs and `py` scripts are fine.
$writer = $cmd -match '(?i)\b(Set-Content|Out-File|Add-Content)\b'
if (-not $writer) { exit 0 }

# A redirect or write aimed at a file the project actually compiles or loads.
$sourceExt = '\.(gd|gdshader|tscn|tres|godot|py|mjs|js|json|csv|md|ps1)\b'
if ($cmd -notmatch "(?i)$sourceExt") { exit 0 }

# Scratch space is not source. Allow freely there.
if ($cmd -match '(?i)(scratchpad|[\\/]Temp[\\/]|\$env:TEMP|/tmp/)') { exit 0 }

[Console]::Error.WriteLine(@"
BLOCKED: PowerShell Set-Content/Out-File/Add-Content aimed at a source file.

/CLAUDE.md hard rule 3: PowerShell re-encodes on write and MANGLES UTF-8. This repo's sources are
full of non-ASCII (warning glyphs, em dashes), and a mangled .gd is a parse error that reads like a
logic bug. A round-trip (Get-Content x | Set-Content x) is the worst case and silently corrupts.

Use instead:
  * the Edit or Write tool                              - for editing a file
  * a python heredoc: py - <<'EOF' ... io.open(p,'w',encoding='utf-8') ...
  * Copy-Item / Move-Item                               - to park or restore a file (byte copy,
                                                          safe; this is how you revert after a
                                                          deliberate red-then-green run)

If the target really is scratch output, put it under the scratchpad directory and this will pass.
"@)
exit 2
