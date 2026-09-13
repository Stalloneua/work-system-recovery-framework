[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$documents = [Environment]::GetFolderPath('MyDocuments')
$config = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'backup-sources.json') | ConvertFrom-Json
$roots = @($config.foundation | ForEach-Object { $_.Replace('%DOCUMENTS%', $documents) } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)

$excludedNames = @(
    'node_modules', 'vendor', '.venv', 'venv', '__pycache__', '.pytest_cache',
    '.mypy_cache', '.ruff_cache', '.cache', 'Cache', 'Caches', '.playwright',
    '.playwright-cli', '.next', '.turbo', 'Temp', 'temp', 'tmp', '.tmp',
    '.work', '.codex-work', 'dist', 'build', 'coverage', 'test-results',
    'restore-tests', 'backups', 'out', 'output', 'outputs', 'reports',
    'outbound_reports', 'data_imports',
    'ocr_work', 'ocr_downloads', '.tmp.driveupload', '.tmp.drivedownload',
    '.autoplac_database_cache', '.autoplac_pl_cache', '.autoria_cache',
    '.autoria_dealers_cache', '.autoria_inventory_cache', '.non_autoria_cache',
    '.rst_cache', '.site_enrichment_cache', '.wrangler', 'secrets', '.sandbox-secrets'
)
$excludedPrefixes = @('tmp_', 'MigrationBackup-', 'reports_to_send_')
$excludedFilePrefixes = @('generated_', 'export_')

function Test-FoundationFile {
    param([System.IO.FileInfo]$File, [string]$Root)

    $relative = $File.FullName.Substring($Root.Length).TrimStart('\')
    $segments = @($relative -split '\\')
    $directorySegments = if ($segments.Count -gt 1) { $segments[0..($segments.Count - 2)] } else { @() }
    foreach ($segment in $directorySegments) {
        if ($excludedNames -contains $segment) { return $false }
        foreach ($prefix in $excludedPrefixes) {
            if ($segment.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
    }

    if ($File.Name -in @('restic-password.xml', 'rclone.conf', 'auth.json')) { return $false }
    foreach ($prefix in $excludedFilePrefixes) {
        if ($File.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($File.Name -like '*_backup_before_*' -or $File.Name -like '*token*' -or $File.Name -like 'Cookies*' -or $File.Extension -in @('.tmp', '.log', '.tsbuildinfo')) { return $false }
    return $true
}

$rows = foreach ($root in $roots) {
    $files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { Test-FoundationFile -File $_ -Root $root })
    [pscustomobject]@{
        root = $root
        files = $files.Count
        bytes = [long](($files | Measure-Object Length -Sum).Sum)
    }
}

$totalBytes = [long](($rows | Measure-Object bytes -Sum).Sum)
[ordered]@{
    measured_at = (Get-Date).ToString('o')
    profile = 'Foundation'
    roots = $rows
    total_files = [long](($rows | Measure-Object files -Sum).Sum)
    total_bytes = $totalBytes
    total_gb = [math]::Round(($totalBytes / 1GB), 3)
} | ConvertTo-Json -Depth 5
