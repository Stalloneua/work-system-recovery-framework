[CmdletBinding()]
param(
    [int]$KeepDaily = 14,
    [int]$KeepWeekly = 8,
    [int]$KeepMonthly = 12,
    [int]$KeepPlainDays = 30
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
$logRoot = Join-Path $stateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Production backup is not initialized.' }

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.backup_mode -eq 'plain-rclone') {
    $remoteRoot = "{0}:{1}" -f $config.remote_name, $config.remote_path.Trim('/')
    $cutoff = (Get-Date).AddDays(-$KeepPlainDays)
    $latestId = $null
    $latestJson = & rclone cat "$remoteRoot/latest.json" --log-level ERROR 2>$null
    if ($LASTEXITCODE -eq 0 -and $latestJson) {
        $latestId = ($latestJson | ConvertFrom-Json).backup_id
    }
    $directories = @(& rclone lsf "$remoteRoot/snapshots" --dirs-only --log-level ERROR 2>$null)
    if ($LASTEXITCODE -notin @(0,3)) { throw 'Cannot list plain backup snapshots.' }
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in $directories) {
        $name = $directory.TrimEnd('/')
        $parsed = [datetime]::MinValue
        if ($name -ne $latestId -and [datetime]::TryParseExact($name, 'yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed) -and $parsed -lt $cutoff) {
            & rclone purge "$remoteRoot/snapshots/$name" --log-level ERROR
            if ($LASTEXITCODE -ne 0) { throw "Cannot purge expired snapshot $name" }
            $removed.Add($name)
        }
    }
    & "$PSScriptRoot\Test-WorkSystemBackupHealth.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Plain backup health check failed.' }
    [ordered]@{checked_at=(Get-Date).ToString('o');backup_mode='plain-rclone';repository=$remoteRoot;keep_plain_days=$KeepPlainDays;removed=@($removed);result='PASS'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logRoot ("maintenance-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Encoding utf8
    exit 0
}
if (-not (Test-Path -LiteralPath $passwordPath)) { throw 'Encrypted backup credential is missing.' }
$secure = Get-Content -Raw -LiteralPath $passwordPath | ConvertTo-SecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
$env:RESTIC_REPOSITORY = $config.repository
$env:RESTIC_PASSWORD = $plain
try {
    $started = Get-Date
    $output = @()
    $output += & restic forget --tag work-system --keep-daily $KeepDaily --keep-weekly $KeepWeekly --keep-monthly $KeepMonthly --prune 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'restic retention/prune failed.' }
    $output += & restic check 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'restic check failed.' }
    [ordered]@{
        started_at = $started.ToString('o')
        finished_at = (Get-Date).ToString('o')
        repository = $config.repository
        keep_daily = $KeepDaily
        keep_weekly = $KeepWeekly
        keep_monthly = $KeepMonthly
        output = @($output | ForEach-Object { "$_" })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logRoot ("maintenance-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Encoding utf8
} finally {
    Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:RESTIC_REPOSITORY -ErrorAction SilentlyContinue
    $plain = $null
}
