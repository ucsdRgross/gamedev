# PreToolUse guard: at most TWO subagents may run at a time (owner ruling), and the overseer keeps
# the Godot suite to ONE of them.
#
# Why: subagents here run the Godot suite, and the suite is a one-process rule — two of them race
# for the same user:// settings file, the same godot.log and the same window. The second slot is
# for an agent that runs no Godot (a reviewer, an auditor, docs work).
#
# Paired with release-subagent-lock.ps1 on SubagentStop and on PostToolUse for Agent: the lock file
# holds one line per running agent. A stale lock older than the timeout below is ignored.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

$lock = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\.subagent.lock'
$staleMinutes = 90

$maxAgents = 2
$holders = @()
if (Test-Path $lock) {
    $age = (Get-Date) - (Get-Item $lock).LastWriteTime
    if ($age.TotalMinutes -lt $staleMinutes) {
        $holders = @(Get-Content $lock -ErrorAction SilentlyContinue | Where-Object { $_ -ne '' })
    }
}
if ($holders.Count -ge $maxAgents) {
    [Console]::Error.WriteLine(@"
BLOCKED: $($holders.Count) subagents are already running (limit $maxAgents).

Held since: $($holders -join ', ')

Two subagents at most, and only ONE of them may run the Godot suite: it is a one-process rule (shared
settings file, log and window), and a failure under two runs is attributable to neither.

Wait for a running agent to report, then dispatch the next. If you are certain nothing is running,
delete .claude/.subagent.lock and retry.
"@)
    exit 2
}

$holders += (Get-Date -Format 's')
Set-Content -Path $lock -Value ($holders -join "`n") -Encoding utf8
exit 0
