[CmdletBinding()]
param(
    [string]$RemoteName = 'work-drive',
    [string]$RemotePath = 'Work System/00 Recovery/plain-foundation',
    [string]$Target = "$([Environment]::GetFolderPath('MyDocuments'))\WorkSystem-Restore-Staging",
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone is not installed.' }
$sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
if (-not (Test-Path -LiteralPath $sevenZip)) {
    $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
}
if (-not (Test-Path -LiteralPath $sevenZip)) { throw '7-Zip is not installed.' }
$remoteRoot = "${RemoteName}:$($RemotePath.Trim('/'))"
$markerCandidates = @()
foreach ($markerName in @('latest-connector.json','latest.json')) {
    $markerJson = & rclone cat "$remoteRoot/$markerName" --log-level ERROR 2>$null
    if ($LASTEXITCODE -eq 0 -and $markerJson) {
        try { $markerCandidates += ($markerJson | ConvertFrom-Json) } catch {}
    }
}
if ($markerCandidates.Count -eq 0) { throw 'Cannot read a plain backup marker.' }
$marker = $markerCandidates | Sort-Object { [DateTimeOffset]$_.created_at } -Descending | Select-Object -First 1
if ($marker.backup_mode -ne 'plain-rclone' -or $marker.layout -ne 'snapshot-archives' -or -not $marker.backup_id) {
    throw 'Invalid or unsupported plain backup marker.'
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
$restoredDocuments = Join-Path $Target 'Documents'
$downloadRoot = Join-Path $Target '.archives'
New-Item -ItemType Directory -Force -Path $restoredDocuments,$downloadRoot | Out-Null

try {
    foreach ($entry in @($marker.archives)) {
        $archivePath = Join-Path $downloadRoot $entry.archive
        & rclone copyto "$remoteRoot/$($entry.remote_path)" $archivePath --checksum --log-level ERROR
        if ($LASTEXITCODE -ne 0) { throw "Cannot download $($entry.archive)" }
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
        if ($sha256 -ne $entry.sha256) { throw "SHA256 mismatch for $($entry.archive)" }
    }

    $extractTargets = @($marker.archives | ForEach-Object {
        if ($_.extract_from) { $_.extract_from } else { $_.archive }
    } | Select-Object -Unique)
    foreach ($archiveName in $extractTargets) {
        $archivePath = Join-Path $downloadRoot $archiveName
        & $sevenZip x $archivePath "-o$restoredDocuments" -y
        if ($LASTEXITCODE -ne 0) { throw "Cannot extract $archiveName" }
    }

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
        layout = 'snapshot-archives'
        backup_id = $marker.backup_id
        target = $Target
        applied = [bool]$Apply
        result = 'PASS'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Target 'restore-result.json') -Encoding utf8
    Write-Output "Plain restore verified at $Target from backup $($marker.backup_id)"
} finally {
    if (Test-Path -LiteralPath $downloadRoot) { Remove-Item -LiteralPath $downloadRoot -Recurse -Force }
}
