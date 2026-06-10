#Requires -Version 5.1
<#
.SYNOPSIS
    Build clean LordZ zip packages for distribution.
.PARAMETER Platform
    Windows, Linux, or Both
#>
param(
    [ValidateSet('Windows', 'Linux', 'Both')]
    [string]$Platform = 'Both',
    [string]$OutputDir = '',
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$installRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $installRoot 'Release'
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-Date -Format 'yyyyMMdd'
}

$discordConfigPath = Join-Path $installRoot 'lordz.discord.json'
$bundleDiscordConfig = Test-Path -LiteralPath $discordConfigPath

function New-LordZReleaseZip {
    param(
        [string]$TargetPlatform,
        [string]$StageName,
        [string]$ZipPath
    )

    $stageRoot = Join-Path $env:TEMP $StageName

    $commonFiles = @(
        'README.txt'
        'LordZ-MirrorEngine.ps1'
        'lordz.settings.example.json'
        'lordz.discord.example.json'
    )

    $commonDirs = @(
        'Assets'
        'Generated'
        'Modules'
    )

    $windowsFiles = @(
        'LordZ - Start Here.bat'
        'Start-LordZ.bat'
        'Start-LordZ-Debug.bat'
        'Create Desktop Shortcut.bat'
        'Tools\New-LordZDesktopShortcut.ps1'
    )

    $linuxFiles = @(
        'lordz.sh'
        'LordZ-MirrorCli.ps1'
        'README-Linux.txt'
    )

    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    $files = $commonFiles
    if ($TargetPlatform -eq 'Windows') { $files += $windowsFiles }
    if ($TargetPlatform -eq 'Linux') { $files += $linuxFiles }

    foreach ($relativePath in $files) {
        $source = Join-Path $installRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing required file for ${TargetPlatform}: $relativePath"
        }

        $target = Join-Path $stageRoot $relativePath
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    foreach ($relativePath in $commonDirs) {
        $source = Join-Path $installRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing required path: $relativePath"
        }

        $target = Join-Path $stageRoot $relativePath
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }

    if ($bundleDiscordConfig) {
        Copy-Item -LiteralPath $discordConfigPath -Destination (Join-Path $stageRoot 'lordz.discord.json') -Force
        Write-Host "[*] $TargetPlatform : bundled lordz.discord.json"
    }
    else {
        Write-Host "[!] $TargetPlatform : lordz.discord.json not found - Discord may be inactive"
    }

    Get-ChildItem -LiteralPath (Join-Path $stageRoot 'Generated') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'README.txt' } |
        Remove-Item -Force

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $ZipPath)
    Remove-Item -LiteralPath $stageRoot -Recurse -Force

    return $ZipPath
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$built = @()
if ($Platform -eq 'Windows' -or $Platform -eq 'Both') {
    $zip = Join-Path $OutputDir "LordZ-windows-$Version.zip"
    [void](New-LordZReleaseZip -TargetPlatform 'Windows' -StageName "LordZ-windows-$Version" -ZipPath $zip)
    $built += $zip
}

if ($Platform -eq 'Linux' -or $Platform -eq 'Both') {
    $zip = Join-Path $OutputDir "LordZ-linux-$Version.zip"
    [void](New-LordZReleaseZip -TargetPlatform 'Linux' -StageName "LordZ-linux-$Version" -ZipPath $zip)
    $built += $zip
}

Write-Host ''
Write-Host '[OK] LordZ release package(s) ready:'
foreach ($path in $built) {
    Write-Host "     $path"
}
Write-Host ''
