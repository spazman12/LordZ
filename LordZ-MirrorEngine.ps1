#Requires -Version 5.1
<#
.SYNOPSIS
    Lord Zolton Mirror Core Engine - All-In-One GUI
.DESCRIPTION
    Workshop mod mirroring via SteamCMD with single-session auth,
    App ID verification, and the [LORDZ] visual matrix interface.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)

$script:InstallRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:SettingsPath = Join-Path $script:InstallRoot 'lordz.settings.json'
$script:LordZLogBuffer = New-Object System.Collections.Generic.List[string]

[void][System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    try {
        $message = [string]$eventArgs.Exception.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = [string]$eventArgs.Exception.GetType().FullName
        }
        Write-LordZCrashLog ('UI thread: ' + $message)
        if ($script:LogBox -and (Get-Command Write-LordZLogError -ErrorAction SilentlyContinue)) {
            Write-LordZLogError $message
            if ($eventArgs.Exception.StackTrace) {
                Write-LordZLogError $eventArgs.Exception.StackTrace
            }
        }
        elseif ($script:LordZLogBuffer) {
            [void]$script:LordZLogBuffer.Add("[!] $message")
        }
    }
    catch { }
})

function Show-LordZSplash {
    $splash = New-Object System.Windows.Forms.Form
    $splash.Text = '[ LORDZ ]'
    $splash.FormBorderStyle = 'None'
    $splash.StartPosition = 'CenterScreen'
    $splash.ClientSize = New-Object System.Drawing.Size(460, 156)
    $splash.BackColor = [System.Drawing.Color]::FromArgb(10, 4, 2)
    $splash.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 175)
    $splash.ShowInTaskbar = $false
    $splash.TopMost = $true
    $splash.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $frame = New-Object System.Windows.Forms.Panel
    $frame.Dock = 'Fill'
    $frame.Padding = New-Object System.Windows.Forms.Padding(2)
    $frame.BackColor = [System.Drawing.Color]::FromArgb(255, 130, 25)

    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = 'Fill'
    $inner.Padding = New-Object System.Windows.Forms.Padding(18, 16, 18, 14)
    $inner.BackColor = [System.Drawing.Color]::FromArgb(26, 12, 6)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '[ LORDZ ] ZOLTON CORE ENGINE'
    $title.Dock = 'Top'
    $title.Height = 28
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 55)
    $title.BackColor = [System.Drawing.Color]::Transparent

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Awakening the Machine Spirit...'
    $status.Dock = 'Top'
    $status.Height = 42
    $status.ForeColor = [System.Drawing.Color]::FromArgb(190, 145, 110)
    $status.BackColor = [System.Drawing.Color]::Transparent
    $status.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Dock = 'Bottom'
    $progress.Height = 10
    $progress.Style = 'Marquee'
    $progress.MarqueeAnimationSpeed = 28

    $inner.Controls.Add($progress)
    $inner.Controls.Add($status)
    $inner.Controls.Add($title)
    $frame.Controls.Add($inner)
    $splash.Controls.Add($frame)

    $script:LordZSplash = $splash
    $script:LordZSplashStatusLabel = $status

    [void]$splash.Show()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-LordZSplashStatus {
    param([string]$Message)

    if (-not $script:LordZSplashStatusLabel) { return }
    $script:LordZSplashStatusLabel.Text = $Message
    [System.Windows.Forms.Application]::DoEvents()
}

function Close-LordZSplash {
    if (-not $script:LordZSplash) { return }

    try {
        if ($script:LordZSplash.Visible) {
            $script:LordZSplash.Hide()
        }
        $script:LordZSplash.Close()
        $script:LordZSplash.Dispose()
    }
    catch { }
    finally {
        $script:LordZSplash = $null
        $script:LordZSplashStatusLabel = $null
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Write-LordZCrashLog {
    param([string]$Message)
    try {
        $path = Join-Path $script:InstallRoot 'lordz-crash.log'
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    }
    catch { }
}

$script:LordZLayoutSyncInProgress = $false
$script:LordZLayoutResizeTimer = $null
$script:SteamCmdInstallRunning = $false

Show-LordZSplash

try {
    if (-not ('LordZNativeConsole' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LordZNativeConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        IntPtr handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) { ShowWindow(handle, 0); }
    }
}
'@
    }
    [LordZNativeConsole]::Hide()
}
catch { }

Set-LordZSplashStatus 'Loading core module...'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor `
        [Net.SecurityProtocolType]::Tls
}
catch { }

$previousWarningPreference = $WarningPreference
$WarningPreference = 'SilentlyContinue'
Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.SteamCmd.psm1') -Force
Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.Core.psm1') -Force
Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.SteamAuth.psm1') -Force
$WarningPreference = $previousWarningPreference

$script:LordZMainRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace

$script:SteamQrDebugConnected = $false
$script:SteamCmdConsoleSession = $null
$script:SteamCmdOutputTimer = $null
$script:SteamSessionReady = $false
$script:SteamLastLoginUsername = ''
$script:PendingSteamGuardCode = ''
$script:SteamConsoleLoginWorker = $null
$script:MirrorHostedWatch = $null
$script:MirrorPrepWorker = $null
$script:MirrorRunWorker = $null

Set-LordZSplashStatus 'Loading settings...'

$qrDebug = Connect-LordZSteamQrDebugBackend -BaseUrl 'http://127.0.0.1:8787'
if ($qrDebug.Connected) {
    $script:SteamQrDebugConnected = $true
    [void]$script:LordZLogBuffer.Add("[OK] $($qrDebug.Message)")
}
else {
    [void]$script:LordZLogBuffer.Add('[*] QR debug backend offline. Start Tools\Start-SteamQrDebug.bat to fix polling live.')
}

function Get-LordZDefaultSteamCmdPath {
    $candidates = @(
        (Join-Path $script:InstallRoot 'steamcmd\steamcmd.exe'),
        (Join-Path $script:InstallRoot 'SteamCMD\steamcmd.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return ''
}

function Test-LordZFirstRun {
    return -not (Test-Path -LiteralPath $script:SettingsPath)
}

function Import-LordZSettings {
    $defaultAppId = '895400'

    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return [PSCustomObject]@{
            SteamCmdPath  = (Get-LordZDefaultSteamCmdPath)
            AppId         = $defaultAppId
            SteamUsername = ''
        }
    }

    try {
        $raw = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $appId = [string]$raw.AppId
        if ([string]::IsNullOrWhiteSpace($appId)) {
            $appId = $defaultAppId
        }

        return [PSCustomObject]@{
            SteamCmdPath  = [string]$raw.SteamCmdPath
            AppId         = $appId
            SteamUsername = [string]$raw.SteamUsername
        }
    }
    catch {
        return [PSCustomObject]@{
            SteamCmdPath  = (Get-LordZDefaultSteamCmdPath)
            AppId         = $defaultAppId
            SteamUsername = ''
        }
    }
}

function Show-LordZFirstRunWelcome {
    $message = @'
Welcome to LordZ Workshop Mirror.

Quick start (3 steps):
  1. Click "Download & Install SteamCMD" (one time)
  2. Enter your Steam username, then click Verify on App ID 895400
  3. Add source mod IDs, click Generate Script, then Run Script

Run Script opens PowerShell and asks for your Steam password there.
Approve Steam Guard on your phone when prompted.

Disclaimer: Obtain permission from the original mod author before mirroring mods.
Any legal liability arising from such use rests solely with you.
'@

    Show-LordZMessage `
        -Message $message `
        -Title '[LORDZ] Quick Start' `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Save-LordZSettings {
    if (-not $script:TxtSteamCmdPath) { return }

    $payload = [PSCustomObject]@{
        SteamCmdPath  = $script:TxtSteamCmdPath.Text.Trim()
        AppId         = $script:TxtAppId.Text.Trim()
        SteamUsername = if ($script:TxtSteamUsername) { $script:TxtSteamUsername.Text.Trim() } else { '' }
    }

    $payload | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

$lordzSettings = Import-LordZSettings

Set-LordZSplashStatus 'Building interface...'

$script:LordZFlame = @{
    BgDeep       = [System.Drawing.Color]::FromArgb(10, 4, 2)
    BgPanel      = [System.Drawing.Color]::FromArgb(26, 12, 6)
    BgInput      = [System.Drawing.Color]::FromArgb(16, 8, 5)
    TextPrimary  = [System.Drawing.Color]::FromArgb(255, 220, 175)
    TextMuted    = [System.Drawing.Color]::FromArgb(190, 145, 110)
    Accent       = [System.Drawing.Color]::FromArgb(255, 130, 25)
    AccentHot    = [System.Drawing.Color]::FromArgb(255, 175, 55)
    EmberLine    = [System.Drawing.Color]::FromArgb(255, 95, 15)
    BtnPrimary   = [System.Drawing.Color]::FromArgb(185, 48, 0)
    BtnSecondary = [System.Drawing.Color]::FromArgb(145, 38, 0)
    BtnNeutral   = [System.Drawing.Color]::FromArgb(58, 30, 18)
    BtnDanger    = [System.Drawing.Color]::FromArgb(120, 22, 12)
    GridLine     = [System.Drawing.Color]::FromArgb(90, 40, 18)
    SelectRow    = [System.Drawing.Color]::FromArgb(150, 45, 0)
    LogText      = [System.Drawing.Color]::FromArgb(255, 185, 95)
    StatusOk     = [System.Drawing.Color]::FromArgb(255, 175, 60)
    StatusWarn   = [System.Drawing.Color]::FromArgb(255, 150, 70)
    StatusBad    = [System.Drawing.Color]::FromArgb(255, 75, 55)
}

function Register-LordZFlameBackground {
    param(
        [System.Windows.Forms.Control]$Control,
        [ValidateSet('Inferno', 'Ember', 'Abyss', 'Action')][string]$Variant = 'Ember'
    )

    $Control.Tag = $Variant
    $Control.Add_Paint({
        param($sender, $eventArgs)

        $rect = $sender.ClientRectangle
        if ($rect.Width -lt 1 -or $rect.Height -lt 1) { return }

        $g = $eventArgs.Graphics
        $mode = [System.Drawing.Drawing2D.LinearGradientMode]::Vertical

        switch ([string]$sender.Tag) {
            'Inferno' {
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    $rect,
                    [System.Drawing.Color]::FromArgb(210, 70, 0),
                    [System.Drawing.Color]::FromArgb(12, 4, 1),
                    $mode
                )
                $g.FillRectangle($brush, $rect)
                $brush.Dispose()

                $glow = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 170, 45), 3)
                $g.DrawLine($glow, 0, $rect.Height - 2, $rect.Width, $rect.Height - 2)
                $glow.Dispose()

                $titleFont = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
                $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 230, 170))
                $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 15, 0))
                $format = New-Object System.Drawing.StringFormat
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center

                $title = "[LORD ZOLTON CORE INTEGRATION ENGINE]`nWorkshop Mirror Matrix  |  Single-Session Steam Authorization"
                $textRect = New-Object System.Drawing.RectangleF(2, 4, $rect.Width, $rect.Height)
                $g.DrawString($title, $titleFont, $shadowBrush, $textRect, $format)
                $textRect = New-Object System.Drawing.RectangleF(0, 2, $rect.Width, $rect.Height)
                $g.DrawString($title, $titleFont, $textBrush, $textRect, $format)

                $titleFont.Dispose()
                $textBrush.Dispose()
                $shadowBrush.Dispose()
            }
            'Abyss' {
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    $rect,
                    [System.Drawing.Color]::FromArgb(22, 10, 6),
                    [System.Drawing.Color]::FromArgb(8, 3, 2),
                    $mode
                )
                $g.FillRectangle($brush, $rect)
                $brush.Dispose()
            }
            'Action' {
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    $rect,
                    [System.Drawing.Color]::FromArgb(34, 14, 8),
                    [System.Drawing.Color]::FromArgb(12, 5, 3),
                    $mode
                )
                $g.FillRectangle($brush, $rect)
                $brush.Dispose()

                $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 110, 20), 2)
                $g.DrawLine($line, 0, 0, $rect.Width, 0)
                $line.Dispose()
            }
            default {
                $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                    $rect,
                    [System.Drawing.Color]::FromArgb(34, 16, 8),
                    [System.Drawing.Color]::FromArgb(14, 6, 4),
                    $mode
                )
                $g.FillRectangle($brush, $rect)
                $brush.Dispose()

                $accent = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 100, 15), 4)
                $g.DrawLine($accent, 0, 0, 0, $rect.Height)
                $accent.Dispose()
            }
        }
    })
}

function Set-LordZFlamePanel {
    param(
        [System.Windows.Forms.Control]$Control,
        [ValidateSet('Inferno', 'Ember', 'Abyss', 'Action')][string]$Variant = 'Ember'
    )

    $Control.BackColor = $script:LordZFlame.BgDeep
    try {
        $flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $prop = $Control.GetType().GetProperty('DoubleBuffered', $flags)
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    }
    catch { }
    Register-LordZFlameBackground -Control $Control -Variant $Variant
}

function Invoke-LordZOnUiThread {
    param(
        [Parameter(Mandatory)][scriptblock]$Action
    )

    if (-not $script:MainForm -or -not $script:MainForm.IsHandleCreated) {
        & $Action
        return
    }

    if (-not $script:MainForm.InvokeRequired) {
        & $Action
        return
    }

    $handler = [System.Action]$Action
    [void]$script:MainForm.Invoke($handler)
}

function Write-LordZLogRaw {
    param([AllowEmptyString()][string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    if (-not $script:LogBox) {
        $script:LordZLogBuffer.Add($Message) | Out-Null
        return
    }

    if ('LordZPipelineLogHub' -as [type]) {
        [LordZPipelineLogHub]::Enqueue($Message)
    }
}

function Write-LordZLog {
    param([AllowEmptyString()][string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $stamp = Get-Date -Format 'HH:mm:ss'
    Write-LordZLogRaw "[$stamp] $Message"
}

function Write-LordZLogError {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    Write-LordZLog "[!] $Message"
}

function Set-LordZSteamConsoleInputEnabled {
    param([bool]$Enabled)

    if (-not $script:TxtSteamCmdInput) { return }

    $enabledState = $Enabled
    Invoke-LordZOnUiThread -Action {
        $script:TxtSteamCmdInput.Enabled = $enabledState
        if ($script:BtnSteamCmdSend) { $script:BtnSteamCmdSend.Enabled = $enabledState }
        if ($enabledState) {
            $script:TxtSteamCmdInput.BackColor = [System.Drawing.Color]::FromArgb(30, 14, 8)
            $script:TxtSteamCmdInput.Focus()
        }
        else {
            $script:TxtSteamCmdInput.BackColor = [System.Drawing.Color]::FromArgb(18, 8, 5)
        }
    }
}

function Update-LordZSteamConsoleLoginState {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return }

    if ($Line -match 'logged in OK|successfully logged in|Waiting for user info|Logging in using cached credentials') {
        if (-not $script:SteamSessionReady) {
            $script:SteamSessionReady = $true
            Write-LordZLog '[OK] SteamCMD login succeeded. Session is cached for mirroring.'
        }
    }
}

function Invoke-LordZSteamConsoleBatchLogin {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$Username,
        [string]$Password,
        [string]$SteamGuardCode
    )

    if ($script:SteamConsoleLoginWorker -and $script:SteamConsoleLoginWorker.IsBusy) {
        Write-LordZLog '[*] Login already in progress. Approve Steam Guard on your phone if prompted.'
        return
    }

    $worker = New-Object System.ComponentModel.BackgroundWorker
    $script:SteamConsoleLoginWorker = $worker
    Register-LordZWorkerLogging -Worker $worker
    [void]$worker.add_DoWork({
        param($sender, $e)
        $threadRunspace = $null
        try {
            $threadRunspace = Enter-LordZWorkerRunspace
            $payload = $e.Argument
            $e.Result = Invoke-LordZSteamCmdLogin `
                -SteamCmdPath $payload.SteamCmdPath `
                -Username $payload.Username `
                -Password $payload.Password `
                -SteamGuardCode $payload.SteamGuardCode `
                -ProgressSender $sender
        }
        finally {
            Exit-LordZWorkerRunspace $threadRunspace
        }
    })
    [void]$worker.add_RunWorkerCompleted({
        param($sender, $e)
        if ($e.Error) {
            Write-LordZLog ("[!] SteamCMD login failed: " + $e.Error.Message)
            return
        }

        $result = $e.Result
        foreach ($outLine in $result.OutputLines) {
            Update-LordZSteamConsoleLoginState $outLine
        }
        if ($result.Success) {
            $script:SteamSessionReady = $true
            Write-LordZLog '[OK] SteamCMD login succeeded. Session is cached for mirroring.'
        }
        else {
            Write-LordZLog "[!] $($result.Message)"
            if ($result.NeedsSteamGuard) {
                Write-LordZLog '[*] Approve on your phone, or type: set_steam_guard_code YOURCODE  then login again.'
            }
        }
    })
    [void]$worker.RunWorkerAsync([PSCustomObject]@{
        SteamCmdPath   = $SteamCmdPath
        Username       = $Username
        Password       = $Password
        SteamGuardCode = $SteamGuardCode
    })
}

function Send-LordZSteamCmdConsoleInput {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

    $trimmed = $Line.Trim()

    if (-not $script:SteamCmdConsoleSession -or $script:SteamCmdConsoleSession.Process.HasExited) {
        $paths = Get-LordZSteamPaths
        if ($paths) {
            Start-LordZHostedSteamConsole -SteamCmdPath $paths.SteamCmdPath
        }
    }

    if (-not $script:SteamCmdConsoleSession -or $script:SteamCmdConsoleSession.Process.HasExited) {
        Write-LordZLog '[!] SteamCMD console is not running. Set a valid SteamCMD path and click Restart Console.'
        return $false
    }

    Write-LordZLogRaw ("> $trimmed")

    if ($trimmed -match '^\s*login\s+(\S+)') {
        $script:SteamLastLoginUsername = $Matches[1]
    }

    if ($trimmed -match '^\s*set_steam_guard_code\s+(\S+)') {
        $script:PendingSteamGuardCode = $Matches[1]
    }

    [void](Send-LordZSteamCmdConsoleLine -Session $script:SteamCmdConsoleSession -Line $trimmed)
    return $true
}

function Stop-LordZSteamConsoleOutputPump {
    if ($script:SteamCmdOutputTimer) {
        $script:SteamCmdOutputTimer.Stop()
    }
}

function Start-LordZHostedSteamConsole {
    param([Parameter(Mandatory)][string]$SteamCmdPath)

    if ($script:SteamCmdConsoleSession -and -not $script:SteamCmdConsoleSession.Process.HasExited) {
        Set-LordZSteamConsoleInputEnabled $true
        if ($script:BtnSteamCmdStop) { $script:BtnSteamCmdStop.Enabled = $true }
        return
    }

    if ($script:SteamCmdInstallRunning) {
        Write-LordZLog '[*] SteamCMD install is running. Console will start when install finishes.'
        return
    }

    try {
        $session = Start-LordZSteamCmdConsoleSession -SteamCmdPath $SteamCmdPath
        $script:SteamCmdConsoleSession = $session
        Set-LordZSteamConsoleInputEnabled $true
        if ($script:BtnSteamCmdStop) { $script:BtnSteamCmdStop.Enabled = $true }

        if (-not $script:SteamCmdOutputTimer) {
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 80
            [void]$timer.add_Tick({
                Sync-LordZPipelineLogHub

                $sess = $script:SteamCmdConsoleSession
                if (-not $sess -or $sess.Process.HasExited) {
                    Stop-LordZSteamConsoleOutputPump
                    $script:SteamCmdConsoleSession = $null
                    Set-LordZSteamConsoleInputEnabled $false
                    if ($script:BtnSteamCmdStop) { $script:BtnSteamCmdStop.Enabled = $false }
                    return
                }

                Sync-LordZPipelineLogHub
            })
            $script:SteamCmdOutputTimer = $timer
        }

        $script:SteamCmdOutputTimer.Start()
        Write-LordZLog '[*] SteamCMD console ready. Type in the bar below when SteamCMD asks (e.g. login yourname yourpassword).'
    }
    catch {
        Write-LordZLog ("[!] Could not start SteamCMD console: " + $_.Exception.Message)
    }
}

function Stop-LordZSteamConsoleSession {
    Stop-LordZSteamConsoleOutputPump
    if ($script:SteamCmdConsoleSession) {
        Stop-LordZSteamCmdConsoleSession -Session $script:SteamCmdConsoleSession
        $script:SteamCmdConsoleSession = $null
    }
    Set-LordZSteamConsoleInputEnabled $false
    if ($script:BtnSteamCmdStop) { $script:BtnSteamCmdStop.Enabled = $false }
}

function Show-LordZMessage {
    param(
        [AllowEmptyString()][string]$Message = '',
        [string]$Title = '[LORDZ]',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = 'An unexpected error occurred.'
    }

    if ($script:MainForm) {
        return [System.Windows.Forms.MessageBox]::Show($script:MainForm, $Message, $Title, $Buttons, $Icon)
    }

    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Get-LordZLogExcerpt {
    param([int]$MaxLength = 900)

    if (-not $script:LogBox -or [string]::IsNullOrWhiteSpace($script:LogBox.Text)) {
        return ''
    }

    $text = $script:LogBox.Text.Trim()
    if ($text.Length -le $MaxLength) {
        return $text
    }

    return $text.Substring($text.Length - $MaxLength)
}

function Get-LordZHelpContext {
    $context = [ordered]@{
        'Windows User' = [System.Environment]::UserName
        'App Version'  = 'LordZ Mirror Core Engine'
    }

    if ($script:TxtAppId -and -not [string]::IsNullOrWhiteSpace($script:TxtAppId.Text)) {
        $context['App ID'] = $script:TxtAppId.Text.Trim()
    }

    if ($script:TxtSteamCmdPath -and -not [string]::IsNullOrWhiteSpace($script:TxtSteamCmdPath.Text)) {
        $context['SteamCMD'] = $script:TxtSteamCmdPath.Text.Trim()
    }

    if ($script:QueueGrid) {
        $context['Queue Items'] = [string]$script:QueueGrid.Rows.Count
    }

    return $context
}

function Update-LordZDiscordPanel {
    if (-not $script:LblDiscordStatus) { return }

    $status = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot
    $parts = New-Object System.Collections.Generic.List[string]

    if ($status.InviteConfigured) {
        [void]$parts.Add("Invite: $($status.ChannelLabel)")
    }
    if ($status.ChatConfigured) {
        [void]$parts.Add('Live chat: ready')
    }
    elseif ($status.WebhookConfigured) {
        [void]$parts.Add('Quick relay: ready')
    }

    if ($parts.Count -eq 0) {
        $script:LblDiscordStatus.Text = 'Discord support not bundled - download the release zip from GitHub (not git clone) for Live Help Chat'
        $script:BtnDiscordOpen.Enabled = $false
        $script:BtnDiscordChat.Enabled = $false
        $script:BtnDiscordSend.Enabled = $false
        return
    }

    if (-not $status.ChatConfigured -and $status.WebhookConfigured) {
        $script:LblDiscordStatus.Text = (($parts -join ' | ') + ' | Add BotToken for 2-way chat')
    }
    else {
        $script:LblDiscordStatus.Text = ($parts -join ' | ')
    }

    $script:BtnDiscordOpen.Enabled = $status.InviteConfigured
    $script:BtnDiscordChat.Enabled = $status.ChatConfigured
    $script:BtnDiscordSend.Enabled = $status.WebhookConfigured
}

function Add-LordZChatLine {
    param(
        [System.Windows.Forms.TextBox]$ChatBox,
        [string]$Speaker,
        [string]$Text
    )

    if (-not $ChatBox) { return }

    $line = "[$Speaker] $Text"
    if ($ChatBox.TextLength -gt 0) {
        $ChatBox.AppendText("`r`n")
    }
    $ChatBox.AppendText($line)
    $ChatBox.SelectionStart = $ChatBox.TextLength
    $ChatBox.ScrollToCaret()
}

function Show-LordZHelpChatDialog {
    $status = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot
    if (-not $status.ChatConfigured) {
        Show-LordZMessage `
            -Message "Live chat needs a Discord bot.`n`n1. Create a bot at https://discord.com/developers/applications`n2. Enable Message Content Intent on the bot`n3. Invite the bot to your server (Send Messages, Read History, Create Public Threads)`n4. Set BotToken and HelpChannelId in lordz.discord.json`n`nHelpChannelId is already set to your help channel. Paste your bot token to enable 2-way chat." `
            -Title '[LORDZ] Live Help Chat' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '[LORDZ] Anonymous Help Chat'
    $dialog.ClientSize = New-Object System.Drawing.Size(620, 480)
    $dialog.StartPosition = 'CenterParent'
    $dialog.MinimumSize = New-Object System.Drawing.Size(520, 360)
    $dialog.BackColor = $script:LordZFlame.BgPanel
    $dialog.ForeColor = $script:LordZFlame.TextPrimary
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $dialog.Tag = @{
        Session = $null
        Polling = $false
    }

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'You are anonymous here. Messages relay to a private thread in Discord. When support replies there, their answer appears below.'
    $intro.Dock = 'Top'
    $intro.Height = 48
    $intro.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 0)
    $intro.ForeColor = $script:LordZFlame.TextMuted

    $statusLine = New-Object System.Windows.Forms.Label
    $statusLine.Text = 'Send your first message to open a help thread.'
    $statusLine.Dock = 'Bottom'
    $statusLine.Height = 28
    $statusLine.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 0)
    $statusLine.ForeColor = $script:LordZFlame.AccentHot
    $statusLine.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $chatLog = New-Object System.Windows.Forms.TextBox
    $chatLog.Multiline = $true
    $chatLog.ReadOnly = $true
    $chatLog.Dock = 'Fill'
    $chatLog.ScrollBars = 'Vertical'
    $chatLog.BackColor = [System.Drawing.Color]::FromArgb(8, 3, 2)
    $chatLog.ForeColor = $script:LordZFlame.LogText
    $chatLog.BorderStyle = 'FixedSingle'
    $chatLog.Font = New-Object System.Drawing.Font('Consolas', 10)
    $chatLog.Margin = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.Multiline = $false
    $inputBox.Dock = 'Fill'
    $inputBox.BackColor = $script:LordZFlame.BgInput
    $inputBox.ForeColor = $script:LordZFlame.TextPrimary
    $inputBox.BorderStyle = 'FixedSingle'
    $inputBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $inputPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $inputPanel.Dock = 'Bottom'
    $inputPanel.Height = 52
    $inputPanel.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
    $inputPanel.ColumnCount = 2
    $inputPanel.RowCount = 1
    [void]$inputPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$inputPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 120))
    $inputPanel.Controls.Add($inputBox, 0, 0)

    $btnSendChat = New-LordZButton -Text 'Send' -BackColor $script:LordZFlame.BtnPrimary -FillCell
    $inputPanel.Controls.Add($btnSendChat, 1, 0)

    $contentPanel = New-Object System.Windows.Forms.Panel
    $contentPanel.Dock = 'Fill'
    $contentPanel.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $contentPanel.Controls.Add($chatLog)

    $dialog.Controls.Add($contentPanel)
    $dialog.Controls.Add($inputPanel)
    $dialog.Controls.Add($statusLine)
    $dialog.Controls.Add($intro)
    $dialog.AcceptButton = $btnSendChat

    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = 4000

    $pollDiscordReplies = {
        if (-not $dialog.Tag.Session) { return }
        if ($dialog.Tag.Polling) { return }

        $dialog.Tag.Polling = $true
        try {
            $updates = Get-LordZDiscordHelpChatUpdates `
                -InstallRoot $script:InstallRoot `
                -ThreadId $dialog.Tag.Session.ThreadId `
                -LastMessageId $dialog.Tag.Session.LastMessageId `
                -BotUserId $dialog.Tag.Session.BotUserId `
                -SupportLabel $dialog.Tag.Session.SupportLabel

            foreach ($update in $updates) {
                $speaker = ('{0} - {1}' -f $update.Speaker, $update.DisplayName)
                Add-LordZChatLine -ChatBox $chatLog -Speaker $speaker -Text $update.Text
                $dialog.Tag.Session.LastMessageId = $update.MessageId
            }
        }
        catch {
            $statusLine.Text = 'Poll error - retrying...'
            Write-LordZLog ("[!] Live chat poll failed: " + $_.Exception.Message)
        }
        finally {
            $dialog.Tag.Polling = $false
            if ($dialog.Tag.Session) {
                $statusLine.Text = ('Session {0} active - listening for Discord replies...' -f $dialog.Tag.Session.SessionId)
            }
        }
    }

    $sendChatMessage = {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

        if (-not $dialog.Tag.Session) {
            $statusLine.Text = 'Opening anonymous help thread...'
            $btnSendChat.Enabled = $false
            $inputBox.Enabled = $false

            $start = Start-LordZDiscordHelpChatSession `
                -InstallRoot $script:InstallRoot `
                -InitialMessage $Text

            if (-not $start.Success) {
                Write-LordZLog "[!] Live chat failed: $($start.Message)"
                Show-LordZMessage `
                    -Message $start.Message `
                    -Title '[LORDZ] Live Help Chat' `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
                $statusLine.Text = 'Could not start chat. Check BotToken and bot permissions.'
                $btnSendChat.Enabled = $true
                $inputBox.Enabled = $true
                return $false
            }

            $dialog.Tag.Session = @{
                SessionId      = $start.SessionId
                AnonymousLabel = $start.AnonymousLabel
                ThreadId       = $start.ThreadId
                LastMessageId  = $start.LastMessageId
                BotUserId      = $start.BotUserId
                SupportLabel   = $start.SupportLabel
            }

            Add-LordZChatLine -ChatBox $chatLog -Speaker 'System' -Text "Connected as $($start.AnonymousLabel). Waiting for support..."
            $statusLine.Text = ('Session {0} active - replies from Discord appear here.' -f $start.SessionId)
            Write-LordZLog "[OK] Live help chat started (session $($start.SessionId))."
            $pollTimer.Start()
            $btnSendChat.Enabled = $true
            $inputBox.Enabled = $true
            Add-LordZChatLine -ChatBox $chatLog -Speaker 'You' -Text $Text.Trim()
            & $pollDiscordReplies
            return $true
        }

        $result = Send-LordZDiscordHelpChatMessage `
            -InstallRoot $script:InstallRoot `
            -ThreadId $dialog.Tag.Session.ThreadId `
            -AnonymousLabel $dialog.Tag.Session.AnonymousLabel `
            -Message $Text

        if (-not $result.Success) {
            Write-LordZLog "[!] Live chat send failed: $($result.Message)"
            Show-LordZMessage `
                -Message $result.Message `
                -Title '[LORDZ] Live Help Chat' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
            return $false
        }

        $dialog.Tag.Session.LastMessageId = $result.MessageId
        Add-LordZChatLine -ChatBox $chatLog -Speaker 'You' -Text $Text.Trim()
        return $true
    }

    $btnSendChat.Add_Click({
        $text = $inputBox.Text
        if (& $sendChatMessage $text) {
            $inputBox.Clear()
        }
        $inputBox.Focus()
    })

    $inputBox.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq 'Enter') {
            $eventArgs.SuppressKeyPress = $true
            $text = $inputBox.Text
            if (& $sendChatMessage $text) {
                $inputBox.Clear()
            }
        }
    })

    $pollTimer.Add_Tick({ & $pollDiscordReplies })

    $dialog.Add_FormClosed({
        $pollTimer.Stop()
        $pollTimer.Dispose()
    })

    [void]$dialog.ShowDialog($script:MainForm)
}

function Show-LordZHelpRequestDialog {
    $status = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot
    if (-not $status.WebhookConfigured) {
        Show-LordZMessage `
            -Message "Discord webhook is not configured.`n`nCopy lordz.discord.example.json to lordz.discord.json beside this app, then set WebhookUrl to a channel webhook in your help channel." `
            -Title '[LORDZ] Discord Help' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '[LORDZ] Send Help Request'
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 360)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:LordZFlame.BgPanel
    $dialog.ForeColor = $script:LordZFlame.TextPrimary
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = "Describe your issue. The relay posts to $($status.ChannelLabel) so the forge-master can respond."
    $intro.Dock = 'Top'
    $intro.Height = 52
    $intro.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 0)
    $intro.ForeColor = $script:LordZFlame.TextMuted

    $messageBox = New-Object System.Windows.Forms.TextBox
    $messageBox.Multiline = $true
    $messageBox.Dock = 'Fill'
    $messageBox.ScrollBars = 'Vertical'
    $messageBox.BackColor = $script:LordZFlame.BgInput
    $messageBox.ForeColor = $script:LordZFlame.TextPrimary
    $messageBox.BorderStyle = 'FixedSingle'
    $messageBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $messageBox.Margin = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

    $optionsPanel = New-Object System.Windows.Forms.Panel
    $optionsPanel.Dock = 'Bottom'
    $optionsPanel.Height = 36
    $optionsPanel.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 4)

    $includeLog = New-Object System.Windows.Forms.CheckBox
    $includeLog.Text = 'Include operation log excerpt'
    $includeLog.Checked = $true
    $includeLog.Dock = 'Fill'
    $includeLog.ForeColor = $script:LordZFlame.TextMuted
    $includeLog.BackColor = [System.Drawing.Color]::Transparent
    $optionsPanel.Controls.Add($includeLog)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = 'Bottom'
    $buttonPanel.Height = 52
    $buttonPanel.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.WrapContents = $false

    $btnCancel = New-LordZButton -Text 'Cancel' -BackColor $script:LordZFlame.BtnNeutral
    $btnSend = New-LordZButton -Text 'Send To Discord' -BackColor $script:LordZFlame.BtnPrimary
    $btnCancel.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnSend.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$buttonPanel.Controls.Add($btnSend)
    [void]$buttonPanel.Controls.Add($btnCancel)

    $contentPanel = New-Object System.Windows.Forms.Panel
    $contentPanel.Dock = 'Fill'
    $contentPanel.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $contentPanel.Controls.Add($messageBox)

    $dialog.Controls.Add($contentPanel)
    $dialog.Controls.Add($optionsPanel)
    $dialog.Controls.Add($buttonPanel)
    $dialog.Controls.Add($intro)
    $dialog.AcceptButton = $btnSend
    $dialog.CancelButton = $btnCancel
    $dialog.Tag = @{ Sent = $false }

    $btnCancel.Add_Click({ $dialog.Close() })
    $btnSend.Add_Click({
        if ([string]::IsNullOrWhiteSpace($messageBox.Text)) {
            Show-LordZMessage `
                -Message 'Describe the issue before sending.' `
                -Title '[LORDZ] Discord Help' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $btnSend.Enabled = $false
        $btnCancel.Enabled = $false
        $logExcerpt = if ($includeLog.Checked) { Get-LordZLogExcerpt } else { '' }
        $result = Send-LordZDiscordHelpMessage `
            -InstallRoot $script:InstallRoot `
            -Message $messageBox.Text `
            -LogExcerpt $logExcerpt `
            -Context (Get-LordZHelpContext)

        if ($result.Success) {
            Write-LordZLog "[OK] $($result.Message)"
            $dialog.Tag.Sent = $true
            $dialog.Close()
        }
        else {
            Write-LordZLog "[!] Discord relay failed: $($result.Message)"
            Show-LordZMessage `
                -Message $result.Message `
                -Title '[LORDZ] Discord Help' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
            $btnSend.Enabled = $true
            $btnCancel.Enabled = $true
        }
    })

    [void]$dialog.ShowDialog($script:MainForm)

    if ($dialog.Tag.Sent) {
        Show-LordZMessage `
            -Message "Your help request was sent to $($status.ChannelLabel). You can also join the Discord server for live support." `
            -Title '[LORDZ] Help Sent' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

function Show-LordZAsciiBanner {
    $bannerPath = Join-Path $script:InstallRoot 'Assets\LordZ-Ascii.txt'
    if (Test-Path -LiteralPath $bannerPath) {
        Get-Content -LiteralPath $bannerPath -ErrorAction SilentlyContinue | ForEach-Object {
            Write-LordZLogRaw $_
        }
        return
    }

    Write-LordZLogRaw '======================================================================'
    Write-LordZLogRaw ' LORDZ // ZOLTON CORE INTEGRATION ENGINE '
    Write-LordZLogRaw '======================================================================'
}

function Import-LordZWorkerModules {
    Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.SteamCmd.psm1') -Force
    Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.Core.psm1') -Force
    Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.SteamAuth.psm1') -Force
}

function Enter-LordZWorkerRunspace {
    $threadRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $threadRunspace.Open()
    [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $threadRunspace
    Import-LordZWorkerModules
    return $threadRunspace
}

function Exit-LordZWorkerRunspace {
    param($Runspace)

    try {
        if ($Runspace) {
            $Runspace.Close()
            $Runspace.Dispose()
        }
    }
    catch {
        Write-LordZCrashLog ('Worker runspace cleanup failed: ' + $_.Exception.Message)
    }
}

function Sync-LordZPipelineLogHub {
    if (-not ('LordZPipelineLogHub' -as [type])) { return }
    if (-not $script:LogBox) { return }

    $line = $null
    while ([LordZPipelineLogHub]::TryDequeue([ref]$line)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $script:LogBox.AppendText($line + "`r`n")
        Update-LordZSteamConsoleLoginState $line
    }

    if ($script:LogBox.TextLength -gt 0) {
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
    }
}

function Stop-LordZMirrorAsyncJob {
    if ($script:MirrorAsyncTimer) {
        try { $script:MirrorAsyncTimer.Stop() } catch { }
        try { $script:MirrorAsyncTimer.Dispose() } catch { }
        $script:MirrorAsyncTimer = $null
    }

    if ($script:MirrorPrepWorker) {
        try {
            if ($script:MirrorPrepWorker.IsBusy) { $script:MirrorPrepWorker.CancelAsync() }
        }
        catch { }
        $script:MirrorPrepWorker = $null
    }

    if ($script:MirrorAsyncPowerShell) {
        try { $script:MirrorAsyncPowerShell.Stop() } catch { }
        try { $script:MirrorAsyncPowerShell.Dispose() } catch { }
        $script:MirrorAsyncPowerShell = $null
    }

    if ($script:MirrorAsyncRunspace) {
        try { $script:MirrorAsyncRunspace.Close() } catch { }
        try { $script:MirrorAsyncRunspace.Dispose() } catch { }
        $script:MirrorAsyncRunspace = $null
    }

    $script:MirrorAsyncHandle = $null
    $script:MirrorHostedWatch = $null
    Sync-LordZPipelineLogHub
}

function Start-LordZMirrorAsyncTimer {
    if ($script:MirrorAsyncTimer) { return }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    [void]$timer.add_Tick({
        Sync-LordZPipelineLogHub

        if ($script:MirrorHostedWatch) {
            $watch = $script:MirrorHostedWatch
            $session = $watch.Session

            if (-not $session -or -not $session.Process -or $session.Process.HasExited) {
                $exitCode = -1
                if ($session -and $session.Process) {
                    try { $exitCode = $session.Process.ExitCode } catch { }
                }

                $loadCount = $watch.LoadCount
                $script:MirrorHostedWatch = $null

                Complete-LordZMirrorAsyncJob -PipelineResult ([PSCustomObject]@{
                    Success   = ($exitCode -eq 0)
                    LoadCount = $loadCount
                    ExitCode  = $exitCode
                }) -ErrorRecord $null
                return
            }

            if (([datetime]::UtcNow - $watch.StartedAt).TotalSeconds -gt $watch.TimeoutSeconds) {
                try {
                    if (-not $session.Process.HasExited) { $session.Process.Kill() }
                }
                catch { }

                $loadCount = $watch.LoadCount
                $script:MirrorHostedWatch = $null
                Write-LordZLog '[!] Mirror batch timed out in the SteamCMD console.'

                Complete-LordZMirrorAsyncJob -PipelineResult ([PSCustomObject]@{
                    Success   = $false
                    LoadCount = $loadCount
                    Message   = 'SteamCMD mirror batch timed out.'
                }) -ErrorRecord $null
            }

            return
        }

        if (-not $script:MirrorAsyncHandle -or -not $script:MirrorAsyncHandle.IsCompleted) { return }

        try {
            $outputs = $script:MirrorAsyncPowerShell.EndInvoke($script:MirrorAsyncHandle)
            if ($script:MirrorAsyncPowerShell.HadErrors) {
                $err = $script:MirrorAsyncPowerShell.Streams.Error | Select-Object -First 1
                if ($err) {
                    Complete-LordZMirrorAsyncJob -PipelineResult $null -ErrorRecord $err
                    return
                }
            }

            $pipelineResult = $null
            if ($outputs -and $outputs.Count -gt 0) {
                $pipelineResult = $outputs[$outputs.Count - 1]
            }

            Complete-LordZMirrorAsyncJob -PipelineResult $pipelineResult -ErrorRecord $null
        }
        catch {
            Complete-LordZMirrorAsyncJob -PipelineResult $null -ErrorRecord $_
        }
    })
    $script:MirrorAsyncTimer = $timer
    $timer.Start()
}

function Complete-LordZMirrorAsyncJob {
    param($PipelineResult, $ErrorRecord)

    Sync-LordZPipelineLogHub
    Stop-LordZMirrorAsyncJob
    Set-LordZBusy $false
    Write-LordZLog '======================================================================'
    Write-LordZLog '>>> THE RITE IS CONCLUDED. GLORY TO THE OMNISSIAH.'

    if ($ErrorRecord) {
        $message = $ErrorRecord.Exception.Message
        Write-LordZLog ("[!] Mirror pipeline error: $message")
        Show-LordZMessage `
            -Message $message `
            -Title '[LORDZ] Mirror Failed' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
        return
    }

    if (-not $PipelineResult) {
        Write-LordZLog '[!] Mirror pipeline returned no result.'
        return
    }

    if ($PipelineResult.Success) {
        Show-LordZMessage `
            -Message "Mirror pipeline finished. $($PipelineResult.LoadCount) item(s) processed." `
            -Title '[LORDZ] Complete' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    elseif ($PipelineResult.Message) {
        Write-LordZLog "[!] $($PipelineResult.Message)"
    }
    else {
        Write-LordZLog '[!] Mirror pipeline failed. Check the Steam console log above.'
    }

    $paths = Get-LordZSteamPaths
    if ($paths) {
        Start-LordZHostedSteamConsole -SteamCmdPath $paths.SteamCmdPath
    }
}

function Start-LordZMirrorPipelineOnHostedConsole {
    param(
        [Parameter(Mandatory)]$Prep,
        [Parameter(Mandatory)]$Payload
    )

    $session = $script:SteamCmdConsoleSession
    if (-not $session -or $session.Process.HasExited) {
        Start-LordZHostedSteamConsole -SteamCmdPath $Payload.SteamCmdPath
        $session = $script:SteamCmdConsoleSession
    }

    if (-not $session -or $session.Process.HasExited) {
        Complete-LordZMirrorAsyncJob -PipelineResult ([PSCustomObject]@{
            Success = $false
            Message = 'Could not start the in-app SteamCMD console.'
            LoadCount = 0
        }) -ErrorRecord $null
        return
    }

    $hosted = Invoke-LordZSteamCmdHostedScript `
        -Session $session `
        -SteamCmdPath $Payload.SteamCmdPath `
        -ScriptLines $Prep.ScriptLines

    Sync-LordZPipelineLogHub

    if (-not $hosted.Started) {
        Complete-LordZMirrorAsyncJob -PipelineResult ([PSCustomObject]@{
            Success   = $false
            LoadCount = $Prep.LoadCount
            Message   = $hosted.Message
        }) -ErrorRecord $null
        return
    }

    Write-LordZLogRaw ("> $($hosted.RunLine)")
    Write-LordZLog '[*] SteamCMD is running the mirror batch in this console. Use the input bar when it asks you to log in.'

    $script:MirrorHostedWatch = @{
        Session        = $session
        StartedAt      = [datetime]::UtcNow
        TimeoutSeconds = 3600
        LoadCount      = $Prep.LoadCount
    }

    Start-LordZMirrorAsyncTimer
}

function Get-LordZMirrorQueueFromGrid {
    param($Grid)

    $queue = @()
    foreach ($row in $Grid.Rows) {
        if ($row.IsNewRow) { continue }
        $queue += [PSCustomObject]@{
            SourceModId     = [string]$row.Cells[0].Value
            MirrorName      = [string]$row.Cells[1].Value
            Visibility      = [string]$row.Cells[2].Value
            PublishedFileId = [string]$row.Cells[3].Value
        }
    }
    return $queue
}

function Invoke-LordZGenerateMirrorScript {
    param(
        $Grid,
        $TxtAppId,
        $TxtSteamUsername
    )

    $paths = Get-LordZSteamPaths
    if (-not $paths) {
        Write-LordZLog '[!] Set a valid SteamCMD path first.'
        return $null
    }

    $appId = $TxtAppId.Text.Trim()
    if ($appId -notmatch '^\d+$') {
        Show-LordZMessage `
            -Message 'App ID must be numeric.' `
            -Title '[LORDZ]' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }

    $steamUser = $TxtSteamUsername.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($steamUser)) {
        Show-LordZMessage `
            -Message 'Enter your Steam username in Core Configuration first.' `
            -Title '[LORDZ] Generate Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-LordZLog '[!] Steam username is required.'
        return $null
    }

    $queue = Get-LordZMirrorQueueFromGrid -Grid $Grid
    if ($queue.Count -eq 0) {
        Show-LordZMessage `
            -Message 'Add at least one mod to the mirror queue first.' `
            -Title '[LORDZ]' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-LordZLog '[!] Mirror queue is empty.'
        return $null
    }

    if (-not $script:AppIdVerified) {
        Write-LordZLog '[!] App ID is not verified yet. Continuing anyway.'
    }

    $appLabel = if ($script:VerifiedAppName) { "$script:VerifiedAppName ($appId)" } else { $appId }
    Write-LordZLog '======================================================================'
    Write-LordZAsciiBannerToLog
    Write-LordZLog '======================================================================'
    Write-LordZLog "[*] Generating mirror script for $appLabel"
    Write-LordZLog "[*] Account: $steamUser | Queue: $($queue.Count) item(s)"
    Write-LordZLog '[*] Run Script will ask for your password (not saved).'

    Save-LordZSettings

    $package = New-LordZMirrorRunPackage `
        -InstallRoot $script:InstallRoot `
        -SteamCmdPath $paths.SteamCmdPath `
        -SteamCmdDir $paths.SteamCmdDir `
        -AppId $appId `
        -Username $steamUser `
        -MirrorQueue $queue `
        -ProgressSender { param($Line) Write-LordZLog $Line }

    if (-not $package -or -not $package.Success) {
        $msg = if ($package -and $package.Message) { $package.Message } else { 'Script generation failed.' }
        Write-LordZLog "[!] $msg"
        Show-LordZMessage `
            -Message $msg `
            -Title '[LORDZ] Generate Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }

    $script:LastGeneratedPackage = $package

    if ($script:BtnRunScript) { $script:BtnRunScript.Enabled = $true }
    if ($script:BtnCopyScript) { $script:BtnCopyScript.Enabled = $true }

    Write-LordZLog "[OK] $($package.Message)"
    Write-LordZLog "[*] Batch file: $($package.BatchPath)"
    Write-LordZLog "[*] Runner script: $($package.RunnerPath)"
    Write-LordZLog '[*] SteamCMD batch commands:'
    foreach ($line in $package.BatchLines) {
        Write-LordZLogRaw "    $line"
    }
    Write-LordZLog '[*] Click Run Script to open a PowerShell window (password entered there).'
    Write-LordZLog '[*] Or Copy Script to paste the standalone runner elsewhere.'

    return $package
}

function Invoke-LordZRunGeneratedMirrorScript {
    $steamUser = $script:TxtSteamUsername.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($steamUser)) {
        Show-LordZMessage `
            -Message 'Enter your Steam username in Core Configuration first.' `
            -Title '[LORDZ] Run Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-LordZLog '[!] Steam username is required.'
        return
    }

    $package = $script:LastGeneratedPackage
    if (-not $package -or -not (Test-Path -LiteralPath $package.RunnerPath)) {
        Write-LordZLog '[*] Generating runner script before launch...'
        $package = Invoke-LordZGenerateMirrorScript -Grid $script:QueueGrid -TxtAppId $script:TxtAppId -TxtSteamUsername $script:TxtSteamUsername
        if (-not $package) { return }
    }

    if (-not (Test-Path -LiteralPath $package.RunnerPath)) {
        Write-LordZLog '[!] Runner script file is missing. Click Generate Script first.'
        return
    }

    Write-LordZLog '======================================================================'
    Write-LordZAsciiBannerToLog
    Write-LordZLog '======================================================================'
    Write-LordZLog "[*] Launching PowerShell: $($package.RunnerPath)"

    try {
        Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-NoExit',
                '-File', $package.RunnerPath
            ) `
            -WorkingDirectory $script:InstallRoot | Out-Null

        Write-LordZLog '[OK] Lord Zolton mirror script opened in a new PowerShell window.'
        Write-LordZLog ('[*] Account: ' + $steamUser + ' - enter your Steam password in that window when asked.')
        Write-LordZLog '[*] Approve Steam Guard on your phone if prompted.'
    }
    catch {
        Write-LordZLog ("[!] Could not start PowerShell: " + $_.Exception.Message)
        Show-LordZMessage `
            -Message $_.Exception.Message `
            -Title '[LORDZ] Run Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
}

function Invoke-LordZCopyGeneratedMirrorScript {
    $package = $script:LastGeneratedPackage
    if (-not $package -or -not $package.RunnerContent) {
        $package = Invoke-LordZGenerateMirrorScript -Grid $script:QueueGrid -TxtAppId $script:TxtAppId -TxtSteamUsername $script:TxtSteamUsername
        if (-not $package) { return }
    }

    try {
        [System.Windows.Forms.Clipboard]::SetText($package.RunnerContent)
        Write-LordZLog '[OK] Runner script copied to clipboard.'
        Write-LordZLog "[*] Or run the saved file: $($package.RunnerPath)"
    }
    catch {
        Write-LordZLog ("[!] Clipboard copy failed: " + $_.Exception.Message)
        Show-LordZMessage `
            -Message ("Could not copy to clipboard. Open this file instead:`n`n" + $package.RunnerPath) `
            -Title '[LORDZ] Copy Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

function Start-LordZMirrorPipelineAsync {
    param(
        [Parameter(Mandatory)]$Payload
    )

    Stop-LordZMirrorAsyncJob

    Start-LordZHostedSteamConsole -SteamCmdPath $Payload.SteamCmdPath
    Set-LordZSteamConsoleInputEnabled $true

    Write-LordZLog '[*] Preparing mirror batch for the in-app SteamCMD console...'
    Write-LordZLog '[*] When SteamCMD asks to log in, type in the bar below and press Enter.'

    try {
        $prep = Prepare-LordZMirrorPipeline `
            -SteamCmdPath $Payload.SteamCmdPath `
            -SteamCmdDir $Payload.SteamCmdDir `
            -AppId $Payload.AppId `
            -Username $Payload.Username `
            -Password $Payload.Password `
            -UsedQrAuth:([bool]$Payload.UsedQrAuth) `
            -SteamGuardCode $Payload.SteamGuardCode `
            -MirrorQueue $Payload.MirrorQueue `
            -InteractiveConsole

        Sync-LordZPipelineLogHub
        [System.Windows.Forms.Application]::DoEvents()

        if (-not $prep -or -not $prep.Success) {
            Set-LordZBusy $false
            Complete-LordZMirrorAsyncJob -PipelineResult $prep -ErrorRecord $null
            return
        }

        Start-LordZMirrorPipelineOnHostedConsole -Prep $prep -Payload $Payload
        Start-LordZMirrorAsyncTimer
    }
    catch {
        Set-LordZBusy $false
        Complete-LordZMirrorAsyncJob -PipelineResult $null -ErrorRecord $_
    }
}

function Register-LordZWorkerLogging {
    param($Worker)

    $Worker.WorkerReportsProgress = $true
    [void]$Worker.add_ProgressChanged({
        param($sender, $e)
        if ($null -eq $e.UserState) { return }
        $text = [string]$e.UserState
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        if ($e.ProgressPercentage -eq 1) {
            Write-LordZLogRaw $text
        }
        else {
            Write-LordZLog $text
        }
    })
}

function New-LordZWorkerLogAction {
    param(
        $Sender,
        [switch]$Raw
    )

    if ($Raw) {
        return {
            param($Line)
            $Sender.ReportProgress(1, $Line)
        }
    }

    return {
        param($Line)
        $Sender.ReportProgress(0, $Line)
    }
}

function Flush-LordZLogBuffer {
    if (-not $script:LogBox -or $script:LordZLogBuffer.Count -eq 0) { return }
    foreach ($line in $script:LordZLogBuffer) {
        Write-LordZLogRaw $line
    }
    $script:LordZLogBuffer.Clear()
}

function Start-LordZWorker {
    param(
        [scriptblock]$Work,
        [scriptblock]$Completed
    )

    $worker = New-Object System.ComponentModel.BackgroundWorker
    [void]$worker.add_DoWork({
        param($sender, $e)
        $threadRunspace = $null
        try {
            $threadRunspace = Enter-LordZWorkerRunspace
            & $Work $sender $e
        }
        finally {
            Exit-LordZWorkerRunspace $threadRunspace
        }
    })
    if ($Completed) { [void]$worker.add_RunWorkerCompleted($Completed) }
    [void]$worker.RunWorkerAsync()
}

function Set-LordZSplitConstraints {
    param(
        [System.Windows.Forms.SplitContainer]$Split,
        [int]$Panel1Min,
        [int]$Panel2Min,
        [int]$PreferredDistance
    )

    if (-not $Split -or -not $Split.IsHandleCreated) { return }

    $total = if ($Split.Orientation -eq 'Horizontal') { $Split.Height } else { $Split.Width }
    if ($total -le 0) { return }

    $required = $Panel1Min + $Panel2Min + $Split.SplitterWidth + 1
    if ($total -lt $required) { return }

    $Split.Panel1MinSize = 25
    $Split.Panel2MinSize = 25

    $maxDistance = $total - $Panel2Min - $Split.SplitterWidth
    if ($maxDistance -lt $Panel1Min) { return }

    $distance = [Math]::Max($Panel1Min, [Math]::Min($PreferredDistance, $maxDistance))

    if ($Split.Panel1MinSize -gt $distance) { $Split.Panel1MinSize = 25 }
    if ($Split.Panel2MinSize -gt ($total - $distance - $Split.SplitterWidth)) { $Split.Panel2MinSize = 25 }

    if ($Split.SplitterDistance -ne $distance) {
        $Split.SplitterDistance = $distance
    }
    if ($Split.Panel1MinSize -ne $Panel1Min) {
        $Split.Panel1MinSize = $Panel1Min
    }
    if ($Split.Panel2MinSize -ne $Panel2Min) {
        $Split.Panel2MinSize = $Panel2Min
    }
}

function Set-LordZBusy {
    param([bool]$IsBusy)

    if (-not $script:MainForm) { return }

    $busyState = $IsBusy
    try {
        Invoke-LordZOnUiThread -Action {
            $script:BtnVerifyApp.Enabled = -not $busyState
            if ($script:BtnGenerateScript) { $script:BtnGenerateScript.Enabled = -not $busyState }
            if ($script:BtnRunScript) {
                $script:BtnRunScript.Enabled = (-not $busyState) -and [bool]$script:LastGeneratedPackage
            }
            if ($script:BtnCopyScript) {
                $script:BtnCopyScript.Enabled = (-not $busyState) -and [bool]$script:LastGeneratedPackage
            }
            $script:BtnAddQueue.Enabled = -not $busyState
            if ($script:BtnInstallSteamCmd) { $script:BtnInstallSteamCmd.Enabled = -not $busyState }
            if ($script:BtnSteamCmdStop) {
                $script:BtnSteamCmdStop.Enabled = [bool]$script:SteamCmdConsoleSession
            }
            if ($busyState -and $script:TxtSteamCmdInput) {
                $script:TxtSteamCmdInput.Enabled = $true
                if ($script:BtnSteamCmdSend) { $script:BtnSteamCmdSend.Enabled = $true }
            }
            if (-not $busyState) {
                Update-LordZDiscordPanel
            }
            else {
                if ($script:BtnDiscordOpen) { $script:BtnDiscordOpen.Enabled = $false }
                if ($script:BtnDiscordChat) { $script:BtnDiscordChat.Enabled = $false }
                if ($script:BtnDiscordSend) { $script:BtnDiscordSend.Enabled = $false }
            }
            if ($script:StatusLabel) {
                $script:StatusLabel.Text = if ($busyState) {
                    'STATUS: THE OMNISSIAH''S RITE PROCEEDS...'
                } else {
                    'STATUS: IN REMEMBRANCE, STAND READY'
                }
                $script:StatusLabel.ForeColor = if ($busyState) { $script:LordZFlame.EmberLine } else { $script:LordZFlame.AccentHot }
            }
        }
    }
    catch {
        Write-LordZCrashLog ('Set-LordZBusy failed: ' + $_.Exception.Message)
    }
}

function Write-LordZAsciiBannerToLog {
    $banner = Get-LordZAsciiBanner -InstallRoot $script:InstallRoot
    foreach ($line in ($banner -split "`r?`n")) {
        $trimmed = $line.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        Write-LordZLogRaw $trimmed
    }
}

function Show-LordZMirrorLoginDialog {
    param([string]$DefaultUsername = '')

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '[ LORD ZOLTON ] Steam Login'
    $dialog.ClientSize = New-Object System.Drawing.Size(460, 300)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:LordZFlame.BgPanel
    $dialog.ForeColor = $script:LordZFlame.TextPrimary
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $bannerBox = New-Object System.Windows.Forms.TextBox
    $bannerBox.Multiline = $true
    $bannerBox.ReadOnly = $true
    $bannerBox.BorderStyle = 'None'
    $bannerBox.BackColor = $script:LordZFlame.BgPanel
    $bannerBox.ForeColor = $script:LordZFlame.AccentHot
    $bannerBox.Font = New-Object System.Drawing.Font('Consolas', 7.5)
    $bannerBox.Dock = 'Top'
    $bannerBox.Height = 108
    $bannerBox.ScrollBars = 'None'
    $bannerBox.Text = Get-LordZAsciiBanner -InstallRoot $script:InstallRoot

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Enter your Steam password. Username comes from Core Configuration.'
    $intro.Dock = 'Top'
    $intro.Height = 28
    $intro.Padding = New-Object System.Windows.Forms.Padding(14, 6, 14, 0)
    $intro.ForeColor = $script:LordZFlame.TextMuted

    $userTable = New-Object System.Windows.Forms.TableLayoutPanel
    $userTable.Dock = 'Top'
    $userTable.Height = 72
    $userTable.ColumnCount = 2
    $userTable.RowCount = 2
    $userTable.Padding = New-Object System.Windows.Forms.Padding(14, 4, 14, 0)
    [void]$userTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 92))
    [void]$userTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))

    $lblUser = New-LordZFieldLabel -Text 'Username'
    $txtUser = New-LordZTextBox
    if (-not [string]::IsNullOrWhiteSpace($DefaultUsername)) {
        $txtUser.Text = $DefaultUsername
    }
    $lblPass = New-LordZFieldLabel -Text 'Password'
    $txtPass = New-LordZTextBox
    $txtPass.UseSystemPasswordChar = $true
    [void]$userTable.Controls.Add($lblUser, 0, 0)
    [void]$userTable.Controls.Add($txtUser, 1, 0)
    [void]$userTable.Controls.Add($lblPass, 0, 1)
    [void]$userTable.Controls.Add($txtPass, 1, 1)

    $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonRow.Dock = 'Bottom'
    $buttonRow.Height = 52
    $buttonRow.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 10)
    $buttonRow.FlowDirection = 'RightToLeft'

    $btnCancel = New-LordZButton -Text 'Cancel' -BackColor $script:LordZFlame.BtnNeutral
    $btnOk = New-LordZButton -Text 'Run Mirror' -BackColor $script:LordZFlame.BtnPrimary
    $btnOk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    [void]$buttonRow.Controls.Add($btnCancel)
    [void]$buttonRow.Controls.Add($btnOk)

    $dialog.Controls.Add($buttonRow)
    $dialog.Controls.Add($userTable)
    $dialog.Controls.Add($intro)
    $dialog.Controls.Add($bannerBox)
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    $btnOk.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtUser.Text.Trim()) -or [string]::IsNullOrWhiteSpace($txtPass.Text)) {
            return
        }
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $btnCancel.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    if ($script:MainForm) {
        [void]$dialog.ShowDialog($script:MainForm)
    }
    else {
        [void]$dialog.ShowDialog()
    }

    if ($dialog.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        $dialog.Dispose()
        return $null
    }

    $user = $txtUser.Text.Trim()
    $pass = $txtPass.Text
    $dialog.Dispose()

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
        return $null
    }

    return [PSCustomObject]@{
        Username = $user
        Password = $pass
    }
}

function Show-LordZSteamGuardDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '[LORDZ] Steam Guard'
    $dialog.ClientSize = New-Object System.Drawing.Size(420, 180)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:LordZFlame.BgPanel
    $dialog.ForeColor = $script:LordZFlame.TextPrimary
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'SteamCMD needs a Steam Guard code. Enter the code from your email or authenticator app.'
    $intro.Dock = 'Top'
    $intro.Height = 56
    $intro.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 0)
    $intro.ForeColor = $script:LordZFlame.TextMuted

    $txtCode = New-LordZTextBox
    $txtCode.Dock = 'Top'
    $txtCode.Margin = New-Object System.Windows.Forms.Padding(14, 10, 14, 0)

    $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonRow.Dock = 'Bottom'
    $buttonRow.Height = 52
    $buttonRow.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 10)
    $buttonRow.FlowDirection = 'RightToLeft'

    $btnCancel = New-LordZButton -Text 'Cancel' -BackColor $script:LordZFlame.BtnNeutral
    $btnOk = New-LordZButton -Text 'Submit Code' -BackColor $script:LordZFlame.BtnPrimary
    $btnOk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    [void]$buttonRow.Controls.Add($btnCancel)
    [void]$buttonRow.Controls.Add($btnOk)

    $dialog.Controls.Add($buttonRow)
    $dialog.Controls.Add($txtCode)
    $dialog.Controls.Add($intro)
    $dialog.AcceptButton = $btnOk
    $dialog.CancelButton = $btnCancel

    $btnCancel.Add_Click({
        $dialog.Tag = $null
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $btnOk.Add_Click({
        $code = $txtCode.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($code)) { return }
        $dialog.Tag = $code
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    [void]$dialog.ShowDialog($script:MainForm)
    return $dialog.Tag
}

function Set-LordZAppStatusLabel {
    param(
        [bool]$Verified,
        [string]$AppName = ''
    )

    if (-not $script:LblAppStatus) { return }

    if ($Verified -and -not [string]::IsNullOrWhiteSpace($AppName)) {
        $script:LblAppStatus.Text = $AppName
        $script:LblAppStatus.ForeColor = $script:LordZFlame.StatusOk
        $script:LblAppStatus.AccessibleDescription = "Verified: $AppName"
    }
    elseif ($Verified) {
        $script:LblAppStatus.Text = 'Verified'
        $script:LblAppStatus.ForeColor = $script:LordZFlame.StatusOk
    }
    else {
        $script:LblAppStatus.Text = 'Not verified'
        $script:LblAppStatus.ForeColor = $script:LordZFlame.StatusWarn
        $script:LblAppStatus.AccessibleDescription = ''
    }
}

function Get-LordZCredentials {
    param(
        $Paths,
        [switch]$AllowInteractiveLogin
    )

    $paths = if ($Paths) { $Paths } else { Get-LordZSteamPaths }
    if (-not $paths) { return $null }

    $cached = Get-LordZSteamCmdCachedAccount -SteamCmdDir $paths.SteamCmdDir
    $settingsUser = if ($lordzSettings) { [string]$lordzSettings.SteamUsername } else { '' }
    $user = if ($cached) {
        $cached.Username
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:SteamLastLoginUsername)) {
        $script:SteamLastLoginUsername
    }
    else {
        $settingsUser
    }

    if ([string]::IsNullOrWhiteSpace($user)) {
        if ($AllowInteractiveLogin) {
            Write-LordZLog '[!] No Steam username saved yet.'
            Write-LordZLog '[*] Type login yourusername yourpassword in the SteamCMD bar below before mirroring.'
            return [PSCustomObject]@{
                Username   = 'steamuser'
                Password   = ''
                UsedQrAuth = $false
            }
        }

        Show-LordZMessage `
            -Message @'
Log in through the SteamCMD console below first.

When SteamCMD is ready, type in the input bar:
  login yourusername yourpassword

Approve Steam Guard on your phone if prompted.
'@ `
            -Title '[LORDZ] Steam Login Required' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-LordZLog '[!] Steam login required. Type login in the SteamCMD bar below when ready.'
        return $null
    }

    if (-not $cached -or -not $cached.HasConnectCache) {
        if ($AllowInteractiveLogin) {
            Write-LordZLog "[!] No cached Steam session for '$user' yet."
            Write-LordZLog '[*] The mirror will run in the SteamCMD console below — log in there when SteamCMD asks.'
            return [PSCustomObject]@{
                Username   = $user
                Password   = ''
                UsedQrAuth = $false
            }
        }

        Show-LordZMessage `
            -Message @"
SteamCMD does not have a cached session for '$user' yet.

Use the console bar below and type:
  login $user yourpassword

Then click Generate Script again.
"@ `
            -Title '[LORDZ] Steam Login Required' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-LordZLog '[!] Log in via the SteamCMD bar below, then retry.'
        return $null
    }

    $script:SteamSessionReady = $true
    $script:SteamLastLoginUsername = $user

    return [PSCustomObject]@{
        Username   = $user
        Password   = ''
        UsedQrAuth = $false
    }
}

function Show-LordZSteamQrLoginDialog {
    if (-not $script:SteamQrDebugConnected) {
        $qrDebug = Connect-LordZSteamQrDebugBackend -BaseUrl 'http://127.0.0.1:8787'
        if ($qrDebug.Connected) {
            $script:SteamQrDebugConnected = $true
            Write-LordZLog "[OK] $($qrDebug.Message)"
        }
    }

    $start = Start-LordZSteamQrLogin
    if (-not $start.Success) {
        Show-LordZMessage `
            -Message ("Could not start Steam QR login.`n`n$($start.Message)") `
            -Title '[LORDZ] QR Login' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '[LORDZ] Steam QR Login'
    $dialog.ClientSize = New-Object System.Drawing.Size(420, 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:LordZFlame.BgPanel
    $dialog.ForeColor = $script:LordZFlame.TextPrimary
    $dialog.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $dialog.Tag = @{
        ClientId     = $start.ClientId
        RequestId    = $start.RequestId
        ChallengeUrl = $start.ChallengeUrl
        PollInterval = $start.PollInterval
        Canceled     = $false
        Polling      = $false
        Result       = $null
    }

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Open the Steam mobile app, tap the camera / QR icon, scan this code, then approve the sign-in request.'
    $intro.Dock = 'Top'
    $intro.Height = 58
    $intro.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 0)
    $intro.ForeColor = $script:LordZFlame.TextMuted

    $statusLine = New-Object System.Windows.Forms.Label
    $statusLine.Text = 'Waiting for scan...'
    $statusLine.Dock = 'Bottom'
    $statusLine.Height = 34
    $statusLine.Padding = New-Object System.Windows.Forms.Padding(14, 6, 14, 0)
    $statusLine.ForeColor = $script:LordZFlame.AccentHot
    $statusLine.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)

    $qrPanel = New-Object System.Windows.Forms.Panel
    $qrPanel.Dock = 'Fill'
    $qrPanel.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
    $qrPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 8, 5)

    $qrPicture = New-Object System.Windows.Forms.PictureBox
    $qrPicture.SizeMode = 'Zoom'
    $qrPicture.Dock = 'Fill'
    $qrPicture.BackColor = [System.Drawing.Color]::White
    $qrPanel.Controls.Add($qrPicture)

    $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonRow.Dock = 'Bottom'
    $buttonRow.Height = 52
    $buttonRow.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 10)
    $buttonRow.FlowDirection = 'RightToLeft'
    $buttonRow.WrapContents = $false

    $btnCancelQr = New-LordZButton -Text 'Cancel' -BackColor $script:LordZFlame.BtnNeutral
    $btnOpenQr = New-LordZButton -Text 'Open in Browser' -BackColor $script:LordZFlame.BtnSecondary
    $btnCancelQr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    $btnOpenQr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    [void]$buttonRow.Controls.Add($btnCancelQr)
    [void]$buttonRow.Controls.Add($btnOpenQr)

    $dialog.Controls.Add($qrPanel)
    $dialog.Controls.Add($buttonRow)
    $dialog.Controls.Add($statusLine)
    $dialog.Controls.Add($intro)
    $dialog.CancelButton = $btnCancelQr

    $setQrImage = {
        param([string]$ChallengeUrl)
        try {
            $image = Get-LordZSteamQrCodeImage -ChallengeUrl $ChallengeUrl -Size 260
            if ($qrPicture.Image) {
                $qrPicture.Image.Dispose()
            }
            $qrPicture.Image = $image
        }
        catch {
            $statusLine.Text = 'Could not render QR image. Use Open in Browser.'
            Write-LordZLog ("[!] QR image render failed: " + $_.Exception.Message)
        }
    }

    & $setQrImage $start.ChallengeUrl

    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = [Math]::Max(1500, [int]($start.PollInterval * 1000))

    $pollWorker = New-Object System.ComponentModel.BackgroundWorker

    [void]$pollWorker.add_DoWork({
        param($sender, $e)
        $threadRunspace = $null
        try {
            $threadRunspace = Enter-LordZWorkerRunspace
            $state = $e.Argument
            $e.Result = Get-LordZSteamQrPollStatus -ClientId $state.ClientId -RequestId $state.RequestId
        }
        finally {
            Exit-LordZWorkerRunspace $threadRunspace
        }
    })

    [void]$pollWorker.add_RunWorkerCompleted({
        param($sender, $e)
        if ($dialog.Tag.Canceled) { return }

        $dialog.Tag.Polling = $false
        if ($e.Error) {
            $statusLine.Text = 'Poll error - retrying...'
            Write-LordZLog ("[!] Steam QR poll failed: " + $e.Error.Message)
            return
        }

        $poll = $e.Result
        if (-not $poll.Success) {
            $shortError = if ($poll.Message.Length -gt 72) { $poll.Message.Substring(0, 72) + '...' } else { $poll.Message }
            $statusLine.Text = "Poll error - retrying... ($shortError)"
            Write-LordZLog ("[!] Steam QR poll failed: $($poll.Message)")
            return
        }

        if ($poll.NewClientId -and [uint64]$poll.NewClientId -ne [uint64]$dialog.Tag.ClientId) {
            $dialog.Tag.ClientId = [uint64]$poll.NewClientId
            Write-LordZLog '[*] Steam QR session rotated client ID after mobile interaction.'
        }

        if (-not [string]::IsNullOrWhiteSpace($poll.NewChallengeUrl) -and $poll.NewChallengeUrl -ne $dialog.Tag.ChallengeUrl) {
            $dialog.Tag.ChallengeUrl = $poll.NewChallengeUrl
            & $setQrImage $poll.NewChallengeUrl
            $statusLine.Text = 'QR code refreshed. Scan the new code.'
            Write-LordZLog '[*] Steam refreshed the QR challenge URL.'
        }

        if ($poll.RemoteInteraction -and -not $poll.Complete) {
            $statusLine.Text = 'Code scanned. Approve the login on your phone...'
        }

        if ($poll.Complete) {
            $pollTimer.Stop()
            $dialog.Tag.Result = [PSCustomObject]@{
                AccountName  = $poll.AccountName
                RefreshToken = $poll.RefreshToken
            }
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
    })

    $requestPoll = {
        if ($dialog.Tag.Canceled -or $dialog.Tag.Polling -or $pollWorker.IsBusy) { return }
        $dialog.Tag.Polling = $true
        [void]$pollWorker.RunWorkerAsync([PSCustomObject]@{
            ClientId  = [uint64]$dialog.Tag.ClientId
            RequestId = [byte[]]$dialog.Tag.RequestId
        })
    }

    [void]$pollTimer.add_Tick($requestPoll)
    [void]$dialog.add_FormClosed({
        $dialog.Tag.Canceled = $true
        $pollTimer.Stop()
        $loginTimeout.Stop()
        if ($qrPicture.Image) {
            $qrPicture.Image.Dispose()
            $qrPicture.Image = $null
        }
    })

    $btnCancelQr.Add_Click({
        $dialog.Tag.Canceled = $true
        $pollTimer.Stop()
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $btnOpenQr.Add_Click({
        try {
            Start-Process $dialog.Tag.ChallengeUrl
        }
        catch {
            Show-LordZMessage `
                -Message ("Could not open the QR link.`n`n$($_.Exception.Message)") `
                -Title '[LORDZ] QR Login' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })

    $loginTimeout = New-Object System.Windows.Forms.Timer
    $loginTimeout.Interval = 120000
    [void]$loginTimeout.add_Tick({
        if ($dialog.Tag.Canceled) { return }
        $dialog.Tag.Canceled = $true
        $pollTimer.Stop()
        $loginTimeout.Stop()
        Show-LordZMessage `
            -Message 'Steam QR login timed out. Start a new QR session and try again.' `
            -Title '[LORDZ] QR Login' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })
    [void]$dialog.add_Shown({
        $pollTimer.Start()
        $loginTimeout.Start()
        & $requestPoll
    })

    [void]$dialog.ShowDialog($script:MainForm)
    return $dialog.Tag.Result
}

function Get-LordZSteamPaths {
    $path = $script:TxtSteamCmdPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        Show-LordZMessage `
            -Message 'Set the path to steamcmd.exe first.' `
            -Title '[LORDZ] Configuration' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $null
    }

    $check = Test-LordZSteamCmdPath -SteamCmdPath $path
    if (-not $check.Valid) {
        Write-LordZLog $check.Message
        Show-LordZMessage `
            -Message $check.Message `
            -Title '[LORDZ] Critical Error' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
        return $null
    }

    return [PSCustomObject]@{
        SteamCmdPath = $path
        SteamCmdDir  = Split-Path -Parent $path
    }
}

Set-LordZSplashStatus 'Constructing workspace...'

$form = New-Object System.Windows.Forms.Form
$form.Text = '[ LORDZ ] Zolton Mirror Core Engine'
$form.ClientSize = New-Object System.Drawing.Size(1280, 860)
$form.MinimumSize = New-Object System.Drawing.Size(1024, 720)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:LordZFlame.BgDeep
$form.ForeColor = $script:LordZFlame.TextPrimary
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 88
Set-LordZFlamePanel -Control $header -Variant Inferno

$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.Dock = 'Bottom'
$statusBar.BackColor = [System.Drawing.Color]::FromArgb(14, 6, 3)
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'STATUS: IN REMEMBRANCE, STAND READY'
$statusLabel.ForeColor = $script:LordZFlame.AccentHot
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
[void]$statusBar.Items.Add($statusLabel)

$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Dock = 'Fill'
$mainSplit.Orientation = 'Horizontal'
$mainSplit.Panel1MinSize = 25
$mainSplit.Panel2MinSize = 25
$mainSplit.BackColor = $script:LordZFlame.BgDeep

$topSplit = New-Object System.Windows.Forms.SplitContainer
$topSplit.Dock = 'Fill'
$topSplit.Orientation = 'Vertical'
$topSplit.Panel1MinSize = 25
$topSplit.Panel2MinSize = 25
$topSplit.BackColor = $script:LordZFlame.BgDeep

foreach ($panel in @($mainSplit.Panel1, $mainSplit.Panel2, $topSplit.Panel1, $topSplit.Panel2)) {
    $panel.BackColor = $script:LordZFlame.BgDeep
}

function Sync-LordZLayout {
    if ($script:LordZLayoutSyncInProgress) { return }
    if (-not $script:MainForm -or -not $script:MainForm.IsHandleCreated) { return }

    $script:LordZLayoutSyncInProgress = $true
    try {
        Set-LordZSplitConstraints `
            -Split $script:TopSplit `
            -Panel1Min 340 `
            -Panel2Min 340 `
            -PreferredDistance ([int]($script:TopSplit.Width * 0.5))

        Set-LordZSplitConstraints `
            -Split $script:MainSplit `
            -Panel1Min 400 `
            -Panel2Min 160 `
            -PreferredDistance ([int]($script:MainSplit.Height * 0.72))

        if ($script:LogActionSplit -and $script:LogActionSplit.IsHandleCreated) {
            Set-LordZSplitConstraints `
                -Split $script:LogActionSplit `
                -Panel1Min 160 `
                -Panel2Min $script:LogActionSplit.Panel2MinSize `
                -PreferredDistance ($script:LogActionSplit.Height - $script:ActionPanel.Height - $script:LogActionSplit.SplitterWidth)
        }
    }
    catch {
        Write-LordZCrashLog ('Layout sync failed: ' + $_.Exception.Message)
    }
    finally {
        $script:LordZLayoutSyncInProgress = $false
    }
}

function Request-LordZLayoutSync {
    if (-not $script:MainForm -or -not $script:MainForm.IsHandleCreated) { return }

    if (-not $script:LordZLayoutResizeTimer) {
        $script:LordZLayoutResizeTimer = New-Object System.Windows.Forms.Timer
        $script:LordZLayoutResizeTimer.Interval = 120
        [void]$script:LordZLayoutResizeTimer.Add_Tick({
            $script:LordZLayoutResizeTimer.Stop()
            Sync-LordZLayout
        })
    }

    $script:LordZLayoutResizeTimer.Stop()
    $script:LordZLayoutResizeTimer.Start()
}

function New-LordZGroup {
    param(
        [string]$Title,
        [System.Windows.Forms.Control]$Parent
    )

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Dock = 'Fill'
    $outer.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 12)
    $outer.BackColor = $script:LordZFlame.BgPanel
    $Parent.Controls.Add($outer)
    Set-LordZFlamePanel -Control $outer -Variant Ember

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = 'Fill'
    $content.Padding = New-Object System.Windows.Forms.Padding(12, 6, 8, 6)
    $content.BackColor = [System.Drawing.Color]::Transparent

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Title
    $label.Dock = 'Top'
    $label.Height = 36
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $label.ForeColor = $script:LordZFlame.AccentHot
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 4)

    $outer.Controls.Add($content)
    $outer.Controls.Add($label)

    return $content
}

function New-LordZInputTable {
    param(
        [int]$RowCount,
        [int]$LabelWidth = 172,
        [int]$ExtraColumnWidth = 118,
        [int]$RowHeight = 48,
        [int[]]$RowHeights
    )

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = 'Top'
    $table.AutoSize = $true
    $table.AutoSizeMode = 'GrowAndShrink'
    $table.ColumnCount = 3
    $table.RowCount = $RowCount
    $table.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 6)
    $table.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$table.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, $LabelWidth))
    [void]$table.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$table.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, $ExtraColumnWidth))

    for ($i = 0; $i -lt $RowCount; $i++) {
        $height = if ($RowHeights -and $i -lt $RowHeights.Count) { $RowHeights[$i] } else { $RowHeight }
        [void]$table.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, $height))
    }

    return $table
}

function New-LordZFieldLabel {
    param([string]$Text)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleLeft'
    $lbl.ForeColor = $script:LordZFlame.TextMuted
    $lbl.Margin = New-Object System.Windows.Forms.Padding(4, 0, 10, 0)
    $lbl.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    return $lbl
}

function New-LordZTextBox {
    param([switch]$IsPassword)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Dock = 'Fill'
    $box.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
    $box.MinimumSize = New-Object System.Drawing.Size(0, 32)
    $box.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $box.BackColor = $script:LordZFlame.BgInput
    $box.ForeColor = $script:LordZFlame.TextPrimary
    $box.BorderStyle = 'FixedSingle'
    if ($IsPassword) { $box.UseSystemPasswordChar = $true }
    return $box
}

function New-LordZButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [switch]$FillCell
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = $BackColor
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(255, 240, 220)
    $btn.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
    $btn.MinimumSize = New-Object System.Drawing.Size(120, 36)
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btn.FlatAppearance.BorderColor = $script:LordZFlame.AccentHot
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $BackColor.R + 35),
        [Math]::Min(255, $BackColor.G + 20),
        [Math]::Min(255, $BackColor.B + 8)
    )
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(95, 18, 0)
    if ($FillCell) { $btn.Dock = 'Fill' }
    return $btn
}

$configPanel = New-LordZGroup -Title 'CORE CONFIGURATION' -Parent $topSplit.Panel1
$queuePanel = New-LordZGroup -Title 'MIRROR QUEUE' -Parent $topSplit.Panel2

$configTable = New-LordZInputTable -RowCount 4 -ExtraColumnWidth 168 -RowHeights @(48, 48, 48, 42)

$configTable.Controls.Add((New-LordZFieldLabel -Text 'SteamCMD Path'), 0, 0)
$txtSteamCmdPath = New-LordZTextBox
$txtSteamCmdPath.Text = $lordzSettings.SteamCmdPath
$configTable.Controls.Add($txtSteamCmdPath, 1, 0)
$btnBrowseSteam = New-LordZButton -Text '...' -BackColor $script:LordZFlame.BtnNeutral -FillCell
$configTable.Controls.Add($btnBrowseSteam, 2, 0)

$configTable.Controls.Add((New-LordZFieldLabel -Text 'Steam Username'), 0, 1)
$txtSteamUsername = New-LordZTextBox
$txtSteamUsername.Text = $lordzSettings.SteamUsername
$configTable.Controls.Add($txtSteamUsername, 1, 1)
$lblSteamUserHint = New-Object System.Windows.Forms.Label
$lblSteamUserHint.Text = 'Saved locally'
$lblSteamUserHint.Dock = 'Fill'
$lblSteamUserHint.TextAlign = 'MiddleLeft'
$lblSteamUserHint.ForeColor = $script:LordZFlame.TextMuted
$lblSteamUserHint.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lblSteamUserHint.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 6)
$configTable.Controls.Add($lblSteamUserHint, 2, 1)

$configTable.Controls.Add((New-LordZFieldLabel -Text 'App ID'), 0, 2)
$txtAppId = New-LordZTextBox
$txtAppId.Text = $lordzSettings.AppId
$configTable.Controls.Add($txtAppId, 1, 2)
$lblAppStatus = New-Object System.Windows.Forms.Label
$lblAppStatus.Text = 'Not verified'
$lblAppStatus.Dock = 'Fill'
$lblAppStatus.TextAlign = 'MiddleLeft'
$lblAppStatus.AutoEllipsis = $true
$lblAppStatus.ForeColor = $script:LordZFlame.StatusWarn
$lblAppStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$lblAppStatus.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 6)
$configTable.Controls.Add($lblAppStatus, 2, 2)

$btnVerifyApp = New-LordZButton -Text 'Verify App ID' -BackColor $script:LordZFlame.BtnSecondary -FillCell
$configTable.Controls.Add($btnVerifyApp, 1, 3)
$configTable.SetColumnSpan($btnVerifyApp, 2)

$steamInstallPanel = New-Object System.Windows.Forms.Panel
$steamInstallPanel.Dock = 'Top'
$steamInstallPanel.AutoSize = $true
$steamInstallPanel.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 10)
$steamInstallPanel.Margin = New-Object System.Windows.Forms.Padding(0)

$steamInstallTable = New-Object System.Windows.Forms.TableLayoutPanel
$steamInstallTable.Dock = 'Top'
$steamInstallTable.AutoSize = $true
$steamInstallTable.AutoSizeMode = 'GrowAndShrink'
$steamInstallTable.ColumnCount = 2
$steamInstallTable.RowCount = 2
$steamInstallTable.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$steamInstallTable.BackColor = [System.Drawing.Color]::FromArgb(22, 10, 6)
$steamInstallTable.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$steamInstallTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 172))
[void]$steamInstallTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$steamInstallTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 28))
[void]$steamInstallTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 48))

$lblSteamInstallTitle = New-LordZFieldLabel -Text 'SteamCMD Setup'
$lblSteamInstallTitle.ForeColor = $script:LordZFlame.AccentHot
$lblSteamInstallTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$steamInstallTable.Controls.Add($lblSteamInstallTitle, 0, 0)
$steamInstallTable.SetColumnSpan($lblSteamInstallTitle, 2)

$lblSteamInstallTarget = New-Object System.Windows.Forms.Label
$lblSteamInstallTarget.Text = 'Install folder: .\steamcmd\  (beside this app)'
$lblSteamInstallTarget.Dock = 'Fill'
$lblSteamInstallTarget.TextAlign = 'MiddleLeft'
$lblSteamInstallTarget.ForeColor = $script:LordZFlame.TextMuted
$lblSteamInstallTarget.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lblSteamInstallTarget.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$steamInstallTable.Controls.Add($lblSteamInstallTarget, 0, 1)

$btnInstallSteamCmd = New-LordZButton -Text "Download & Install SteamCMD" -BackColor $script:LordZFlame.BtnSecondary -FillCell
$steamInstallTable.Controls.Add($btnInstallSteamCmd, 1, 1)

$steamInstallPanel.Controls.Add($steamInstallTable)

$discordPanel = New-Object System.Windows.Forms.Panel
$discordPanel.Dock = 'Top'
$discordPanel.AutoSize = $true
$discordPanel.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 6)
$discordPanel.Margin = New-Object System.Windows.Forms.Padding(0)

$discordTable = New-Object System.Windows.Forms.TableLayoutPanel
$discordTable.Dock = 'Top'
$discordTable.AutoSize = $true
$discordTable.AutoSizeMode = 'GrowAndShrink'
$discordTable.ColumnCount = 2
$discordTable.RowCount = 3
$discordTable.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$discordTable.BackColor = [System.Drawing.Color]::FromArgb(22, 10, 6)
$discordTable.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$discordTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 172))
[void]$discordTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$discordTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 28))
[void]$discordTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 28))
[void]$discordTable.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 44))

$lblDiscordTitle = New-LordZFieldLabel -Text 'Discord Support'
$lblDiscordTitle.ForeColor = $script:LordZFlame.AccentHot
$lblDiscordTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$discordTable.Controls.Add($lblDiscordTitle, 0, 0)
$discordTable.SetColumnSpan($lblDiscordTitle, 2)

$lblDiscordStatus = New-Object System.Windows.Forms.Label
$lblDiscordStatus.Text = 'Loading...'
$lblDiscordStatus.Dock = 'Fill'
$lblDiscordStatus.TextAlign = 'MiddleLeft'
$lblDiscordStatus.ForeColor = $script:LordZFlame.TextMuted
$lblDiscordStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lblDiscordStatus.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$discordTable.Controls.Add($lblDiscordStatus, 0, 1)
$discordTable.SetColumnSpan($lblDiscordStatus, 2)

$discordButtonRow = New-Object System.Windows.Forms.FlowLayoutPanel
$discordButtonRow.Dock = 'Fill'
$discordButtonRow.AutoSize = $false
$discordButtonRow.WrapContents = $false
$discordButtonRow.Margin = New-Object System.Windows.Forms.Padding(0)
$discordButtonRow.Padding = New-Object System.Windows.Forms.Padding(0)
$btnDiscordOpen = New-LordZButton -Text 'Open Help Channel' -BackColor $script:LordZFlame.BtnSecondary
$btnDiscordChat = New-LordZButton -Text 'Live Help Chat' -BackColor $script:LordZFlame.BtnPrimary
$btnDiscordSend = New-LordZButton -Text 'Quick Request' -BackColor $script:LordZFlame.BtnNeutral
$btnDiscordOpen.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$btnDiscordChat.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
[void]$discordButtonRow.Controls.Add($btnDiscordOpen)
[void]$discordButtonRow.Controls.Add($btnDiscordChat)
[void]$discordButtonRow.Controls.Add($btnDiscordSend)
$discordTable.Controls.Add($discordButtonRow, 0, 2)
$discordTable.SetColumnSpan($discordButtonRow, 2)

$discordPanel.Controls.Add($discordTable)

$lordzDisclaimer = New-Object System.Windows.Forms.Label
$lordzDisclaimer.Text = 'Disclaimer: You must obtain permission from the original mod author before mirroring Workshop content. Any legal liability arising from such use rests solely with you.'
$lordzDisclaimer.Dock = 'Bottom'
$lordzDisclaimer.Height = 56
$lordzDisclaimer.ForeColor = $script:LordZFlame.TextMuted
$lordzDisclaimer.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lordzDisclaimer.Padding = New-Object System.Windows.Forms.Padding(6, 10, 6, 0)

$configPanel.Controls.Add($discordPanel)
$configPanel.Controls.Add($steamInstallPanel)
$configPanel.Controls.Add($configTable)
$configPanel.Controls.Add($lordzDisclaimer)

Set-LordZSplashStatus 'Assembling mirror queue...'

$queueTable = New-LordZInputTable -RowCount 5 -ExtraColumnWidth 168 -RowHeights @(48, 48, 48, 48, 52)

$queueTable.Controls.Add((New-LordZFieldLabel -Text 'Original Mod ID'), 0, 0)
$txtSourceModId = New-LordZTextBox
$queueTable.Controls.Add($txtSourceModId, 1, 0)
$queueTable.SetColumnSpan($txtSourceModId, 2)

$queueTable.Controls.Add((New-LordZFieldLabel -Text 'Mirror Name'), 0, 1)
$txtMirrorName = New-LordZTextBox
$queueTable.Controls.Add($txtMirrorName, 1, 1)
$queueTable.SetColumnSpan($txtMirrorName, 2)

$queueTable.Controls.Add((New-LordZFieldLabel -Text 'Visibility'), 0, 2)
$cmbVisibility = New-Object System.Windows.Forms.ComboBox
$cmbVisibility.Dock = 'Fill'
$cmbVisibility.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
$cmbVisibility.MinimumSize = New-Object System.Drawing.Size(0, 32)
$cmbVisibility.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$cmbVisibility.DropDownStyle = 'DropDownList'
$cmbVisibility.BackColor = $script:LordZFlame.BgInput
$cmbVisibility.ForeColor = $script:LordZFlame.TextPrimary
[void]$cmbVisibility.Items.AddRange(@(Get-LordZVisibilityLabels))
$cmbVisibility.SelectedIndex = 0
$queueTable.Controls.Add($cmbVisibility, 1, 2)
$queueTable.SetColumnSpan($cmbVisibility, 2)

$queueTable.Controls.Add((New-LordZFieldLabel -Text 'Mirror ID (update)'), 0, 3)
$txtPublishedId = New-LordZTextBox
$txtPublishedId.Text = '0'
$queueTable.Controls.Add($txtPublishedId, 1, 3)
$pubHint = New-Object System.Windows.Forms.Label
$pubHint.Text = 'Use 0 for new mirrors'
$pubHint.Dock = 'Fill'
$pubHint.TextAlign = 'MiddleLeft'
$pubHint.ForeColor = $script:LordZFlame.TextMuted
$pubHint.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$pubHint.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 6)
$queueTable.Controls.Add($pubHint, 2, 3)

$queueButtonRow = New-Object System.Windows.Forms.FlowLayoutPanel
$queueButtonRow.Dock = 'Fill'
$queueButtonRow.AutoSize = $false
$queueButtonRow.WrapContents = $true
$queueButtonRow.Margin = New-Object System.Windows.Forms.Padding(0)
$queueButtonRow.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
$btnGenerateScript = New-LordZButton -Text 'Generate Script' -BackColor $script:LordZFlame.BtnPrimary
$btnGenerateScript.MinimumSize = New-Object System.Drawing.Size(140, 36)
$btnGenerateScript.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$btnRunScript = New-LordZButton -Text 'Run Script' -BackColor $script:LordZFlame.BtnPrimary
$btnRunScript.MinimumSize = New-Object System.Drawing.Size(110, 36)
$btnRunScript.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$btnRunScript.Enabled = $false
$btnCopyScript = New-LordZButton -Text 'Copy Script' -BackColor $script:LordZFlame.BtnSecondary
$btnCopyScript.MinimumSize = New-Object System.Drawing.Size(110, 36)
$btnCopyScript.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$btnCopyScript.Enabled = $false
$btnAddQueue = New-LordZButton -Text 'Add To Queue' -BackColor $script:LordZFlame.BtnSecondary
$btnRemoveQueue = New-LordZButton -Text 'Remove Selected' -BackColor $script:LordZFlame.BtnDanger
$btnAddQueue.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
[void]$queueButtonRow.Controls.Add($btnGenerateScript)
[void]$queueButtonRow.Controls.Add($btnRunScript)
[void]$queueButtonRow.Controls.Add($btnCopyScript)
[void]$queueButtonRow.Controls.Add($btnAddQueue)
[void]$queueButtonRow.Controls.Add($btnRemoveQueue)
$queueTable.Controls.Add($queueButtonRow, 1, 4)
$queueTable.SetColumnSpan($queueButtonRow, 2)

$queueGrid = New-Object System.Windows.Forms.DataGridView
$queueGrid.Dock = 'Fill'
$queueGrid.BackgroundColor = $script:LordZFlame.BgInput
$queueGrid.ForeColor = $script:LordZFlame.TextPrimary
$queueGrid.GridColor = $script:LordZFlame.GridLine
$queueGrid.BorderStyle = 'None'
$queueGrid.RowHeadersVisible = $false
$queueGrid.AllowUserToAddRows = $false
$queueGrid.ReadOnly = $true
$queueGrid.SelectionMode = 'FullRowSelect'
$queueGrid.AutoSizeColumnsMode = 'Fill'
$queueGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$queueGrid.ColumnHeadersHeight = 36
$queueGrid.RowTemplate.Height = 32
$queueGrid.DefaultCellStyle.BackColor = $script:LordZFlame.BgInput
$queueGrid.DefaultCellStyle.ForeColor = $script:LordZFlame.TextPrimary
$queueGrid.DefaultCellStyle.SelectionBackColor = $script:LordZFlame.SelectRow
$queueGrid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(255, 245, 230)
$queueGrid.DefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$queueGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(48, 20, 8)
$queueGrid.ColumnHeadersDefaultCellStyle.ForeColor = $script:LordZFlame.AccentHot
$queueGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$queueGrid.EnableHeadersVisualStyles = $false
[void]$queueGrid.Columns.Add('SourceModId', 'Source Mod ID')
[void]$queueGrid.Columns.Add('MirrorName', 'Mirror Name')
[void]$queueGrid.Columns.Add('Visibility', 'Visibility')
[void]$queueGrid.Columns.Add('PublishedFileId', 'Mirror ID')

$queuePanel.Controls.Add($queueGrid)
$queuePanel.Controls.Add($queueTable)

Set-LordZSplashStatus 'Preparing operation log...'

$logPanel = New-LordZGroup -Title 'LORD ZOLTON STEAM CONSOLE' -Parent $mainSplit.Panel2

$lordzBannerPanel = New-Object System.Windows.Forms.Panel
$lordzBannerPanel.Dock = 'Top'
$lordzBannerPanel.Height = 118
$lordzBannerPanel.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 2)
Set-LordZFlamePanel -Control $lordzBannerPanel -Variant Inferno

$lblLordZBanner = New-Object System.Windows.Forms.TextBox
$lblLordZBanner.Dock = 'Fill'
$lblLordZBanner.Multiline = $true
$lblLordZBanner.ReadOnly = $true
$lblLordZBanner.BorderStyle = 'None'
$lblLordZBanner.BackColor = [System.Drawing.Color]::FromArgb(18, 8, 5)
$lblLordZBanner.ForeColor = $script:LordZFlame.AccentHot
$lblLordZBanner.Font = New-Object System.Drawing.Font('Consolas', 7.5)
$lblLordZBanner.ScrollBars = 'None'
$lblLordZBanner.Text = Get-LordZAsciiBanner -InstallRoot $script:InstallRoot
$lordzBannerPanel.Controls.Add($lblLordZBanner)

$steamInputPanel = New-Object System.Windows.Forms.Panel
$steamInputPanel.Dock = 'Bottom'
$steamInputPanel.Height = 42
$steamInputPanel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
Set-LordZFlamePanel -Control $steamInputPanel -Variant Ember

$steamInputTable = New-Object System.Windows.Forms.TableLayoutPanel
$steamInputTable.Dock = 'Fill'
$steamInputTable.ColumnCount = 3
$steamInputTable.RowCount = 1
$steamInputTable.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$steamInputTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 92))
[void]$steamInputTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$steamInputTable.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, 88))

$lblSteamInput = New-Object System.Windows.Forms.Label
$lblSteamInput.Text = 'SteamCMD >'
$lblSteamInput.Dock = 'Fill'
$lblSteamInput.TextAlign = 'MiddleLeft'
$lblSteamInput.ForeColor = $script:LordZFlame.AccentHot
$lblSteamInput.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)

$txtSteamCmdInput = New-LordZTextBox
$txtSteamCmdInput.Font = New-Object System.Drawing.Font('Consolas', 10.5)
$txtSteamCmdInput.Enabled = $false

$btnSteamCmdSend = New-LordZButton -Text 'Enter' -BackColor $script:LordZFlame.BtnPrimary -FillCell
$btnSteamCmdSend.Enabled = $false
$btnSteamCmdSend.MinimumSize = New-Object System.Drawing.Size(72, 30)

$steamInputTable.Controls.Add($lblSteamInput, 0, 0)
$steamInputTable.Controls.Add($txtSteamCmdInput, 1, 0)
$steamInputTable.Controls.Add($btnSteamCmdSend, 2, 0)
$steamInputPanel.Controls.Add($steamInputTable)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = 'Fill'
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::FromArgb(8, 3, 2)
$logBox.ForeColor = $script:LordZFlame.LogText
$logBox.Font = New-Object System.Drawing.Font('Consolas', 10.5)
$logBox.BorderStyle = 'None'
$logPanel.Controls.Add($logBox)
$logPanel.Controls.Add($steamInputPanel)
$logPanel.Controls.Add($lordzBannerPanel)

$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Dock = 'Bottom'
$actionPanel.Height = 52
$actionPanel.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
Set-LordZFlamePanel -Control $actionPanel -Variant Action

$actionFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$actionFlow.Dock = 'Fill'
$actionFlow.WrapContents = $false
$actionFlow.FlowDirection = 'LeftToRight'
$actionPanel.Controls.Add($actionFlow)

$btnClearLog = New-LordZButton -Text 'Clear Log' -BackColor $script:LordZFlame.BtnNeutral
$btnClearLog.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$btnSteamCmdStop = New-LordZButton -Text 'Restart Console' -BackColor $script:LordZFlame.BtnNeutral
$btnSteamCmdStop.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$btnSteamCmdStop.Enabled = $false
$btnClearQueue = New-LordZButton -Text 'Clear Queue' -BackColor $script:LordZFlame.BtnNeutral
[void]$actionFlow.Controls.Add($btnSteamCmdStop)
[void]$actionFlow.Controls.Add($btnClearLog)
[void]$actionFlow.Controls.Add($btnClearQueue)

$logActionSplit = New-Object System.Windows.Forms.SplitContainer
$logActionSplit.Dock = 'Fill'
$logActionSplit.Orientation = 'Horizontal'
$logActionSplit.Panel1MinSize = 25
$logActionSplit.Panel2MinSize = 52
$logActionSplit.FixedPanel = 'Panel2'
$logActionSplit.IsSplitterFixed = $true
$logActionSplit.SplitterWidth = 1
$logActionSplit.Panel1.Controls.Add($logPanel)
$logActionSplit.Panel2.Controls.Add($actionPanel)

$mainSplit.Panel1.Controls.Add($topSplit)
$mainSplit.Panel2.Controls.Add($logActionSplit)

$form.Controls.Add($mainSplit)
$form.Controls.Add($header)
$form.Controls.Add($statusBar)

$script:MainForm = $form
$script:TopSplit = $topSplit
$script:MainSplit = $mainSplit
$script:LogActionSplit = $logActionSplit
$script:ActionPanel = $actionPanel
$script:LogBox = $logBox
$script:LblLordZBanner = $lblLordZBanner
$script:PipelineLogTimer = New-Object System.Windows.Forms.Timer
$script:PipelineLogTimer.Interval = 80
[void]$script:PipelineLogTimer.add_Tick({ Sync-LordZPipelineLogHub })
$script:PipelineLogTimer.Start()
$script:TxtSteamCmdInput = $txtSteamCmdInput
$script:BtnSteamCmdSend = $btnSteamCmdSend
$script:BtnSteamCmdStop = $btnSteamCmdStop
$script:StatusLabel = $statusLabel
$script:TxtSteamCmdPath = $txtSteamCmdPath
$script:TxtSteamUsername = $txtSteamUsername
$script:TxtAppId = $txtAppId
$script:BtnVerifyApp = $btnVerifyApp
$script:BtnGenerateScript = $btnGenerateScript
$script:BtnRunScript = $btnRunScript
$script:BtnCopyScript = $btnCopyScript
$script:BtnAddQueue = $btnAddQueue
$script:QueueGrid = $queueGrid
$script:LastGeneratedPackage = $null
$script:BtnInstallSteamCmd = $btnInstallSteamCmd
$script:BtnDiscordOpen = $btnDiscordOpen
$script:BtnDiscordChat = $btnDiscordChat
$script:BtnDiscordSend = $btnDiscordSend
$script:LblDiscordStatus = $lblDiscordStatus
$script:LblAppStatus = $lblAppStatus
$script:AppIdVerified = $false
$script:VerifiedAppName = ''

Set-LordZSplashStatus 'Wiring controls...'

function Update-LordZSteamInstallButton {
    $targetPath = Get-LordZSteamCmdInstallPath -InstallRoot $script:InstallRoot
    if (Test-Path -LiteralPath $targetPath) {
        $script:BtnInstallSteamCmd.Text = 'Reinstall SteamCMD'
    }
    else {
        $script:BtnInstallSteamCmd.Text = "Download & Install SteamCMD"
    }
}

$btnInstallSteamCmd.Add_Click({
    if ($script:SteamCmdInstallRunning) { return }

    $targetPath = Get-LordZSteamCmdInstallPath -InstallRoot $script:InstallRoot
    $targetDir = Get-LordZSteamCmdInstallDir -InstallRoot $script:InstallRoot

    if (Test-Path -LiteralPath $targetPath) {
        $answer = Show-LordZMessage `
            -Message "SteamCMD already exists at:`n$targetPath`n`nReinstall and replace it?" `
            -Title '[LORDZ] Reinstall SteamCMD' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne 'Yes') { return }
    }

    $script:SteamCmdInstallRunning = $true
    Write-LordZLog '======================================================================'
    Write-LordZLog '[*] PHASE: SteamCMD download and install...'
    Write-LordZLog ("[*] Target folder: " + $targetDir)
    Write-LordZLog '[*] Downloading from Valve CDN - watch this log for progress.'
    if ($script:LogBox) {
        $script:LogBox.Focus()
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
    }

    Set-LordZBusy $true
    $installRoot = $script:InstallRoot

    $worker = New-Object System.ComponentModel.BackgroundWorker
    [void]$worker.add_DoWork({
        param($sender, $e)
        $threadRunspace = $null
        try {
            $threadRunspace = Enter-LordZWorkerRunspace
            $e.Result = Install-LordZSteamCmd `
                -InstallRoot $installRoot `
                -ProgressSender $sender
        }
        catch {
            $e.Result = [PSCustomObject]@{
                Success      = $false
                SteamCmdPath = (Get-LordZSteamCmdInstallPath -InstallRoot $installRoot)
                Message      = $_.Exception.Message
            }
        }
        finally {
            Exit-LordZWorkerRunspace $threadRunspace
        }
    })
    Register-LordZWorkerLogging -Worker $worker
    [void]$worker.add_RunWorkerCompleted({
        param($sender, $e)
        $script:SteamCmdInstallRunning = $false
        Set-LordZBusy $false

        if ($e.Error) {
            Write-LordZLogError $e.Error.Message
            Show-LordZMessage `
                -Message $e.Error.Message `
                -Title '[LORDZ] Install Failed' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
            return
        }

        $result = $e.Result
        if (-not $result) {
            Show-LordZMessage `
                -Message 'SteamCMD install ended without a result. Check the Operation Log.' `
                -Title '[LORDZ] Install Failed' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
            return
        }

        if ($result.Success) {
            $script:TxtSteamCmdPath.Text = $result.SteamCmdPath
            $script:AppIdVerified = $false
            $script:LblAppStatus.Text = 'Not verified'
            $script:LblAppStatus.ForeColor = $script:LordZFlame.StatusWarn
            Save-LordZSettings
            Update-LordZSteamInstallButton
            Write-LordZLog ("[OK] " + $result.Message)
            Start-LordZHostedSteamConsole -SteamCmdPath $result.SteamCmdPath
            Show-LordZMessage `
                -Message ("SteamCMD is ready at:`n" + $result.SteamCmdPath) `
                -Title '[LORDZ] Install Complete' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        else {
            Write-LordZLog ("[!] Install failed: " + $result.Message)
            Show-LordZMessage `
                -Message $result.Message `
                -Title '[LORDZ] Install Failed' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
        }
    })
    [void]$worker.RunWorkerAsync()
})

$btnDiscordOpen.Add_Click({
    $result = Open-LordZDiscordInvite -InstallRoot $script:InstallRoot
    if ($result.Success) {
        Write-LordZLog "[OK] $($result.Message)"
    }
    else {
        Write-LordZLog "[!] $($result.Message)"
        Show-LordZMessage `
            -Message $result.Message `
            -Title '[LORDZ] Discord Help' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
})

$btnDiscordSend.Add_Click({ Show-LordZHelpRequestDialog })
$btnDiscordChat.Add_Click({ Show-LordZHelpChatDialog })

$btnBrowseSteam.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'steamcmd.exe|steamcmd.exe|Executable (*.exe)|*.exe'
    $dialog.Title = 'Locate steamcmd.exe'
    if ($dialog.ShowDialog() -eq 'OK') {
        $txtSteamCmdPath.Text = $dialog.FileName
        $script:AppIdVerified = $false
        $lblAppStatus.Text = 'Not verified'
        $lblAppStatus.ForeColor = $script:LordZFlame.StatusWarn
        Save-LordZSettings
    }
})

$btnAddQueue.Add_Click({
    $sourceId = $txtSourceModId.Text.Trim()
    $mirrorName = $txtMirrorName.Text.Trim()
    $visibility = [string]$cmbVisibility.SelectedItem
    $publishedId = $txtPublishedId.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($publishedId)) { $publishedId = '0' }

    if ([string]::IsNullOrWhiteSpace($sourceId)) {
        Show-LordZMessage `
            -Message 'Original Mod ID is required.' `
            -Title '[LORDZ] Queue' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    if ($sourceId -notmatch '^\d+$') {
        Show-LordZMessage `
            -Message 'Original Mod ID must be numeric.' `
            -Title '[LORDZ] Queue' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $appId = $txtAppId.Text.Trim()
    if ($appId -match '^\d+$') {
        $modCheck = Test-LordZWorkshopModAvailable -PublishedFileId $sourceId -ExpectedAppId $appId
        if (-not $modCheck.Available) {
            Show-LordZMessage `
                -Message $modCheck.Message `
                -Title '[LORDZ] Mod Not Found' `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            Write-LordZLog "[!] $($modCheck.Message)"
            return
        }
        if ([string]::IsNullOrWhiteSpace($mirrorName)) {
            $mirrorName = $modCheck.Title
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($mirrorName)) {
        $mirrorName = 'New Mirror'
    }

    [void]$queueGrid.Rows.Add($sourceId, $mirrorName, $visibility, $publishedId)
    Write-LordZLog "Queued mirror '$mirrorName' from source mod $sourceId ($visibility)."
    $txtSourceModId.Clear()
    $txtMirrorName.Clear()
    $txtPublishedId.Text = '0'
})

$btnRemoveQueue.Add_Click({
    foreach ($row in @($queueGrid.SelectedRows)) {
        if (-not $row.IsNewRow) { [void]$queueGrid.Rows.Remove($row) }
    }
})

$btnClearQueue.Add_Click({
    $queueGrid.Rows.Clear()
    Write-LordZLog 'Mirror queue cleared.'
})

$btnClearLog.Add_Click({ $logBox.Clear() })

$submitSteamCmdInput = {
    $line = $script:TxtSteamCmdInput.Text
    if (Send-LordZSteamCmdConsoleInput -Line $line) {
        $script:TxtSteamCmdInput.Clear()
    }
}

$btnSteamCmdSend.Add_Click($submitSteamCmdInput)

[void]$txtSteamCmdInput.add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        & $submitSteamCmdInput
    }
})

$btnSteamCmdStop.Add_Click({
    Stop-LordZSteamConsoleSession
    $paths = Get-LordZSteamPaths
    if ($paths) {
        Start-LordZHostedSteamConsole -SteamCmdPath $paths.SteamCmdPath
        Write-LordZLog '[*] SteamCMD console restarted.'
    }
    else {
        Write-LordZLog '[!] SteamCMD path is missing or invalid. Set the path above, then click Restart Console.'
    }
    Set-LordZBusy $false
})

$txtAppId.Add_TextChanged({
    $script:AppIdVerified = $false
    $script:VerifiedAppName = ''
    Set-LordZAppStatusLabel -Verified $false
})

$btnVerifyApp.Add_Click({
    $appId = $txtAppId.Text.Trim()
    if ($appId -notmatch '^\d+$') {
        Show-LordZMessage `
            -Message 'App ID must be numeric.' `
            -Title '[LORDZ]' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    Set-LordZBusy $true
    Write-LordZLog '======================================================================'
    Write-LordZLog '[*] PHASE: App ID verification via Steam Store API...'

    try {
        $result = Test-LordZSteamAppIdViaStore `
            -AppId $appId `
            -OnLogLine { param($Line) Write-LordZLog $Line }

        if ($result -and $result.Valid) {
            $script:AppIdVerified = $true
            $script:VerifiedAppName = [string]$result.AppName
            Set-LordZAppStatusLabel -Verified $true -AppName $script:VerifiedAppName
            Write-LordZLog "[OK] $($result.Message)"
            Save-LordZSettings
        }
        else {
            $script:AppIdVerified = $false
            $script:VerifiedAppName = ''
            $script:LblAppStatus.Text = 'Failed'
            $script:LblAppStatus.ForeColor = $script:LordZFlame.StatusBad
            $failMessage = if ($result -and $result.Message) { $result.Message } else { 'App ID verification returned no result.' }
            Write-LordZLog "[!] $failMessage"
        }
    }
    catch {
        $script:AppIdVerified = $false
        $lblAppStatus.Text = 'Failed'
        $lblAppStatus.ForeColor = $script:LordZFlame.StatusBad
        Write-LordZLog ("[!] App ID verification failed: " + $_.Exception.Message)
    }
    finally {
        Set-LordZBusy $false
        [System.Windows.Forms.Application]::DoEvents()
    }
})

$btnGenerateScript.Add_Click({
    try {
        Invoke-LordZGenerateMirrorScript -Grid $queueGrid -TxtAppId $txtAppId -TxtSteamUsername $txtSteamUsername | Out-Null
    }
    catch {
        Write-LordZLog ("[!] Generate Script failed: " + $_.Exception.Message)
        Show-LordZMessage `
            -Message $_.Exception.Message `
            -Title '[LORDZ] Generate Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
})

$btnRunScript.Add_Click({
    try {
        Invoke-LordZRunGeneratedMirrorScript
    }
    catch {
        Write-LordZLog ("[!] Run Script failed: " + $_.Exception.Message)
        Show-LordZMessage `
            -Message $_.Exception.Message `
            -Title '[LORDZ] Run Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
})

$btnCopyScript.Add_Click({
    try {
        Invoke-LordZCopyGeneratedMirrorScript
    }
    catch {
        Write-LordZLog ("[!] Copy Script failed: " + $_.Exception.Message)
        Show-LordZMessage `
            -Message $_.Exception.Message `
            -Title '[LORDZ] Copy Script' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
})

$form.Add_Resize({ Request-LordZLayoutSync })

$form.Add_Shown({
    try {
        $defaultSteamPath = Get-LordZSteamCmdInstallPath -InstallRoot $script:InstallRoot
        if ([string]::IsNullOrWhiteSpace($script:TxtSteamCmdPath.Text) -and (Test-Path -LiteralPath $defaultSteamPath)) {
            $script:TxtSteamCmdPath.Text = $defaultSteamPath
        }

        Sync-LordZLayout
        Update-LordZSteamInstallButton
        Update-LordZDiscordPanel
        Show-LordZAsciiBanner
        Flush-LordZLogBuffer
        if (Test-LordZFirstRun) {
            Write-LordZLog '[*] First run detected. Quick Start guide will open in a moment.'
        }

        Write-LordZLog 'LordZ ready. Double-click "LordZ - Start Here.bat" anytime to reopen this app.'
        Write-LordZLog 'Step 1: Download and Install SteamCMD (if you have not already).'
        Write-LordZLog 'Step 2: Enter Steam username, verify App ID, add mods to the queue.'
        Write-LordZLog 'Step 3: Generate Script, then Run Script and enter your Steam password in PowerShell.'
        Write-LordZLog ('Install folder: ' + $script:InstallRoot)
        Write-LordZLog 'Settings save automatically to lordz.settings.json beside this app.'
        Write-LordZLog 'Need help? Use Quick Request or Live Help Chat from the Discord Support panel.'
        Write-LordZLog '======================================================================'

        $savedAppId = $script:TxtAppId.Text.Trim()
        if ($savedAppId -match '^\d+$') {
            $appCheck = Test-LordZSteamAppIdViaStore -AppId $savedAppId
            if ($appCheck.Valid) {
                $script:AppIdVerified = $true
                $script:VerifiedAppName = [string]$appCheck.AppName
                Set-LordZAppStatusLabel -Verified $true -AppName $script:VerifiedAppName
                Write-LordZLog ("[*] Saved App ID $savedAppId -> $($appCheck.AppName)")
            }
        }

        $script:SteamLastLoginUsername = ''
        $script:SteamSessionReady = $false

        $paths = Get-LordZSteamPaths
        if ($paths) {
            Start-LordZHostedSteamConsole -SteamCmdPath $paths.SteamCmdPath
            Write-LordZLog '[*] Steam console ready. Run Script always prompts for a fresh Steam login.'
        }
        else {
            Write-LordZLog '[*] Set a valid SteamCMD path above to start the console.'
        }

        if (Test-LordZFirstRun) {
            Show-LordZFirstRunWelcome
        }
    }
    catch {
        Write-LordZCrashLog ('Shown handler failed: ' + $_.Exception.Message)
        if ($_.ScriptStackTrace) { Write-LordZCrashLog $_.ScriptStackTrace }
        Show-LordZMessage `
            -Message ('Startup failed: ' + $_.Exception.Message) `
            -Title '[LORDZ] Startup Error' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
})

$form.Add_FormClosing({
    if ($script:PipelineLogTimer) {
        try { $script:PipelineLogTimer.Stop() } catch { }
        try { $script:PipelineLogTimer.Dispose() } catch { }
        $script:PipelineLogTimer = $null
    }
    Stop-LordZMirrorAsyncJob
    Stop-LordZSteamConsoleSession
    Save-LordZSettings
})

Set-LordZSplashStatus 'Opening forge...'
Close-LordZSplash

try {
    [void]$form.ShowDialog()
}
catch {
    Close-LordZSplash
    Write-LordZCrashLog ('ShowDialog failed: ' + $_.Exception.Message)
    if ($script:LogBox) {
        Write-LordZLogError $_.Exception.Message
        if ($_.ScriptStackTrace) { Write-LordZLogError $_.ScriptStackTrace }
    }
    else {
        Show-LordZMessage `
            -Message $_.Exception.Message `
            -Title '[LORDZ] Fatal Error' `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Stop) | Out-Null
    }
}
