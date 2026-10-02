# PreToolUse guard: a command that launches Godot must give it a private APPDATA.
#
# Why: user:// resolves through %APPDATA%, so a probe or suite on the shared one writes the player's
# real save and settings and races every other session's godot.log. The owner's editor (-e) passes.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

. "$PSScriptRoot\_hook_input.ps1"
if (-not $cmd) { exit 0 }

$runner = $cmd -match '(?i)\b(py|python3?)\s+[^|;&]*run_tests\.py'
$binary = $cmd -match '(?i)(Godot_v[^\s''"]*|\bgodot(_console)?(\.exe)?|\$\{?(env:)?GODOT_BIN\}?)["'']?\s+[^|;&]*(--path|res://|\.tscn|--script|--headless|-s\s)'
$started = $cmd -match '(?i)Start-Process\s[^|;]*godot'
if (-not ($runner -or $binary -or $started)) { exit 0 }

if ($cmd -match '(?i)(^|\s)(-e|--editor)(\s|$)') { exit 0 }
if ($cmd -match '(?i)(^|[\s;&(])(export\s+)?APPDATA=|\$env:APPDATA\s*=') { exit 0 }

[Console]::Error.WriteLine(@"
BLOCKED: Godot launched on the shared APPDATA.

user:// lives under %APPDATA%: without a private one this run writes the player's real save and
settings and shares godot.log with every other session on the box.

Set it IN THE SAME COMMAND:
  bash:        APPDATA="`$(cygpath -w "`$SCRATCH/appdata")" py solatro/tools/run_tests.py ...
  PowerShell:  `$env:APPDATA = "<scratchpad>\appdata"; & <godot> --path solatro ...
"@)
exit 2
