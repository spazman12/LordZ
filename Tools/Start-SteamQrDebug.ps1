#Requires -Version 5.1
<#
.SYNOPSIS
    Temporary local backend for debugging/fixing Steam QR polling.
.DESCRIPTION
    Proxies Steam IAuthenticationService QR calls, keeps the live client_id on the
    server side, and exposes a small dashboard at http://127.0.0.1:8787/
#>

param(
    [int]$Port = 8787,
    [string]$ListenHost = '127.0.0.1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:InstallRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:InstallRoot 'Modules\LordZ.SteamAuth.psm1') -Force

$script:SteamApiBase = 'https://api.steampowered.com'
$script:Sessions = @{}
$script:EventLog = New-Object System.Collections.Generic.List[string]
$script:Listener = $null

function Add-QrDebugLog {
    param([string]$Message)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
    [void]$script:EventLog.Add($line)
    if ($script:EventLog.Count -gt 300) {
        $script:EventLog.RemoveAt(0)
    }
    Write-Host $line
}

function Get-QrSessionKey {
    param([byte[]]$RequestId)
    return [Convert]::ToBase64String($RequestId)
}

function Invoke-SteamAuthForward {
    param(
        [Parameter(Mandatory)][string]$ApiMethod,
        [Parameter(Mandatory)][byte[]]$RequestBytes
    )

    $url = '{0}/IAuthenticationService/{1}/v1/' -f $script:SteamApiBase, $ApiMethod
    $formBody = 'input_protobuf_encoded=' + [Uri]::EscapeDataString([Convert]::ToBase64String($RequestBytes))
    $formBytes = [Text.Encoding]::UTF8.GetBytes($formBody)

    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Method = 'POST'
        $request.ContentType = 'application/x-www-form-urlencoded'
        $request.Accept = 'application/json, text/plain, */*'
        $request.UserAgent = 'okhttp/4.9.2'
        $request.Headers.Add('Cookie', 'mobileClient=android; mobileClientVersion=777777 3.10.3')
        $request.ContentLength = $formBytes.Length

        $requestStream = $request.GetRequestStream()
        try {
            $requestStream.Write($formBytes, 0, $formBytes.Length)
        }
        finally {
            $requestStream.Close()
        }

        $response = $request.GetResponse()
        try {
            $responseStream = $response.GetResponseStream()
            $memoryStream = New-Object System.IO.MemoryStream
            try {
                $responseStream.CopyTo($memoryStream)
                $bodyBytes = $memoryStream.ToArray()
            }
            finally {
                $memoryStream.Close()
                $responseStream.Close()
            }

            return [PSCustomObject]@{
                StatusCode = [int]$response.StatusCode
                BodyBytes  = $bodyBytes
                Headers    = @{
                    EResult      = $response.Headers['X-eresult']
                    ErrorMessage = $response.Headers['X-error_message']
                }
            }
        }
        finally {
            $response.Close()
        }
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function Handle-BeginAuthSessionViaQr {
    $requestBytes = [LordZSteamAuthApi]::BuildBeginAuthSessionViaQrRequest()
    Add-QrDebugLog 'BEGIN QR session requested by client.'

    $forward = Invoke-SteamAuthForward -ApiMethod 'BeginAuthSessionViaQR' -RequestBytes $requestBytes
    if ($forward.StatusCode -lt 200 -or $forward.StatusCode -ge 300) {
        throw ('Steam begin QR failed with HTTP {0}' -f $forward.StatusCode)
    }

    if ($forward.Headers.EResult -and $forward.Headers.EResult -ne '1') {
        Add-QrDebugLog ('BEGIN Steam EResult {0}: {1}' -f $forward.Headers.EResult, $forward.Headers.ErrorMessage)
        return $forward
    }

    $session = [LordZSteamAuthApi]::DecodeBeginAuthSessionViaQrBytes($forward.BodyBytes)
    $sessionKey = Get-QrSessionKey -RequestId $session.RequestId

    $script:Sessions[$sessionKey] = [PSCustomObject]@{
        SessionKey          = $sessionKey
        ClientId            = $session.ClientId
        RequestId           = $session.RequestId
        ChallengeUrl        = $session.ChallengeUrl
        PollInterval        = [Math]::Max(1.5, [double]$session.PollInterval)
        CreatedAt           = Get-Date
        LastPollAt          = $null
        PollCount           = 0
        RemoteInteraction   = $false
        Complete            = $false
        AccountName         = ''
        ClientIdCorrections = 0
    }

    Add-QrDebugLog ('BEGIN OK client_id={0} challenge={1}' -f $session.ClientId, $session.ChallengeUrl)
    return $forward
}

function Handle-PollAuthSessionStatus {
    param([Parameter(Mandatory)][byte[]]$IncomingRequestBytes)

    $incoming = [LordZSteamAuthApi]::DecodePollAuthSessionStatusRequestBytes($IncomingRequestBytes)
    if (-not $incoming.RequestId -or $incoming.RequestId.Length -eq 0) {
        throw 'Poll request missing request_id.'
    }

    $sessionKey = Get-QrSessionKey -RequestId $incoming.RequestId
    $forwardRequestBytes = $IncomingRequestBytes

    if ($script:Sessions.ContainsKey($sessionKey)) {
        $state = $script:Sessions[$sessionKey]
        $clientIdToUse = [uint64]$state.ClientId

        if ($incoming.ClientId -ne 0 -and [uint64]$incoming.ClientId -ne $clientIdToUse) {
            $state.ClientIdCorrections++
            Add-QrDebugLog ('POLL corrected stale client_id {0} -> {1}' -f $incoming.ClientId, $clientIdToUse)
        }

        $forwardRequestBytes = [LordZSteamAuthApi]::BuildPollAuthSessionStatusRequest($clientIdToUse, $state.RequestId)
    }
    else {
        Add-QrDebugLog 'POLL unknown session; forwarding request unchanged.'
    }

    $forward = Invoke-SteamAuthForward -ApiMethod 'PollAuthSessionStatus' -RequestBytes $forwardRequestBytes

    if ($forward.StatusCode -lt 200 -or $forward.StatusCode -ge 300) {
        throw ('Steam poll failed with HTTP {0}' -f $forward.StatusCode)
    }

    if ($forward.Headers.EResult -and $forward.Headers.EResult -ne '1') {
        Add-QrDebugLog ('POLL Steam EResult {0}: {1}' -f $forward.Headers.EResult, $forward.Headers.ErrorMessage)
        return $forward
    }

    if ($script:Sessions.ContainsKey($sessionKey)) {
        $state = $script:Sessions[$sessionKey]
        $poll = [LordZSteamAuthApi]::DecodePollAuthSessionStatusBytes($forward.BodyBytes)
        $state.PollCount++
        $state.LastPollAt = Get-Date

        if ($poll.NewClientId -and [uint64]$poll.NewClientId -ne [uint64]$state.ClientId) {
            Add-QrDebugLog ('POLL Steam rotated client_id {0} -> {1}' -f $state.ClientId, $poll.NewClientId)
            $state.ClientId = [uint64]$poll.NewClientId
        }

        if ($poll.RemoteInteraction) {
            $state.RemoteInteraction = $true
        }

        if ($poll.Complete) {
            $state.Complete = $true
            $state.AccountName = $poll.AccountName
            Add-QrDebugLog ('POLL COMPLETE account={0}' -f $poll.AccountName)
        }
        else {
            $status = if ($poll.RemoteInteraction) { 'scanned, waiting for phone approval' } else { 'waiting for scan' }
            Add-QrDebugLog ('POLL #{0} {1}' -f $state.PollCount, $status)
        }
    }

    return $forward
}

function Read-RequestBodyBytes {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) {
        return [byte[]]@()
    }

    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [byte[]]@()
    }

    if ($raw -match '(?:^|&)input_protobuf_encoded=([^&]+)') {
        return [Convert]::FromBase64String([System.Uri]::UnescapeDataString($Matches[1]))
    }

    return [Text.Encoding]::UTF8.GetBytes($raw)
}

function Write-RawResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$ContentType = 'application/octet-stream',
        [byte[]]$BodyBytes = [byte[]]@(),
        [hashtable]$Headers
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    if ($Headers) {
        foreach ($key in $Headers.Keys) {
            if ($null -ne $Headers[$key]) {
                $Response.Headers[$key] = [string]$Headers[$key]
            }
        }
    }

    $Response.ContentLength64 = $BodyBytes.Length
    if ($BodyBytes.Length -gt 0) {
        $Response.OutputStream.Write($BodyBytes, 0, $BodyBytes.Length)
    }
    $Response.OutputStream.Close()
}

function Get-QrDebugDashboardHtml {
    $sessionRows = foreach ($session in $script:Sessions.Values) {
        $status = if ($session.Complete) { 'complete' } elseif ($session.RemoteInteraction) { 'scanned' } else { 'waiting' }
        @"
<tr>
  <td>$($session.SessionKey.Substring(0, [Math]::Min(12, $session.SessionKey.Length)))...</td>
  <td>$($session.ClientId)</td>
  <td>$status</td>
  <td>$($session.PollCount)</td>
  <td>$($session.ClientIdCorrections)</td>
  <td><a href="$($session.ChallengeUrl)" target="_blank">open</a></td>
</tr>
"@
    }

    if (-not $sessionRows) {
        $sessionRows = '<tr><td colspan="6">No active sessions yet. Click Login with QR Code in LordZ.</td></tr>'
    }

    $logLines = ($script:EventLog | Select-Object -Last 40 | ForEach-Object {
        $encoded = [System.Net.WebUtility]::HtmlEncode($_)
        "<div class='log'>$encoded</div>"
    }) -join "`n"

    return @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>LordZ Steam QR Debug Backend</title>
  <style>
    body { font-family: Segoe UI, sans-serif; background:#120804; color:#f5d7b0; margin:24px; }
    h1 { color:#ff9f2f; }
    .card { background:#24120a; border:1px solid #6f3b12; border-radius:8px; padding:16px; margin-bottom:16px; }
    table { width:100%; border-collapse:collapse; }
    td, th { border-bottom:1px solid #4a2810; padding:8px; text-align:left; }
    .log { font-family: Consolas, monospace; font-size: 12px; padding:2px 0; color:#d8b48a; }
    .ok { color:#7dffb0; }
  </style>
  <meta http-equiv="refresh" content="3" />
</head>
<body>
  <h1>LordZ Steam QR Debug Backend</h1>
  <div class="card">
    <div class="ok">Online on http://127.0.0.1:$Port</div>
    <p>LordZ should auto-connect here. This backend fixes stale client_id during polling.</p>
    <p>Open LordZ, click <strong>Login with QR Code</strong>, then watch this page update.</p>
  </div>
  <div class="card">
    <h2>Active Sessions</h2>
    <table>
      <tr><th>Session</th><th>Client ID</th><th>Status</th><th>Polls</th><th>Corrections</th><th>QR</th></tr>
      $sessionRows
    </table>
  </div>
  <div class="card">
    <h2>Recent Log</h2>
    $logLines
  </div>
</body>
</html>
"@
}

function Start-QrDebugServer {
    $prefix = "http://${ListenHost}:${Port}/"
    $script:Listener = New-Object System.Net.HttpListener
    [void]$script:Listener.Prefixes.Add($prefix)
    $script:Listener.Start()

    Add-QrDebugLog "QR debug backend listening at $prefix"
    Add-QrDebugLog 'Waiting for LordZ to connect and start QR login...'

    while ($script:Listener.IsListening) {
        $context = $script:Listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath.TrimEnd('/')

        try {
            if ($path -eq '' -or $path -eq '/') {
                $html = Get-QrDebugDashboardHtml
                $bytes = [Text.Encoding]::UTF8.GetBytes($html)
                Write-RawResponse -Response $response -ContentType 'text/html; charset=utf-8' -BodyBytes $bytes
                continue
            }

            if ($path -eq '/api/status') {
                $payload = [PSCustomObject]@{
                    service  = 'LordZ Steam QR Debug Backend'
                    online   = $true
                    sessions = @($script:Sessions.Values | ForEach-Object {
                        [PSCustomObject]@{
                            clientId          = $_.ClientId
                            pollCount         = $_.PollCount
                            remoteInteraction = $_.RemoteInteraction
                            complete          = $_.Complete
                            accountName       = $_.AccountName
                            corrections       = $_.ClientIdCorrections
                            challengeUrl      = $_.ChallengeUrl
                        }
                    })
                }
                $json = $payload | ConvertTo-Json -Depth 5
                $bytes = [Text.Encoding]::UTF8.GetBytes($json)
                Write-RawResponse -Response $response -ContentType 'application/json; charset=utf-8' -BodyBytes $bytes
                continue
            }

            if ($path -eq '/api/logs') {
                $json = ($script:EventLog | ConvertTo-Json)
                $bytes = [Text.Encoding]::UTF8.GetBytes($json)
                Write-RawResponse -Response $response -ContentType 'application/json; charset=utf-8' -BodyBytes $bytes
                continue
            }

            if ($path -eq '/IAuthenticationService/BeginAuthSessionViaQR/v1') {
                $result = Handle-BeginAuthSessionViaQr
                Write-RawResponse -Response $response -BodyBytes $result.BodyBytes -Headers @{
                    'X-eresult'       = $result.Headers.EResult
                    'X-error_message' = $result.Headers.ErrorMessage
                }
                continue
            }

            if ($path -eq '/IAuthenticationService/PollAuthSessionStatus/v1') {
                $incoming = Read-RequestBodyBytes -Request $request
                $result = Handle-PollAuthSessionStatus -IncomingRequestBytes $incoming
                Write-RawResponse -Response $response -BodyBytes $result.BodyBytes -Headers @{
                    'X-eresult'       = $result.Headers.EResult
                    'X-error_message' = $result.Headers.ErrorMessage
                }
                continue
            }

            Write-RawResponse -Response $response -StatusCode 404 -ContentType 'text/plain' -BodyBytes ([Text.Encoding]::UTF8.GetBytes('Not found'))
        }
        catch {
            Add-QrDebugLog ('ERROR {0} {1}' -f $path, $_.Exception.Message)
            $message = $_.Exception.Message
            Write-RawResponse -Response $response -StatusCode 500 -ContentType 'text/plain' -BodyBytes ([Text.Encoding]::UTF8.GetBytes($message))
        }
    }
}

try {
    Start-QrDebugServer
}
catch [System.Net.HttpListenerException] {
    Add-QrDebugLog ("Could not bind to http://${ListenHost}:${Port}. Port may already be in use.")
    throw
}
finally {
    if ($script:Listener) {
        try {
            if ($script:Listener.IsListening) {
                $script:Listener.Stop()
            }
        }
        catch { }

        try {
            $script:Listener.Close()
        }
        catch { }
    }
}
