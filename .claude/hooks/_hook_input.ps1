# Shared PreToolUse preamble. Dot-source it:  . "$PSScriptRoot\_hook_input.ps1"
#
# Sets $cmd to the command line the tool is about to run, or '' when there is none to judge
# (a non-command tool, an unreadable payload, no stdin). Every caller's next line is
# `if (-not $cmd) { exit 0 }` — a guard with nothing to guard allows.
#
# It lives here because the payload SHAPE is one fact: when Claude Code changes it, one file
# changes, not three that must be found.

$cmd = ''
$raw = [Console]::In.ReadToEnd()
if ($raw) {
    try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null }
    if ($payload -and $payload.tool_input -and $payload.tool_input.command) {
        $cmd = [string]$payload.tool_input.command
    }
}
