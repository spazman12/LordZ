$InstallRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $InstallRoot 'Modules\LordZ.SteamCmd.psm1') -Force
Import-Module (Join-Path $InstallRoot 'Modules\LordZ.Core.psm1') -Force

Write-Host '=== Store API ==='
$result = Test-LordZSteamAppIdViaStore -AppId '895400' -OnLogLine { param($l) Write-Host $l }
$result | Format-List *

Write-Host '=== Cached account ==='
Get-LordZSteamCmdCachedAccount -SteamCmdDir 'D:\steam cmd' | Format-List *
