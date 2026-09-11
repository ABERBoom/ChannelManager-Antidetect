Add-Type -AssemblyName System.Drawing
$files = Get-ChildItem -Filter "*png" | Where-Object Name -match "icon.*chorm|icon.*firefox"
foreach ($f in $files) {
    $bmp = New-Object System.Drawing.Bitmap($f.FullName)
    $bmp.MakeTransparent([System.Drawing.Color]::White)
    $tempPath = $f.FullName + ".tmp.png"
    $bmp.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Move-Item -Path $tempPath -Destination $f.FullName -Force
    Write-Host "Made white background transparent for $($f.Name)"
}
