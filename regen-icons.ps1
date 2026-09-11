$data = Get-Content profiles.json | ConvertFrom-Json
$scriptDir = $PWD.Path
$iconsDir = Join-Path $scriptDir "data\icons"

Add-Type -TypeDefinition (Get-Content server.ps1 | Select-String -Pattern "public class IconGenerator" -Context 0, 85 | Out-String) -ReferencedAssemblies System.Drawing -IgnoreWarnings -ErrorAction SilentlyContinue

foreach ($p in $data.profiles) {
    if ($p.browser) {
        $iconPath = Join-Path $iconsDir "$($p.id).ico"
        $chromeImg = (Get-ChildItem -Path $scriptDir -Filter "*chorm.png" | Select-Object -First 1).FullName
        $firefoxImg = (Get-ChildItem -Path $scriptDir -Filter "*firefox.png" | Select-Object -First 1).FullName
        
        $baseImagePath = if ($p.browser -eq 'chrome' -and (Test-Path $chromeImg)) { $chromeImg } elseif ($p.browser -eq 'firefox' -and (Test-Path $firefoxImg)) { $firefoxImg } else { Join-Path $scriptDir "icon.png" }
        
        Write-Host "Regenerating $($p.name) with $baseImagePath"
        [IconGenerator]::GenerateIcon($iconPath, $baseImagePath, $p.iconBadge)
    }
}
