Add-Type -AssemblyName System.Drawing
$file = (Get-ChildItem -Filter "*firefox.png").FullName
$bmp = New-Object System.Drawing.Bitmap($file)

$minX = $bmp.Width
$minY = $bmp.Height
$maxX = 0
$maxY = 0

for ($y = 0; $y -lt $bmp.Height; $y++) {
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -lt 250 -or $c.G -lt 250 -or $c.B -lt 250) {
            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}

Write-Host "Image size: $($bmp.Width)x$($bmp.Height)"
Write-Host "Non-white bounds: X=$minX Y=$minY W=$($maxX-$minX) H=$($maxY-$minY)"
