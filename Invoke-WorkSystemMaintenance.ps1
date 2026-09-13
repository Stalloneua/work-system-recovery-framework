[CmdletBinding()]
param(
    [int]$KeepDaily = 14,
    [int]$KeepWeekly = 8,
    [int]$KeepMonthly = 12
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
$logRoot = Join-Path $stateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $passwordPath)) { throw 'Production backup is not initialized.' }

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
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
