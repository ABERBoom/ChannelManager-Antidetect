$ErrorActionPreference = 'Stop'

# Create fake portable directory
$testDir = "e:\TOOL\Source Code\Agent Antigravity\installers\test_portable"
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
New-Item -ItemType File -Path "$testDir\FirefoxPortable.exe" -Force | Out-Null

# Create a fake Other\Source directory and .ini
$sourceDir = "$testDir\Other\Source"
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
Set-Content -Path "$sourceDir\FirefoxPortable.ini" -Value "AllowMultipleInstances=false" -Encoding UTF8

# Test API Create Profile
$profilePayload = @{ name = "TestProfileABC"; iconBadge = "TP" } | ConvertTo-Json
$resCreate = Invoke-RestMethod -Uri "http://localhost:8780/api/profiles" -Method POST -Body $profilePayload -ContentType "application/json"
$id = $resCreate.data.id
Write-Host "Created profile $id"

# Test API Link Profile
$linkPayload = @{ path = $testDir } | ConvertTo-Json
try {
    $resLink = Invoke-RestMethod -Uri "http://localhost:8780/api/profiles/$id/link" -Method POST -Body $linkPayload -ContentType "application/json"
    Write-Host "Link successful"
} catch {
    Write-Host "Link failed: $_"
}

# Verify if folder was renamed to TestProfileABC
$renamedDir = "e:\TOOL\Source Code\Agent Antigravity\installers\TestProfileABC"
$dirExists = Test-Path $renamedDir
$iniExists = Test-Path "$renamedDir\FirefoxPortable.ini"
$iniContent = if ($iniExists) { (Get-Content "$renamedDir\FirefoxPortable.ini") -join '|' } else { "" }

Write-Host "Dir renamed: $dirExists"
Write-Host "INI copied: $iniExists"
Write-Host "INI content: $iniContent"

# Clean up
if (Test-Path $renamedDir) { Remove-Item $renamedDir -Recurse -Force }
Invoke-RestMethod -Uri "http://localhost:8780/api/profiles/$id" -Method DELETE
