# PreToolUse guard: block NAME-BASED process kills.
#
# Why: a broad kill filter (taskkill /IM godot*, Get-Process *odot* | Stop-Process) has twice
# closed the owner's open Godot editor with unsaved changes. Killing a specific PID that was
# verified as an orphan (window title "Solatro (DEBUG)", not an editor) is still allowed.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$cmd = ''
if ($payload.tool_input) {
    if ($payload.tool_input.command) { $cmd = [string]$payload.tool_input.command }
}
if (-not $cmd) { exit 0 }

$killVerb = $cmd -match '(?i)\b(taskkill|Stop-Process|pkill|killall)\b'
if (-not $killVerb) { exit 0 }

# An explicit numeric PID is the only sanctioned way to kill anything here.
$explicitPid = $cmd -match '(?i)(/PID\s+\d+|-Id\s+\d+|\$\w*\.Id\b)'
if ($explicitPid) { exit 0 }

[Console]::Error.WriteLine(@"
BLOCKED: name-based process kill.

This machine has an owner-rule against it: a broad filter has killed their open Godot editor
with unsaved changes twice. Never kill by image name, wildcard, or Get-Process pipeline.

Instead:
  1. Get-Process | Where-Object { `$_.ProcessName -like '*odot*' } | Select-Object Id, MainWindowTitle
  2. Read MainWindowTitle. An EDITOR/scene title is the owner's session - STOP and ask them.
     Only a harness orphan (e.g. "Solatro (DEBUG)") is yours to kill.
  3. Kill that one verified PID explicitly: Stop-Process -Id <pid>
"@)
exit 2
