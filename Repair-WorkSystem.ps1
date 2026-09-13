[CmdletBinding()]
param([switch]$RepairSchedules,[switch]$RunBackup,[switch]$RunRestoreTest)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery'
$issues = [System.Collections.Generic.List[string]]::new()
foreach ($command in 'git','rclone','restic') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { $issues.Add("Missing command: $command") }
}

$freeGb = [math]::Round(([System.IO.DriveInfo]::new('C')).AvailableFreeSpace / 1GB, 2)
if ($freeGb -lt 5) { $issues.Add("Low disk space: $freeGb GB free on C:") }

$configPath = Join-Path $stateRoot 'config.json'
$passwordPath = Join-Path $stateRoot 'restic-password.xml'
if (-not (Test-Path -LiteralPath $configPath)) { $issues.Add('Missing production backup config.') }
if (-not (Test-Path -LiteralPath $passwordPath)) { $issues.Add('Missing DPAPI backup credential for scheduled runs.') }

$taskNames = @(
    'Work System Encrypted Backup',
    'Work System Verified Scratch Cleanup',
    'Work System Backup Health',
    'Work System Backup Maintenance'
)
foreach ($name in $taskNames) {
    if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) { $issues.Add("Missing scheduled task: $name") }
}

if ($RepairSchedules -and (Test-Path -LiteralPath $configPath) -and (Test-Path -LiteralPath $passwordPath)) {
    & "$PSScriptRoot\Register-WorkSystemScheduledTasks.ps1"
}
if ($RunBackup) { & "$PSScriptRoot\Invoke-WorkSystemBackup.ps1" -Check }
if ($RunRestoreTest) { & "$PSScriptRoot\Test-DisasterRecovery.ps1" }

$result = [ordered]@{
    checked_at = (Get-Date).ToString('o')
    free_gb = $freeGb
    issues = @($issues)
    result = if ($issues.Count) { 'ATTENTION' } else { 'PASS' }
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stateRoot 'repair-report.json') -Encoding utf8
$result | ConvertTo-Json -Depth 5
if ($issues.Count) { exit 2 }
