# PreToolUse guard: only ONE subagent may run at a time.
#
# Why: subagents here run the Godot suite, and the suite is a one-process rule — two of them race
# for the same user:// settings file, the same godot.log and the same window. A parallel fan-out
# also makes a failure unattributable, which is the same reason fixes land one at a time.
#
# Paired with release-subagent-lock.ps1 on SubagentStop. A stale lock older than the timeout below
# is ignored, so a killed session cannot wedge the repo shut.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

$lock = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\.subagent.lock'
$staleMinutes = 90

if (Test-Path $lock) {
    $age = (Get-Date) - (Get-Item $lock).LastWriteTime
    if ($age.TotalMinutes -lt $staleMinutes) {
        $holder = (Get-Content $lock -Raw -ErrorAction SilentlyContinue)
        [Console]::Error.WriteLine(@"
BLOCKED: a subagent is already running.

Held since: $holder ($([int]$age.TotalMinutes) min ago)

One subagent at a time. They run the Godot suite, which is a one-process rule: two at once race for
the same settings file and log, and a failure stops being attributable to any one of them.

Wait for the running agent to report, then dispatch the next. If you are certain nothing is running,
delete .claude/.subagent.lock and retry.
"@)
        exit 2
    }
}

Set-Content -Path $lock -Value (Get-Date -Format 's') -Encoding utf8
exit 0
