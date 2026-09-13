[CmdletBinding()]
param([switch]$SkipRepository)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($error in @($parseErrors)) { $errors.Add("$($_.Name): $($error.Message)") }
}

$sshBootstrapPath = Join-Path $PSScriptRoot 'Enable-WorkSystemSsh.ps1'
if (Select-String -LiteralPath $sshBootstrapPath -SimpleMatch '-AssociatedNetFirewallRule' -Quiet) {
    $errors.Add('SSH bootstrap uses a NetSecurity parameter unavailable in Windows PowerShell 5.1.')
}

foreach ($file in 'README.md','DEPLOYMENT-GUIDE.md','backup-sources.example.json','backup-excludes.txt','foundation-excludes.txt','deployment-config.example.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { $errors.Add("Missing $file") }
}

$sourcePath = Join-Path $PSScriptRoot 'backup-sources.json'
if (-not (Test-Path -LiteralPath $sourcePath)) { $sourcePath = Join-Path $PSScriptRoot 'backup-sources.example.json' }
$sources = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json
if (-not $sources.foundation -or @($sources.foundation).Count -lt 2) {
    $errors.Add('Foundation profile is missing or incomplete.')
}

$measurementPath = Join-Path $PSScriptRoot 'foundation-profile-measurement.json'
if (Test-Path -LiteralPath $measurementPath) {
    $measurement = Get-Content -Raw -LiteralPath $measurementPath | ConvertFrom-Json
    if ($measurement.total_bytes -gt 2GB) { $errors.Add('Foundation profile exceeds the 2 GB safety target.') }
}

if (Test-Path -LiteralPath "$PSScriptRoot\chat-organization-manifest.json") {
    $manifest = Get-Content -Raw -LiteralPath "$PSScriptRoot\chat-organization-manifest.json" | ConvertFrom-Json
    if ($manifest.record_count -lt 1) { $errors.Add('Chat organization manifest has no records.') }
}

if (-not $SkipRepository) {
    $stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
    if (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'config.json'))) { $errors.Add('Production backup is not initialized.') }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'PASS: package syntax, required files and chat/project manifest.'
