$path = Join-Path (Split-Path -Parent $PSScriptRoot) 'lordz.sh'
$text = [System.IO.File]::ReadAllText($path)
$normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
$encoding = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($path, $normalized, $encoding)
Write-Host "[OK] Normalized LF: $path"
