[CmdletBinding()]
param(
    [string]$RemoteName = 'work-drive',
    [ValidateSet('Plain','Encrypted')]
    [string]$BackupMode = 'Plain',
    [string]$PlainRemotePath = 'Work System/00 Recovery/plain-foundation',
    [switch]$RegisterSchedule,
    [string]$ScheduleTime = '02:00',
    [string]$CleanupScheduleTime = '03:00',
    [int]$ScratchRetentionDays = 7
)

$ErrorActionPreference = 'Stop'
$commands = @('rclone')
if ($BackupMode -eq 'Encrypted') { $commands += 'restic' }
foreach ($command in $commands) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command is not installed." }
}

$remotes = @(& rclone listremotes --log-level ERROR | ForEach-Object { $_.TrimEnd(':') })
if ($RemoteName -notin $remotes) {
    Write-Host "Create the Google Drive remote '$RemoteName'. Browser OAuth approval is required once."
    & rclone config create $RemoteName drive config_is_local true --log-level ERROR
    if ($LASTEXITCODE -ne 0) { throw 'rclone Google Drive configuration failed.' }
}

& rclone lsd "${RemoteName}:" --log-level ERROR | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Cannot read Google Drive remote '$RemoteName'." }

if ($BackupMode -eq 'Plain') {
    & "$PSScriptRoot\Initialize-WorkSystemPlainBackup.ps1" -RemoteName $RemoteName -RemotePath $PlainRemotePath -Profile Foundation -RegisterSchedule:$RegisterSchedule -ScheduleTime $ScheduleTime
    if ($LASTEXITCODE -ne 0) { throw 'Plain Foundation backup initialization failed.' }
    $repository = "${RemoteName}:$PlainRemotePath"
} else {
    $repository = "rclone:${RemoteName}:Work System/00 Recovery/restic-foundation"
    & "$PSScriptRoot\Initialize-WorkSystemBackup.ps1" -Repository $repository -Profile Foundation -RegisterSchedule:$RegisterSchedule -ScheduleTime $ScheduleTime
    if ($LASTEXITCODE -ne 0) { throw 'Encrypted Foundation backup initialization failed.' }
}

if ($RegisterSchedule) {
    & "$PSScriptRoot\Register-WorkSystemScheduledTasks.ps1" -BackupTime $ScheduleTime -CleanupTime $CleanupScheduleTime -ScratchRetentionDays $ScratchRetentionDays
}

[ordered]@{
    schema_version = 1
    remote_name = $RemoteName
    backup_mode = $BackupMode
    repository = $repository
    initialized_at = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'WorkSystemRecovery\google-drive.json') -Encoding utf8

Write-Output "Google Drive foundation backup is initialized at $repository"
