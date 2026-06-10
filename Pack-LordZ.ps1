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

function Repair-LordZUnixLineEndings {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $text = [System.IO.File]::ReadAllText($Path)
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
}

function Write-LordZUnixFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
}

function Get-LordZLinuxLauncherScript {
    return @'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/Modules/LordZ.Core.psm1" ]]; then
  echo "[!] Incomplete LordZ folder."
  echo "    Extract the full LordZ-linux zip into one folder, cd there, then run:"
  echo "    bash start-lordz.sh"
  echo "    Missing: $ROOT/Modules/LordZ.Core.psm1"
  exit 1
fi

if [[ -d /etc/ssl/certs ]]; then
  export SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/ssl/certs}"
fi
if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
  export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
fi

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$ROOT/LordZ-MirrorCli.ps1" "$@"
fi

if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -File "$ROOT/LordZ-MirrorCli.ps1" "$@"
fi

echo "[!] PowerShell is required."
echo "    Install: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
echo "    Ubuntu/Debian: sudo apt-get install -y powershell"
exit 1
'@
}
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
        if ($TargetPlatform -eq 'Linux' -and $relativePath -match '\.(sh|ps1|psm1|txt|json)$') {
            Repair-LordZUnixLineEndings -Path $target
        }
    }

    if ($TargetPlatform -eq 'Linux') {
        $launcher = Get-LordZLinuxLauncherScript
        Write-LordZUnixFile -Path (Join-Path $stageRoot 'lordz.sh') -Content $launcher
        Write-LordZUnixFile -Path (Join-Path $stageRoot 'start-lordz.sh') -Content $launcher
        Write-LordZUnixFile -Path (Join-Path $stageRoot 'START-LORDZ-LINUX.txt') -Content @'
LINUX QUICK START
-----------------
1. unzip LordZ-linux-*.zip -d LordZ
2. cd LordZ
3. bash start-lordz.sh

If you see: env: bash\r: No such file or directory
Run this inside the LordZ folder first:
  sed -i 's/\r$//' *.sh
  bash start-lordz.sh
'@
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

    if ($TargetPlatform -eq 'Linux') {
        Get-ChildItem -LiteralPath $stageRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.sh', '.ps1', '.psm1', '.txt', '.json' } |
            ForEach-Object { Repair-LordZUnixLineEndings -Path $_.FullName }
    }

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
