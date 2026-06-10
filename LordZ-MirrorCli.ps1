#Requires -Version 7.0
<#
.SYNOPSIS
    LordZ Workshop Mirror - Linux/macOS terminal interface.
#>
$ErrorActionPreference = 'Stop'

$script:InstallRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:SettingsPath = Join-Path $script:InstallRoot 'lordz.settings.json'
$script:QueuePath = Join-Path $script:InstallRoot 'lordz.queue.json'
$script:LastPackage = $null

Import-Module (Join-Path $script:InstallRoot 'Modules/LordZ.Core.psm1') -Force
Initialize-LordZTls

function Write-LordZCli {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
}

function Get-LordZCliSettings {
    $defaultAppId = '895400'
    $defaultSteam = Get-LordZSteamCmdInstallPath -InstallRoot $script:InstallRoot

    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return [PSCustomObject]@{
            SteamCmdPath  = $defaultSteam
            AppId         = $defaultAppId
            SteamUsername = ''
        }
    }

    $raw = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
    $appId = [string]$raw.AppId
    if ([string]::IsNullOrWhiteSpace($appId)) { $appId = $defaultAppId }

    return [PSCustomObject]@{
        SteamCmdPath  = if ($raw.SteamCmdPath) { [string]$raw.SteamCmdPath } else { $defaultSteam }
        AppId         = $appId
        SteamUsername = [string]$raw.SteamUsername
    }
}

function Save-LordZCliSettings {
    param($Settings)
    $Settings | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Get-LordZCliQueue {
    if (-not (Test-Path -LiteralPath $script:QueuePath)) { return @() }
    try {
        return @(Get-Content -LiteralPath $script:QueuePath -Raw | ConvertFrom-Json)
    }
    catch {
        return @()
    }
}

function Save-LordZCliQueue {
    param([array]$Queue)
    $Queue | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:QueuePath -Encoding UTF8
}

function Show-LordZCliBanner {
    $banner = Get-LordZAsciiBanner -InstallRoot $script:InstallRoot
    Write-LordZCli $banner ([ConsoleColor]::Cyan)
    Write-LordZCli 'LordZ CLI - Workshop Mirror Engine' ([ConsoleColor]::Yellow)
    Write-LordZCli ('Platform: ' + (Get-LordZPlatform)) ([ConsoleColor]::DarkGray)
    Write-Host ''
}

function Show-LordZCliMenu {
    $settings = Get-LordZCliSettings
    $queue = Get-LordZCliQueue
    $discord = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot

    Write-Host ''
    Write-LordZCli '=== LORDZ MENU ===' ([ConsoleColor]::Yellow)
    Write-LordZCli " 1) Install SteamCMD"
    Write-LordZCli " 2) Settings (Steam user / App ID / SteamCMD path)"
    Write-LordZCli " 3) Verify App ID"
    Write-LordZCli " 4) Add mod to queue"
    Write-LordZCli " 5) View queue"
    Write-LordZCli " 6) Clear queue"
    Write-LordZCli " 7) Generate mirror script"
    Write-LordZCli " 8) Run generated script"
    Write-LordZCli " 9) Discord Quick Request"
    if ($discord.ChatConfigured) {
        Write-LordZCli "10) Discord Live Help Chat (terminal)"
    }
    Write-LordZCli " 0) Exit"
    Write-Host ''
    Write-LordZCli ("Steam user: " + $(if ($settings.SteamUsername) { $settings.SteamUsername } else { '(not set)' })) ([ConsoleColor]::DarkGray)
    Write-LordZCli ("App ID: " + $settings.AppId) ([ConsoleColor]::DarkGray)
    Write-LordZCli ("Queue: $($queue.Count) mod(s)") ([ConsoleColor]::DarkGray)
}

function Edit-LordZCliSettings {
    $settings = Get-LordZCliSettings
    $user = Read-Host "Steam username [$($settings.SteamUsername)]"
    if (-not [string]::IsNullOrWhiteSpace($user)) { $settings.SteamUsername = $user.Trim() }

    $appId = Read-Host "App ID [$($settings.AppId)]"
    if (-not [string]::IsNullOrWhiteSpace($appId)) { $settings.AppId = $appId.Trim() }

    $steam = Read-Host "SteamCMD path [$($settings.SteamCmdPath)]"
    if (-not [string]::IsNullOrWhiteSpace($steam)) { $settings.SteamCmdPath = $steam.Trim() }

    Save-LordZCliSettings -Settings $settings
    Write-LordZCli '[OK] Settings saved.' ([ConsoleColor]::Green)
}

function Add-LordZCliQueueItem {
    $settings = Get-LordZCliSettings
    $sourceId = Read-Host 'Source Workshop mod ID'
    if ($sourceId -notmatch '^\d+$') {
        Write-LordZCli '[!] Mod ID must be numeric.' ([ConsoleColor]::Red)
        return
    }

    $check = Test-LordZWorkshopModAvailable -PublishedFileId $sourceId -ExpectedAppId $settings.AppId
    if (-not $check.Available) {
        Write-LordZCli "[!] $($check.Message)" ([ConsoleColor]::Red)
        return
    }

    $defaultName = if ($check.Title) { $check.Title } else { "Mirror $sourceId" }
    $mirrorName = Read-Host "Mirror name [$defaultName]"
    if ([string]::IsNullOrWhiteSpace($mirrorName)) { $mirrorName = $defaultName }

    Write-LordZCli 'Visibility: 1=Public  2=Friends  3=Private' ([ConsoleColor]::DarkGray)
    $visChoice = Read-Host 'Visibility [1]'
    $visibility = switch ($visChoice) {
        '2' { 'Friends Only' }
        '3' { 'Private' }
        default { 'Public' }
    }

    $mirrorId = Read-Host 'Mirror ID (0 = new) [0]'
    if ([string]::IsNullOrWhiteSpace($mirrorId)) { $mirrorId = '0' }

    $queue = @(Get-LordZCliQueue)
    $queue += [PSCustomObject]@{
        SourceModId      = $sourceId
        MirrorName       = $mirrorName
        Visibility       = $visibility
        PublishedFileId  = $mirrorId
    }
    Save-LordZCliQueue -Queue $queue
    Write-LordZCli "[OK] Added $mirrorName ($sourceId)" ([ConsoleColor]::Green)
}

function Invoke-LordZCliGenerate {
    $settings = Get-LordZCliSettings
    $queue = @(Get-LordZCliQueue)

    if ($queue.Count -le 0) {
        Write-LordZCli '[!] Queue is empty. Add mods first.' ([ConsoleColor]::Red)
        return
    }

    if ([string]::IsNullOrWhiteSpace($settings.SteamUsername)) {
        Write-LordZCli '[!] Set Steam username in Settings first.' ([ConsoleColor]::Red)
        return
    }

    $steamPath = $settings.SteamCmdPath
    if (-not (Test-Path -LiteralPath $steamPath)) {
        $steamPath = Get-LordZSteamCmdInstallPath -InstallRoot $script:InstallRoot
    }

    $check = Test-LordZSteamCmdPath -SteamCmdPath $steamPath
    if (-not $check.Valid) {
        Write-LordZCli "[!] $($check.Message)" ([ConsoleColor]::Red)
        return
    }

    $steamDir = Split-Path -Parent $steamPath
    $mirrorQueue = $queue | ForEach-Object {
        [PSCustomObject]@{
            SourceModId     = [string]$_.SourceModId
            MirrorName      = [string]$_.MirrorName
            Visibility      = [string]$_.Visibility
            PublishedFileId = if ($_.PublishedFileId) { [string]$_.PublishedFileId } else { '0' }
        }
    }

    $package = New-LordZMirrorRunPackage `
        -InstallRoot $script:InstallRoot `
        -SteamCmdPath $steamPath `
        -SteamCmdDir $steamDir `
        -AppId $settings.AppId `
        -Username $settings.SteamUsername `
        -MirrorQueue $mirrorQueue `
        -ProgressSender $null

    if (-not $package -or -not $package.Success) {
        Write-LordZCli "[!] $($package.Message)" ([ConsoleColor]::Red)
        return
    }

    $script:LastPackage = $package
    Write-LordZCli "[OK] $($package.Message)" ([ConsoleColor]::Green)
    Write-LordZCli "    Batch: $($package.BatchPath)" ([ConsoleColor]::DarkGray)
    Write-LordZCli "    Runner: $($package.RunnerPath)" ([ConsoleColor]::DarkGray)
}

function Invoke-LordZCliRun {
    if (-not $script:LastPackage -or -not (Test-Path -LiteralPath $script:LastPackage.RunnerPath)) {
        Invoke-LordZCliGenerate
        if (-not $script:LastPackage) { return }
    }

    $runner = $script:LastPackage.RunnerPath
    Write-LordZCli "[*] Running: $runner" ([ConsoleColor]::Yellow)

    if ($runner -like '*.sh') {
        & chmod '+x' $runner 2>$null
        & /bin/bash $runner
    }
    else {
        & pwsh -NoProfile -File $runner
    }
}

function Invoke-LordZCliDiscordRequest {
    $discord = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot
    if (-not $discord.WebhookConfigured) {
        Write-LordZCli '[!] Discord webhook not configured in lordz.discord.json' ([ConsoleColor]::Red)
        return
    }

    $message = Read-Host 'Describe your issue'
    if ([string]::IsNullOrWhiteSpace($message)) { return }

    $result = Send-LordZDiscordHelpMessage `
        -InstallRoot $script:InstallRoot `
        -Message $message `
        -Context @{
            'Platform' = Get-LordZPlatform
            'User'     = [System.Environment]::UserName
        }

    if ($result.Success) {
        Write-LordZCli "[OK] $($result.Message)" ([ConsoleColor]::Green)
    }
    else {
        Write-LordZCli "[!] $($result.Message)" ([ConsoleColor]::Red)
    }
}

function Invoke-LordZCliDiscordChat {
    $discord = Test-LordZDiscordConfig -InstallRoot $script:InstallRoot
    if (-not $discord.ChatConfigured) {
        Write-LordZCli '[!] Live chat needs lordz.discord.json with BotToken + HelpChannelId' ([ConsoleColor]::Red)
        return
    }

    $first = Read-Host 'Message to start chat'
    if ([string]::IsNullOrWhiteSpace($first)) { return }

    $session = Start-LordZDiscordHelpChatSession -InstallRoot $script:InstallRoot -InitialMessage $first
    if (-not $session.Success) {
        Write-LordZCli "[!] $($session.Message)" ([ConsoleColor]::Red)
        return
    }

    Write-LordZCli "[OK] Session $($session.SessionId) - type messages, blank line + Enter to quit" ([ConsoleColor]::Green)

    while ($true) {
        $updates = Get-LordZDiscordHelpChatUpdates `
            -InstallRoot $script:InstallRoot `
            -ThreadId $session.ThreadId `
            -LastMessageId $session.LastMessageId `
            -BotUserId $session.BotUserId `
            -SupportLabel $session.SupportLabel

        foreach ($update in $updates) {
            Write-LordZCli ("[{0}] {1}" -f $update.Speaker, $update.Text) ([ConsoleColor]::Cyan)
            $session.LastMessageId = $update.MessageId
        }

        Write-Host -NoNewline '> '
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }

        $send = Send-LordZDiscordHelpChatMessage `
            -InstallRoot $script:InstallRoot `
            -ThreadId $session.ThreadId `
            -AnonymousLabel $session.AnonymousLabel `
            -Message $line

        if (-not $send.Success) {
            Write-LordZCli "[!] $($send.Message)" ([ConsoleColor]::Red)
        }
        else {
            $session.LastMessageId = $send.MessageId
        }
    }
}

Show-LordZCliBanner

if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
    Write-LordZCli 'First run: install SteamCMD and set your Steam username in Settings.' ([ConsoleColor]::Yellow)
}

while ($true) {
    Show-LordZCliMenu
    $choice = Read-Host 'Choose'

    switch ($choice) {
        '1' {
            $result = Install-LordZSteamCmd -InstallRoot $script:InstallRoot -OnLogLine { param($line) Write-LordZCli $line }
            if ($result.Success) {
                $settings = Get-LordZCliSettings
                $settings.SteamCmdPath = $result.SteamCmdPath
                Save-LordZCliSettings -Settings $settings
                Write-LordZCli "[OK] $($result.Message)" ([ConsoleColor]::Green)
            }
            else {
                Write-LordZCli "[!] $($result.Message)" ([ConsoleColor]::Red)
            }
        }
        '2' { Edit-LordZCliSettings }
        '3' {
            $settings = Get-LordZCliSettings
            $result = Test-LordZSteamAppIdViaStore -AppId $settings.AppId -OnLogLine { param($line) Write-LordZCli $line }
            if ($result.Valid) { Write-LordZCli "[OK] $($result.Message)" ([ConsoleColor]::Green) }
            else { Write-LordZCli "[!] $($result.Message)" ([ConsoleColor]::Red) }
        }
        '4' { Add-LordZCliQueueItem }
        '5' {
            $queue = Get-LordZCliQueue
            if ($queue.Count -eq 0) {
                Write-LordZCli 'Queue is empty.' ([ConsoleColor]::DarkGray)
            }
            else {
                $i = 1
                foreach ($item in $queue) {
                    Write-LordZCli ("{0}. {1} ({2}) - {3}" -f $i, $item.MirrorName, $item.SourceModId, $item.Visibility)
                    $i++
                }
            }
        }
        '6' {
            Save-LordZCliQueue -Queue @()
            Write-LordZCli '[OK] Queue cleared.' ([ConsoleColor]::Green)
        }
        '7' { Invoke-LordZCliGenerate }
        '8' { Invoke-LordZCliRun }
        '9' { Invoke-LordZCliDiscordRequest }
        '10' { Invoke-LordZCliDiscordChat }
        '0' { break }
        default { Write-LordZCli '[!] Invalid choice.' ([ConsoleColor]::Red) }
    }
}

Write-LordZCli 'Goodbye.' ([ConsoleColor]::Yellow)
