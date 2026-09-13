[CmdletBinding()]
param(
    [ValidateSet('Critical','Foundation','Full')]
    [string]$Profile,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$logRoot = Join-Path $stateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Backup is not initialized.' }
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone is not installed.' }

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.backup_mode -ne 'plain-rclone') { throw 'Configured backup mode is not plain-rclone.' }
if (-not $Profile) { $Profile = $config.profile }

& "$PSScriptRoot\New-ChatOrganizationManifest.ps1" | Out-Null
$sourceConfig = Get-Content -Raw -LiteralPath "$PSScriptRoot\backup-sources.json" | ConvertFrom-Json
$documents = [Environment]::GetFolderPath('MyDocuments').TrimEnd('\')
$rawSources = switch ($Profile) {
    'Full' { $sourceConfig.full }
    'Foundation' { $sourceConfig.foundation }
    default { $sourceConfig.critical }
}
$sources = @($rawSources | ForEach-Object { $_.Replace('%DOCUMENTS%', $documents) } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
if ($sources.Count -eq 0) { throw 'No backup sources resolved.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$remoteRoot = "{0}:{1}" -f $config.remote_name, $config.remote_path.Trim('/')
$logPath = Join-Path $logRoot ("plain-backup-{0}.log" -f $stamp)
$entries = [System.Collections.Generic.List[object]]::new()

foreach ($source in $sources) {
    $fullSource = [IO.Path]::GetFullPath($source).TrimEnd('\')
    if (-not $fullSource.StartsWith($documents, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Source is outside Documents and is not portable: $fullSource"
    }
    $relative = $fullSource.Substring($documents.Length).TrimStart('\').Replace('\','/')
    if (-not $relative) { throw 'Backing up the complete Documents root is not allowed.' }
    $current = "$remoteRoot/current/Documents/$relative"
    $item = Get-Item -LiteralPath $fullSource
    $history = "$remoteRoot/history/$stamp/Documents/$relative"
    if (-not $item.PSIsContainer) {
        $relativeParent = [IO.Path]::GetDirectoryName($relative.Replace('/','\'))
        if ($relativeParent) { $relativeParent = $relativeParent.Replace('\','/') }
        $history = "$remoteRoot/history/$stamp/Documents"
        if ($relativeParent) { $history = "$history/$relativeParent" }
    }

    $common = @('--backup-dir', $history, '--checksum', '--metadata', '--log-file', $logPath, '--log-level', 'INFO')
    if ($item.PSIsContainer) {
        $args = @('sync', $fullSource, $current, '--create-empty-src-dirs', '--exclude-from', "$PSScriptRoot\backup-excludes.txt")
        if ($Profile -eq 'Foundation') {
            $args += @('--exclude-from', "$PSScriptRoot\foundation-excludes.txt")
            $localExcludes = Join-Path $PSScriptRoot 'foundation-excludes.local.txt'
            if (Test-Path -LiteralPath $localExcludes) { $args += @('--exclude-from', $localExcludes) }
        }
        & rclone @args @common
    } else {
        & rclone copyto $fullSource $current @common
    }
    if ($LASTEXITCODE -ne 0) { throw "Plain backup failed for $relative. See $logPath" }
    $entries.Add([ordered]@{ relative_path = $relative; remote_path = "current/Documents/$relative" })
}

$manifest = [ordered]@{
    schema_version = 1
    backup_mode = 'plain-rclone'
    backup_id = $stamp
    started_by = $env:USERNAME
    source_machine = $env:COMPUTERNAME
    created_at = (Get-Date).ToString('o')
    profile = $Profile
    source_count = $entries.Count
    sources = @($entries)
}
$manifestPath = Join-Path $stateRoot ("plain-manifest-{0}.json" -f $stamp)
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
& rclone copyto $manifestPath "$remoteRoot/manifests/$stamp.json" --metadata
if ($LASTEXITCODE -ne 0) { throw 'Failed to publish the backup manifest.' }
& rclone copyto $manifestPath "$remoteRoot/latest.json" --metadata
if ($LASTEXITCODE -ne 0) { throw 'Failed to publish the latest backup marker.' }

if ($Check) {
    $remoteManifest = & rclone cat "$remoteRoot/latest.json"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read back the latest backup marker.' }
    $readback = $remoteManifest | ConvertFrom-Json
    if ($readback.backup_id -ne $stamp -or $readback.source_count -ne $entries.Count) {
        throw 'Backup marker readback did not match the completed backup.'
    }
}

[ordered]@{
    backup_id = $stamp
    backup_mode = 'plain-rclone'
    profile = $Profile
    source_count = $entries.Count
    remote_root = $remoteRoot
    manifest = $manifestPath
    result = 'PASS'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot ("plain-backup-{0}.json" -f $stamp)) -Encoding utf8

Write-Output $manifestPath
