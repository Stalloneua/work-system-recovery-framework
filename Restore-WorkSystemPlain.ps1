[CmdletBinding()]
param(
    [string]$RemoteName = 'work-drive',
    [string]$RemotePath = 'Work System/00 Recovery/plain-foundation',
    [string]$Target = "$([Environment]::GetFolderPath('MyDocuments'))\WorkSystem-Restore-Staging",
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone is not installed.' }
$remoteRoot = "${RemoteName}:$($RemotePath.Trim('/'))"

$markerJson = & rclone cat "$remoteRoot/latest.json"
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the plain backup marker.' }
$marker = $markerJson | ConvertFrom-Json
if ($marker.backup_mode -ne 'plain-rclone' -or -not $marker.backup_id) { throw 'Invalid plain backup marker.' }

New-Item -ItemType Directory -Force -Path $Target | Out-Null
$restoredDocuments = Join-Path $Target 'Documents'
New-Item -ItemType Directory -Force -Path $restoredDocuments | Out-Null
& rclone copy "$remoteRoot/current/Documents" $restoredDocuments --checksum --metadata --create-empty-src-dirs
if ($LASTEXITCODE -ne 0) { throw 'Plain Google Drive restore failed.' }

$vault = Get-ChildItem -LiteralPath $Target -Filter 'Work Management System.md' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
$architecture = Get-ChildItem -LiteralPath $Target -Filter 'Cross-machine Continuity and One-command Recovery Architecture.md' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $vault -or -not $architecture) { throw 'Recovery validation failed: required operating notes are missing.' }

if ($Apply) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    & robocopy $restoredDocuments $documents /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ
    if ($LASTEXITCODE -ge 8) { throw "robocopy apply failed with exit code $LASTEXITCODE" }
}

[ordered]@{
    checked_at = (Get-Date).ToString('o')
    backup_mode = 'plain-rclone'
    backup_id = $marker.backup_id
    target = $Target
    applied = [bool]$Apply
    result = 'PASS'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Target 'restore-result.json') -Encoding utf8

Write-Output "Plain restore verified at $Target from backup $($marker.backup_id)"
