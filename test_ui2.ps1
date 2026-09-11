Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.OpenFileDialog
$f.Title = "Chon thu muc Portable (Bam 'Open' hoac 'Mo' de chon thu muc hien tai)"
$f.ValidateNames = $false
$f.CheckFileExists = $false
$f.CheckPathExists = $true
$f.FileName = "Folder Selection."
$f.Filter = "Thu muc|*.none"
$f.InitialDirectory = "E:\TOOL\Source Code\Agent Antigravity\installers"
if ($f.ShowDialog() -eq 'OK') {
    Write-Output "SELECTED: $((Split-Path $f.FileName))"
}
