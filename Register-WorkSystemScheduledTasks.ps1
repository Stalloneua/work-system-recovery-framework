[CmdletBinding()]
param(
    [string]$BackupTime = '02:00',
    [string]$CleanupTime = '03:00',
    [string]$HealthTime = '06:00',
    [string]$MaintenanceTime = '04:00',
    [int]$ScratchRetentionDays = 7
)

$ErrorActionPreference = 'Stop'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

function Register-DailyScriptTask {
    param([string]$Name,[string]$Script,[string]$At,[string]$Arguments,[string]$Description)
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" $Arguments"
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings -Description $Description -Force | Out-Null
}

Register-DailyScriptTask -Name 'Work System Encrypted Backup' -Script (Join-Path $PSScriptRoot 'Invoke-WorkSystemBackup.ps1') -At $BackupTime -Arguments '' -Description 'Encrypted Foundation backup.'
Register-DailyScriptTask -Name 'Work System Verified Scratch Cleanup' -Script (Join-Path $PSScriptRoot 'Clear-WorkSystemScratch.ps1') -At $CleanupTime -Arguments "-RetentionDays $ScratchRetentionDays" -Description 'Delete only Drive-verified scratch artifacts after retention.'
Register-DailyScriptTask -Name 'Work System Backup Health' -Script (Join-Path $PSScriptRoot 'Test-WorkSystemBackupHealth.ps1') -At $HealthTime -Arguments '' -Description 'Fail when the latest verified snapshot is stale or unavailable.'

$maintenance = Join-Path $PSScriptRoot 'Invoke-WorkSystemMaintenance.ps1'
$maintenanceAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$maintenance`""
$maintenanceTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $MaintenanceTime
Register-ScheduledTask -TaskName 'Work System Backup Maintenance' -Action $maintenanceAction -Trigger $maintenanceTrigger -Settings $settings -Description 'Apply retention, prune and repository integrity check.' -Force | Out-Null

Write-Output 'Registered backup, cleanup, health and maintenance scheduled tasks.'
