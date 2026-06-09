$InstallRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $InstallRoot 'Modules\LordZ.Core.psm1') -Force

$s = Start-LordZSteamCmdConsoleSession -SteamCmdPath 'D:\steam cmd\steamcmd.exe'
Start-Sleep -Seconds 1
while ($s.Process.StandardOutput.Peek() -ge 0) { Write-Host $s.Process.StandardOutput.ReadLine() }
[void](Send-LordZSteamCmdConsoleLine -Session $s -Line 'login spazman122 Savanh9922')
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline -and -not $s.Process.HasExited) {
    while ($s.Process.StandardOutput.Peek() -ge 0) { Write-Host ('> ' + $s.Process.StandardOutput.ReadLine()) }
    while ($s.Process.StandardError.Peek() -ge 0) { Write-Host ('! ' + $s.Process.StandardError.ReadLine()) }
    Start-Sleep -Milliseconds 100
}
[void](Send-LordZSteamCmdConsoleLine -Session $s -Line 'quit')
