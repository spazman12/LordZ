#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$installRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $installRoot 'LordZ - Start Here.bat'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LordZ Workshop Mirror.lnk'

if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Launcher not found: $launcherPath"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcherPath
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'LordZ Deadside Workshop Mirror'
$shortcut.Save()

Write-Host "[OK] Desktop shortcut created:"
Write-Host "     $shortcutPath"
