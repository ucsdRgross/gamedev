# SubagentStop hook: release the lock one-subagent-at-a-time.ps1 took.
#
# Always exits 0. A failure to release must never block the session — the lock's own staleness
# timeout is the backstop for a release that never ran.

$lock = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\.subagent.lock'
if (Test-Path $lock) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
exit 0
