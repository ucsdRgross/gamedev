# Stop hook, warn-only: a handoff that declares its rows done needs the plan-auditor's AUDIT.md.
#
# The marker is the handoff's State line opening "**State:** every row is done", or any line
# saying "Pending: the close only". Checks every */HANDOFF_*.md changed on this branch.

$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { exit 0 }
$changed = @(git diff --name-only main...HEAD 2>$null) + @(git diff --name-only HEAD 2>$null)
$handoffs = $changed | Where-Object { $_ -match '(^|/)HANDOFF_[^/]*\.md$' } | Sort-Object -Unique

foreach ($h in $handoffs) {
    $path = Join-Path $root $h
    if (-not (Test-Path $path)) { continue }
    $text = Get-Content -Raw -Encoding UTF8 $path
    if ($text -notmatch '\*\*State:\*\* every row is done|Pending: the close only') { continue }
    if (Test-Path (Join-Path (Split-Path $path) 'AUDIT.md')) { continue }
    Write-Output "[audit-check] $h says only the close is pending and no AUDIT.md sits beside it - the plan-auditor has not written one."
}
exit 0
