#Requires -Version 5.1
<#
.SYNOPSIS
    Retries Steam login until SteamCMD accepts the session.
.DESCRIPTION
    Uses the local Node backend (steam-session) to obtain a refresh token,
    writes it into SteamCMD cache, then verifies login. Retries on failure.

    Provide credentials via -Username/-Password or env vars LORDZ_STEAM_USERNAME
    and LORDZ_STEAM_PASSWORD. Never commit credentials to disk.
#>
param(
    [string]$Username,
    [string]$Password,
    [string]$SteamCmdPath,
    [string]$BackendUrl = 'http://127.0.0.1:8765',
    [int]$MaxAttempts = 8,
    [int]$RetryDelaySeconds = 20,
    [int]$GuardWaitSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $scriptRoot 'lordz.settings.json'

if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $Username) { $Username = $settings.SteamUsername }
    if (-not $SteamCmdPath) { $SteamCmdPath = $settings.SteamCmdPath }
}

if (-not $Username) { $Username = $env:LORDZ_STEAM_USERNAME }
if (-not $Password) { $Password = $env:LORDZ_STEAM_PASSWORD }
if (-not $SteamCmdPath) { $SteamCmdPath = 'D:\steam cmd\steamcmd.exe' }

if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Read-Host 'Steam username'
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $secure = Read-Host 'Steam password' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw 'Username and password are required.'
}

Import-Module (Join-Path $scriptRoot 'Modules\LordZ.SteamCmd.psm1') -Force
Import-Module (Join-Path $scriptRoot 'Modules\LordZ.Core.psm1') -Force

function Write-Step {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
}

function Test-LordZBackendOnline {
    param([string]$BaseUrl)
    try {
        $health = Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + '/health') -TimeoutSec 3
        return [bool]$health.ok
    }
    catch {
        return $false
    }
}

function Start-LordZCredentialLogin {
    param(
        [string]$BaseUrl,
        [string]$AccountName,
        [string]$AccountPassword,
        [string]$SteamGuardCode
    )

    $body = @{
        accountName = $AccountName
        password    = $AccountPassword
    }
    if ($SteamGuardCode) {
        $body.steamGuardCode = $SteamGuardCode
    }

    return Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + '/api/login/start') -Method Post -Body ($body | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 120
}

function Get-LordZCredentialLoginStatus {
    param(
        [string]$BaseUrl,
        [string]$SessionId
    )

    $encoded = [Uri]::EscapeDataString($SessionId)
    return Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + "/api/login/poll/$encoded") -TimeoutSec 30
}

function Wait-LordZCredentialLogin {
    param(
        [string]$BaseUrl,
        [string]$SessionId,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ''
    $script:GuardPrompted = $false
    $script:GuardCodeSubmitted = $false

    while ((Get-Date) -lt $deadline) {
        $status = Get-LordZCredentialLoginStatus -BaseUrl $BaseUrl -SessionId $SessionId

        if ($status.state -ne $lastState) {
            Write-Step $status.message
            $lastState = $status.state
        }
        elseif ($status.state -eq 'scanned') {
            Write-Step 'Steam Guard prompt opened on your phone. Tap Approve.'
            $lastState = 'scanned_notified'
        }

        if ($status.complete -and $status.refreshToken) {
            return $status
        }

        if ($status.state -eq 'error') {
            throw $status.message
        }

        if ($status.needsConfirmation -and -not $script:GuardPrompted) {
            Write-Step 'Open the Steam app and approve the sign-in request (or enter your 6-digit authenticator code below).'
            $script:GuardPrompted = $true
        }

        if ($status.needsSteamGuardCode -and -not $script:GuardCodeSubmitted) {
            $code = $env:LORDZ_STEAM_GUARD_CODE
            if (-not $code) {
                Write-Step 'Enter the 6-digit Steam Guard code from your phone app (or press Enter to keep waiting for approval).'
                $code = Read-Host 'Steam Guard code'
            }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                Write-Step 'Submitting Steam Guard code...'
                $null = Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + '/api/login/guard') -Method Post -Body (@{
                    sessionId = $SessionId
                    code      = $code.Trim()
                } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 60
                $script:GuardCodeSubmitted = $true
            }
        }

        Start-Sleep -Seconds 2
    }

    throw 'Timed out waiting for Steam Guard approval.'
}

if (-not (Test-LordZBackendOnline -BaseUrl $BackendUrl)) {
    throw "LordZ backend is offline at $BackendUrl. Start Start-LordZ-QrBackend.bat first."
}

$steamCmdDir = Split-Path -Parent $SteamCmdPath
$attempt = 0
$success = $false

while (-not $success -and $attempt -lt $MaxAttempts) {
    $attempt++
    Write-Step "=== Login attempt $attempt of $MaxAttempts ==="

    try {
        Write-Step "Starting Steam credential session for $Username..."
        $start = Start-LordZCredentialLogin -BaseUrl $BackendUrl -AccountName $Username -AccountPassword $Password
        $sessionId = $start.sessionId

        if (-not $sessionId) {
            throw 'Backend did not return a session id.'
        }

        if ($start.complete -and $start.refreshToken) {
            $auth = $start
        }
        else {
            $auth = Wait-LordZCredentialLogin -BaseUrl $BackendUrl -SessionId $sessionId -TimeoutSeconds $GuardWaitSeconds
        }

        Write-Step "Got refresh token for $($auth.accountName). Writing SteamCMD cache..."
        $cache = Set-LordZSteamCmdRefreshToken -SteamCmdDir $steamCmdDir -Username $Username -RefreshToken $auth.refreshToken
        if (-not $cache.Success) {
            throw $cache.Message
        }

        Write-Step 'Testing SteamCMD cached login...'
        $login = Invoke-LordZSteamCmdLogin `
            -SteamCmdPath $SteamCmdPath `
            -Username $Username `
            -Password $auth.refreshToken `
            -UsedQrAuth `
            -OnLogLine { param($Line) Write-Step $Line }

        if ($login.Success) {
            $success = $true
            Write-Step '[OK] SteamCMD login succeeded.'
            break
        }

        Write-Step "[!] SteamCMD login failed: $($login.Message)"
    }
    catch {
        Write-Step "[!] Attempt failed: $($_.Exception.Message)"
    }

    if (-not $success -and $attempt -lt $MaxAttempts) {
        Write-Step "Waiting $RetryDelaySeconds seconds before retry..."
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

if (-not $success) {
    Write-Step '[FAIL] All login attempts exhausted.'
    exit 1
}

Write-Step 'Done. You can open LordZ and mirror now.'
exit 0
