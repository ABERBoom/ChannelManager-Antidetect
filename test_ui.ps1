Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.FolderBrowserDialog
$f.Description = 'Chon thu muc Portable da giai nen'
$f.SelectedPath = 'e:\TOOL\Source Code\Agent Antigravity\installers'
$f.ShowNewFolderButton = $false
$form = New-Object System.Windows.Forms.Form
$form.TopMost = $true
if ($f.ShowDialog($form) -eq 'OK') { Write-Output $f.SelectedPath }
$form.Close()
