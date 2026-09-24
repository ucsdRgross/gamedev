# PostToolUse, warn-only: parse-check an edited .gd file in its Godot project (~3 s on Box A).
#
# Never blocks: the edit has already landed; errors go back to the model as additionalContext.
# Its own private APPDATA keeps user:// untouched; a hang is killed by -Id after 20 s.

. "$PSScriptRoot\_hook_input.ps1"
if ($file -notmatch '\.gd$') { exit 0 }

$root = Split-Path $file
while ($root -and -not (Test-Path (Join-Path $root 'project.godot'))) { $root = Split-Path $root }
if (-not $root) { exit 0 }

function Tell([string]$text) {
    @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $text } } |
        ConvertTo-Json -Compress
    exit 0
}

. "$PSScriptRoot\_godot_console.ps1"
if (Get-GodotConsole) { Tell '[gd-parse-check] another Godot is running - parse check skipped.' }
if (-not $env:GODOT_BIN) { Tell '[gd-parse-check] GODOT_BIN is unset - parse check skipped.' }

$work = Join-Path $env:TEMP 'claude-gd-parse-check'
New-Item -ItemType Directory -Force (Join-Path $work 'appdata') | Out-Null
$out = Join-Path $work 'out.txt'
$res = 'res://' + $file.Substring($root.Length + 1).Replace('\', '/')

$env:APPDATA = Join-Path $work 'appdata'
$p = Start-Process -FilePath $env:GODOT_BIN -PassThru -NoNewWindow `
    -ArgumentList @('--headless', '--path', "`"$root`"", '-s', "`"$PSScriptRoot\gd_parse_check.gd`"", '--', $res) `
    -RedirectStandardOutput $out -RedirectStandardError (Join-Path $work 'err.txt')
# PowerShell 5.1 reports a null ExitCode unless the handle was taken while the process ran.
$null = $p.Handle
if (-not $p.WaitForExit(20000)) {
    Stop-Process -Id $p.Id -Force
    Tell "[gd-parse-check] $res : no result in 20 s, killed Id=$($p.Id)."
}
if ($p.ExitCode -eq 0) { exit 0 }

$errors = Get-Content $out, (Join-Path $work 'err.txt') | Where-Object { $_ -match 'ERROR|^\s+at: ' }
Tell ("[gd-parse-check] $res does not compile:`n" + ($errors -join "`n"))
