$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseDir = Join-Path $scriptDir "release\ChannelManager"

Write-Host "1. Khoi tao thu muc Release..." -ForegroundColor Cyan
if (Test-Path $releaseDir) {
    Remove-Item $releaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $releaseDir "webapp") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $releaseDir "data\profiles") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $releaseDir "data\icons") -Force | Out-Null

Write-Host "2. Ma hoa giao dien Frontend (JavaScript Obfuscation)..." -ForegroundColor Cyan
# Thử chạy javascript-obfuscator (dùng cmd.exe để gọi file .cmd global)
$obfInput = Join-Path $scriptDir "webapp\app.js"
$obfOutput = Join-Path $releaseDir "webapp\app.js"
try {
    cmd.exe /c "javascript-obfuscator `"$obfInput`" --output `"$obfOutput`" --compact true --control-flow-flattening true --dead-code-injection true"
    if (-not (Test-Path $obfOutput)) { throw "Obfuscation failed" }
} catch {
    Write-Host "Loi: Khong the chay javascript-obfuscator. Copy file goc." -ForegroundColor Yellow
    Copy-Item $obfInput -Destination $obfOutput -Force
}

# Copy HTML và CSS
Copy-Item (Join-Path $scriptDir "webapp\index.html") -Destination (Join-Path $releaseDir "webapp\") -Force
Copy-Item (Join-Path $scriptDir "webapp\index.css") -Destination (Join-Path $releaseDir "webapp\") -Force

Write-Host "3. Ma hoa Backend (Base64)..." -ForegroundColor Cyan
$serverSrc = Join-Path $scriptDir "server.ps1"
$coreBin = Join-Path $releaseDir "data\core.bin"
$serverContent = Get-Content -Path $serverSrc -Raw
$serverBytes = [System.Text.Encoding]::UTF8.GetBytes($serverContent)
$serverBase64 = [System.Convert]::ToBase64String($serverBytes)
Set-Content -Path $coreBin -Value $serverBase64 -Encoding Ascii

Write-Host "4. Bien dich Launcher C# Native [Channel Manager.exe]..." -ForegroundColor Cyan
$launcherSrc = Join-Path $scriptDir "scratch\Launcher.cs"
$launcherExe = Join-Path $releaseDir "Channel Manager.exe"
$iconPath = Join-Path $scriptDir "scratch\app.ico"

# Find csc.exe compiler
$csc = Get-ChildItem -Path $env:windir\Microsoft.NET\Framework64\v4.* -Filter csc.exe -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $csc) {
    $csc = Get-ChildItem -Path $env:windir\Microsoft.NET\Framework\v4.* -Filter csc.exe -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $csc) {
    throw "Khong tim thay trinh bien dich C# (csc.exe) tren he thong!"
}

# Compile Launcher
& $csc /target:winexe /win32icon:"$iconPath" /out:"$launcherExe" "$launcherSrc"

Write-Host "5. Copy Favicon cho Frontend..." -ForegroundColor Cyan
Copy-Item $iconPath -Destination (Join-Path $releaseDir "webapp\favicon.ico") -Force

Write-Host "6. Copy du lieu he thong..." -ForegroundColor Cyan
Copy-Item (Join-Path $scriptDir "extensions") -Destination $releaseDir -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $releaseDir "installers") -Force | Out-Null
Copy-Item (Join-Path $scriptDir "installers\*.exe") -Destination (Join-Path $releaseDir "installers\") -Force
Copy-Item (Join-Path $scriptDir "Inject-WebRTC.ps1") -Destination $releaseDir -Force

# Khởi tạo profiles.json trống mới
$emptyProfile = @{ profiles = @(); proxies = @() } | ConvertTo-Json -Depth 5
Set-Content -Path (Join-Path $releaseDir "profiles.json") -Value $emptyProfile -Encoding UTF8

Write-Host "Hoàn thành Build! Toàn bộ file đã sẵn sàng trong thư mục: $releaseDir" -ForegroundColor Green
