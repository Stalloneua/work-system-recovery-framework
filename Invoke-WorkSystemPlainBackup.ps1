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
$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $sevenZip) { $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not (Test-Path -LiteralPath $sevenZip)) { throw '7-Zip is not installed.' }

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
$snapshotRoot = Join-Path $stateRoot "plain-snapshot-$stamp"
New-Item -ItemType Directory -Force -Path $snapshotRoot | Out-Null
$entries = [System.Collections.Generic.List[object]]::new()
$excludeFiles = @("$PSScriptRoot\backup-excludes.txt")
if ($Profile -eq 'Foundation') {
    $excludeFiles += "$PSScriptRoot\foundation-excludes.txt"
    $localExcludes = Join-Path $PSScriptRoot 'foundation-excludes.local.txt'
    if (Test-Path -LiteralPath $localExcludes) { $excludeFiles += $localExcludes }
}
$excludeArgs = @($excludeFiles | ForEach-Object { Get-Content -LiteralPath $_ } | Where-Object { $_ -and -not $_.Trim().StartsWith('#') } | ForEach-Object {
    $pattern = $_.Trim().Replace('\','/') -replace '^\*\*/','' -replace '/\*\*$',''
    "-xr!$pattern"
})

try {
    $index = 0
    foreach ($source in $sources) {
        $index++
        $fullSource = [IO.Path]::GetFullPath($source).TrimEnd('\')
        if (-not $fullSource.StartsWith($documents, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source is outside Documents and is not portable: $fullSource"
        }
        $relative = $fullSource.Substring($documents.Length).TrimStart('\')
        if (-not $relative) { throw 'Backing up the complete Documents root is not allowed.' }
        $safeName = [regex]::Replace((Split-Path -Leaf $relative), '[^A-Za-z0-9._-]', '_')
        if (-not $safeName) { $safeName = 'source' }
        $archiveName = '{0:D2}-{1}.zip' -f $index, $safeName
        $archivePath = Join-Path $snapshotRoot $archiveName

        Push-Location $documents
        try { & $sevenZip a -tzip $archivePath $relative -mx=5 @excludeArgs } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archivePath)) { throw "Archive creation failed for $relative" }

        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
        $md5 = (Get-FileHash -Algorithm MD5 -LiteralPath $archivePath).Hash.ToLowerInvariant()
        $remoteArchive = "$remoteRoot/snapshots/$stamp/archives/$archiveName"
        & rclone copyto $archivePath $remoteArchive --checksum --retries 5 --low-level-retries 10 --log-level ERROR
        if ($LASTEXITCODE -ne 0) { throw "Archive upload failed for $relative" }
        $remoteMd5 = $null
        for ($attempt = 0; $attempt -lt 5 -and $remoteMd5 -ne $md5; $attempt++) {
            Start-Sleep -Seconds 3
            $remoteMd5Line = & rclone md5sum $remoteArchive --log-level ERROR 2>$null
            if ($LASTEXITCODE -eq 0 -and $remoteMd5Line) { $remoteMd5 = ($remoteMd5Line -split '\s+')[0].ToLowerInvariant() }
        }
        if (-not $remoteMd5) { throw "Cannot verify remote archive $archiveName" }
        if ($remoteMd5 -ne $md5) { throw "Remote checksum mismatch for $archiveName" }

        $entries.Add([ordered]@{
            relative_path = $relative.Replace('\','/')
            archive = $archiveName
            remote_path = "snapshots/$stamp/archives/$archiveName"
            bytes = (Get-Item -LiteralPath $archivePath).Length
            sha256 = $sha256
            md5 = $md5
        })
    }

    $manifest = [ordered]@{
        schema_version = 2
        backup_mode = 'plain-rclone'
        layout = 'snapshot-archives'
        backup_id = $stamp
        started_by = $env:USERNAME
        source_machine = $env:COMPUTERNAME
        created_at = (Get-Date).ToString('o')
        profile = $Profile
        source_count = $entries.Count
        archives = @($entries)
    }
    $manifestPath = Join-Path $snapshotRoot 'manifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    & rclone copyto $manifestPath "$remoteRoot/snapshots/$stamp/manifest.json" --checksum --retries 5 --low-level-retries 10 --log-level ERROR
    if ($LASTEXITCODE -ne 0) { throw 'Failed to publish the snapshot manifest.' }
    & rclone copyto $manifestPath "$remoteRoot/latest.json" --checksum --retries 5 --low-level-retries 10 --log-level ERROR
    if ($LASTEXITCODE -ne 0) { throw 'Failed to publish the latest backup marker.' }

    if ($Check) {
        $remoteManifest = & rclone cat "$remoteRoot/latest.json" --log-level ERROR
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read back the latest backup marker.' }
        $readback = $remoteManifest | ConvertFrom-Json
        if ($readback.backup_id -ne $stamp -or $readback.source_count -ne $entries.Count) {
            throw 'Backup marker readback did not match the completed backup.'
        }
    }

    [ordered]@{
        backup_id = $stamp
        backup_mode = 'plain-rclone'
        layout = 'snapshot-archives'
        profile = $Profile
        source_count = $entries.Count
        remote_root = $remoteRoot
        result = 'PASS'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot "plain-backup-$stamp.json") -Encoding utf8
    Write-Output $manifestPath
} finally {
    if (Test-Path -LiteralPath $snapshotRoot) { Remove-Item -LiteralPath $snapshotRoot -Recurse -Force }
}
