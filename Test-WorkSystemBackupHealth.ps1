[CmdletBinding()]
param([int]$MaxAgeHours = 30)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
$healthPath = Join-Path $stateRoot 'health.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Production backup is not initialized.' }

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.backup_mode -eq 'plain-rclone') {
    $remoteRoot = "{0}:{1}" -f $config.remote_name, $config.remote_path.Trim('/')
    $markerCandidates = @()
    foreach ($markerName in @('latest-connector.json','latest.json')) {
        $json = & rclone cat "$remoteRoot/$markerName" --log-level ERROR 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            try { $markerCandidates += ($json | ConvertFrom-Json) } catch {}
        }
    }
    if ($markerCandidates.Count -eq 0) { throw 'Cannot read a plain backup marker.' }
    $latest = $markerCandidates | Sort-Object { [DateTimeOffset]$_.created_at } -Descending | Select-Object -First 1
    $age = [DateTimeOffset]::Now - [DateTimeOffset]$latest.created_at
    $status = if ($age.TotalHours -le $MaxAgeHours) { 'healthy' } else { 'stale' }
    [ordered]@{checked_at=(Get-Date).ToString('o');status=$status;backup_mode='plain-rclone';latest_backup=$latest.backup_id;backup_time=$latest.created_at;age_hours=[math]::Round($age.TotalHours,2);max_age_hours=$MaxAgeHours;repository=$remoteRoot} | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding utf8
    if ($status -ne 'healthy') { throw "Latest backup is $([math]::Round($age.TotalHours,2)) hours old." }
    Write-Output $healthPath
    exit 0
}
if (-not (Test-Path -LiteralPath $passwordPath)) { throw 'Encrypted backup credential is missing.' }
$secure = Get-Content -Raw -LiteralPath $passwordPath | ConvertTo-SecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
$env:RESTIC_REPOSITORY = $config.repository
$env:RESTIC_PASSWORD = $plain
try {
    $json = & restic snapshots --json 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read restic snapshots.' }
    $snapshots = @($json | ConvertFrom-Json)
    if ($snapshots.Count -eq 0) { throw 'No snapshots exist.' }
    $latest = $snapshots | Sort-Object { [DateTimeOffset]$_.time } -Descending | Select-Object -First 1
    $age = [DateTimeOffset]::Now - [DateTimeOffset]$latest.time
    $status = if ($age.TotalHours -le $MaxAgeHours) { 'healthy' } else { 'stale' }
    [ordered]@{checked_at=(Get-Date).ToString('o');status=$status;latest_snapshot=$latest.short_id;snapshot_time=$latest.time;age_hours=[math]::Round($age.TotalHours,2);max_age_hours=$MaxAgeHours;repository=$config.repository} | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding utf8
    if ($status -ne 'healthy') { throw "Latest snapshot is $([math]::Round($age.TotalHours,2)) hours old." }
    Write-Output $healthPath
} finally {
    Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:RESTIC_REPOSITORY -ErrorAction SilentlyContinue
    $plain = $null
}
