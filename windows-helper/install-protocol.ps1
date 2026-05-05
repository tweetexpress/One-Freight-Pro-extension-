# Registers the ONE Freight Pro local email protocol in HKCU (no admin required).
# Run this once. Re-run any time the script location changes.

$psScript = Join-Path $PSScriptRoot 'dathelper.ps1'

if (-not (Test-Path $psScript)) {
    Write-Error "dathelper.ps1 not found at: $psScript"
    exit 1
}

$cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$psScript`" `"%1`""

$root = 'HKCU:\Software\Classes\dathelper'
New-Item         -Path $root                           -Force | Out-Null
Set-ItemProperty -Path $root -Name '(Default)'  -Value 'ONE Freight Pro Email Protocol'
New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

New-Item         -Path "$root\shell\open\command"      -Force | Out-Null
Set-ItemProperty -Path "$root\shell\open\command" -Name '(Default)' -Value $cmd

Write-Host "ONE Freight Pro protocol registered."
Write-Host "Command: $cmd"
