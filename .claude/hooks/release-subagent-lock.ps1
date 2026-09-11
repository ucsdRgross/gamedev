# Release the lock one-subagent-at-a-time.ps1 took, on SubagentStop AND on PostToolUse for Agent.
#
# PostToolUse is the release that always fires: a subagent stopped at its maxTurns cap does NOT fire
# SubagentStop (measured twice), and the lock then blocked every dispatch until the stale timeout.
# A BACKGROUND Agent call returns the moment it launches, so on PostToolUse only a call made with
# run_in_background false releases; a background agent is released by its own SubagentStop.
#
# Always exits 0. A failure to release must never block the session — the lock's own staleness
# timeout is the backstop for a release that never ran.

$lock = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\.subagent.lock'
$event = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($event.hook_event_name -eq 'PostToolUse' -and $event.tool_input.run_in_background -ne $false) { exit 0 }
if (Test-Path $lock) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
exit 0
