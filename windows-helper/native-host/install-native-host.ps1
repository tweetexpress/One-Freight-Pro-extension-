# ONE Freight Pro — native messaging host installer.
# Compiles OfpNativeHost.cs with the .NET Framework compiler that ships with
# Windows, writes the host manifest, and registers it for Edge and Chrome.
# Also removes the old dathelper: protocol handler (the browser→PowerShell
# path that Malwarebytes flagged).
#
# Usage:
#   1. Load the extension (edge://extensions or chrome://extensions, Developer
#      mode → Load unpacked → browser-extension folder).
#   2. Copy the extension ID shown on the extension card.
#   3. Run:  powershell -ExecutionPolicy Bypass -File install-native-host.ps1 -ExtensionId <id>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-p]{32}$')]
    [string]$ExtensionId
)

$ErrorActionPreference = 'Stop'

$hostName     = 'com.tweetexpress.onefreightpro'
$dir          = $PSScriptRoot
$source       = Join-Path $dir 'OfpNativeHost.cs'
$exePath      = Join-Path $dir 'ofp-native-host.exe'
$manifestPath = Join-Path $dir "$hostName.json"

# ── Compile ──────────────────────────────────────────────────────────────────
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $csc)) { throw 'csc.exe not found — .NET Framework 4.x is required.' }

& $csc /nologo /target:exe /platform:anycpu /out:"$exePath" `
    /r:Microsoft.CSharp.dll /r:System.Web.Extensions.dll "$source"
if ($LASTEXITCODE -ne 0) { throw "Compilation failed (csc exit code $LASTEXITCODE)." }
Write-Host "Compiled: $exePath"

# ── Host manifest ────────────────────────────────────────────────────────────
$manifest = [ordered]@{
    name            = $hostName
    description     = 'ONE Freight Pro Outlook helper'
    path            = $exePath
    type            = 'stdio'
    allowed_origins = @("chrome-extension://$ExtensionId/")
} | ConvertTo-Json
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Manifest:  $manifestPath"

# ── Registry registration (per-user, Edge + Chrome) ─────────────────────────
$roots = @(
    'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts',
    'HKCU:\Software\Google\Chrome\NativeMessagingHosts'
)
foreach ($root in $roots) {
    $key = "$root\$hostName"
    New-Item -Path $key -Force | Out-Null
    Set-Item -Path $key -Value $manifestPath
    Write-Host "Registered: $key"
}

# ── Retire the old dathelper: protocol handler ───────────────────────────────
if (Test-Path 'HKCU:\Software\Classes\dathelper') {
    Remove-Item 'HKCU:\Software\Classes\dathelper' -Recurse -Force -Confirm:$false
    Write-Host 'Removed old dathelper: protocol handler.'
}

Write-Host ''
Write-Host 'Done. Reload the extension, then test an email from a DAT load card.'
