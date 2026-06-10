param([string]$ZipPath)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $entry = $zip.GetEntry('lordz.sh')
    $stream = $entry.Open()
    $reader = New-Object System.IO.StreamReader($stream)
    $line = $reader.ReadLine()
    $reader.Close()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    $hasCr = $bytes -contains 13
    Write-Host "Shebang: $line"
    Write-Host $(if ($hasCr) { 'FAIL: contains CR' } else { 'OK: Unix line endings' })
}
finally {
    $zip.Dispose()
}
