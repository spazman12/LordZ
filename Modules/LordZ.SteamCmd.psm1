# Lord Zolton SteamCMD credential cache + login integration

Set-StrictMode -Version Latest

if (-not ('LordZSteamCmdAuth' -as [type])) {
    $steamCmdAuthSource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

public static class LordZSteamCmdAuth
{
    private static readonly int[] ObfTable = new int[]
    {
        unchecked((int)0x1739a3b0), unchecked((int)0xb8907fe1), unchecked((int)0x8290d3b7), unchecked((int)0x72839cd0),
        unchecked((int)0x242df096), unchecked((int)0x3829750b), unchecked((int)0x38de7a77), unchecked((int)0x72f0924c),
        unchecked((int)0x44783927), unchecked((int)0x01925372), unchecked((int)0x20902714), unchecked((int)0x27585920),
        unchecked((int)0x27890632), unchecked((int)0x82910476), unchecked((int)0x72906721), unchecked((int)0x28798904),
        unchecked((int)0x78592700)
    };

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DataBlob
    {
        public uint cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CryptProtectData(
        ref DataBlob dataIn,
        string description,
        ref DataBlob entropy,
        IntPtr reserved,
        IntPtr promptStruct,
        uint flags,
        ref DataBlob dataOut);

    public static string GetConnectCacheKey(string accountName)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(accountName ?? string.Empty);
        uint crc = Crc32(bytes);
        return crc.ToString("x") + "1";
    }

    public static string GetSteamIdFromJwt(string jwt)
    {
        if (string.IsNullOrWhiteSpace(jwt))
        {
            return null;
        }

        string[] parts = jwt.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        string payload = parts[1].Replace('-', '+').Replace('_', '/');
        switch (payload.Length % 4)
        {
            case 2: payload += "=="; break;
            case 3: payload += "="; break;
        }

        string json = Encoding.UTF8.GetString(Convert.FromBase64String(payload));
        Match match = Regex.Match(json, "\"sub\"\\s*:\\s*\"([^\"]+)\"");
        if (!match.Success)
        {
            return null;
        }

        return match.Groups[1].Value;
    }

    public static void ApplyRefreshToken(string steamCmdDir, string accountName, string refreshToken)
    {
        if (string.IsNullOrWhiteSpace(steamCmdDir))
        {
            throw new ArgumentException("SteamCMD directory is required.");
        }

        if (string.IsNullOrWhiteSpace(accountName))
        {
            throw new ArgumentException("Account name is required.");
        }

        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            throw new ArgumentException("Refresh token is required.");
        }

        string steamId = GetSteamIdFromJwt(refreshToken);
        if (string.IsNullOrWhiteSpace(steamId))
        {
            throw new InvalidOperationException("Refresh token did not contain a Steam ID.");
        }

        string configDir = Path.Combine(steamCmdDir, "config");
        Directory.CreateDirectory(configDir);

        string configPath = Path.Combine(configDir, "config.vdf");
        string localPath = Path.Combine(steamCmdDir, "local.vdf");
        string appDataLocal = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Steam",
            "local.vdf");

        long mtbf = ReadMtbf(configPath);
        if (mtbf <= 0)
        {
            mtbf = CreateMtbf();
        }

        string cacheKey = GetConnectCacheKey(accountName);
        string encoded = ObfuscateToken(refreshToken + "\0", mtbf);

        WriteConfigVdf(configPath, accountName, steamId, cacheKey, encoded, mtbf);

        string protectedHex = ProtectTokenHex(refreshToken, accountName);
        WriteLocalVdf(localPath, cacheKey, protectedHex);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(appDataLocal));
            WriteLocalVdf(appDataLocal, cacheKey, protectedHex);
        }
        catch
        {
        }
    }

    private static long CreateMtbf()
    {
        var random = new Random();
        return (long)random.Next(1000000000, 2000000000);
    }

    private static long ReadMtbf(string configPath)
    {
        if (!File.Exists(configPath))
        {
            return 0;
        }

        string content = File.ReadAllText(configPath);
        Match match = Regex.Match(content, "\"MTBF\"\\s+\"(\\d+)\"");
        if (!match.Success)
        {
            return 0;
        }

        long value;
        if (long.TryParse(match.Groups[1].Value, out value))
        {
            return value;
        }

        return 0;
    }

    private static void WriteConfigVdf(string configPath, string accountName, string steamId, string cacheKey, string encoded, long mtbf)
    {
        if (!File.Exists(configPath))
        {
            string fresh = BuildConfigVdf(accountName, steamId, cacheKey, encoded, mtbf);
            File.WriteAllText(configPath, fresh, Encoding.UTF8);
            return;
        }

        string content = File.ReadAllText(configPath, Encoding.UTF8);
        content = Regex.Replace(content, "\"MTBF\"\\s+\"\\d+\"", "\"MTBF\"\t\t\"" + mtbf + "\"");
        if (!Regex.IsMatch(content, "\"MTBF\""))
        {
            content = InsertBeforeAccounts(content, "\"MTBF\"\t\t\"" + mtbf + "\"\n");
        }

        string connectEntry = "\t\t\t\t\"" + cacheKey + "\"\t\t\"" + encoded + "\0\"";
        if (Regex.IsMatch(content, "\"ConnectCache\"\\s*\\{[^}]*\\}", RegexOptions.Singleline))
        {
            content = Regex.Replace(
                content,
                "\"ConnectCache\"\\s*\\{[^}]*\\}",
                "\"ConnectCache\"\n\t\t\t\t{\n" + connectEntry + "\n\t\t\t\t}",
                RegexOptions.Singleline);
        }
        else
        {
            content = InsertBeforeAccounts(content, "\"ConnectCache\"\n\t\t\t\t{\n" + connectEntry + "\n\t\t\t\t}\n");
        }

        if (Regex.IsMatch(content, "\"Accounts\"\\s*\\{", RegexOptions.Singleline))
        {
            if (!Regex.IsMatch(content, "\"" + Regex.Escape(accountName) + "\"\\s*\\{", RegexOptions.Singleline))
            {
                content = Regex.Replace(
                    content,
                    "\"Accounts\"\\s*\\{",
                    "\"Accounts\"\n\t\t\t\t{\n\t\t\t\t\t\"" + accountName + "\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"SteamID\"\t\t\"" + steamId + "\"\n\t\t\t\t\t}",
                    RegexOptions.Singleline);
            }
            else
            {
                content = Regex.Replace(
                    content,
                    "(\"" + Regex.Escape(accountName) + "\"\\s*\\{[^}]*\"SteamID\"\\s+\")[^\"]*(\")",
                    "${1}" + steamId + "${2}",
                    RegexOptions.Singleline);
            }
        }
        else
        {
            content = InsertBeforeCellId(content,
                "\"Accounts\"\n\t\t\t\t{\n\t\t\t\t\t\"" + accountName + "\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"SteamID\"\t\t\"" + steamId + "\"\n\t\t\t\t\t}\n\t\t\t\t}");
        }

        File.WriteAllText(configPath, content, Encoding.UTF8);
    }

    private static string InsertBeforeAccounts(string content, string block)
    {
        if (Regex.IsMatch(content, "\"Accounts\""))
        {
            return Regex.Replace(content, "\"Accounts\"", block + "\t\t\t\t\"Accounts\"", RegexOptions.Singleline);
        }

        return InsertBeforeCellId(content, block);
    }

    private static string InsertBeforeCellId(string content, string block)
    {
        if (Regex.IsMatch(content, "\"CellIDServerOverride\""))
        {
            return Regex.Replace(content, "\"CellIDServerOverride\"", block + "\t\t\t\t\"CellIDServerOverride\"", RegexOptions.Singleline);
        }

        return Regex.Replace(content, "\n\t\t\t}\n\t\t}\n\t}\n}", "\n\t\t\t\t" + block + "\n\t\t\t}\n\t\t}\n\t}\n}", RegexOptions.Singleline);
    }

    private static string BuildConfigVdf(string accountName, string steamId, string cacheKey, string encoded, long mtbf)
    {
        return "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"MTBF\"\t\t\"" + mtbf + "\"\n\t\t\t\t\"ConnectCache\"\n\t\t\t\t{\n\t\t\t\t\t\"" + cacheKey + "\"\t\t\"" + encoded + "\0\"\n\t\t\t\t}\n\t\t\t\t\"Accounts\"\n\t\t\t\t{\n\t\t\t\t\t\"" + accountName + "\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"SteamID\"\t\t\"" + steamId + "\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n";
    }

    private static void WriteLocalVdf(string path, string cacheKey, string protectedHex)
    {
        string content = "\"MachineUserConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"ConnectCache\"\n\t\t\t\t{\n\t\t\t\t\t\"" + cacheKey + "\"\t\t\"" + protectedHex + "\"\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n";
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, content, Encoding.UTF8);
    }

    private static string ProtectTokenHex(string token, string accountName)
    {
        byte[] data = Encoding.UTF8.GetBytes(token);
        byte[] entropy = Encoding.UTF8.GetBytes(accountName);
        byte[] protectedBytes = ProtectData(data, entropy);
        return BytesToHex(protectedBytes);
    }

    private static byte[] ProtectData(byte[] data, byte[] entropy)
    {
        DataBlob dataIn = new DataBlob();
        DataBlob entropyBlob = new DataBlob();
        DataBlob dataOut = new DataBlob();

        try
        {
            dataIn.pbData = Marshal.AllocHGlobal(data.Length);
            Marshal.Copy(data, 0, dataIn.pbData, data.Length);
            dataIn.cbData = (uint)data.Length;

            entropyBlob.pbData = Marshal.AllocHGlobal(entropy.Length);
            Marshal.Copy(entropy, 0, entropyBlob.pbData, entropy.Length);
            entropyBlob.cbData = (uint)entropy.Length;

            if (!CryptProtectData(ref dataIn, null, ref entropyBlob, IntPtr.Zero, IntPtr.Zero, 0, ref dataOut))
            {
                throw new InvalidOperationException("CryptProtectData failed with code " + Marshal.GetLastWin32Error());
            }

            byte[] output = new byte[dataOut.cbData];
            Marshal.Copy(dataOut.pbData, output, 0, (int)dataOut.cbData);
            return output;
        }
        finally
        {
            if (dataIn.pbData != IntPtr.Zero) Marshal.FreeHGlobal(dataIn.pbData);
            if (entropyBlob.pbData != IntPtr.Zero) Marshal.FreeHGlobal(entropyBlob.pbData);
            if (dataOut.pbData != IntPtr.Zero) Marshal.FreeHGlobal(dataOut.pbData);
        }
    }

    private static string ObfuscateToken(string token, long key)
    {
        byte[] ptext = Encoding.UTF8.GetBytes(token);
        var ctext = new MemoryStream();
        ctext.WriteByte(0x02);
        ctext.WriteByte(0x00);
        ctext.WriteByte(0x00);
        ctext.WriteByte(0x00);

        int k1 = (int)(key >> 31);
        int k2 = (int)key;
        uint csum = 0;
        int offset = 0;

        while (offset + 4 <= ptext.Length)
        {
            k1 = unchecked(k1 + 0x25fe6761);
            k2 = unchecked(k2 + 1);

            uint d = BitConverter.ToUInt32(ptext, offset);
            uint t = unchecked((uint)ObfTable[((uint)k2) % 0x11] ^ (uint)k1 ^ d);
            csum = unchecked(csum + d);

            ctext.Write(BitConverter.GetBytes(t), 0, 4);
            offset += 4;
        }

        while (offset < ptext.Length)
        {
            ctext.WriteByte(ptext[offset]);
            offset++;
        }

        k1 = unchecked(k1 + 0x25fe6761);
        k2 = unchecked(k2 + 1);
        uint checksum = unchecked((uint)ObfTable[((uint)k2) % 0x11] ^ (uint)k1 ^ csum);
        ctext.Write(BitConverter.GetBytes(checksum), 0, 4);

        return BytesToHex(ctext.ToArray());
    }

    private static uint Crc32(byte[] bytes)
    {
        const uint polynomial = 0xEDB88320;
        uint crc = 0xFFFFFFFF;
        foreach (byte b in bytes)
        {
            crc ^= b;
            for (int i = 0; i < 8; i++)
            {
                uint mask = (crc & 1) == 1 ? polynomial : 0;
                crc = (crc >> 1) ^ mask;
            }
        }

        return ~crc;
    }

    private static string BytesToHex(byte[] bytes)
    {
        var builder = new StringBuilder(bytes.Length * 2);
        foreach (byte b in bytes)
        {
            builder.Append(b.ToString("x2"));
        }

        return builder.ToString();
    }
}
'@

    Add-Type -TypeDefinition $steamCmdAuthSource -ErrorAction Stop
}

function Set-LordZSteamCmdRefreshToken {
    param(
        [Parameter(Mandatory)][string]$SteamCmdDir,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$RefreshToken
    )

    try {
        [LordZSteamCmdAuth]::ApplyRefreshToken($SteamCmdDir, $Username, $RefreshToken)
        return [PSCustomObject]@{
            Success = $true
            Message = 'SteamCMD credential cache updated from QR session token.'
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Test-LordZSteamCmdLoginOutput {
    param([Parameter(Mandatory)][string[]]$Lines)

    $joined = ($Lines -join "`n")
    $failed = $false
    $message = 'SteamCMD login did not complete successfully.'

    if ($joined -match 'Login Failure|Invalid Password|ERROR \(Invalid|Access Denied|Account Logon Denied') {
        $failed = $true
        if ($joined -match 'Steam Guard|two-factor|two factor|authentication code|SteamGuard') {
            $message = 'Steam Guard approval is required. Use password login with your Steam Guard code, or approve the sign-in in the Steam app.'
        }
        elseif ($joined -match 'Invalid Password') {
            $message = 'SteamCMD rejected the login. Cached credentials may be stale or the QR token was not applied.'
        }
    }

    $loggedIn = -not $failed -and (
        $joined -match 'Waiting for user info' -or
        $joined -match 'Logging in using cached credentials' -or
        $joined -match 'Logged in OK' -or
        $joined -match 'successfully logged in'
    )

    return [PSCustomObject]@{
        LoggedIn = $loggedIn
        Failed   = $failed
        Message  = if ($loggedIn) { 'SteamCMD session established.' } else { $message }
    }
}

function Get-LordZVdfInnerBlock {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Key
    )

    $pattern = '"' + [regex]::Escape($Key) + '"\s*\{'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $index = $match.Index + $match.Length
    $depth = 1
    while ($index -lt $Content.Length -and $depth -gt 0) {
        switch ($Content[$index]) {
            '{' { $depth++ }
            '}' { $depth-- }
        }
        $index++
    }

    if ($depth -ne 0) {
        return $null
    }

    return $Content.Substring($match.Index + $match.Length, $index - $match.Index - $match.Length - 1)
}

function Get-LordZSteamCmdCachedAccount {
    param(
        [Parameter(Mandatory)][string]$SteamCmdDir
    )

    $configPath = Join-Path (Join-Path $SteamCmdDir 'config') 'config.vdf'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    }
    catch {
        return $null
    }

    $connectCache = Get-LordZVdfInnerBlock -Content $content -Key 'ConnectCache'
    if ([string]::IsNullOrWhiteSpace($connectCache)) {
        return $null
    }

    $accountsInner = Get-LordZVdfInnerBlock -Content $content -Key 'Accounts'
    if ([string]::IsNullOrWhiteSpace($accountsInner)) {
        return $null
    }

    $accountMatches = [regex]::Matches(
        $accountsInner,
        '"([^"]+)"\s*\{[^{}]*"SteamID"',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($accountMatches.Count -le 0) {
        return $null
    }

    $username = $accountMatches[$accountMatches.Count - 1].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($username)) {
        return $null
    }

    return [PSCustomObject]@{
        Username        = $username
        HasConnectCache = $true
    }
}

function Get-LordZSteamCmdLoginLines {
    param(
        [Parameter(Mandatory)][string]$Username,
        [string]$Password,
        [switch]$UseCachedCredentials,
        [string]$SteamGuardCode,
        [switch]$InteractiveConsole
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (-not $InteractiveConsole) {
        [void]$lines.Add('@NoPromptForPassword 1')
    }

    if ($UseCachedCredentials -or [string]::IsNullOrWhiteSpace($Password)) {
        [void]$lines.Add("login $Username")
        [void]$lines.Add('quit')
        return $lines.ToArray()
    }

    if (-not [string]::IsNullOrWhiteSpace($SteamGuardCode)) {
        [void]$lines.Add("set_steam_guard_code $SteamGuardCode")
    }

    [void]$lines.Add("login $Username $Password")
    [void]$lines.Add('quit')
    return $lines.ToArray()
}

Export-ModuleMember -Function @(
    'Set-LordZSteamCmdRefreshToken'
    'Test-LordZSteamCmdLoginOutput'
    'Get-LordZSteamCmdLoginLines'
    'Get-LordZSteamCmdCachedAccount'
)
