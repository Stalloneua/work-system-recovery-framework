[CmdletBinding()]
param(
    [ValidateSet('Critical','Foundation','Full')]
    [string]$Profile,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
$logRoot = Join-Path $stateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Backup is not initialized. Run Initialize-WorkSystemBackup.ps1 first.'
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.backup_mode -eq 'plain-rclone') {
    & "$PSScriptRoot\Invoke-WorkSystemPlainBackup.ps1" -Profile $Profile -Check:$Check
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $passwordPath)) {
    throw 'Encrypted backup credential is missing.'
}
if (-not $Profile) { $Profile = $config.profile }
$secure = Get-Content -Raw -LiteralPath $passwordPath | ConvertTo-SecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
$env:RESTIC_REPOSITORY = $config.repository
$env:RESTIC_PASSWORD = $plain

try {
    & "$PSScriptRoot\New-ChatOrganizationManifest.ps1" | Out-Null
    $sourceConfig = Get-Content -Raw -LiteralPath "$PSScriptRoot\backup-sources.json" | ConvertFrom-Json
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $rawSources = switch ($Profile) {
        'Full' { $sourceConfig.full }
        'Foundation' { $sourceConfig.foundation }
        default { $sourceConfig.critical }
    }
    $sources = @($rawSources | ForEach-Object { $_.Replace('%DOCUMENTS%', $documents) } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
    if ($sources.Count -eq 0) { throw 'No backup sources resolved.' }

    $started = Get-Date
    $excludeArgs = @('--exclude-file', "$PSScriptRoot\backup-excludes.txt")
    if ($Profile -eq 'Foundation') {
        $excludeArgs += @('--exclude-file', "$PSScriptRoot\foundation-excludes.txt")
        $localExcludes = Join-Path $PSScriptRoot 'foundation-excludes.local.txt'
        if (Test-Path -LiteralPath $localExcludes) {
            $excludeArgs += @('--exclude-file', $localExcludes)
        }
    }
    $output = & restic backup @sources @excludeArgs --tag "work-system" --tag $Profile.ToLowerInvariant() --json 2>&1
    $exit = $LASTEXITCODE
    $log = [ordered]@{
        started_at = $started.ToString('o')
        finished_at = (Get-Date).ToString('o')
        profile = $Profile
        repository = $config.repository
        source_count = $sources.Count
        exit_code = $exit
        output = @($output | ForEach-Object { "$_" })
    }
    $logPath = Join-Path $logRoot ("backup-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $log | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $logPath -Encoding utf8
    if ($exit -ne 0) { throw "Backup failed. See $logPath" }

    if ($Check) {
        & restic check
        if ($LASTEXITCODE -ne 0) { throw 'restic check failed.' }
    }

    Write-Output $logPath
} finally {
    Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:RESTIC_REPOSITORY -ErrorAction SilentlyContinue
    $plain = $null
}
