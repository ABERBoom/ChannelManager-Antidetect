# cleanup_webrtc_prefs.ps1 - One-time cleanup for stale WebRTC prefs
# Run this BEFORE restarting ChannelManager

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== WebRTC Prefs Cleanup Tool ===" -ForegroundColor Cyan

# Clean Firefox profiles
$profiles = @(
    "installers\kenh1",
    "installers\kenh2"
)

foreach ($relPath in $profiles) {
    $profileDir = Join-Path $scriptDir "$relPath\Data\profile"
    Write-Host "`n--- Cleaning $relPath ---" -ForegroundColor Yellow
    
    # 1. Clean prefs.js
    $prefsJs = Join-Path $profileDir "prefs.js"
    if (Test-Path $prefsJs) {
        $content = Get-Content $prefsJs -Raw
        $before = ($content | Select-String "peerconnection" -AllMatches).Matches.Count
        
        # Remove ALL stale WebRTC ICE prefs
        $content = $content -replace '(?m)^user_pref\("media\.peerconnection\.ice\.(proxy_only_if_behind_proxy|default_address_only|no_host|obfuscate_host_addresses|relay_only)".*$\r?\n?', ''
        # Also remove stale proxy settings
        $content = $content -replace '(?m)^user_pref\("network\.proxy\.(http|http_port|ssl|ssl_port|share_proxy_settings|type)".*$\r?\n?', ''
        
        Set-Content -Path $prefsJs -Value $content -Encoding UTF8
        $after = ($content | Select-String "peerconnection" -AllMatches).Matches.Count
        Write-Host "  prefs.js: Cleaned $($before - $after) WebRTC entries" -ForegroundColor Green
    } else {
        Write-Host "  prefs.js: Not found (OK for first run)" -ForegroundColor Gray
    }
    
    # 2. Show current user.js (will be rewritten by server on launch)
    $userJs = Join-Path $profileDir "user.js"
    if (Test-Path $userJs) {
        $lines = (Get-Content $userJs | Measure-Object).Count
        Write-Host "  user.js: $lines lines (will be rewritten on next launch)" -ForegroundColor Gray
    }
    
    # 3. Check extension
    $extDir = Join-Path $profileDir "extensions"
    $xpi = Join-Path $extDir "webrtc-guard@channelmanager.xpi"
    if (Test-Path $xpi) {
        Write-Host "  Extension XPI: Found" -ForegroundColor Green
    } else {
        Write-Host "  Extension XPI: Not found (will be created on proxy launch)" -ForegroundColor Gray
    }
}

# Clean Chrome profile
$chromeProfile = "installers\kenh3"
Write-Host "`n--- Cleaning $chromeProfile ---" -ForegroundColor Yellow
$chromePrefPath = Join-Path $scriptDir "$chromeProfile\Data\profile\Default\Preferences"
if (Test-Path $chromePrefPath) {
    try {
        $prefs = Get-Content $chromePrefPath -Raw | ConvertFrom-Json -AsHashtable
        if ($prefs.webrtc) {
            Write-Host "  Current WebRTC policy: $($prefs.webrtc.ip_handling_policy)" -ForegroundColor Gray
            Write-Host "  Will be updated to 'default_public_interface_only' on next proxy launch" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Error reading Chrome Preferences: $_" -ForegroundColor Red
    }
}

# Check Chrome extension
$chromeExt = Join-Path $scriptDir "$chromeProfile\Data\profile\extensions\webrtc-guard-chrome\spoof.js"
if (Test-Path $chromeExt) {
    $firstLine = Get-Content $chromeExt -TotalCount 2 | Select-Object -Last 1
    Write-Host "  Extension spoof.js: $firstLine" -ForegroundColor Green
}

Write-Host "`n=== Cleanup complete ===" -ForegroundColor Cyan
Write-Host "Now restart ChannelManager and relaunch each profile." -ForegroundColor Yellow
