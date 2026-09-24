# Stop hook, warn-only: list the Godot console processes still running at a task boundary.
#
# Why: a run you started and lost track of holds the window and user:// and fabricates failures in
# the next run. Editor processes (-e / --editor) are the owner's and are not listed. Never kills.

. "$PSScriptRoot\_godot_console.ps1"
$procs = Get-GodotConsole
if (-not $procs) { exit 0 }

Write-Output "[godot-check] Godot processes still running - kill only your own, by -Id:"
foreach ($p in $procs) {
    Write-Output ("  {0}  Id={1}  started={2}  {3}" -f $p.Name, $p.ProcessId, $p.CreationDate, $p.CommandLine)
}
exit 0
