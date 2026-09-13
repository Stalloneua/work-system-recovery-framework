[CmdletBinding()]
param(
    [string]$Repository,
    [string]$ExistingRestoreTarget,
    [switch]$KeepRestore
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
if (-not $Repository) {
    $configPath = Join-Path $stateRoot 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) { throw 'Production backup is not initialized.' }
    $Repository = (Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json).repository
}

$target = $ExistingRestoreTarget
$createdTarget = $false
if (-not $target) {
    $target = Join-Path $stateRoot ("restore-test-{0}" -f ([guid]::NewGuid().ToString('N')))
    & "$PSScriptRoot\Restore-WorkSystem.ps1" -Repository $Repository -Target $target
    if ($LASTEXITCODE -ne 0) { throw 'Restore command failed.' }
    $createdTarget = $true
}

$required = @(
    'Work Management System.md',
    'Google Sheets Sync Contract.md',
    'Directions.md',
    'Cross-machine Continuity and One-command Recovery Architecture.md'
)
foreach ($name in $required) {
    if (-not (Get-ChildItem -LiteralPath $target -Filter $name -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        throw "Required recovery marker is missing: $name"
    }
}

$manifest = Get-ChildItem -LiteralPath $target -Filter 'chat-organization-manifest.json' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $manifest) { throw 'Chat organization manifest is missing.' }
$records = @((Get-Content -Raw -LiteralPath $manifest.FullName | ConvertFrom-Json).records)
if ($records.Count -eq 0) { throw 'Chat organization manifest has no records.' }

& "$PSScriptRoot\Test-WorkSystemBackupHealth.ps1"
if ($LASTEXITCODE -ne 0) { throw 'Backup health validation failed.' }

[ordered]@{checked_at=(Get-Date).ToString('o');repository=$Repository;target=$target;required_markers=$required;chat_records=$records.Count;result='PASS'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateRoot 'last-restore-test.json') -Encoding utf8
Write-Output "PASS: restored required operating notes and $($records.Count) chat records."

if ($createdTarget -and -not $KeepRestore) { Remove-Item -LiteralPath $target -Recurse -Force }
