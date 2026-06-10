Add-Type -AssemblyName System.Drawing
$path = Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\LordZ-Placeholder.png'
$bitmap = New-Object System.Drawing.Bitmap 512, 512
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(26, 12, 6))
    $font = New-Object System.Drawing.Font('Arial', 20, [System.Drawing.FontStyle]::Bold)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 140, 35))
    $graphics.DrawString('[LORDZ]', $font, $brush, 180, 230)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "[OK] $path"
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}
