#Requires -Version 5.1
<#
.SYNOPSIS
    Build a clean LordZ zip for distribution.
#>
param(
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

$stageName = "LordZ-$Version"
$stageRoot = Join-Path $env:TEMP $stageName
$zipPath = Join-Path $OutputDir "$stageName.zip"

$includeFiles = @(
    'LordZ - Start Here.bat'
    'Start-LordZ.bat'
    'Start-LordZ-Debug.bat'
    'Create Desktop Shortcut.bat'
    'README.txt'
    'LordZ-MirrorEngine.ps1'
    'lordz.settings.example.json'
    'lordz.discord.example.json'
)

$includeDirs = @(
    'Assets'
    'Generated'
    'Modules'
    'Tools\New-LordZDesktopShortcut.ps1'
)

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

foreach ($relativePath in $includeFiles) {
    $source = Join-Path $installRoot $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing required file: $relativePath"
    }

    $target = Join-Path $stageRoot $relativePath
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $source -Destination $target -Force
}

foreach ($relativePath in $includeDirs) {
    $source = Join-Path $installRoot $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing required path: $relativePath"
    }

    $target = Join-Path $stageRoot $relativePath
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
        continue
    }

    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

# Strip dev-only generated scripts from the distributable copy.
Get-ChildItem -LiteralPath (Join-Path $stageRoot 'Generated') -File |
    Where-Object { $_.Name -ne 'README.txt' } |
    Remove-Item -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $zipPath)

Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Host ''
Write-Host '[OK] LordZ release package ready:'
Write-Host "     $zipPath"
Write-Host ''
Write-Host 'Give users these instructions:'
Write-Host '  1. Unzip anywhere (e.g. Desktop\LordZ)'
Write-Host '  2. Double-click "LordZ - Start Here.bat"'
Write-Host '  3. Follow the Quick Start popup'
Write-Host ''
