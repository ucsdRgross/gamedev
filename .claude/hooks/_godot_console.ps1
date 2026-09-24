# Shared: the Godot console processes running now. Dot-source it:  . "$PSScriptRoot\_godot_console.ps1"
# Editor processes (-e / --editor) are the owner's and never count.

function Get-GodotConsole {
    Get-CimInstance Win32_Process -Filter "Name LIKE '%godot%'" |
        Where-Object { $_.CommandLine -notmatch '(?i)(^|\s)(-e|--editor)(\s|$)' }
}
