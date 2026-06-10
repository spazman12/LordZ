# Lord Zolton Mirror Core Engine
# SteamCMD workshop mirroring, VDF generation, and single-session batch execution.

Set-StrictMode -Version Latest

if (-not ('LordZPipelineLogHub' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;

public static class LordZPipelineLogHub
{
    private static readonly ConcurrentQueue<string> Queue = new ConcurrentQueue<string>();

    public static void Enqueue(string line)
    {
        if (string.IsNullOrWhiteSpace(line)) { return; }
        Queue.Enqueue(line);
    }

    public static bool TryDequeue(out string line)
    {
        return Queue.TryDequeue(out line);
    }
}

public static class LordZSteamCmdStreamBridge
{
    private static readonly DataReceivedEventHandler Handler = OnData;

    private static void OnData(object sender, DataReceivedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(e.Data)) { return; }
        LordZPipelineLogHub.Enqueue(e.Data);
    }

    public static void Attach(Process process)
    {
        if (process == null) { return; }
        process.OutputDataReceived += Handler;
        process.ErrorDataReceived += Handler;
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }
}
'@
}

$script:LordZDiscordBotUserId = ''
$script:LordZDiscordBotToken = ''

$script:LordZVisibilityMap = @{
    'Public'       = '0'
    'Friends Only' = '1'
    'Hidden'       = '2'
    'Unlisted'     = '3'
}

function Get-LordZVisibilityValue {
    param([Parameter(Mandatory)][string]$Label)
    if ($script:LordZVisibilityMap.ContainsKey($Label)) {
        return $script:LordZVisibilityMap[$Label]
    }
    return '2'
}

function Get-LordZVisibilityLabels {
    return @($script:LordZVisibilityMap.Keys)
}

function Write-LordZPipelineLog {
    param(
        [Parameter(Mandatory)][string]$Line,
        $ProgressSender,
        [int]$ProgressPercentage = 1
    )

    if ([string]::IsNullOrWhiteSpace($Line)) { return }

    [LordZPipelineLogHub]::Enqueue($Line)

    if ($null -ne $ProgressSender) {
        try {
            $ProgressSender.ReportProgress($ProgressPercentage, $Line)
        }
        catch { }
    }
}

function Get-LordZPlatform {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsLinux) { return 'Linux' }
        if ($IsMacOS) { return 'MacOS' }
        if ($IsWindows) { return 'Windows' }
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return 'Linux'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return 'MacOS'
    }

    return 'Windows'
}

function Get-LordZSteamCmdExecutableName {
    if ((Get-LordZPlatform) -eq 'Linux') { return 'steamcmd.sh' }
    return 'steamcmd.exe'
}

function Test-LordZSteamCmdPath {
    param([Parameter(Mandatory)][string]$SteamCmdPath)

    $label = Get-LordZSteamCmdExecutableName
    if (-not (Test-Path -LiteralPath $SteamCmdPath)) {
        return [PSCustomObject]@{
            Valid   = $false
            Message = "$label not found at: $SteamCmdPath"
        }
    }

    return [PSCustomObject]@{
        Valid   = $true
        Message = "$label located."
    }
}

function Get-LordZSteamCmdInstallDir {
    param([Parameter(Mandatory)][string]$InstallRoot)
    return Join-Path $InstallRoot 'steamcmd'
}

function Get-LordZSteamCmdInstallPath {
    param([Parameter(Mandatory)][string]$InstallRoot)
    return Join-Path (Get-LordZSteamCmdInstallDir -InstallRoot $InstallRoot) (Get-LordZSteamCmdExecutableName)
}

function Set-LordZSteamCmdExecutable {
    param([Parameter(Mandatory)][string]$SteamCmdPath)

    if ((Get-LordZPlatform) -ne 'Linux') { return }
    if (-not (Test-Path -LiteralPath $SteamCmdPath)) { return }

    try {
        & chmod '+x' $SteamCmdPath 2>$null
    }
    catch { }
}

function Install-LordZSteamCmd {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [string]$DownloadUrl = '',
        [switch]$SkipBootstrap,
        [scriptblock]$OnLogLine,
        $ProgressSender
    )

    $platform = Get-LordZPlatform
    $targetDir = Get-LordZSteamCmdInstallDir -InstallRoot $InstallRoot
    $steamCmdPath = Get-LordZSteamCmdInstallPath -InstallRoot $InstallRoot
    $steamLabel = Get-LordZSteamCmdExecutableName

    if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
        if ($platform -eq 'Linux') {
            $DownloadUrl = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
        }
        else {
            $DownloadUrl = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
        }
    }

    $archivePath = if ($platform -eq 'Linux') {
        Join-Path ([System.IO.Path]::GetTempPath()) 'lordz_steamcmd_install.tar.gz'
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'lordz_steamcmd_install.zip'
    }

    try {
        Write-LordZPipelineLog -Line '[*] Preparing SteamCMD install directory...' -ProgressSender $ProgressSender

        if (-not (Test-Path -LiteralPath $InstallRoot)) {
            New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        }

        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        else {
            Get-ChildItem -LiteralPath $targetDir -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Write-LordZPipelineLog -Line "[*] Downloading SteamCMD archive from: $DownloadUrl" -ProgressSender $ProgressSender

        $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
        }
        catch { }

        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $archivePath -UseBasicParsing -ErrorAction Stop
        }
        finally {
            [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        }

        if (-not (Test-Path -LiteralPath $archivePath)) {
            throw 'SteamCMD download did not produce an archive file.'
        }

        if ($platform -eq 'Linux') {
            Write-LordZPipelineLog -Line '[*] Extracting steamcmd_linux.tar.gz...' -ProgressSender $ProgressSender
            & tar -xf $archivePath -C $targetDir
            if ($LASTEXITCODE -ne 0) {
                throw "tar failed with exit code $LASTEXITCODE while extracting SteamCMD."
            }
        }
        else {
            Write-LordZPipelineLog -Line '[*] Built-in extractor deploying steamcmd.zip payload...' -ProgressSender $ProgressSender
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $targetDir)
        }

        if (-not (Test-Path -LiteralPath $steamCmdPath)) {
            throw "$steamLabel was not found after extraction. Expected: $steamCmdPath"
        }

        Set-LordZSteamCmdExecutable -SteamCmdPath $steamCmdPath
        Write-LordZPipelineLog -Line "[OK] Archive extracted. $steamLabel is present on disk." -ProgressSender $ProgressSender

        if (-not $SkipBootstrap) {
            Write-LordZPipelineLog -Line '[*] Running first-time SteamCMD bootstrap (+quit)...' -ProgressSender $ProgressSender
            Write-LordZPipelineLog -Line '[*] This may take a minute while core files download.' -ProgressSender $ProgressSender

            $bootstrap = Invoke-LordZSteamCmdScript -SteamCmdPath $steamCmdPath -ScriptLines @('quit') -OnLogLine $OnLogLine -ProgressSender $ProgressSender
            if ($bootstrap.ExitCode -ne 0) {
                Write-LordZPipelineLog -Line "[!] Bootstrap finished with exit code $($bootstrap.ExitCode). $steamLabel is still installed." -ProgressSender $ProgressSender
            }
        }

        Write-LordZPipelineLog -Line "[OK] SteamCMD installed: $steamCmdPath" -ProgressSender $ProgressSender

        return [PSCustomObject]@{
            Success      = $true
            SteamCmdPath = $steamCmdPath
            InstallDir   = $targetDir
            Message      = 'SteamCMD downloaded and installed successfully.'
        }
    }
    catch {
        Write-LordZPipelineLog -Line "[!] SteamCMD install failed: $($_.Exception.Message)" -ProgressSender $ProgressSender
        return [PSCustomObject]@{
            Success      = $false
            SteamCmdPath = $steamCmdPath
            InstallDir   = $targetDir
            Message      = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-LordZAsciiBanner {
    param([string]$InstallRoot = '')

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
        $candidates += Join-Path $InstallRoot 'Assets\LordZ-Ascii.txt'
    }
    $candidates += Join-Path $PSScriptRoot '..\Assets\LordZ-Ascii.txt'

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            $lines = Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object { $_.TrimEnd() }
            return ($lines -join [Environment]::NewLine).TrimEnd()
        }
    }

    return @'
======================================================================
              [ LORD ZOLTON CORE INTEGRATION ENGINE ]
======================================================================
'@.TrimEnd()
}

function Get-LordZAsciiBannerRunnerLines {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $installLiteral = $InstallRoot -replace "'", "''"
    $bannerLiteral = (Join-Path $InstallRoot 'Assets\LordZ-Ascii.txt') -replace "'", "''"

    return @(
        'Write-Host '''''
        ('$lordzBannerFile = ''' + $bannerLiteral + '''')
        ('$lordzInstallRoot = ''' + $installLiteral + '''')
        'if (-not (Test-Path -LiteralPath $lordzBannerFile)) {'
        ('    $lordzBannerFile = Join-Path $lordzInstallRoot ''Assets\LordZ-Ascii.txt''')
        '}'
        'if (Test-Path -LiteralPath $lordzBannerFile) {'
        '    Get-Content -LiteralPath $lordzBannerFile -Encoding UTF8 | ForEach-Object {'
        '        $line = $_.TrimEnd()'
        '        if ([string]::IsNullOrWhiteSpace($line)) { Write-Host '''' }'
        '        else { Write-Host $line -ForegroundColor Cyan }'
        '    }'
        '}'
        'else {'
        '    Write-Host ''======================================================================'' -ForegroundColor Cyan'
        '    Write-Host ''              [ LORD ZOLTON CORE INTEGRATION ENGINE ]'' -ForegroundColor Cyan'
        '    Write-Host ''======================================================================'' -ForegroundColor Cyan'
        '}'
        'Write-Host '''''
    )
}

function Write-LordZUtf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines,
        [switch]$UseLf
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not $UseLf -and $Path -match '\.(sh|bash)$') {
        $UseLf = $true
    }

    $newline = if ($UseLf) { "`n" } else { "`r`n" }
    $text = ($Lines -join $newline) + $newline
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $text, $encoding)
}

function Repair-LordZUnixLineEndings {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $text = [System.IO.File]::ReadAllText($Path)
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized -ne $text) {
        $encoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
    }
}

function ConvertTo-LordZEscapedPath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = $Path
    if (Test-Path -LiteralPath $Path) {
        $item = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($item) { $resolved = $item.Path }
    }
    return ($resolved -replace '\\', '/')
}

function Get-LordZWorkshopFileDetails {
    param(
        [Parameter(Mandatory)][string[]]$PublishedFileIds
    )

    if ($PublishedFileIds.Count -le 0) { return @() }

    $apiUrl = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
    $body = @{ itemcount = $PublishedFileIds.Count }
    for ($i = 0; $i -lt $PublishedFileIds.Count; $i++) {
        $body["publishedfileids[$i]"] = $PublishedFileIds[$i]
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $apiUrl -Body $body -ErrorAction Stop
        if ($null -eq $response) { return @() }

        $items = $null
        if ($response.PSObject.Properties['response'] -and $response.response.publishedfiledetails) {
            $items = $response.response.publishedfiledetails
        }
        elseif ($response.publishedfiledetails) {
            $nested = $response.publishedfiledetails
            if ($nested.PSObject.Properties['publishedfiledetails']) {
                $items = $nested.publishedfiledetails
            }
            else {
                $items = $nested
            }
        }

        if ($null -eq $items) { return @() }
        if ($items -is [System.Array]) { return @($items) }
        return @($items)
    }
    catch {
        return @()
    }
}

function Test-LordZWorkshopModAvailable {
    param(
        [Parameter(Mandatory)][string]$PublishedFileId,
        [string]$ExpectedAppId = ''
    )

    $details = @(Get-LordZWorkshopFileDetails -PublishedFileIds @($PublishedFileId))
    if ($details.Length -le 0) {
        return [PSCustomObject]@{
            Available = $false
            Title     = ''
            Message   = "Workshop item $PublishedFileId was not found on Steam."
        }
    }

    $item = $details[0]
    if ($item.result -ne 1 -or [string]::IsNullOrWhiteSpace($item.title)) {
        return [PSCustomObject]@{
            Available = $false
            Title     = ''
            Message   = "Workshop item $PublishedFileId is deleted or unavailable."
        }
    }

    $itemAppId = ''
    if ($item.PSObject.Properties['consumer_app_id'] -and $null -ne $item.consumer_app_id) {
        $itemAppId = [string]$item.consumer_app_id
    }
    elseif ($item.PSObject.Properties['appid'] -and $null -ne $item.appid) {
        $itemAppId = [string]$item.appid
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedAppId) -and $itemAppId -ne $ExpectedAppId) {
        return [PSCustomObject]@{
            Available = $false
            Title     = [string]$item.title
            Message   = "Workshop item $PublishedFileId belongs to app $itemAppId, not $ExpectedAppId."
        }
    }

    return [PSCustomObject]@{
        Available = $true
        Title     = [string]$item.title
        Message   = [string]$item.title
    }
}

function Find-LordZPreviewImage {
    param([Parameter(Mandatory)][string]$ContentFolder)

    if (-not (Test-Path -LiteralPath $ContentFolder)) { return $null }

    $preferred = @('preview.jpg', 'preview.png', 'preview.jpeg', 'thumbnail.jpg', 'thumbnail.png')
    foreach ($name in $preferred) {
        $candidate = Join-Path $ContentFolder $name
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $images = Get-ChildItem -LiteralPath $ContentFolder -Recurse -Include *.jpg, *.jpeg, *.png -File -ErrorAction SilentlyContinue |
        Sort-Object Length |
        Select-Object -First 1

    if ($images) { return $images.FullName }
    return $null
}

function Get-LordZBundledPlaceholderPath {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $candidate = Join-Path $InstallRoot 'Assets\LordZ-Placeholder.png'
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    $candidate = Join-Path $InstallRoot 'Assets/LordZ-Placeholder.png'
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    return $null
}

function New-LordZPlaceholderPreview {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$MirrorName,
        [string]$InstallRoot = ''
    )

    $dir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ((Get-LordZPlatform) -ne 'Windows') {
        $bundled = $null
        if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
            $bundled = Get-LordZBundledPlaceholderPath -InstallRoot $InstallRoot
        }
        if ($bundled) {
            Copy-Item -LiteralPath $bundled -Destination $TargetPath -Force
            return $TargetPath
        }
    }

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $bitmap = New-Object System.Drawing.Bitmap 512, 512
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(12, 4, 2))
        $font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 140, 35))
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = 'Center'
        $format.LineAlignment = 'Center'
        $rect = New-Object System.Drawing.RectangleF 0, 0, 512, 512
        $label = if ($MirrorName.Length -gt 40) { $MirrorName.Substring(0, 40) + '...' } else { $MirrorName }
        $graphics.DrawString("[LORDZ]`n$label", $font, $brush, $rect, $format)
        $bitmap.Save($TargetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    return $TargetPath
}

function New-LordZWorkshopVdf {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ContentFolder,
        [Parameter(Mandatory)][string]$PreviewFile,
        [Parameter(Mandatory)][string]$Title,
        [string]$Description = 'Mirrored via Lord Zolton Core Integration Engine.',
        [string]$ChangeNote = 'Initial mirror upload.',
        [string]$Visibility = '2',
        [string]$PublishedFileId = '0'
    )

    $contentEscaped = ConvertTo-LordZEscapedPath -Path $ContentFolder
    $previewEscaped = ConvertTo-LordZEscapedPath -Path $PreviewFile
    $titleEscaped = ($Title -replace '"', '\"')
    $descEscaped = ($Description -replace '"', '\"')
    $noteEscaped = ($ChangeNote -replace '"', '\"')

    $vdf = @"
"workshopitem"
{
    "appid"               "$AppId"
    "publishedfileid"     "$PublishedFileId"
    "contentfolder"       "$contentEscaped"
    "previewfile"         "$previewEscaped"
    "visibility"          "$Visibility"
    "title"               "$titleEscaped"
    "description"         "$descEscaped"
    "changenote"          "$noteEscaped"
}
"@

    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -LiteralPath $OutputPath -Value $vdf -Encoding UTF8
    return $OutputPath
}

function Get-LordZWorkshopContentPath {
    param(
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$WorkshopId
    )

    return Join-Path $SteamCmdDir "steamapps\workshop\content\$AppId\$WorkshopId"
}

function Get-LordZMirrorRoot {
    param([Parameter(Mandatory)][string]$SteamCmdDir)
    return Join-Path $SteamCmdDir 'lordz_mirrors'
}

function Send-LordZSteamCmdConsoleLine {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Line
    )

    if (-not $Session -or -not $Session.Process) { return $false }
    if ($Session.Process.HasExited) { return $false }

    [System.Threading.Monitor]::Enter($Session.SyncRoot)
    try {
        $Session.Process.StandardInput.WriteLine($Line)
        $Session.Process.StandardInput.Flush()
        return $true
    }
    finally {
        [System.Threading.Monitor]::Exit($Session.SyncRoot)
    }
}

function Start-LordZSteamCmdConsoleSession {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [string[]]$InitialLines = @()
    )

    $steamCmdDir = Split-Path -Parent $SteamCmdPath

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SteamCmdPath
    $psi.Arguments = ''
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $steamCmdDir

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true
    [void]$process.Start()

    [LordZSteamCmdStreamBridge]::Attach($process)

    $session = [PSCustomObject]@{
        Process     = $process
        SteamCmdDir = $steamCmdDir
        SyncRoot    = (New-Object object)
    }

    foreach ($line in $InitialLines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void](Send-LordZSteamCmdConsoleLine -Session $session -Line $line)
        }
    }

    return $session
}

function Stop-LordZSteamCmdConsoleSession {
    param($Session)

    if (-not $Session) { return }
    try {
        if ($Session.Process -and -not $Session.Process.HasExited) {
            try {
                [void](Send-LordZSteamCmdConsoleLine -Session $Session -Line 'quit')
            }
            catch { }

            Start-Sleep -Milliseconds 400
            if (-not $Session.Process.HasExited) {
                $Session.Process.Kill()
            }
        }
    }
    catch { }

    try {
        if ($Session.Process) {
            $Session.Process.Dispose()
        }
    }
    catch { }
}

function Invoke-LordZSteamCmdInteractive {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [string[]]$InitialLines = @(),
        [scriptblock]$OnLogLine,
        [ref]$SessionOut,
        [scriptblock]$OnSessionReady,
        [int]$TimeoutSeconds = 900,
        [switch]$StopAfterLogin
    )

    $outputLines = New-Object System.Collections.Generic.List[string]
    $session = Start-LordZSteamCmdConsoleSession -SteamCmdPath $SteamCmdPath -InitialLines @()
    if ($SessionOut) {
        $SessionOut.Value = $session
    }
    if ($OnSessionReady) {
        & $OnSessionReady $session
    }

    $streamState = @{
        OutputLines = $outputLines
        LoggedIn    = $false
        OnLogLine   = $OnLogLine
    }

    $process = $session.Process
    $recordLine = {
        param([string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        [void]$streamState.OutputLines.Add($Line)
        if ($streamState.OnLogLine) {
            & $streamState.OnLogLine $Line
        }
        if ($Line -match 'Waiting for user info|Logging in user|Logged in OK|successfully logged in') {
            $streamState.LoggedIn = $true
        }
    }

    Start-Sleep -Milliseconds 400
    foreach ($line in $InitialLines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void](Send-LordZSteamCmdConsoleLine -Session $session -Line $line)
        }
    }

    $startedAt = [datetime]::UtcNow
    while (-not $process.HasExited) {
        if (([datetime]::UtcNow - $startedAt).TotalSeconds -gt $TimeoutSeconds) {
            [void]$outputLines.Add("[!] SteamCMD console timed out after $TimeoutSeconds seconds.")
            if ($OnLogLine) { & $OnLogLine "[!] SteamCMD console timed out after $TimeoutSeconds seconds." }
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            break
        }

        $readAny = $false
        try {
            while ($process.StandardError.Peek() -ge 0) {
                & $recordLine $process.StandardError.ReadLine()
                $readAny = $true
            }
            while ($process.StandardOutput.Peek() -ge 0) {
                & $recordLine $process.StandardOutput.ReadLine()
                $readAny = $true
            }
        }
        catch {
            [void]$outputLines.Add("[!] SteamCMD read error: $($_.Exception.Message)")
            if ($OnLogLine) { & $OnLogLine "[!] SteamCMD read error: $($_.Exception.Message)" }
            break
        }

        if ($StopAfterLogin -and $streamState.LoggedIn) {
            if ($OnLogLine) { & $OnLogLine '[*] Login detected. Sending quit...' }
            [void](Send-LordZSteamCmdConsoleLine -Session $session -Line 'quit')
            Start-Sleep -Milliseconds 800
            continue
        }

        if (-not $readAny) {
            Start-Sleep -Milliseconds 80
        }
    }

    try {
        while ($process.StandardOutput.Peek() -ge 0) {
            & $recordLine $process.StandardOutput.ReadLine()
        }
        while ($process.StandardError.Peek() -ge 0) {
            & $recordLine $process.StandardError.ReadLine()
        }
    }
    catch { }

    $process.WaitForExit()
    $loggedIn = [bool]$streamState.LoggedIn
    $parsed = Test-LordZSteamCmdLoginOutput -Lines $outputLines.ToArray()

    return [PSCustomObject]@{
        Success          = $parsed.LoggedIn
        ExitCode         = $process.ExitCode
        Message          = $parsed.Message
        OutputLines      = $outputLines.ToArray()
        NeedsSteamGuard  = ($parsed.Failed -and ($parsed.Message -match 'Steam Guard'))
        Session          = $session
    }
}

function Invoke-LordZSteamCmdScript {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string[]]$ScriptLines,
        [scriptblock]$OnLogLine,
        $ProgressSender,
        [switch]$KeepScriptFile,
        [int]$TimeoutSeconds = 180
    )

    $scriptDir = Split-Path -Parent $SteamCmdPath
    $queuePath = Join-Path $scriptDir 'lordz_batch_execution.txt'
    $outputLines = New-Object System.Collections.Generic.List[string]

    try {
        Write-LordZUtf8NoBom -Path $queuePath -Lines $ScriptLines

        Set-LordZSteamCmdExecutable -SteamCmdPath $SteamCmdPath

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $scriptDir

        if ((Get-LordZPlatform) -eq 'Linux') {
            $psi.FileName = '/bin/bash'
            $escapedQueue = $queuePath -replace "'", "'\\''"
            $escapedSteam = $SteamCmdPath -replace "'", "'\\''"
            $psi.Arguments = "-lc 'cd ''$scriptDir'' && ''$escapedSteam'' +runscript ''$escapedQueue'''"
        }
        else {
            $psi.FileName = $SteamCmdPath
            $psi.Arguments = "+runscript `"$queuePath`""
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        if ($process.StartInfo.RedirectStandardInput) {
            try { $process.StandardInput.Close() } catch { }
        }

        $startedAt = [datetime]::UtcNow
        while (-not $process.HasExited) {
            if (([datetime]::UtcNow - $startedAt).TotalSeconds -gt $TimeoutSeconds) {
                try { if (-not $process.HasExited) { $process.Kill() } } catch { }
                $timeoutLine = "[!] SteamCMD timed out after $TimeoutSeconds seconds."
                [void]$outputLines.Add($timeoutLine)
                Write-LordZPipelineLog -Line $timeoutLine -ProgressSender $ProgressSender
                break
            }

            if ($process.StandardOutput.Peek() -ge 0) {
                $line = $process.StandardOutput.ReadLine()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    [void]$outputLines.Add($line)
                    Write-LordZPipelineLog -Line $line -ProgressSender $ProgressSender
                }
            }
            if ($process.StandardError.Peek() -ge 0) {
                $line = $process.StandardError.ReadLine()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    [void]$outputLines.Add($line)
                    Write-LordZPipelineLog -Line $line -ProgressSender $ProgressSender
                }
            }
            Start-Sleep -Milliseconds 40
        }

        while ($process.StandardOutput.Peek() -ge 0) {
            $line = $process.StandardOutput.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                [void]$outputLines.Add($line)
                Write-LordZPipelineLog -Line $line -ProgressSender $ProgressSender
            }
        }
        while ($process.StandardError.Peek() -ge 0) {
            $line = $process.StandardError.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                [void]$outputLines.Add($line)
                Write-LordZPipelineLog -Line $line -ProgressSender $ProgressSender
            }
        }

        $process.WaitForExit()

        return [PSCustomObject]@{
            ExitCode    = $process.ExitCode
            Success     = ($process.ExitCode -eq 0)
            OutputLines = $outputLines.ToArray()
        }
    }
    finally {
        if (-not $KeepScriptFile -and (Test-Path -LiteralPath $queuePath)) {
            Remove-Item -LiteralPath $queuePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-LordZSteamCmdHostedScript {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string[]]$ScriptLines,
        $ProgressSender,
        [switch]$KeepScriptFile
    )

    if (-not $Session -or -not $Session.Process -or $Session.Process.HasExited) {
        return [PSCustomObject]@{
            Started = $false
            Message = 'SteamCMD console session is not running.'
        }
    }

    $scriptDir = Split-Path -Parent $SteamCmdPath
    $queuePath = Join-Path $scriptDir 'lordz_batch_execution.txt'

    try {
        Write-LordZUtf8NoBom -Path $queuePath -Lines $ScriptLines

        Write-LordZPipelineLog -Line '[*] Sending mirror batch to the in-app SteamCMD console...' -ProgressSender $ProgressSender
        Write-LordZPipelineLog -Line '[*] Watch this log — when SteamCMD asks to log in, use the input bar below (Enter or Send).' -ProgressSender $ProgressSender

        $runLine = "+runscript `"$queuePath`""
        [void](Send-LordZSteamCmdConsoleLine -Session $Session -Line $runLine)

        return [PSCustomObject]@{
            Started   = $true
            QueuePath = $queuePath
            RunLine   = $runLine
        }
    }
    catch {
        return [PSCustomObject]@{
            Started = $false
            Message = $_.Exception.Message
        }
    }
}

function Prepare-LordZMirrorPipeline {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$Password = '',
        [switch]$UsedQrAuth,
        [string]$SteamGuardCode,
        [Parameter(Mandatory)][array]$MirrorQueue,
        [switch]$InteractiveConsole,
        [scriptblock]$OnLogLine,
        $ProgressSender
    )

    Write-LordZPipelineLog -Line "[*] Mirror pipeline worker started for App ID $AppId ($($MirrorQueue.Count) item(s))." -ProgressSender $ProgressSender

    $useCached = $false
    if ($UsedQrAuth) {
        Write-LordZPipelineLog -Line '[*] Priming SteamCMD cache before mirror batch...' -ProgressSender $ProgressSender
        $cache = Set-LordZSteamCmdRefreshToken -SteamCmdDir $SteamCmdDir -Username $Username -RefreshToken $Password
        if (-not $cache.Success) {
            Write-LordZPipelineLog -Line "[!] $($cache.Message)" -ProgressSender $ProgressSender
            return [PSCustomObject]@{ Success = $false; LoadCount = 0; Message = $cache.Message }
        }
        $useCached = $true
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SteamGuardCode)) {
        if ($InteractiveConsole) {
            Write-LordZPipelineLog -Line '[*] Steam Guard code will be sent through the in-app console.' -ProgressSender $ProgressSender
            $useCached = $false
        }
        else {
            $login = Invoke-LordZSteamCmdLogin `
                -SteamCmdPath $SteamCmdPath `
                -Username $Username `
                -Password $Password `
                -SteamGuardCode $SteamGuardCode `
                -OnLogLine $OnLogLine `
                -ProgressSender $ProgressSender
            if (-not $login.Success) {
                Write-LordZPipelineLog -Line "[!] $($login.Message)" -ProgressSender $ProgressSender
                return [PSCustomObject]@{ Success = $false; LoadCount = 0; Message = $login.Message }
            }
            $useCached = $true
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($Password)) {
        $useCached = $true
    }

    $batch = Build-LordZMirrorBatchScript `
        -SteamCmdDir $SteamCmdDir `
        -SteamCmdPath $SteamCmdPath `
        -AppId $AppId `
        -Username $Username `
        -Password $Password `
        -UseCachedCredentials:$useCached `
        -InteractiveConsole:$InteractiveConsole `
        -MirrorQueue $MirrorQueue `
        -OnLogLine $OnLogLine `
        -ProgressSender $ProgressSender

    if ($batch.Skipped.Count -gt 0) {
        foreach ($skip in $batch.Skipped) {
            Write-LordZPipelineLog -Line "[!] Skipped $($skip.SourceModId): $($skip.Reason)" -ProgressSender $ProgressSender
        }
    }

    if ($batch.LoadCount -le 0) {
        Write-LordZPipelineLog -Line '[!] No valid mirrors in queue. Execution skipped.' -ProgressSender $ProgressSender
        return [PSCustomObject]@{ Success = $false; LoadCount = 0; Message = 'No valid mirrors in queue.' }
    }

    Write-LordZPipelineLog -Line "[OK] Matrix compiled: $($batch.LoadCount) mirror(s) ready." -ProgressSender $ProgressSender
    Write-LordZPipelineLog -Line '[!] Connecting via single authorization pipeline...' -ProgressSender $ProgressSender
    Write-LordZPipelineLog -Line '[!] If Steam Guard triggers, complete it once for the entire batch.' -ProgressSender $ProgressSender

    return [PSCustomObject]@{
        Success     = $true
        LoadCount   = $batch.LoadCount
        ScriptLines = $batch.ScriptLines
    }
}

function Invoke-LordZSteamCmdLogin {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$Username,
        [string]$Password,
        [switch]$UsedQrAuth,
        [string]$SteamGuardCode,
        [scriptblock]$OnLogLine,
        $ProgressSender,
        [int]$TimeoutSeconds = 600
    )

    $steamCmdDir = Split-Path -Parent $SteamCmdPath
    $useCached = $false

    if ($UsedQrAuth) {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            return [PSCustomObject]@{
                Success  = $false
                ExitCode = 1
                Message  = 'QR login token missing. Scan the QR code again.'
            }
        }

        Write-LordZPipelineLog -Line '[*] Writing QR session token into SteamCMD credential cache...' -ProgressSender $ProgressSender
        $cache = Set-LordZSteamCmdRefreshToken -SteamCmdDir $steamCmdDir -Username $Username -RefreshToken $Password
        if (-not $cache.Success) {
            Write-LordZPipelineLog -Line "[!] $($cache.Message)" -ProgressSender $ProgressSender
            return [PSCustomObject]@{
                Success  = $false
                ExitCode = 1
                Message  = $cache.Message
            }
        }

        Write-LordZPipelineLog -Line '[OK] SteamCMD cache primed. Logging in with cached credentials...' -ProgressSender $ProgressSender
        $useCached = $true
    }

    $lines = Get-LordZSteamCmdLoginLines -Username $Username -Password $Password -UseCachedCredentials:$useCached -SteamGuardCode $SteamGuardCode
    $result = Invoke-LordZSteamCmdScript -SteamCmdPath $SteamCmdPath -ScriptLines $lines -OnLogLine $OnLogLine -ProgressSender $ProgressSender -TimeoutSeconds $TimeoutSeconds
    $parsed = Test-LordZSteamCmdLoginOutput -Lines $result.OutputLines

    $success = $result.Success -and $parsed.LoggedIn
    if (-not $success) {
        Write-LordZPipelineLog -Line "[!] $($parsed.Message)" -ProgressSender $ProgressSender
    }

    return [PSCustomObject]@{
        Success          = $success
        ExitCode         = $result.ExitCode
        Message          = $parsed.Message
        OutputLines      = $result.OutputLines
        NeedsSteamGuard  = ($parsed.Failed -and ($parsed.Message -match 'Steam Guard'))
    }
}

function Test-LordZSteamAppIdViaStore {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [scriptblock]$OnLogLine
    )

    if ($OnLogLine) { & $OnLogLine "[*] Checking App ID $AppId via Steam Store API (no login required)..." }

    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls

        $uri = "https://store.steampowered.com/api/appdetails?appids=$AppId&l=english"
        $headers = @{ 'User-Agent' = 'LordZ-MirrorEngine/1.0 (+https://store.steampowered.com)' }
        $webResponse = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 30
        $payload = $webResponse.Content | ConvertFrom-Json
        $entry = $null
        if ($payload.PSObject.Properties.Name -contains $AppId) {
            $entry = $payload.$AppId
        }

        if ($entry -and $entry.success -eq $true -and $entry.data) {
            $name = [string]$entry.data.name
            return [PSCustomObject]@{
                Valid    = $true
                AppName  = $name
                Message  = "App ID $AppId verified: $name"
                ExitCode = 0
            }
        }

        return [PSCustomObject]@{
            Valid    = $false
            AppName  = ''
            Message  = "App ID $AppId was not found on Steam."
            ExitCode = 1
        }
    }
    catch {
        $message = "Steam Store API check failed: $($_.Exception.Message)"
        if ($OnLogLine) { & $OnLogLine "[!] $message" }
        return [PSCustomObject]@{
            Valid    = $false
            AppName  = ''
            Message  = $message
            ExitCode = 1
        }
    }
}

function Test-LordZSteamAppId {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$Password = '',
        [switch]$UsedQrAuth,
        [string]$SteamGuardCode,
        [scriptblock]$OnLogLine
    )

    if ($OnLogLine) { & $OnLogLine "[*] Verifying App ID $AppId against Steam network..." }

    $login = Invoke-LordZSteamCmdLogin `
        -SteamCmdPath $SteamCmdPath `
        -Username $Username `
        -Password $Password `
        -UsedQrAuth:$UsedQrAuth `
        -SteamGuardCode $SteamGuardCode `
        -OnLogLine $OnLogLine

    if (-not $login.Success) {
        return [PSCustomObject]@{
            Valid    = $false
            Message  = $login.Message
            ExitCode = $login.ExitCode
            NeedsSteamGuard = $login.NeedsSteamGuard
        }
    }

    $lines = @(
        "login $Username"
        "app_info_print $AppId"
        'quit'
    )

    $result = Invoke-LordZSteamCmdScript -SteamCmdPath $SteamCmdPath -ScriptLines $lines -OnLogLine $OnLogLine

    $valid = $false
    $message = 'App ID verification failed or returned no data.'

    if ($result.ExitCode -eq 0) {
        $valid = $true
        $message = "App ID $AppId verified via Steam."
    }

    return [PSCustomObject]@{
        Valid    = $valid
        Message  = $message
        ExitCode = $result.ExitCode
    }
}

function Initialize-LordZSteamSession {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$Password = '',
        [switch]$UsedQrAuth,
        [string]$SteamGuardCode,
        [scriptblock]$OnLogLine
    )

    if ($OnLogLine) {
        if ($UsedQrAuth) {
            & $OnLogLine '[*] Establishing SteamCMD session from QR authorization token...'
        }
        else {
            & $OnLogLine '[*] Establishing single-session Steam authorization...'
        }
    }

    return Invoke-LordZSteamCmdLogin `
        -SteamCmdPath $SteamCmdPath `
        -Username $Username `
        -Password $Password `
        -UsedQrAuth:$UsedQrAuth `
        -SteamGuardCode $SteamGuardCode `
        -OnLogLine $OnLogLine
}

function Build-LordZMirrorBatchScript {
    param(
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$Password = '',
        [switch]$UseCachedCredentials,
        [switch]$InteractiveConsole,
        [Parameter(Mandatory)][array]$MirrorQueue,
        [scriptblock]$OnLogLine,
        $ProgressSender
    )

    $mirrorRoot = Get-LordZMirrorRoot -SteamCmdDir $SteamCmdDir
    if (-not (Test-Path -LiteralPath $mirrorRoot)) {
        New-Item -ItemType Directory -Path $mirrorRoot -Force | Out-Null
    }

    if ($InteractiveConsole) {
        $scriptLines = @()
    }
    else {
        $loginLines = Get-LordZSteamCmdLoginLines `
            -Username $Username `
            -Password $Password `
            -UseCachedCredentials:$UseCachedCredentials `
            -InteractiveConsole:$InteractiveConsole
        $scriptLines = @($loginLines | Where-Object { $_ -ne 'quit' })
    }
    $scheduled = @()
    $skipped = @()

    foreach ($item in $MirrorQueue) {
        $sourceId = [string]$item.SourceModId
        $mirrorName = [string]$item.MirrorName
        $visibility = Get-LordZVisibilityValue -Label ([string]$item.Visibility)

        if ([string]::IsNullOrWhiteSpace($sourceId)) {
            $skipped += [PSCustomObject]@{ SourceModId = $sourceId; Reason = 'Missing source mod ID.' }
            continue
        }

        $modCheck = Test-LordZWorkshopModAvailable -PublishedFileId $sourceId -ExpectedAppId $AppId
        if (-not $modCheck.Available) {
            $skipped += [PSCustomObject]@{ SourceModId = $sourceId; Reason = $modCheck.Message }
            Write-LordZPipelineLog -Line ('[!] Skipping ' + $sourceId + ' - ' + $modCheck.Message) -ProgressSender $ProgressSender
            continue
        }

        if ([string]::IsNullOrWhiteSpace($mirrorName)) {
            $mirrorName = if ($modCheck.Title) { $modCheck.Title } else { 'New Mirror' }
        }

        $queueLabel = '{0} ({1})' -f $modCheck.Title, $sourceId
        Write-LordZPipelineLog -Line ('[*] Queueing ' + $queueLabel + '...') -ProgressSender $ProgressSender
        $scriptLines += "workshop_download_item $AppId $sourceId"

        $contentPath = Get-LordZWorkshopContentPath -SteamCmdDir $SteamCmdDir -AppId $AppId -WorkshopId $sourceId
        $safeName = ($mirrorName -replace '[\\/:*?"<>|]', '_').Trim()
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "mirror_$sourceId" }

        $itemRoot = Join-Path $mirrorRoot (Join-Path $AppId ("{0}_{1}" -f $safeName, $sourceId))
        if (-not (Test-Path -LiteralPath $itemRoot)) {
            New-Item -ItemType Directory -Path $itemRoot -Force | Out-Null
        }

        $preview = Find-LordZPreviewImage -ContentFolder $contentPath
        if (-not $preview) {
            $lordzRoot = Split-Path -Parent $SteamCmdDir
            $preview = New-LordZPlaceholderPreview -TargetPath (Join-Path $itemRoot 'preview.png') -MirrorName $mirrorName -InstallRoot $lordzRoot
            Write-LordZPipelineLog -Line "    -> Generated placeholder preview for '$mirrorName'." -ProgressSender $ProgressSender
        }

        $vdfPath = Join-Path $itemRoot 'mirror.vdf'
        $publishedId = '0'
        if ($item.PSObject.Properties['PublishedFileId'] -and $null -ne $item.PublishedFileId) {
            $publishedVal = [string]$item.PublishedFileId
            if (-not [string]::IsNullOrWhiteSpace($publishedVal)) {
                $publishedId = $publishedVal
            }
        }

        New-LordZWorkshopVdf `
            -OutputPath $vdfPath `
            -AppId $AppId `
            -ContentFolder $contentPath `
            -PreviewFile $preview `
            -Title $mirrorName `
            -Description "Lord Zolton mirror of workshop item $sourceId." `
            -ChangeNote 'Mirror sync via LordZ engine.' `
            -Visibility $visibility `
            -PublishedFileId $publishedId | Out-Null

        $scheduled += [PSCustomObject]@{
            SourceModId  = $sourceId
            MirrorName   = $mirrorName
            ContentPath  = $contentPath
            VdfPath      = $vdfPath
            Visibility   = $visibility
        }
    }

    # Second pass: build items after downloads (content paths must exist post-download)
    foreach ($entry in $scheduled) {
        $vdfForBatch = ConvertTo-LordZEscapedPath -Path $entry.VdfPath
        $scriptLines += "workshop_build_item `"$vdfForBatch`""
        Write-LordZPipelineLog -Line "[+] Scheduled mirror build: $($entry.MirrorName) (source $($entry.SourceModId))" -ProgressSender $ProgressSender
    }

    $scriptLines += 'quit'

    return [PSCustomObject]@{
        ScriptLines = $scriptLines
        Scheduled   = $scheduled
        Skipped     = $skipped
        LoadCount   = $scheduled.Count
    }
}

function New-LordZMirrorRunPackage {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][array]$MirrorQueue,
        $ProgressSender
    )

    $batch = Build-LordZMirrorBatchScript `
        -SteamCmdDir $SteamCmdDir `
        -SteamCmdPath $SteamCmdPath `
        -AppId $AppId `
        -Username $Username `
        -Password '' `
        -UseCachedCredentials `
        -InteractiveConsole `
        -MirrorQueue $MirrorQueue `
        -ProgressSender $ProgressSender

    if ($batch.Skipped.Count -gt 0) {
        foreach ($skip in $batch.Skipped) {
            Write-LordZPipelineLog -Line "[!] Skipped $($skip.SourceModId): $($skip.Reason)" -ProgressSender $ProgressSender
        }
    }

    if ($batch.LoadCount -le 0) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'No valid mirrors in queue.'
            LoadCount = 0
        }
    }

    $genDir = Join-Path $InstallRoot 'Generated'
    if (-not (Test-Path -LiteralPath $genDir)) {
        New-Item -ItemType Directory -Path $genDir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $batchPath = Join-Path $genDir "lordz_mirror_$stamp.txt"
    $platform = Get-LordZPlatform
    $steamLabel = Get-LordZSteamCmdExecutableName

    $useLf = ($platform -eq 'Linux')
    Write-LordZUtf8NoBom -Path $batchPath -Lines $batch.ScriptLines -UseLf:$useLf

    $bannerWriteLines = Get-LordZAsciiBannerRunnerLines -InstallRoot $InstallRoot
    $runnerContent = ''
    $runnerPath = ''

    if ($platform -eq 'Linux') {
        $runnerPath = Join-Path $genDir "LordZ-Mirror-$stamp.sh"
        $steamCmdLiteral = $SteamCmdPath -replace '\\', '/'
        $batchLiteral = $batchPath -replace '\\', '/'
        $userLiteral = $Username -replace "'", "'\\''"
        $installLiteral = $InstallRoot -replace '\\', '/'

        $runnerLines = @(
            '#!/usr/bin/env bash'
            'set -euo pipefail'
            ''
            "INSTALL_ROOT='$installLiteral'"
            "STEAMCMD='$steamCmdLiteral'"
            "BATCH_PATH='$batchLiteral'"
            "STEAM_USER='$userLiteral'"
            ''
            'BANNER_FILE="$INSTALL_ROOT/Assets/LordZ-Ascii.txt"'
            'if [[ -f "$BANNER_FILE" ]]; then'
            '  cat "$BANNER_FILE"'
            'else'
            '  echo "======================================================================"'
            '  echo "              [ LORD ZOLTON CORE INTEGRATION ENGINE ]"'
            '  echo "======================================================================"'
            'fi'
            'echo'
            ''
            'if [[ ! -f "$STEAMCMD" ]]; then'
            '  echo "[!] $STEAMCMD not found"'
            '  exit 1'
            'fi'
            'if [[ ! -f "$BATCH_PATH" ]]; then'
            '  echo "[!] Batch file not found: $BATCH_PATH"'
            '  exit 1'
            'fi'
            'chmod +x "$STEAMCMD" 2>/dev/null || true'
            ''
            'if [[ -z "$STEAM_USER" ]]; then'
            '  read -r -p "Steam username: " STEAM_USER'
            'fi'
            'read -r -s -p "Steam password: " STEAM_PASS'
            'echo'
            ''
            'if [[ -z "$STEAM_USER" || -z "$STEAM_PASS" ]]; then'
            '  echo "[!] Username and password are required."'
            '  exit 1'
            'fi'
            ''
            'RUNTIME_BATCH="$(mktemp /tmp/lordz_mirror_run.XXXXXX.txt)"'
            'trap ''rm -f "$RUNTIME_BATCH"'' EXIT'
            '{'
            '  echo "login $STEAM_USER $STEAM_PASS"'
            '  grep -v ''^[[:space:]]*login[[:space:]]'' "$BATCH_PATH" | sed ''/^[[:space:]]*$/d'''
            '} > "$RUNTIME_BATCH"'
            ''
            'echo "[*] Starting SteamCMD..."'
            'cd "$(dirname "$STEAMCMD")"'
            '"$STEAMCMD" +runscript "$RUNTIME_BATCH"'
            'exit $?'
        )

        Write-LordZUtf8NoBom -Path $runnerPath -Lines $runnerLines -UseLf
        Repair-LordZUnixLineEndings -Path $runnerPath
        $runnerContent = [System.IO.File]::ReadAllText($runnerPath)
        try { & chmod '+x' $runnerPath 2>$null } catch { }
    }
    else {
        $runnerPath = Join-Path $genDir "LordZ-Mirror-$stamp.ps1"
        $steamCmdLiteral = $SteamCmdPath -replace "'", "''"
        $batchLiteral = $batchPath -replace "'", "''"
        $userLiteral = $Username -replace "'", "''"

        $runnerLines = @(
            '#Requires -Version 5.1'
            '$ErrorActionPreference = ''Stop'''
            ''
        ) + @($bannerWriteLines) + @(
            ('$SteamCmd = ''' + $steamCmdLiteral + '''')
            ('$BatchPath = ''' + $batchLiteral + '''')
            ('$SteamUser = ''' + $userLiteral + '''')
            ''
            'if (-not (Test-Path -LiteralPath $SteamCmd)) {'
            ("    Write-Host '[!] $steamLabel not found' -ForegroundColor Red")
            '    Read-Host ''Press Enter to close'''
            '    exit 1'
            '}'
            ''
            'if (-not (Test-Path -LiteralPath $BatchPath)) {'
            '    Write-Host ''[!] Batch file not found'' -ForegroundColor Red'
            '    Read-Host ''Press Enter to close'''
            '    exit 1'
            '}'
            ''
            'Write-Host (''Account: '' + $SteamUser)'
            'Write-Host ''One login for the whole queue. Approve Steam Guard on your phone if asked.'''
            'Write-Host '''''
            ''
            'if ([string]::IsNullOrWhiteSpace($SteamUser)) {'
            '    $SteamUser = Read-Host ''Steam username'''
            '}'
            ''
            '$securePass = Read-Host ''Steam password'' -AsSecureString'
            '$passPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)'
            '$SteamPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passPtr)'
            '[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passPtr)'
            '$securePass.Dispose()'
            ''
            'if ([string]::IsNullOrWhiteSpace($SteamUser) -or [string]::IsNullOrWhiteSpace($SteamPass)) {'
            '    Write-Host ''[!] Username and password are required.'' -ForegroundColor Red'
            '    Read-Host ''Press Enter to close'''
            '    exit 1'
            '}'
            ''
            '$ops = Get-Content -LiteralPath $BatchPath | Where-Object { $_ -notmatch ''^\s*login\s'' -and -not [string]::IsNullOrWhiteSpace($_) }'
            '$runtimeBatch = Join-Path $env:TEMP (''lordz_mirror_run_{0}.txt'' -f (Get-Date -Format ''yyyyMMddHHmmss''))'
            '$finalLines = @(''login '' + $SteamUser + '' '' + $SteamPass) + @($ops)'
            '$utf8 = New-Object System.Text.UTF8Encoding $false'
            '[System.IO.File]::WriteAllText($runtimeBatch, (($finalLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8)'
            ''
            'Write-Host ''[*] Starting SteamCMD...'' -ForegroundColor Yellow'
            'Push-Location (Split-Path -Parent $SteamCmd)'
            'try {'
            '    & $SteamCmd +runscript $runtimeBatch'
            '    $exit = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }'
            '}'
            'finally {'
            '    Pop-Location'
            '    if (Test-Path -LiteralPath $runtimeBatch) { Remove-Item -LiteralPath $runtimeBatch -Force -ErrorAction SilentlyContinue }'
            '}'
            ''
            'Write-Host (''Finished. Exit code: '' + $exit)'
            'Read-Host ''Press Enter to close'''
            'exit $exit'
        )

        $runnerContent = $runnerLines -join [Environment]::NewLine
        Write-LordZUtf8NoBom -Path $runnerPath -Lines $runnerLines
    }

    return [PSCustomObject]@{
        Success        = $true
        LoadCount      = $batch.LoadCount
        BatchPath      = $batchPath
        BatchLines     = $batch.ScriptLines
        RunnerPath     = $runnerPath
        RunnerContent  = $runnerContent
        Message        = "Generated $($batch.LoadCount) mirror(s)."
    }
}

function Start-LordZMirrorPipeline {
    param(
        [Parameter(Mandatory)][string]$SteamCmdPath,
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Username,
        [AllowEmptyString()][string]$Password = '',
        [switch]$UsedQrAuth,
        [string]$SteamGuardCode,
        [Parameter(Mandatory)][array]$MirrorQueue,
        [scriptblock]$OnLogLine,
        $ProgressSender,
        $HostedSession
    )

    $prep = Prepare-LordZMirrorPipeline `
        -SteamCmdPath $SteamCmdPath `
        -SteamCmdDir $SteamCmdDir `
        -AppId $AppId `
        -Username $Username `
        -Password $Password `
        -UsedQrAuth:$UsedQrAuth `
        -SteamGuardCode $SteamGuardCode `
        -MirrorQueue $MirrorQueue `
        -InteractiveConsole:([bool]$HostedSession) `
        -OnLogLine $OnLogLine `
        -ProgressSender $ProgressSender

    if (-not $prep.Success) {
        return [PSCustomObject]@{
            Success   = $false
            LoadCount = $prep.LoadCount
            Message   = $prep.Message
        }
    }

    if ($HostedSession) {
        $hosted = Invoke-LordZSteamCmdHostedScript `
            -Session $HostedSession `
            -SteamCmdPath $SteamCmdPath `
            -ScriptLines $prep.ScriptLines `
            -ProgressSender $ProgressSender
        if (-not $hosted.Started) {
            Write-LordZPipelineLog -Line "[!] $($hosted.Message)" -ProgressSender $ProgressSender
            return [PSCustomObject]@{ Success = $false; LoadCount = $prep.LoadCount; Message = $hosted.Message }
        }

        return [PSCustomObject]@{
            Success       = $true
            LoadCount     = $prep.LoadCount
            HostedStarted = $true
        }
    }

    $result = Invoke-LordZSteamCmdScript `
        -SteamCmdPath $SteamCmdPath `
        -ScriptLines $prep.ScriptLines `
        -OnLogLine $OnLogLine `
        -ProgressSender $ProgressSender `
        -TimeoutSeconds 3600

    if ($result.Success) {
        Write-LordZPipelineLog -Line "[OK] Batch operation complete. $($batch.LoadCount) mirror(s) processed." -ProgressSender $ProgressSender
    }
    else {
        Write-LordZPipelineLog -Line "[!] SteamCMD exited with code $($result.ExitCode). Review log above." -ProgressSender $ProgressSender
    }

    return [PSCustomObject]@{
        Success   = $result.Success
        LoadCount = $prep.LoadCount
        ExitCode  = $result.ExitCode
    }
}

function Get-LordZVdfCache {
    param(
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$AppId,
        [string]$TargetKeywords = 'stack|multiplier|size|x\d+|\d+x'
    )

    $results = @()
    $vdfFiles = Get-ChildItem -Path $SteamCmdDir -Filter '*.vdf' -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $vdfFiles) {
        $raw = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        if ($raw -notmatch "`"appid`"\s+`"$AppId`"") { continue }

        $modId = ''
        $folder = ''
        $title = ''
        $desc = ''

        foreach ($line in $raw) {
            if ($line -match "`"publishedfileid`"\s+`"(\d+)`"") { $modId = $Matches[1] }
            if ($line -match "`"contentfolder`"\s+`"(.*?)`"") { $folder = $Matches[1] }
            if ($line -match "`"title`"\s+`"(.*?)`"") { $title = $Matches[1] }
            if ($line -match "`"description`"\s+`"(.*?)`"") { $desc = $Matches[1] }
        }

        $isMatch = ($title -match $TargetKeywords) -or ($desc -match $TargetKeywords)
        if (-not $isMatch -and (Test-Path -LiteralPath $folder)) {
            $assets = Get-ChildItem -LiteralPath $folder -Recurse -Name -ErrorAction SilentlyContinue
            if ($assets -match $TargetKeywords) { $isMatch = $true }
        }

        $results += [PSCustomObject]@{
            FileName   = $file.Name
            FullPath   = $file.FullName
            WorkshopID = $modId
            ContentDir = $folder
            Title      = $title
            IsKeywordMatch = $isMatch
        }
    }

    return $results
}

function Get-LordZDiscordConfigPath {
    param([Parameter(Mandatory)][string]$InstallRoot)
    return Join-Path $InstallRoot 'lordz.discord.json'
}

function Get-LordZDiscordConfig {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $defaults = [PSCustomObject]@{
        InviteUrl      = ''
        WebhookUrl     = ''
        BotToken       = ''
        HelpChannelId  = ''
        ChannelLabel   = '#lordz-help'
        SupportLabel   = 'Support'
    }

    $configPath = Get-LordZDiscordConfigPath -InstallRoot $InstallRoot
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $defaults
    }

    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return [PSCustomObject]@{
            InviteUrl     = [string]$raw.InviteUrl
            WebhookUrl    = [string]$raw.WebhookUrl
            BotToken      = [string]$raw.BotToken
            HelpChannelId = [string]$raw.HelpChannelId
            ChannelLabel  = if ($raw.ChannelLabel) { [string]$raw.ChannelLabel } else { '#lordz-help' }
            SupportLabel  = if ($raw.SupportLabel) { [string]$raw.SupportLabel } else { 'Support' }
        }
    }
    catch {
        return $defaults
    }
}

function Test-LordZDiscordPlaceholder {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }

    $trimmed = $Value.Trim()
    $placeholders = @(
        'YOUR_BOT_TOKEN'
        'YOUR_WEBHOOK_ID'
        'YOUR_WEBHOOK_TOKEN'
        'YOUR_CLIENT_ID'
        'CHANGEME'
        'REPLACE_ME'
    )

    foreach ($placeholder in $placeholders) {
        if ($trimmed -ieq $placeholder) { return $true }
        if ($trimmed -match [regex]::Escape($placeholder)) { return $true }
    }

    return $false
}

function Test-LordZDiscordConfig {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot
    $inviteReady = (-not [string]::IsNullOrWhiteSpace($config.InviteUrl)) -and (-not (Test-LordZDiscordPlaceholder -Value $config.InviteUrl))
    $webhookReady = (-not [string]::IsNullOrWhiteSpace($config.WebhookUrl)) -and (-not (Test-LordZDiscordPlaceholder -Value $config.WebhookUrl))
    $chatReady = (-not [string]::IsNullOrWhiteSpace($config.BotToken)) `
        -and (-not [string]::IsNullOrWhiteSpace($config.HelpChannelId)) `
        -and (-not (Test-LordZDiscordPlaceholder -Value $config.BotToken))

    return [PSCustomObject]@{
        InviteConfigured  = $inviteReady
        WebhookConfigured = $webhookReady
        ChatConfigured    = $chatReady
        ChannelLabel      = $config.ChannelLabel
        ConfigPath        = (Get-LordZDiscordConfigPath -InstallRoot $InstallRoot)
    }
}

function Invoke-LordZDiscordBotRequest {
    param(
        [Parameter(Mandatory)][string]$BotToken,
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Patch', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )

    $uri = 'https://discord.com/api/v10' + $Path
    $headers = @{
        Authorization = "Bot $BotToken"
        'User-Agent'  = 'LordZMirrorEngine/1.0'
    }

    $params = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try {
                $err = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($err.message) { $detail = [string]$err.message }
            }
            catch { }
        }
        throw [System.InvalidOperationException]::new($detail)
    }
}

function Get-LordZDiscordBotUserId {
    param([Parameter(Mandatory)][string]$BotToken)

    if ($script:LordZDiscordBotToken -eq $BotToken -and -not [string]::IsNullOrWhiteSpace($script:LordZDiscordBotUserId)) {
        return $script:LordZDiscordBotUserId
    }

    $me = Invoke-LordZDiscordBotRequest -BotToken $BotToken -Method Get -Path '/users/@me'
    $script:LordZDiscordBotUserId = [string]$me.id
    $script:LordZDiscordBotToken = $BotToken
    return $script:LordZDiscordBotUserId
}

function Start-LordZDiscordHelpChatSession {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$InitialMessage
    )

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot
    if ([string]::IsNullOrWhiteSpace($config.BotToken) -or [string]::IsNullOrWhiteSpace($config.HelpChannelId)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Live chat needs BotToken and HelpChannelId in lordz.discord.json.'
        }
    }

    $trimmed = $InitialMessage.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Enter a message before starting chat.'
        }
    }

    if ($trimmed.Length -gt 1800) {
        $trimmed = $trimmed.Substring(0, 1797) + '...'
    }

    try {
        $sessionId = [guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
        $anonymousLabel = "Pilgrim-$sessionId"
        $botUserId = Get-LordZDiscordBotUserId -BotToken $config.BotToken

        $starterBody = @{
            embeds = @(
                @{
                    title       = 'LordZ Anonymous Help Session'
                    description = "Session **$sessionId** opened. Reply in the thread below - the app user stays anonymous."
                    color       = 16738816
                    footer      = @{ text = 'LordZ Mirror Core Engine' }
                }
            )
        }

        $starter = Invoke-LordZDiscordBotRequest `
            -BotToken $config.BotToken `
            -Method Post `
            -Path "/channels/$($config.HelpChannelId)/messages" `
            -Body $starterBody

        $threadBody = @{
            name                  = "Help - $sessionId"
            auto_archive_duration = 1440
        }

        $thread = Invoke-LordZDiscordBotRequest `
            -BotToken $config.BotToken `
            -Method Post `
            -Path "/channels/$($config.HelpChannelId)/messages/$($starter.id)/threads" `
            -Body $threadBody

        $relayBody = @{
            content = "**Anonymous ($anonymousLabel):** $trimmed"
        }

        $relay = Invoke-LordZDiscordBotRequest `
            -BotToken $config.BotToken `
            -Method Post `
            -Path "/channels/$($thread.id)/messages" `
            -Body $relayBody

        return [PSCustomObject]@{
            Success        = $true
            Message        = 'Live help chat connected.'
            SessionId      = $sessionId
            AnonymousLabel = $anonymousLabel
            ThreadId       = [string]$thread.id
            LastMessageId  = [string]$relay.id
            BotUserId      = $botUserId
            SupportLabel   = $config.SupportLabel
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Send-LordZDiscordHelpChatMessage {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][string]$AnonymousLabel,
        [Parameter(Mandatory)][string]$Message
    )

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot
    $trimmed = $Message.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Enter a message before sending.'
        }
    }

    if ($trimmed.Length -gt 1800) {
        $trimmed = $trimmed.Substring(0, 1797) + '...'
    }

    try {
        $relayBody = @{
            content = "**Anonymous ($AnonymousLabel):** $trimmed"
        }

        $relay = Invoke-LordZDiscordBotRequest `
            -BotToken $config.BotToken `
            -Method Post `
            -Path "/channels/$ThreadId/messages" `
            -Body $relayBody

        return [PSCustomObject]@{
            Success   = $true
            Message   = 'Message sent.'
            MessageId = [string]$relay.id
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Get-LordZDiscordMessageText {
    param($Message)

    $text = [string]$Message.content
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        return $text.Trim()
    }

    if ($Message.embeds) {
        $embeds = @($Message.embeds)
        foreach ($embed in $embeds) {
            if (-not [string]::IsNullOrWhiteSpace([string]$embed.description)) {
                return ([string]$embed.description).Trim()
            }
        }
    }

    return ''
}

function Get-LordZDiscordHelpChatUpdates {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][string]$LastMessageId,
        [Parameter(Mandatory)][string]$BotUserId,
        [string]$SupportLabel = 'Support'
    )

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot

    try {
        $path = "/channels/$ThreadId/messages?limit=50"
        if (-not [string]::IsNullOrWhiteSpace($LastMessageId)) {
            $path = '{0}&after={1}' -f $path, $LastMessageId
        }

        $messages = Invoke-LordZDiscordBotRequest `
            -BotToken $config.BotToken `
            -Method Get `
            -Path $path

        if (-not $messages) {
            return @()
        }

        if ($messages -isnot [System.Array]) {
            $messages = @($messages)
        }

        $updates = New-Object System.Collections.Generic.List[object]
        foreach ($msg in ($messages | Sort-Object { [uint64]$_.id })) {
            if ([string]$msg.author.id -eq $BotUserId) { continue }

            $text = Get-LordZDiscordMessageText -Message $msg
            if ([string]::IsNullOrWhiteSpace($text)) { continue }

            $displayName = if ($msg.author.global_name) { [string]$msg.author.global_name } else { [string]$msg.author.username }
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = $SupportLabel
            }

            [void]$updates.Add([PSCustomObject]@{
                    Speaker     = $SupportLabel
                    DisplayName = $displayName
                    Text        = $text
                    MessageId   = [string]$msg.id
                })
        }

        return @($updates.ToArray())
    }
    catch {
        throw
    }
}

function Open-LordZDiscordInvite {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot
    if ([string]::IsNullOrWhiteSpace($config.InviteUrl)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Discord invite URL is not configured. Copy lordz.discord.example.json to lordz.discord.json and set InviteUrl.'
        }
    }

    try {
        Start-Process -FilePath $config.InviteUrl | Out-Null
        return [PSCustomObject]@{
            Success = $true
            Message = "Opened Discord invite for $($config.ChannelLabel)."
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Send-LordZDiscordHelpMessage {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$Message,
        [string]$LogExcerpt = '',
        [hashtable]$Context = @{}
    )

    $config = Get-LordZDiscordConfig -InstallRoot $InstallRoot
    if ([string]::IsNullOrWhiteSpace($config.WebhookUrl)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Discord webhook URL is not configured. Copy lordz.discord.example.json to lordz.discord.json and set WebhookUrl.'
        }
    }

    $trimmedMessage = $Message.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedMessage)) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Enter a message before sending.'
        }
    }

    if ($trimmedMessage.Length -gt 1800) {
        $trimmedMessage = $trimmedMessage.Substring(0, 1797) + '...'
    }

    $fields = New-Object System.Collections.Generic.List[object]
    [void]$fields.Add(@{
            name   = 'Help Channel'
            value  = $config.ChannelLabel
            inline = $true
        })

    foreach ($key in ($Context.Keys | Sort-Object)) {
        $value = [string]$Context[$key]
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value.Length -gt 1024) {
            $value = $value.Substring(0, 1021) + '...'
        }
        [void]$fields.Add(@{
                name   = $key
                value  = $value
                inline = $true
            })
    }

    if (-not [string]::IsNullOrWhiteSpace($LogExcerpt)) {
        if ($LogExcerpt.Length -gt 900) {
            $LogExcerpt = $LogExcerpt.Substring($LogExcerpt.Length - 900)
        }
        [void]$fields.Add(@{
                name   = 'Operation Log (tail)'
                value  = ('```' + $LogExcerpt + '```')
                inline = $false
            })
    }

    $payload = [ordered]@{
        username   = 'LordZ Help Relay'
        embeds     = @(
            [ordered]@{
                title       = 'LordZ Help Request'
                description = $trimmedMessage
                color       = 16738816
                timestamp   = (Get-Date).ToUniversalTime().ToString('o')
                footer      = @{ text = 'LordZ Mirror Core Engine' }
                fields      = @($fields.ToArray())
            }
        )
    }

    try {
        $body = $payload | ConvertTo-Json -Depth 6 -Compress
        Invoke-RestMethod -Uri $config.WebhookUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -ErrorAction Stop | Out-Null
        return [PSCustomObject]@{
            Success = $true
            Message = "Help request relayed to $($config.ChannelLabel)."
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LordZPlatform'
    'Get-LordZSteamCmdExecutableName'
    'Get-LordZVisibilityLabels'
    'Get-LordZVisibilityValue'
    'Test-LordZSteamCmdPath'
    'Get-LordZSteamCmdInstallDir'
    'Get-LordZSteamCmdInstallPath'
    'Install-LordZSteamCmd'
    'Test-LordZSteamAppId'
    'Test-LordZSteamAppIdViaStore'
    'Invoke-LordZSteamCmdLogin'
    'Start-LordZSteamCmdConsoleSession'
    'Send-LordZSteamCmdConsoleLine'
    'Stop-LordZSteamCmdConsoleSession'
    'Invoke-LordZSteamCmdInteractive'
    'Initialize-LordZSteamSession'
    'Start-LordZMirrorPipeline'
    'Prepare-LordZMirrorPipeline'
    'Invoke-LordZSteamCmdHostedScript'
    'Build-LordZMirrorBatchScript'
    'New-LordZMirrorRunPackage'
    'Write-LordZUtf8NoBom'
    'Repair-LordZUnixLineEndings'
    'Get-LordZAsciiBanner'
    'Get-LordZAsciiBannerRunnerLines'
    'Invoke-LordZSteamCmdScript'
    'Get-LordZWorkshopFileDetails'
    'Test-LordZWorkshopModAvailable'
    'Get-LordZVdfCache'
    'Get-LordZWorkshopContentPath'
    'New-LordZWorkshopVdf'
    'Get-LordZDiscordConfig'
    'Get-LordZDiscordConfigPath'
    'Test-LordZDiscordConfig'
    'Open-LordZDiscordInvite'
    'Send-LordZDiscordHelpMessage'
    'Invoke-LordZDiscordBotRequest'
    'Get-LordZDiscordBotUserId'
    'Get-LordZDiscordMessageText'
    'Start-LordZDiscordHelpChatSession'
    'Send-LordZDiscordHelpChatMessage'
    'Get-LordZDiscordHelpChatUpdates'
)
