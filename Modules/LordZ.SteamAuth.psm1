# Lord Zolton Steam QR Authentication
# Uses Steam IAuthenticationService Web API (same flow as the Steam mobile app QR login).

Set-StrictMode -Version Latest

if (-not ('LordZSteamAuthApi' -as [type])) {
    $steamAuthSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

public sealed class LordZSteamQrSession
{
    public ulong ClientId { get; set; }
    public byte[] RequestId { get; set; }
    public string ChallengeUrl { get; set; }
    public float PollInterval { get; set; }
}

public sealed class LordZSteamPollRequest
{
    public ulong ClientId { get; set; }
    public byte[] RequestId { get; set; }
}

public sealed class LordZSteamQrPollResult
{
    public ulong NewClientId { get; set; }
    public bool Complete { get; set; }
    public bool RemoteInteraction { get; set; }
    public string AccountName { get; set; }
    public string RefreshToken { get; set; }
    public string AccessToken { get; set; }
    public string NewChallengeUrl { get; set; }
}

internal static class LordZSteamProtobuf
{
    public static byte[] EncodeBeginAuthSessionViaQr()
    {
        var deviceDetails = new MemoryStream();
        WriteString(deviceDetails, 1, "LordZ Mirror Engine");
        WriteVarint(deviceDetails, 2, 3); // MobileApp
        WriteSignedVarint(deviceDetails, 3, -500); // AndroidUnknown
        WriteVarint(deviceDetails, 4, 528);

        var request = new MemoryStream();
        WriteMessage(request, 3, deviceDetails.ToArray());
        WriteString(request, 4, "Mobile");
        return request.ToArray();
    }

    public static byte[] EncodePollAuthSessionStatus(ulong clientId, byte[] requestId)
    {
        var request = new MemoryStream();
        WriteVarint(request, 1, clientId);
        WriteBytes(request, 2, requestId);
        return request.ToArray();
    }

    public static LordZSteamPollRequest DecodePollAuthSessionStatusRequest(byte[] data)
    {
        var request = new LordZSteamPollRequest();
        foreach (var field in ReadFields(data))
        {
            switch (field.Number)
            {
                case 1:
                    request.ClientId = ReadVarint(field.Value);
                    break;
                case 2:
                    request.RequestId = field.Value;
                    break;
            }
        }

        return request;
    }

    public static LordZSteamQrSession DecodeBeginAuthSessionViaQr(byte[] data)
    {
        var session = new LordZSteamQrSession { PollInterval = 2f };
        foreach (var field in ReadFields(data))
        {
            switch (field.Number)
            {
                case 1:
                    session.ClientId = ReadVarint(field.Value);
                    break;
                case 2:
                    session.ChallengeUrl = Encoding.UTF8.GetString(field.Value);
                    break;
                case 3:
                    session.RequestId = field.Value;
                    break;
                case 4:
                    session.PollInterval = ReadFloat(field.Value);
                    break;
            }
        }

        if (session.ClientId == 0 || session.RequestId == null || session.RequestId.Length == 0 || string.IsNullOrWhiteSpace(session.ChallengeUrl))
        {
            throw new InvalidOperationException("Steam QR session response was incomplete.");
        }

        return session;
    }

    public static LordZSteamQrPollResult DecodePollAuthSessionStatus(byte[] data)
    {
        var result = new LordZSteamQrPollResult();
        foreach (var field in ReadFields(data))
        {
            switch (field.Number)
            {
                case 1:
                    result.NewClientId = ReadVarint(field.Value);
                    break;
                case 2:
                    result.NewChallengeUrl = Encoding.UTF8.GetString(field.Value);
                    break;
                case 3:
                    result.RefreshToken = Encoding.UTF8.GetString(field.Value);
                    result.Complete = !string.IsNullOrWhiteSpace(result.RefreshToken);
                    break;
                case 4:
                    result.AccessToken = Encoding.UTF8.GetString(field.Value);
                    break;
                case 5:
                    result.RemoteInteraction = field.Value.Length > 0 && field.Value[0] != 0;
                    break;
                case 6:
                    result.AccountName = Encoding.UTF8.GetString(field.Value);
                    break;
            }
        }

        return result;
    }

    private sealed class ProtoField
    {
        public int Number;
        public byte[] Value;
    }

    private static IEnumerable<ProtoField> ReadFields(byte[] data)
    {
        int offset = 0;
        while (offset < data.Length)
        {
            ulong tag = ReadVarint(data, ref offset);
            int fieldNumber = (int)(tag >> 3);
            int wireType = (int)(tag & 7);
            byte[] value;

            switch (wireType)
            {
                case 0:
                    ulong varint = ReadVarint(data, ref offset);
                    value = EncodeVarint(varint);
                    break;
                case 1:
                    value = new byte[8];
                    Buffer.BlockCopy(data, offset, value, 0, 8);
                    offset += 8;
                    break;
                case 2:
                    int length = (int)ReadVarint(data, ref offset);
                    value = new byte[length];
                    Buffer.BlockCopy(data, offset, value, 0, length);
                    offset += length;
                    break;
                case 5:
                    value = new byte[4];
                    Buffer.BlockCopy(data, offset, value, 0, 4);
                    offset += 4;
                    break;
                default:
                    throw new InvalidOperationException("Unsupported protobuf wire type: " + wireType);
            }

            yield return new ProtoField { Number = fieldNumber, Value = value };
        }
    }

    private static void WriteVarint(Stream stream, int fieldNumber, ulong value)
    {
        WriteTag(stream, fieldNumber, 0);
        WriteVarint(stream, value);
    }

    private static void WriteSignedVarint(Stream stream, int fieldNumber, int value)
    {
        WriteTag(stream, fieldNumber, 0);
        WriteSignedVarint(stream, value);
    }

    private static void WriteString(Stream stream, int fieldNumber, string value)
    {
        WriteTag(stream, fieldNumber, 2);
        var bytes = Encoding.UTF8.GetBytes(value ?? string.Empty);
        WriteVarint(stream, (ulong)bytes.Length);
        stream.Write(bytes, 0, bytes.Length);
    }

    private static void WriteBytes(Stream stream, int fieldNumber, byte[] value)
    {
        WriteTag(stream, fieldNumber, 2);
        int length = value == null ? 0 : value.Length;
        WriteVarint(stream, (ulong)length);
        if (length > 0)
        {
            stream.Write(value, 0, length);
        }
    }

    private static void WriteMessage(Stream stream, int fieldNumber, byte[] value)
    {
        WriteTag(stream, fieldNumber, 2);
        int length = value == null ? 0 : value.Length;
        WriteVarint(stream, (ulong)length);
        if (length > 0)
        {
            stream.Write(value, 0, length);
        }
    }

    private static void WriteTag(Stream stream, int fieldNumber, int wireType)
    {
        WriteVarint(stream, (ulong)((fieldNumber << 3) | wireType));
    }

    private static void WriteVarint(Stream stream, ulong value)
    {
        var bytes = EncodeVarint(value);
        stream.Write(bytes, 0, bytes.Length);
    }

    private static void WriteSignedVarint(Stream stream, int value)
    {
        long encoded = value;
        while (true)
        {
            byte part = (byte)(encoded & 0x7F);
            encoded >>= 7;
            if ((encoded == 0 && (part & 0x40) == 0) || (encoded == -1 && (part & 0x40) != 0))
            {
                stream.WriteByte(part);
                break;
            }

            stream.WriteByte((byte)(part | 0x80));
        }
    }

    private static byte[] EncodeVarint(ulong value)
    {
        var buffer = new MemoryStream();
        while (value >= 0x80)
        {
            buffer.WriteByte((byte)((value & 0x7F) | 0x80));
            value >>= 7;
        }

        buffer.WriteByte((byte)value);
        return buffer.ToArray();
    }

    private static ulong ReadVarint(byte[] data, ref int offset)
    {
        ulong result = 0;
        int shift = 0;
        while (offset < data.Length)
        {
            byte b = data[offset++];
            result |= (ulong)(b & 0x7F) << shift;
            if ((b & 0x80) == 0)
            {
                return result;
            }

            shift += 7;
            if (shift > 63)
            {
                throw new InvalidOperationException("Protobuf varint overflow.");
            }
        }

        throw new InvalidOperationException("Protobuf stream ended before varint completed.");
    }

    private static ulong ReadVarint(byte[] data)
    {
        int offset = 0;
        return ReadVarint(data, ref offset);
    }

    private static float ReadFloat(byte[] data)
    {
        if (data.Length != 4)
        {
            return 2f;
        }

        if (BitConverter.IsLittleEndian)
        {
            return BitConverter.ToSingle(data, 0);
        }

        var reversed = (byte[])data.Clone();
        Array.Reverse(reversed);
        return BitConverter.ToSingle(reversed, 0);
    }
}

public static class LordZSteamAuthApi
{
    private static string ApiBase = "https://api.steampowered.com";
    private static readonly HttpClient Client = CreateClient();

    public static void SetApiBase(string apiBase)
    {
        if (string.IsNullOrWhiteSpace(apiBase))
        {
            ApiBase = "https://api.steampowered.com";
            return;
        }

        ApiBase = apiBase.Trim().TrimEnd('/');
    }

    public static string GetApiBase()
    {
        return ApiBase;
    }

    public static byte[] BuildBeginAuthSessionViaQrRequest()
    {
        return LordZSteamProtobuf.EncodeBeginAuthSessionViaQr();
    }

    public static byte[] BuildPollAuthSessionStatusRequest(ulong clientId, byte[] requestId)
    {
        return LordZSteamProtobuf.EncodePollAuthSessionStatus(clientId, requestId);
    }

    public static LordZSteamQrSession DecodeBeginAuthSessionViaQrBytes(byte[] responseBytes)
    {
        return LordZSteamProtobuf.DecodeBeginAuthSessionViaQr(responseBytes);
    }

    public static LordZSteamQrPollResult DecodePollAuthSessionStatusBytes(byte[] responseBytes)
    {
        return LordZSteamProtobuf.DecodePollAuthSessionStatus(responseBytes);
    }

    public static LordZSteamPollRequest DecodePollAuthSessionStatusRequestBytes(byte[] requestBytes)
    {
        return LordZSteamProtobuf.DecodePollAuthSessionStatusRequest(requestBytes);
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");
        client.DefaultRequestHeaders.TryAddWithoutValidation("sec-fetch-site", "cross-site");
        client.DefaultRequestHeaders.TryAddWithoutValidation("sec-fetch-mode", "cors");
        client.DefaultRequestHeaders.TryAddWithoutValidation("sec-fetch-dest", "empty");
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "okhttp/4.9.2");
        client.DefaultRequestHeaders.TryAddWithoutValidation("Cookie", "mobileClient=android; mobileClientVersion=777777 3.10.3");
        return client;
    }

    public static LordZSteamQrSession BeginQrSession()
    {
        return BeginQrSessionAsync().GetAwaiter().GetResult();
    }

    public static LordZSteamQrPollResult PollSession(ulong clientId, byte[] requestId)
    {
        return PollSessionAsync(clientId, requestId).GetAwaiter().GetResult();
    }

    private static async Task<LordZSteamQrSession> BeginQrSessionAsync()
    {
        var requestBytes = LordZSteamProtobuf.EncodeBeginAuthSessionViaQr();
        var responseBytes = await SendProtobufRequestAsync(
            "Authentication",
            "BeginAuthSessionViaQR",
            1,
            requestBytes).ConfigureAwait(false);
        return LordZSteamProtobuf.DecodeBeginAuthSessionViaQr(responseBytes);
    }

    private static async Task<LordZSteamQrPollResult> PollSessionAsync(ulong clientId, byte[] requestId)
    {
        var requestBytes = LordZSteamProtobuf.EncodePollAuthSessionStatus(clientId, requestId);
        var responseBytes = await SendProtobufRequestAsync(
            "Authentication",
            "PollAuthSessionStatus",
            1,
            requestBytes).ConfigureAwait(false);
        return LordZSteamProtobuf.DecodePollAuthSessionStatus(responseBytes);
    }

    private static async Task<byte[]> SendProtobufRequestAsync(string apiInterface, string apiMethod, int apiVersion, byte[] requestBytes)
    {
        string url = string.Format("{0}/I{1}Service/{2}/v{3}/", ApiBase, apiInterface, apiMethod, apiVersion);
        using (var content = new FormUrlEncodedContent(new[]
        {
            new KeyValuePair<string, string>("input_protobuf_encoded", Convert.ToBase64String(requestBytes))
        }))
        using (var response = await Client.PostAsync(url, content).ConfigureAwait(false))
        {
            byte[] bodyBytes = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                string bodyText = bodyBytes.Length == 0 ? string.Empty : Encoding.UTF8.GetString(bodyBytes);
                throw new InvalidOperationException("Steam API HTTP " + (int)response.StatusCode + ": " + bodyText);
            }

            IEnumerable<string> eresultValues;
            if (response.Headers.TryGetValues("X-eresult", out eresultValues))
            {
                foreach (string value in eresultValues)
                {
                    int eresult;
                    if (int.TryParse(value, out eresult) && eresult != 1)
                    {
                        string errorMessage = null;
                        IEnumerable<string> errorValues;
                        if (response.Headers.TryGetValues("X-error_message", out errorValues))
                        {
                            foreach (string error in errorValues)
                            {
                                errorMessage = error;
                                break;
                            }
                        }

                        throw new InvalidOperationException(string.IsNullOrWhiteSpace(errorMessage)
                            ? ("Steam API error EResult " + eresult)
                            : errorMessage);
                    }
                }
            }

            return ExtractResponseBytes(bodyBytes);
        }
    }

    private static byte[] ExtractResponseBytes(byte[] bodyBytes)
    {
        if (bodyBytes == null || bodyBytes.Length == 0)
        {
            return new byte[0];
        }

        if (bodyBytes[0] == (byte)'{')
        {
            string body = Encoding.UTF8.GetString(bodyBytes);
            string encoded = ExtractJsonStringValue(body, "response");
            if (!string.IsNullOrWhiteSpace(encoded))
            {
                return Convert.FromBase64String(encoded);
            }
        }

        return bodyBytes;
    }

    private static string ExtractJsonStringValue(string json, string key)
    {
        string marker = "\"" + key + "\":\"";
        int start = json.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (start < 0)
        {
            return null;
        }

        start += marker.Length;
        var builder = new StringBuilder();
        bool escaping = false;
        for (int i = start; i < json.Length; i++)
        {
            char ch = json[i];
            if (escaping)
            {
                builder.Append(ch);
                escaping = false;
                continue;
            }

            if (ch == '\\')
            {
                escaping = true;
                continue;
            }

            if (ch == '"')
            {
                break;
            }

            builder.Append(ch);
        }

        return builder.Length > 0 ? builder.ToString() : null;
    }
}
'@

    Add-Type -TypeDefinition $steamAuthSource -ReferencedAssemblies @(
        'System.Net.Http'
    ) -ErrorAction Stop
}

function Start-LordZSteamQrLogin {
    try {
        $session = [LordZSteamAuthApi]::BeginQrSession()
        return [PSCustomObject]@{
            Success       = $true
            ClientId      = $session.ClientId
            RequestId     = $session.RequestId
            ChallengeUrl  = $session.ChallengeUrl
            PollInterval  = [Math]::Max(1.5, [double]$session.PollInterval)
            Message       = 'QR session started.'
        }
    }
    catch {
        return [PSCustomObject]@{
            Success      = $false
            Message      = $_.Exception.Message
        }
    }
}

function Get-LordZSteamQrPollStatus {
    param(
        [Parameter(Mandatory)][uint64]$ClientId,
        [Parameter(Mandatory)][byte[]]$RequestId
    )

    try {
        $result = [LordZSteamAuthApi]::PollSession($ClientId, $RequestId)
        return [PSCustomObject]@{
            Success            = $true
            NewClientId        = $result.NewClientId
            Complete           = $result.Complete
            RemoteInteraction  = $result.RemoteInteraction
            AccountName        = $result.AccountName
            RefreshToken       = $result.RefreshToken
            AccessToken        = $result.AccessToken
            NewChallengeUrl    = $result.NewChallengeUrl
            Message            = if ($result.Complete) { 'QR login approved.' } else { 'Waiting for approval...' }
        }
    }
    catch {
        return [PSCustomObject]@{
            Success   = $false
            Complete  = $false
            Message   = $_.Exception.Message
        }
    }
}

function Set-LordZSteamQrDebugBackend {
    param(
        [string]$BaseUrl = 'http://127.0.0.1:8787',
        [switch]$Disable
    )

    if ($Disable) {
        [LordZSteamAuthApi]::SetApiBase($null)
        return [PSCustomObject]@{
            Enabled = $false
            BaseUrl = [LordZSteamAuthApi]::GetApiBase()
        }
    }

    $normalized = $BaseUrl.Trim().TrimEnd('/')
    [LordZSteamAuthApi]::SetApiBase($normalized)
    return [PSCustomObject]@{
        Enabled = $true
        BaseUrl = [LordZSteamAuthApi]::GetApiBase()
    }
}

function Test-LordZSteamQrDebugBackend {
    param([string]$BaseUrl = 'http://127.0.0.1:8787')

    $statusUrl = ($BaseUrl.Trim().TrimEnd('/')) + '/api/status'
    try {
        $response = Invoke-WebRequest -Uri $statusUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $payload = $response.Content | ConvertFrom-Json
        return [PSCustomObject]@{
            Online  = $true
            BaseUrl = $BaseUrl
            Status  = $payload
        }
    }
    catch {
        return [PSCustomObject]@{
            Online  = $false
            BaseUrl = $BaseUrl
            Message = $_.Exception.Message
        }
    }
}

function Connect-LordZSteamQrDebugBackend {
    param([string]$BaseUrl = 'http://127.0.0.1:8787')

    $check = Test-LordZSteamQrDebugBackend -BaseUrl $BaseUrl
    if (-not $check.Online) {
        return [PSCustomObject]@{
            Connected = $false
            Message     = "QR debug backend is not running at $BaseUrl. Start Tools\Start-SteamQrDebug.bat first."
        }
    }

    $connected = Set-LordZSteamQrDebugBackend -BaseUrl $BaseUrl
    return [PSCustomObject]@{
        Connected = $true
        BaseUrl   = $connected.BaseUrl
        Message   = 'LordZ is routing Steam QR auth through the local debug backend.'
    }
}

function Get-LordZSteamQrCodeImage {
    param(
        [Parameter(Mandatory)][string]$ChallengeUrl,
        [int]$Size = 240
    )

    $encoded = [System.Uri]::EscapeDataString($ChallengeUrl)
    $qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=${Size}x${Size}&margin=10&data=$encoded"

    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
        $bytes = Invoke-WebRequest -Uri $qrUrl -UseBasicParsing -ErrorAction Stop
        $stream = New-Object System.IO.MemoryStream (, $bytes.Content)
        return [System.Drawing.Image]::FromStream($stream)
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

Export-ModuleMember -Function @(
    'Start-LordZSteamQrLogin'
    'Get-LordZSteamQrPollStatus'
    'Get-LordZSteamQrCodeImage'
    'Set-LordZSteamQrDebugBackend'
    'Test-LordZSteamQrDebugBackend'
    'Connect-LordZSteamQrDebugBackend'
)
