Add-Type -AssemblyName System.Drawing
$file = (Get-ChildItem -Filter "*firefox.png").FullName
$bmp = New-Object System.Drawing.Bitmap($file)
$c = $bmp.GetPixel(0,0)
Write-Host "Top-Left pixel: A=$($c.A) R=$($c.R) G=$($c.G) B=$($c.B)"
$c = $bmp.GetPixel($bmp.Width/2, $bmp.Height/2)
Write-Host "Center pixel: A=$($c.A) R=$($c.R) G=$($c.G) B=$($c.B)"
